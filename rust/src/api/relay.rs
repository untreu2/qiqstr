use std::collections::{HashMap, HashSet};
use std::fs;
use std::sync::OnceLock;
use std::time::Duration;

use anyhow::{anyhow, Result};
use flutter_rust_bridge::frb;
use nostr_lmdb::NostrLMDB;
use nostr_sdk::prelude::*;
use tokio::sync::RwLock;

use crate::frb_generated::StreamSink;

static COUNTING_CLIENT: OnceLock<RwLock<Option<Client>>> = OnceLock::new();

fn counting_client_lock() -> &'static RwLock<Option<Client>> {
    COUNTING_CLIENT.get_or_init(|| RwLock::new(None))
}

const DISCOVERY_RELAYS: &[&str] = &[
    "wss://relay.damus.io",
    "wss://nos.lol",
    "wss://relay.primal.net",
    "wss://vitor.nostr1.com",
];

const MAX_OUTBOX_RELAYS: usize = 30;
const MIN_RELAY_FREQUENCY: usize = 2;

static CLIENT: OnceLock<RwLock<Option<Client>>> = OnceLock::new();
static USER_RELAYS: OnceLock<RwLock<Vec<String>>> = OnceLock::new();
static DB_PATH: OnceLock<RwLock<Option<String>>> = OnceLock::new();

fn state() -> &'static RwLock<Option<Client>> {
    CLIENT.get_or_init(|| RwLock::new(None))
}

fn user_relays_state() -> &'static RwLock<Vec<String>> {
    USER_RELAYS.get_or_init(|| RwLock::new(Vec::new()))
}

pub(crate) fn db_path_state() -> &'static RwLock<Option<String>> {
    DB_PATH.get_or_init(|| RwLock::new(None))
}

async fn get_client() -> Result<Client> {
    let lock = state().read().await;
    lock.as_ref()
        .cloned()
        .ok_or_else(|| anyhow!("Client not initialized"))
}

pub(crate) async fn get_client_pub() -> Result<Client> {
    get_client().await
}

fn sanitize_lmdb_dir(path: &str) {
    let db_dir = std::path::Path::new(path);
    if !db_dir.exists() {
        return;
    }

    let lock_file = db_dir.join("lock.mdb");
    if lock_file.exists() {
        let _ = fs::remove_file(&lock_file);
    }

    let data_file = db_dir.join("data.mdb");
    if data_file.exists() {
        match fs::metadata(&data_file) {
            Ok(meta) if meta.len() == 0 => {
                let _ = fs::remove_dir_all(db_dir);
            }
            Err(_) => {
                let _ = fs::remove_dir_all(db_dir);
            }
            _ => {}
        }
    }
}

const LMDB_MAP_SIZES: &[usize] = &[
    2 * 1024 * 1024 * 1024,  // 2 GB
    1024 * 1024 * 1024,       // 1 GB
    512 * 1024 * 1024,        // 512 MB
    256 * 1024 * 1024,        // 256 MB
];

fn try_open_lmdb(path: &str) -> Result<NostrLMDB> {
    let path_owned = path.to_string();

    for &map_size in LMDB_MAP_SIZES {
        let p = path_owned.clone();
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            NostrLMDB::builder(&p)
                .map_size(map_size)
                .build()
        }));

        match result {
            Ok(Ok(db)) => return Ok(db),
            Ok(Err(_)) => continue,
            Err(_) => continue,
        }
    }

    Err(anyhow!("LMDB open failed with all map sizes"))
}

fn wipe_db_directory(path: &str) {
    let db_path = std::path::Path::new(path);
    if db_path.exists() {
        let _ = fs::remove_dir_all(db_path);
    }
}

fn open_or_recreate_lmdb(path: &str) -> Result<NostrLMDB> {
    sanitize_lmdb_dir(path);

    match try_open_lmdb(path) {
        Ok(db) => Ok(db),
        Err(_) => {
            wipe_db_directory(path);
            try_open_lmdb(path)
        }
    }
}

pub async fn init_client(
    relay_urls: Vec<String>,
    private_key_hex: Option<String>,
    db_path: Option<String>,
) -> Result<()> {
    let mut builder = Client::builder();

    if let Some(ref sk_hex) = private_key_hex {
        let keys = Keys::parse(sk_hex)?;
        builder = builder.signer(keys);
    }

    if let Some(ref path) = db_path {
        let database = open_or_recreate_lmdb(path)?;
        builder = builder.database(database);

        let mut db_path_lock = db_path_state().write().await;
        *db_path_lock = Some(path.clone());
    }

    let client = builder.build();

    let relay_futures: Vec<_> = relay_urls
        .iter()
        .map(|url| client.add_relay(url.as_str()))
        .collect();
    futures::future::join_all(relay_futures).await;

    let discovery_futures: Vec<_> = DISCOVERY_RELAYS
        .iter()
        .map(|url| client.add_discovery_relay(*url))
        .collect();
    futures::future::join_all(discovery_futures).await;

    {
        let mut ur = user_relays_state().write().await;
        *ur = relay_urls;
    }

    let mut lock = state().write().await;
    if let Some(old_client) = lock.take() {
        old_client.disconnect().await;
    }
    *lock = Some(client);

    Ok(())
}

pub async fn connect_relays() -> Result<()> {
    let client = get_client().await?;
    client.connect().await;
    Ok(())
}

pub async fn disconnect_relays() -> Result<()> {
    let client = get_client().await?;
    client.disconnect().await;
    Ok(())
}

