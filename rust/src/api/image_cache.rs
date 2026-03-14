use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::Result;
use sha2::{Digest, Sha256};
use tokio::sync::Semaphore;

static CACHE_DIR: OnceLock<PathBuf> = OnceLock::new();
static SEMAPHORE: OnceLock<Semaphore> = OnceLock::new();

fn semaphore() -> &'static Semaphore {
    SEMAPHORE.get_or_init(|| Semaphore::new(8))
}

pub async fn init_image_cache(cache_dir: String) -> Result<()> {
    let path = PathBuf::from(&cache_dir);
    tokio::fs::create_dir_all(&path).await?;

    let meta_path = path.join("meta");
    tokio::fs::create_dir_all(&meta_path).await?;

    CACHE_DIR.set(path).ok();
    Ok(())
}

fn cache_dir() -> Option<&'static PathBuf> {
    CACHE_DIR.get()
}

fn url_to_filename(url: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(url.as_bytes());
    hex::encode(hasher.finalize())
}

fn ext_from_url(url: &str) -> &str {
    let path = url.split('?').next().unwrap_or(url);
    let lower = path.to_lowercase();
    if lower.ends_with(".png") { return "png"; }
    if lower.ends_with(".gif") { return "gif"; }
    if lower.ends_with(".webp") { return "webp"; }
    if lower.ends_with(".jpg") || lower.ends_with(".jpeg") { return "jpg"; }
    "jpg"
}

fn cached_path(dir: &Path, url: &str) -> PathBuf {
    let name = url_to_filename(url);
    let ext = ext_from_url(url);
    dir.join(format!("{}.{}", name, ext))
}

fn touch_meta(dir: &Path, url: &str) {
    let name = url_to_filename(url);
    let meta_file = dir.join("meta").join(name);
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let _ = std::fs::write(meta_file, now.to_string());
}

pub async fn get_cached_image_path(url: String) -> Result<Option<String>> {
    if url.is_empty() {
        return Ok(None);
    }
    let dir = match cache_dir() {
        Some(d) => d,
        None => return Ok(None),
    };
    let path = cached_path(dir, &url);
    if path.exists() {
        touch_meta(dir, &url);
        return Ok(Some(path.to_string_lossy().into_owned()));
    }
    Ok(None)
}

pub async fn fetch_and_cache_image(url: String) -> Result<String> {
    if url.is_empty() {
        anyhow::bail!("empty url");
    }
    let dir = match cache_dir() {
        Some(d) => d.clone(),
        None => anyhow::bail!("cache not initialized"),
    };

    let path = cached_path(&dir, &url);

    if path.exists() {
        touch_meta(&dir, &url);
        return Ok(path.to_string_lossy().into_owned());
    }

    let _permit = semaphore().acquire().await?;

    if path.exists() {
        touch_meta(&dir, &url);
        return Ok(path.to_string_lossy().into_owned());
    }

    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()?;

    let response = client.get(&url).send().await?;
    if !response.status().is_success() {
        anyhow::bail!("HTTP {}", response.status());
    }

    let bytes = response.bytes().await?;
    if bytes.is_empty() {
        anyhow::bail!("empty response");
    }

    tokio::fs::write(&path, &bytes).await?;
    touch_meta(&dir, &url);

    Ok(path.to_string_lossy().into_owned())
}

pub async fn prefetch_images(urls: Vec<String>) -> Result<()> {
    let dir = match cache_dir() {
        Some(d) => d.clone(),
        None => return Ok(()),
    };

    let uncached: Vec<String> = urls
        .into_iter()
        .filter(|u| !u.is_empty() && !cached_path(&dir, u).exists())
        .collect();

    if uncached.is_empty() {
        return Ok(());
    }

    let tasks: Vec<_> = uncached
        .into_iter()
        .map(|url| tokio::spawn(async move {
            let _ = fetch_and_cache_image(url).await;
        }))
        .collect();

    for t in tasks {
        let _ = t.await;
    }

    Ok(())
}

pub fn is_video_url(url: &str) -> bool {
    let path = url.split('?').next().unwrap_or(url).to_lowercase();
    path.ends_with(".mp4")
        || path.ends_with(".mov")
        || path.ends_with(".avi")
        || path.ends_with(".mkv")
        || path.ends_with(".webm")
        || path.ends_with(".m4v")
}

pub fn is_cached(url: &str) -> bool {
    if url.is_empty() { return false; }
    let dir = match cache_dir() {
        Some(d) => d,
        None => return false,
    };
    cached_path(dir, url).exists()
}

pub async fn prefetch_note_images(urls: Vec<String>) {
    if urls.is_empty() { return; }
    let dir = match cache_dir() {
        Some(d) => d.clone(),
        None => return,
    };

    let uncached: Vec<String> = urls
        .into_iter()
        .filter(|u| !u.is_empty() && !is_video_url(u) && !cached_path(&dir, u).exists())
        .collect();

    if uncached.is_empty() { return; }

    let tasks: Vec<_> = uncached
        .into_iter()
        .map(|url| {
            tokio::spawn(async move {
                let _ = tokio::time::timeout(
                    std::time::Duration::from_secs(3),
                    fetch_and_cache_image(url),
                )
                .await;
            })
        })
        .collect();

    let _ = tokio::time::timeout(
        std::time::Duration::from_secs(3),
        async {
            for t in tasks {
                let _ = t.await;
            }
        },
    )
    .await;
}

pub async fn evict_image_cache(max_age_secs: u64) -> Result<u32> {
    let dir = match cache_dir() {
        Some(d) => d.clone(),
        None => return Ok(0),
    };

    let meta_dir = dir.join("meta");
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);

    let mut deleted: u32 = 0;

    let mut meta_entries = tokio::fs::read_dir(&meta_dir).await?;
    while let Some(entry) = meta_entries.next_entry().await? {
        let meta_path = entry.path();
        if let Ok(content) = tokio::fs::read_to_string(&meta_path).await {
            if let Ok(last_access) = content.trim().parse::<u64>() {
                if now.saturating_sub(last_access) > max_age_secs {
                    let name = meta_path
                        .file_name()
                        .and_then(|n| n.to_str())
                        .unwrap_or("")
                        .to_string();

                    for ext in &["jpg", "png", "gif", "webp"] {
                        let img_path = dir.join(format!("{}.{}", name, ext));
                        if img_path.exists() {
                            let _ = tokio::fs::remove_file(&img_path).await;
                            deleted += 1;
                        }
                    }
                    let _ = tokio::fs::remove_file(&meta_path).await;
                }
            }
        }
    }

    Ok(deleted)
}

pub async fn get_image_cache_size_mb() -> Result<f64> {
    let dir = match cache_dir() {
        Some(d) => d.clone(),
        None => return Ok(0.0),
    };

    let mut total_bytes: u64 = 0;
    let mut entries = tokio::fs::read_dir(&dir).await?;
    while let Some(entry) = entries.next_entry().await? {
        let path = entry.path();
        if path.is_file() {
            if let Ok(meta) = tokio::fs::metadata(&path).await {
                total_bytes += meta.len();
            }
        }
    }

    Ok(total_bytes as f64 / 1_048_576.0)
}