pub async fn update_signer(private_key_hex: String) -> Result<()> {
    let client = get_client().await?;
    let keys = Keys::parse(&private_key_hex)?;
    client.set_signer(keys).await;
    Ok(())
}

pub async fn is_client_initialized() -> bool {
    let lock = state().read().await;
    lock.is_some()
}

pub async fn add_relay(url: String) -> Result<bool> {
    let client = get_client().await?;
    let added = client.add_relay(&url).await.is_ok();
    if added {
        let mut ur = user_relays_state().write().await;
        if !ur.contains(&url) {
            ur.push(url);
        }
        client.connect().await;
    }
    Ok(added)
}

pub async fn add_relay_with_flags(url: String, read: bool, write: bool) -> Result<bool> {
    let client = get_client().await?;
    let relay_url = RelayUrl::parse(&url)?;

    let added = client.add_relay(relay_url.as_str()).await.is_ok();
    if added {
        let relays = client.relays().await;
        if let Some(relay) = relays.get(&relay_url) {
            let flags = relay.flags();
            if !read {
                flags.remove(RelayServiceFlags::READ);
            }
            if !write {
                flags.remove(RelayServiceFlags::WRITE);
            }
        }
        let mut ur = user_relays_state().write().await;
        if !ur.contains(&url) {
            ur.push(url);
        }
    }
    Ok(added)
}

pub async fn remove_relay(url: String) -> Result<()> {
    let client = get_client().await?;
    let relay_url = RelayUrl::parse(&url)?;
    client.remove_relay(&relay_url).await?;
    let mut ur = user_relays_state().write().await;
    ur.retain(|u| u != &url);
    Ok(())
}

pub async fn get_relay_list() -> Result<Vec<String>> {
    let client = get_client().await?;
    let relays = client.relays().await;
    Ok(relays
        .iter()
        .filter(|(_, r)| {
            let flags = r.flags();
            !(flags.has(RelayServiceFlags::DISCOVERY, FlagCheck::All)
                && !flags.has(RelayServiceFlags::READ, FlagCheck::All)
                && !flags.has(RelayServiceFlags::WRITE, FlagCheck::All))
        })
        .map(|(u, _)| u.to_string())
        .collect())
}

pub async fn get_connected_relay_count() -> Result<u32> {
    let client = get_client().await?;
    let relays = client.relays().await;
    let mut count: u32 = 0;
    for (_, relay) in relays.iter() {
        let flags = relay.flags();
        let is_discovery_only = flags.has(RelayServiceFlags::DISCOVERY, FlagCheck::All)
            && !flags.has(RelayServiceFlags::READ, FlagCheck::All)
            && !flags.has(RelayServiceFlags::WRITE, FlagCheck::All);
        if !is_discovery_only && relay.status() == RelayStatus::Connected {
            count += 1;
        }
    }
    Ok(count)
}

pub async fn get_relay_status() -> Result<String> {
    let client = get_client().await?;
    let relays = client.relays().await;

    let mut relay_list = Vec::new();
    for (url, relay) in relays.iter() {
        let status = relay.status();
        let stats = relay.stats();
        let flags = relay.flags();
        let is_discovery = flags.has(RelayServiceFlags::DISCOVERY, FlagCheck::All)
            && !flags.has(RelayServiceFlags::READ, FlagCheck::All)
            && !flags.has(RelayServiceFlags::WRITE, FlagCheck::All);

        let status_str = match status {
            RelayStatus::Initialized => "initialized",
            RelayStatus::Pending => "pending",
            RelayStatus::Connecting => "connecting",
            RelayStatus::Connected => "connected",
            RelayStatus::Disconnected => "disconnected",
            RelayStatus::Terminated => "terminated",
            RelayStatus::Banned => "banned",
            RelayStatus::Sleeping => "sleeping",
        };

        let relay_info = serde_json::json!({
            "url": url.to_string(),
            "status": status_str,
            "isDiscovery": is_discovery,
            "attempts": stats.attempts(),
            "success": stats.success(),
            "bytesSent": stats.bytes_sent(),
            "bytesReceived": stats.bytes_received(),
            "connectedAt": stats.connected_at().as_secs(),
        });
        relay_list.push(relay_info);
    }

    let total = relay_list
        .iter()
        .filter(|r| r["isDiscovery"] == false)
        .count();
    let connected = relay_list
        .iter()
        .filter(|r| r["status"] == "connected" && r["isDiscovery"] == false)
        .count();

    let result = serde_json::json!({
        "summary": {
            "totalRelays": total,
            "connectedRelays": connected,
        },
        "relays": relay_list,
    });

    Ok(result.to_string())
}

pub async fn discover_and_connect_outbox_relays(pubkeys_hex: Vec<String>) -> Result<String> {
    let client = get_client().await?;

    let public_keys: Vec<PublicKey> = pubkeys_hex
        .iter()
        .filter_map(|h| PublicKey::from_hex(h).ok())
        .collect();

    if public_keys.is_empty() {
        return Ok(serde_json::json!({
            "discoveredRelays": 0,
            "addedRelays": 0,
            "totalConnected": 0,
        }).to_string());
    }

    let mut outbox_freq: HashMap<String, usize> = HashMap::new();
    let mut inbox_freq: HashMap<String, usize> = HashMap::new();

    let chunk_futures: Vec<_> = public_keys
        .chunks(50)
        .map(|chunk| {
            let filter = Filter::new()
                .authors(chunk.to_vec())
                .kind(Kind::RelayList)
                .limit(chunk.len());
            client.fetch_events(filter, Duration::from_secs(10))
        })
        .collect();

    let chunk_results = futures::future::join_all(chunk_futures).await;

    for result in chunk_results {
        if let Ok(events) = result {
            for event in events.into_iter() {
                for tag in event.tags.iter() {
                    let tag_vec: Vec<&str> = tag.as_slice().iter().map(|s| s.as_str()).collect();
                    if tag_vec.len() >= 2 && tag_vec[0] == "r" {
                        let relay_url = tag_vec[1].to_string();
                        let mode = tag_vec.get(2).copied().unwrap_or("");

                        match mode {
                            "write" => {
                                *outbox_freq.entry(relay_url).or_insert(0) += 1;
                            }
                            "read" => {
                                *inbox_freq.entry(relay_url).or_insert(0) += 1;
                            }
                            _ => {
                                *outbox_freq.entry(relay_url.clone()).or_insert(0) += 1;
                                *inbox_freq.entry(relay_url).or_insert(0) += 1;
                            }
                        }
                    }
                }
            }
        }
    }

    let existing_relays: Vec<String> = client
        .relays()
        .await
        .keys()
        .map(|u| u.to_string())
        .collect();

    let mut all_relays: HashMap<String, (usize, bool, bool)> = HashMap::new();

    for (url, count) in &outbox_freq {
        if !existing_relays.contains(url) {
            let entry = all_relays.entry(url.clone()).or_insert((0, false, false));
            entry.0 += count;
            entry.1 = true;
        }
    }

    for (url, count) in &inbox_freq {
        if !existing_relays.contains(url) {
            let entry = all_relays.entry(url.clone()).or_insert((0, false, false));
            entry.0 += count;
            entry.2 = true;
        }
    }

    let mut candidates: Vec<(String, usize, bool, bool)> = all_relays
        .into_iter()
        .filter(|(_, (count, _, _))| *count >= MIN_RELAY_FREQUENCY)
        .map(|(url, (count, is_outbox, is_inbox))| (url, count, is_outbox, is_inbox))
        .collect();

    candidates.sort_by(|a, b| b.1.cmp(&a.1));
    candidates.truncate(MAX_OUTBOX_RELAYS);

    let discovered_count = candidates.len() as u32;
    let mut added_count: u32 = 0;

    let parsed_candidates: Vec<_> = candidates
        .iter()
        .filter_map(|(url, _, is_outbox, is_inbox)| {
            RelayUrl::parse(url.as_str()).ok().map(|relay_url| (relay_url, *is_outbox, *is_inbox))
        })
        .collect();

    let add_futures: Vec<_> = parsed_candidates
        .iter()
        .map(|(relay_url, _, _)| client.add_relay(relay_url.as_str()))
        .collect();
    let add_results = futures::future::join_all(add_futures).await;

    for (i, result) in add_results.into_iter().enumerate() {
        if result.is_ok() {
            let (ref relay_url, is_outbox, is_inbox) = parsed_candidates[i];
            let relays = client.relays().await;
            if let Some(relay) = relays.get(relay_url) {
                let flags = relay.flags();
                if is_outbox && !is_inbox {
                    flags.remove(RelayServiceFlags::WRITE);
                } else if is_inbox && !is_outbox {
                    flags.remove(RelayServiceFlags::READ);
                }
            }
            added_count += 1;
        }
    }

    if added_count > 0 {
        client.connect().await;
    }

    let mut connected_count: u32 = 0;
    let relays = client.relays().await;
    for (_, relay) in relays.iter() {
        if relay.status() == RelayStatus::Connected {
            connected_count += 1;
        }
    }

    let result = serde_json::json!({
        "discoveredRelays": discovered_count,
        "addedRelays": added_count,
        "totalConnected": connected_count,
    });

    Ok(result.to_string())
}

pub async fn sync_events(filter_json: String) -> Result<String> {
    let client = get_client().await?;
    let filter = Filter::from_json(&filter_json)?;
    let opts = SyncOptions::default();

    let output = client.sync(filter, &opts).await
        .map_err(|e| anyhow!("Negentropy sync failed: {}", e))?;

    let received: Vec<String> = output.received.iter().map(|id| id.to_hex()).collect();
    let sent: Vec<String> = output.sent.iter().map(|id| id.to_hex()).collect();

    let result = serde_json::json!({
        "received": received.len(),
        "sent": sent.len(),
        "local": output.local.len(),
        "remote": output.remote.len(),
    });

    Ok(result.to_string())
}

pub async fn fetch_events(filter_json: String, timeout_secs: u32) -> Result<String> {
    let client = get_client().await?;
    let filter = Filter::from_json(&filter_json)?;
    let timeout = Duration::from_secs(timeout_secs as u64);

    let events: Events = client.fetch_events(filter, timeout).await?;

    let events_json: Vec<serde_json::Value> = events
        .into_iter()
        .filter_map(|e: Event| serde_json::from_str(&e.as_json()).ok())
        .collect();

    Ok(serde_json::to_string(&events_json)?)
}


pub async fn fetch_counts_from_relays(
    note_ids: Vec<String>,
    user_pubkey_hex: Option<String>,
) -> Result<String> {
    let main_client = get_client().await?;

    let ids: Vec<EventId> = note_ids
        .iter()
        .filter_map(|id| EventId::from_hex(id).ok())
        .collect();

    if ids.is_empty() {
        return Ok("{}".to_string());
    }

    let user_pk = user_pubkey_hex
        .as_ref()
        .and_then(|h| PublicKey::from_hex(h).ok());

    let lock = counting_client_lock();
    let client = {
        let reader = lock.read().await;
        reader.clone()
    };
    let client = match client {
        Some(c) => c,
        None => {
            let mut writer = lock.write().await;
            if let Some(ref c) = *writer {
                c.clone()
            } else {
                let c = Client::builder()
                    .database(MemoryDatabase::default())
                    .build();
                *writer = Some(c.clone());
                c
            }
        }
    };

    let relay_urls: Vec<String> = main_client
        .relays()
        .await
        .keys()
        .map(|u| u.to_string())
        .collect();
    for url in &relay_urls {
        let _ = client.add_relay(url.as_str()).await;
    }
    client.connect().await;

    let filter = Filter::new()
        .kinds([Kind::Reaction, Kind::Repost, Kind::ZapReceipt, Kind::TextNote])
        .events(ids)
        .limit(500);

    let timeout = Duration::from_secs(5);
    let events = client.fetch_events(filter, timeout).await
        .unwrap_or_default();

    let mut counts: HashMap<String, [usize; 4]> = HashMap::new();
    let mut user_reacted: HashMap<String, bool> = HashMap::new();
    let mut user_reposted: HashMap<String, bool> = HashMap::new();

    for nid in &note_ids {
        counts.insert(nid.clone(), [0; 4]);
        user_reacted.insert(nid.clone(), false);
        user_reposted.insert(nid.clone(), false);
    }

    for event in events.iter() {
        let kind = event.kind;
        let is_user = user_pk.as_ref().map_or(false, |pk| event.pubkey == *pk);
        let zap_sats = if kind == Kind::ZapReceipt {
            super::database::extract_zap_amount_sats(event) as usize
        } else {
            0
        };

        let mut counted_for: HashSet<String> = HashSet::new();
        for tag in event.tags.iter() {
            let tag_kind = tag.kind();
            if matches!(tag_kind, TagKind::SingleLetter(SingleLetterTag { character: Alphabet::E, .. })) {
                if let Some(ref_id) = tag.content() {
                    let ref_hex = ref_id.to_string();
                    if counted_for.contains(&ref_hex) { continue; }
                    if let Some(c) = counts.get_mut(&ref_hex) {
                        counted_for.insert(ref_hex.clone());
                        match kind {
                            k if k == Kind::Reaction => {
                                c[0] += 1;
                                if is_user {
                                    user_reacted.insert(ref_hex, true);
                                }
                            }
                            k if k == Kind::Repost => {
                                c[1] += 1;
                                if is_user {
                                    user_reposted.insert(ref_hex, true);
                                }
                            }
                            k if k == Kind::ZapReceipt => c[2] += zap_sats,
                            k if k == Kind::TextNote => c[3] += 1,
                            _ => {}
                        }
                    }
                }
            }
        }
    }

    let mut result = serde_json::Map::new();
    for (nid, c) in &counts {
        result.insert(
            nid.clone(),
            serde_json::json!({
                "reactions": c[0],
                "reposts": c[1],
                "zaps": c[2],
                "replies": c[3],
                "hasReacted": user_reacted.get(nid).copied().unwrap_or(false),
                "hasReposted": user_reposted.get(nid).copied().unwrap_or(false),
            }),
        );
    }
    Ok(serde_json::to_string(&result)?)
}

#[frb]
pub async fn stream_interaction_counts(
    note_ids: Vec<String>,
    user_pubkey_hex: Option<String>,
    sink: StreamSink<String>,
) -> Result<()> {
    let main_client = get_client().await?;

    let ids: Vec<EventId> = note_ids
        .iter()
        .filter_map(|id| EventId::from_hex(id).ok())
        .collect();

    if ids.is_empty() {
        return Ok(());
    }

    let user_pk = user_pubkey_hex
        .as_ref()
        .and_then(|h| PublicKey::from_hex(h).ok());

    let lock = counting_client_lock();
    let client = {
        let reader = lock.read().await;
        reader.clone()
    };
    let client = match client {
        Some(c) => c,
        None => {
            let mut writer = lock.write().await;
            if let Some(ref c) = *writer {
                c.clone()
            } else {
                let c = Client::builder()
                    .database(MemoryDatabase::default())
                    .build();
                *writer = Some(c.clone());
                c
            }
        }
    };

    let relay_urls: Vec<String> = main_client
        .relays()
        .await
        .keys()
        .map(|u| u.to_string())
        .collect();
    for url in &relay_urls {
        let _ = client.add_relay(url.as_str()).await;
    }
    client.connect().await;

    let filter = Filter::new()
        .kinds([Kind::Reaction, Kind::Repost, Kind::ZapReceipt, Kind::TextNote])
        .events(ids);

    let Output { val: sub_id, .. } = client
        .subscribe(filter, None)
        .await
        .map_err(|e| anyhow!("Subscribe failed: {}", e))?;

    let mut notifications = client.notifications();

    let mut counts: HashMap<String, [usize; 4]> = HashMap::new();
    let mut user_reacted: HashMap<String, bool> = HashMap::new();
    let mut user_reposted: HashMap<String, bool> = HashMap::new();
    let mut seen_events: HashSet<String> = HashSet::new();

    for nid in &note_ids {
        counts.insert(nid.clone(), [0; 4]);
        user_reacted.insert(nid.clone(), false);
        user_reposted.insert(nid.clone(), false);
    }

    let mut eose_count: usize = 0;
    let relay_count = relay_urls.len();
    let mut last_emit = std::time::Instant::now();
    let mut has_data = false;

    loop {
        let recv = tokio::time::timeout(
            Duration::from_secs(3),
            notifications.recv(),
        )
        .await;

        match recv {
            Ok(Ok(notification)) => match notification {
                RelayPoolNotification::Event {
                    subscription_id,
                    event,
                    ..
                } => {
                    if subscription_id != sub_id {
                        continue;
                    }
                    let event_id = event.id.to_hex();
                    if seen_events.contains(&event_id) {
                        continue;
                    }
                    seen_events.insert(event_id);

                    let kind = event.kind;
                    let is_user = user_pk
                        .as_ref()
                        .map_or(false, |pk| event.pubkey == *pk);
                    let zap_sats = if kind == Kind::ZapReceipt {
                        super::database::extract_zap_amount_sats(&event) as usize
                    } else {
                        0
                    };

                    let mut counted_for: HashSet<String> = HashSet::new();
                    for tag in event.tags.iter() {
                        let tag_kind = tag.kind();
                        if matches!(
                            tag_kind,
                            TagKind::SingleLetter(SingleLetterTag {
                                character: Alphabet::E,
                                ..
                            })
                        ) {
                            if let Some(ref_id) = tag.content() {
                                let ref_hex = ref_id.to_string();
                                if counted_for.contains(&ref_hex) {
                                    continue;
                                }
                                if let Some(c) = counts.get_mut(&ref_hex) {
                                    counted_for.insert(ref_hex.clone());
                                    has_data = true;
                                    match kind {
                                        k if k == Kind::Reaction => {
                                            c[0] += 1;
                                            if is_user {
                                                user_reacted
                                                    .insert(ref_hex, true);
                                            }
                                        }
                                        k if k == Kind::Repost => {
                                            c[1] += 1;
                                            if is_user {
                                                user_reposted
                                                    .insert(ref_hex, true);
                                            }
                                        }
                                        k if k == Kind::ZapReceipt => {
                                            c[2] += zap_sats;
                                        }
                                        k if k == Kind::TextNote => {
                                            c[3] += 1;
                                        }
                                        _ => {}
                                    }
                                }
                            }
                        }
                    }

                    if has_data
                        && last_emit.elapsed() >= Duration::from_millis(250)
                    {
                        let json = build_counts_json(
                            &counts,
                            &note_ids,
                            &user_reacted,
                            &user_reposted,
                        );
                        if sink.add(json).is_err() {
                            break;
                        }
                        last_emit = std::time::Instant::now();
                    }
                }
                RelayPoolNotification::Message { message, .. } => {
                    if let RelayMessage::EndOfStoredEvents(sid) = message {
                        if *sid == sub_id {
                            eose_count += 1;
                            if eose_count >= relay_count {
                                break;
                            }
                        }
                    }
                }
                RelayPoolNotification::Shutdown => break,
            },
            Ok(Err(_)) => break,
            Err(_) => break,
        }
    }

    if has_data {
        let json = build_counts_json(
            &counts,
            &note_ids,
            &user_reacted,
            &user_reposted,
        );
        let _ = sink.add(json);
    }

    let _ = client.unsubscribe(&sub_id).await;
    Ok(())
}

fn build_counts_json(
    counts: &HashMap<String, [usize; 4]>,
    note_ids: &[String],
    user_reacted: &HashMap<String, bool>,
    user_reposted: &HashMap<String, bool>,
) -> String {
    let mut result = serde_json::Map::new();
    for nid in note_ids {
        if let Some(c) = counts.get(nid) {
            result.insert(
                nid.clone(),
                serde_json::json!({
                    "reactions": c[0],
                    "reposts": c[1],
                    "zaps": c[2],
                    "replies": c[3],
                    "hasReacted": user_reacted.get(nid).copied().unwrap_or(false),
                    "hasReposted": user_reposted.get(nid).copied().unwrap_or(false),
                }),
            );
        }
    }
    serde_json::to_string(&result).unwrap_or_else(|_| "{}".to_string())
}

pub async fn fetch_event_by_id(event_id: String, timeout_secs: u32) -> Result<Option<String>> {
    let client = get_client().await?;
    let id = EventId::from_hex(&event_id)?;
    let filter = Filter::new().id(id).limit(1);
    let timeout = Duration::from_secs(timeout_secs as u64);

    let events: Events = client.fetch_events(filter, timeout).await?;
    
    if let Some(event) = events.first_owned() {
        Ok(Some(event.as_json()))
    } else {
        Ok(None)
    }
}

pub async fn send_event(event_json: String) -> Result<String> {
    let client = get_client().await?;
    let event = Event::from_json(&event_json)?;
    let event_id = event.id;

    tokio::spawn(async move {
        let _ = client.send_event(&event).await;
    });

    let result = serde_json::json!({
        "id": event_id.to_hex(),
    });

    Ok(result.to_string())
}

pub async fn send_event_to(event_json: String, relay_urls: Vec<String>) -> Result<String> {
    let client = get_client().await?;
    let event = Event::from_json(&event_json)?;

    let urls: Vec<RelayUrl> = relay_urls
        .iter()
        .filter_map(|u| RelayUrl::parse(u).ok())
        .collect();

    let add_futures: Vec<_> = urls.iter().map(|url| client.add_relay(url.as_str())).collect();
    futures::future::join_all(add_futures).await;
    client.connect().await;

    let output = client.send_event_to(urls, &event).await?;

    let success: Vec<String> = output.success.iter().map(|u| u.to_string()).collect();
    let failed: HashMap<String, String> = output
        .failed
        .iter()
        .map(|(u, e)| (u.to_string(), e.to_string()))
        .collect();

    let result = serde_json::json!({
        "id": output.id().to_hex(),
        "success": success,
        "failed": failed,
    });

    Ok(result.to_string())
}

pub async fn broadcast_events(
    events_json: String,
    relay_urls: Option<Vec<String>>,
) -> Result<String> {
    let client = get_client().await?;
    let events: Vec<serde_json::Value> = serde_json::from_str(&events_json)?;

    let mut total_success = 0u32;
    let mut total_failed = 0u32;

    let target_urls: Option<Vec<RelayUrl>> = relay_urls.map(|urls| {
        urls.iter()
            .filter_map(|u| RelayUrl::parse(u).ok())
            .collect()
    });

    if let Some(ref urls) = target_urls {
        let add_futures: Vec<_> = urls.iter().map(|url| client.add_relay(url.as_str())).collect();
        futures::future::join_all(add_futures).await;
        client.connect().await;
    }

    for event_val in &events {
        let event_str = event_val.to_string();
        if let Ok(event) = Event::from_json(&event_str) {
            let send_result = if let Some(ref urls) = target_urls {
                client.send_event_to(urls.clone(), &event).await
            } else {
                client.send_event(&event).await
            };

            match send_result {
                Ok(output) => {
                    total_success += output.success.len() as u32;
                    total_failed += output.failed.len() as u32;
                }
                Err(_) => {
                    total_failed += 1;
                }
            }
        }
    }

    let result = serde_json::json!({
        "totalSuccess": total_success,
        "totalFailed": total_failed,
    });

    Ok(result.to_string())
}

pub async fn request_to_vanish(relay_urls: Vec<String>, reason: String) -> Result<String> {
    let client = get_client().await?;
    
    let tags: Vec<Tag> = if relay_urls.len() == 1 && relay_urls[0] == "ALL_RELAYS" {
        vec![Tag::custom(TagKind::Custom("relay".into()), vec!["ALL_RELAYS"])]
    } else {
        relay_urls.iter()
            .map(|url| Tag::custom(TagKind::Custom("relay".into()), vec![url.as_str()]))
            .collect()
    };

    let builder = EventBuilder::new(Kind::from(62), reason).tags(tags);
    let event = client.sign_event_builder(builder).await?;

    let ur = user_relays_state().read().await;
    let urls: Vec<RelayUrl> = if relay_urls.len() == 1 && relay_urls[0] == "ALL_RELAYS" {
        ur.iter()
            .filter_map(|u| RelayUrl::parse(u).ok())
            .collect()
    } else {
        relay_urls.iter()
            .filter_map(|u| RelayUrl::parse(u).ok())
            .collect()
    };
    drop(ur);

    let output = client.send_event_to(urls, &event).await?;

    let success_count = output.success.len();
    let failed_count = output.failed.len();

    let result = serde_json::json!({
        "id": output.id().to_hex(),
        "totalSuccess": success_count,
        "totalFailed": failed_count,
    });

    Ok(result.to_string())
}

pub async fn delete_events(event_ids: Vec<String>, reason: String) -> Result<String> {
    let client = get_client().await?;
    
    let event_tags: Vec<Tag> = event_ids
        .iter()
        .filter_map(|id| EventId::from_hex(id).ok())
        .map(|event_id| Tag::event(event_id))
        .collect();

    if event_tags.is_empty() {
        return Ok(serde_json::json!({
            "totalSuccess": 0,
            "totalFailed": 0,
        }).to_string());
    }

    let builder = EventBuilder::new(Kind::EventDeletion, reason).tags(event_tags);
    let event = client.sign_event_builder(builder).await?;

    let ur = user_relays_state().read().await;
    let urls: Vec<RelayUrl> = ur
        .iter()
        .filter_map(|u| RelayUrl::parse(u).ok())
        .collect();
    drop(ur);

    let output = client.send_event_to(urls, &event).await?;

    let success_count = output.success.len();
    let failed_count = output.failed.len();

    let result = serde_json::json!({
        "id": output.id().to_hex(),
        "totalSuccess": success_count,
        "totalFailed": failed_count,
    });

    Ok(result.to_string())
}

#[frb]
pub async fn subscribe_to_events(
    filter_json: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let client = get_client().await?;
    let filter = Filter::from_json(&filter_json)?;

    let Output { val: sub_id, .. } = client.subscribe(filter, None).await
        .map_err(|e| anyhow!("Subscribe failed: {}", e))?;

    let mut notifications = client.notifications();

    loop {
        match notifications.recv().await {
            Ok(notification) => {
                if let RelayPoolNotification::Event {
                    subscription_id,
                    event,
                    ..
                } = notification
                {
                    if subscription_id == sub_id {
                        if let Ok(json) = serde_json::to_string(
                            &serde_json::from_str::<serde_json::Value>(&event.as_json())
                                .unwrap_or_default(),
                        ) {
                            let _ = sink.add(json);
                        }
                    }
                } else if let RelayPoolNotification::Shutdown = notification {
                    break;
                }
            }
            Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
            Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
        }
    }

    Ok(())
}

pub async fn resolve_thread_root(note_id: String) -> Result<String> {
    let client = get_client().await?;
    let mut current_id = note_id.clone();
    let mut visited: HashSet<String> = HashSet::new();

    for _ in 0..15 {
        if visited.contains(&current_id) {
            break;
        }
        visited.insert(current_id.clone());

        let eid = EventId::from_hex(&current_id)?;
        let mut event = client.database().event_by_id(&eid).await.ok().flatten();

        if event.is_none() {
            let filter = Filter::new().id(eid).limit(1);
            let _ = client.fetch_events(filter, Duration::from_secs(5)).await;
            event = client.database().event_by_id(&eid).await.ok().flatten();
            if event.is_none() {
                break;
            }
        }

        let ev = event.unwrap();
        let mut root_id: Option<String> = None;
        let mut parent_id: Option<String> = None;

        for tag in ev.tags.iter() {
            let tag_kind = tag.kind();
            if !matches!(
                tag_kind,
                TagKind::SingleLetter(SingleLetterTag {
                    character: Alphabet::E,
                    ..
                })
            ) {
                continue;
            }
            if let Some(ref_id) = tag.content() {
                let tag_vec: Vec<String> =
                    tag.as_slice().iter().map(|s| s.to_string()).collect();
                let marker = tag_vec.get(3).map(|s| s.as_str());
                match marker {
                    Some("root") => {
                        root_id = Some(ref_id.to_string());
                        break;
                    }
                    Some("reply") => {
                        parent_id = Some(ref_id.to_string());
                    }
                    None if parent_id.is_none() => {
                        parent_id = Some(ref_id.to_string());
                    }
                    _ => {}
                }
            }
        }

        if let Some(rid) = root_id {
            if !rid.is_empty() {
                let root_eid = EventId::from_hex(&rid)?;
                if client
                    .database()
                    .event_by_id(&root_eid)
                    .await
                    .ok()
                    .flatten()
                    .is_none()
                {
                    let f = Filter::new().id(root_eid).limit(1);
                    let _ = client.fetch_events(f, Duration::from_secs(5)).await;
                }
                return Ok(rid);
            }
        }

        if let Some(pid) = parent_id {
            if !pid.is_empty() && pid != current_id {
                current_id = pid;
                continue;
            }
        }

        break;
    }

    Ok(current_id)
}

pub async fn sync_replies_recursive(
    note_id: String,
    max_depth: u32,
) -> Result<u32> {
    let client = get_client().await?;
    let mut processed_ids: HashSet<String> = HashSet::new();
    processed_ids.insert(note_id.clone());
    let mut pending_ids: Vec<EventId> = vec![EventId::from_hex(&note_id)?];
    let mut total_fetched: u32 = 0;

    for _ in 0..max_depth {
        if pending_ids.is_empty() {
            break;
        }

        let filter = Filter::new()
            .kind(Kind::TextNote)
            .events(pending_ids.clone())
            .limit(200);

        let events: Events = client
            .fetch_events(filter, Duration::from_secs(8))
            .await?;

        let mut new_ids: Vec<EventId> = Vec::new();
        for event in events.iter() {
            let eid_hex = event.id.to_hex();
            if !processed_ids.contains(&eid_hex) {
                processed_ids.insert(eid_hex);
                new_ids.push(event.id);
                total_fetched += 1;
            }
        }

        pending_ids = new_ids;
        if total_fetched > 500 {
            break;
        }
    }

    let all_pubkeys: HashSet<PublicKey> = {
        let mut pks = HashSet::new();
        for id_hex in &processed_ids {
            if let Ok(eid) = EventId::from_hex(id_hex) {
                if let Ok(Some(ev)) = client.database().event_by_id(&eid).await {
                    pks.insert(ev.pubkey);
                }
            }
        }
        pks
    };

    if !all_pubkeys.is_empty() {
        let existing_filter = Filter::new()
            .authors(all_pubkeys.iter().cloned().collect::<Vec<_>>())
            .kind(Kind::Metadata)
            .limit(all_pubkeys.len());
        let existing = client.database().query(existing_filter.clone()).await?;
        let existing_pks: HashSet<PublicKey> =
            existing.iter().map(|e| e.pubkey).collect();
        let missing: Vec<PublicKey> = all_pubkeys
            .into_iter()
            .filter(|pk| !existing_pks.contains(pk))
            .collect();

        if !missing.is_empty() {
            let profile_filter = Filter::new()
                .authors(missing)
                .kind(Kind::Metadata)
                .limit(200);
            let _ = client
                .fetch_events(profile_filter, Duration::from_secs(5))
                .await;
        }
    }

    Ok(total_fetched)
}

pub async fn build_thread_structure(
    root_note_json: String,
    replies_json: String,
) -> Result<String> {
    let root: serde_json::Value = serde_json::from_str(&root_note_json)?;
    let replies: Vec<serde_json::Value> = serde_json::from_str(&replies_json)?;

    let root_id = root["id"].as_str().unwrap_or("").to_string();
    let mut notes_map: HashMap<String, serde_json::Value> = HashMap::new();
    notes_map.insert(root_id.clone(), root.clone());
    let mut reply_ids: HashSet<String> = HashSet::new();

    for reply in &replies {
        let rid = reply["id"].as_str().unwrap_or("").to_string();
        if !rid.is_empty() {
            notes_map.insert(rid.clone(), reply.clone());
            reply_ids.insert(rid);
        }
    }

    let mut children_map: HashMap<String, Vec<serde_json::Value>> = HashMap::new();

    for reply in &replies {
        let reply_id = reply["id"].as_str().unwrap_or("").to_string();
        if reply_id.is_empty() {
            continue;
        }

        let mut parent = reply["parentId"]
            .as_str()
            .filter(|s| !s.is_empty())
            .map(|s| s.to_string());

        let reply_root = reply["rootId"]
            .as_str()
            .filter(|s| !s.is_empty())
            .map(|s| s.to_string());

        if parent.is_none() {
            if let Some(ref rr) = reply_root {
                if *rr == root_id
                    || reply_ids.contains(rr)
                    || notes_map.contains_key(rr)
                {
                    parent = Some(rr.clone());
                } else {
                    parent = Some(root_id.clone());
                }
            }
        }

        let parent = parent.unwrap_or_else(|| root_id.clone());

        let parent = if parent != root_id
            && !reply_ids.contains(&parent)
            && !notes_map.contains_key(&parent)
        {
            root_id.clone()
        } else {
            parent
        };

        children_map
            .entry(parent)
            .or_default()
            .push(reply.clone());
    }

    for children in children_map.values_mut() {
        children.sort_by(|a, b| {
            let at = a["created_at"].as_i64().unwrap_or(0);
            let bt = b["created_at"].as_i64().unwrap_or(0);
            at.cmp(&bt)
        });
    }

    let result = serde_json::json!({
        "rootNote": root,
        "childrenMap": children_map,
        "notesMap": notes_map,
        "totalReplies": replies.len(),
    });

    Ok(serde_json::to_string(&result)?)
}

pub async fn fetch_missing_references(event_ids: Vec<String>) -> Result<u32> {
    let client = get_client().await?;

    let own_ids: HashSet<String> = event_ids.iter().cloned().collect();
    let mut ref_ids: HashSet<String> = HashSet::new();

    for id_hex in &event_ids {
        let eid = match EventId::from_hex(id_hex) {
            Ok(e) => e,
            Err(_) => continue,
        };
        let event = match client.database().event_by_id(&eid).await {
            Ok(Some(e)) => e,
            _ => continue,
        };

        for tag in event.tags.iter() {
            let tag_vec: Vec<String> =
                tag.as_slice().iter().map(|s| s.to_string()).collect();
            let tag_type = tag_vec.first().map(|s| s.as_str());
            let ref_id = tag_vec.get(1).cloned().unwrap_or_default();
            if ref_id.is_empty() || own_ids.contains(&ref_id) {
                continue;
            }
            match tag_type {
                Some("q") => {
                    ref_ids.insert(ref_id);
                }
                Some("e") => {
                    let marker = tag_vec.get(3).map(|s| s.as_str());
                    if marker == Some("mention") || marker.is_none() {
                        ref_ids.insert(ref_id);
                    }
                }
                _ => {}
            }
        }
    }

    if ref_ids.is_empty() {
        return Ok(0);
    }

    let mut missing_ids: Vec<EventId> = Vec::new();
    for ref_hex in &ref_ids {
        if let Ok(eid) = EventId::from_hex(ref_hex) {
            let status = client.database().check_id(&eid).await;
            if !matches!(status, Ok(DatabaseEventStatus::Saved)) {
                missing_ids.push(eid);
            }
        }
    }

    if missing_ids.is_empty() {
        return Ok(0);
    }

    if missing_ids.len() > 30 {
        missing_ids.truncate(30);
    }

    let filter = Filter::new().ids(missing_ids.clone()).limit(30);
    let fetched: Events = client
        .fetch_events(filter, Duration::from_secs(5))
        .await?;

    let fetched_count = fetched.len() as u32;

    if fetched_count > 0 {
        let mut missing_pks: HashSet<PublicKey> = HashSet::new();
        for ev in fetched.iter() {
            let pk_filter = Filter::new()
                .author(ev.pubkey)
                .kind(Kind::Metadata)
                .limit(1);
            let profile = client.database().query(pk_filter).await?;
            if profile.is_empty() {
                missing_pks.insert(ev.pubkey);
            }
        }

        if !missing_pks.is_empty() {
            let profile_filter = Filter::new()
                .authors(missing_pks.into_iter().collect::<Vec<_>>())
                .kind(Kind::Metadata)
                .limit(50);
            let _ = client
                .fetch_events(profile_filter, Duration::from_secs(5))
                .await;
        }
    }

    Ok(fetched_count)
}

pub async fn merge_and_sort_notes(
    existing_json: String,
    incoming_json: String,
) -> Result<String> {
    let existing: Vec<serde_json::Value> = serde_json::from_str(&existing_json)?;
    let incoming: Vec<serde_json::Value> = serde_json::from_str(&incoming_json)?;

    let mut seen: HashSet<String> = HashSet::new();
    let mut merged: Vec<serde_json::Value> = Vec::new();

    for note in incoming.into_iter().chain(existing.into_iter()) {
        let id = note["id"].as_str().unwrap_or("").to_string();
        if id.is_empty() || seen.contains(&id) {
            continue;
        }
        seen.insert(id);
        merged.push(note);
    }

    merged.sort_by(|a, b| {
        let at = a["repostCreatedAt"]
            .as_i64()
            .or_else(|| a["created_at"].as_i64())
            .unwrap_or(0);
        let bt = b["repostCreatedAt"]
            .as_i64()
            .or_else(|| b["created_at"].as_i64())
            .unwrap_or(0);
        bt.cmp(&at)
    });

    Ok(serde_json::to_string(&merged)?)
}

pub async fn get_database_size_mb() -> Result<u64> {
    let db_path_lock = db_path_state().read().await;
    
    if let Some(path) = db_path_lock.as_ref() {
        // LMDB data.mdb dosyasının boyutunu kontrol et
        let data_file = format!("{}/data.mdb", path);
        
        match fs::metadata(&data_file) {
            Ok(metadata) => {
                let size_bytes = metadata.len();
                let size_mb = size_bytes / (1024 * 1024);
                Ok(size_mb)
            }
            Err(_) => Ok(0),
        }
    } else {
        Ok(0)
    }
}
