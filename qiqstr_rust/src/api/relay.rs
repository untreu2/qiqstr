use std::collections::{HashMap, HashSet};
use std::path::Path;
use std::sync::{Arc, OnceLock};
use std::time::Duration;

use anyhow::{anyhow, Result};
use nostr::prelude::*;
use tokio::sync::RwLock;

use super::crypto::Secret;
use crate::pool::{
    is_public_secure_relay, NostrClient, PublishOutput, RelayStatus, SubNotification, FLAG_AUTH,
    FLAG_READ, FLAG_WRITE,
};
use crate::sink::StreamSink;
use crate::store::EventStore;

static CLIENT: OnceLock<RwLock<Option<NostrClient>>> = OnceLock::new();
static USER_RELAYS: OnceLock<RwLock<Vec<String>>> = OnceLock::new();
static DB_PATH: OnceLock<RwLock<Option<String>>> = OnceLock::new();

fn state() -> &'static RwLock<Option<NostrClient>> {
    CLIENT.get_or_init(|| RwLock::new(None))
}

fn user_relays_state() -> &'static RwLock<Vec<String>> {
    USER_RELAYS.get_or_init(|| RwLock::new(Vec::new()))
}

pub(crate) fn db_path_state() -> &'static RwLock<Option<String>> {
    DB_PATH.get_or_init(|| RwLock::new(None))
}

async fn get_client() -> Result<NostrClient> {
    let lock = state().read().await;
    lock.as_ref()
        .cloned()
        .ok_or_else(|| anyhow!("Client not initialized"))
}

pub(crate) async fn get_client_pub() -> Result<NostrClient> {
    get_client().await
}

fn events_to_json(events: Vec<Event>) -> Result<String> {
    Ok(serde_json::to_string(&events)?)
}

pub(crate) async fn quick_fetch(
    client: &NostrClient,
    filter: Filter,
    timeout: Duration,
) -> Result<Vec<Event>> {
    client.fetch(filter, timeout, true).await
}

/// Fetches profiles the app has never seen, for display. Any version will do, so this does not
/// wait for every relay the way a lookup of one author's newest profile does.
async fn fetch_unseen_profiles(
    client: &NostrClient,
    authors: Vec<PublicKey>,
    limit: usize,
    timeout: Duration,
) -> Vec<Event> {
    let filter = Filter::new()
        .authors(authors)
        .kind(Kind::Metadata)
        .limit(limit);
    client
        .quick_fetch(filter, timeout, true)
        .await
        .unwrap_or_default()
}

pub async fn init_client(
    relay_urls: Vec<String>,
    private_key_hex: Option<String>,
    db_path: Option<String>,
    discovery_relays: Vec<String>,
) -> Result<()> {
    let private_key_hex = private_key_hex.map(Secret::new);
    let mut lock = state().write().await;
    for url in relay_urls.iter().chain(&discovery_relays) {
        RelayUrl::parse(url)?;
    }

    let signer = match private_key_hex {
        Some(sk_hex) => Some(Keys::parse(&sk_hex)?),
        None => None,
    };

    let store = if let Some(ref path) = db_path {
        let store = EventStore::open(Path::new(path))?;
        let marker = Path::new(path).join("replaceables_verified_v2");
        if !marker.exists() {
            store.remove_invalid_replaceable_events()?;
            let _ = std::fs::write(&marker, b"1");
        }
        Arc::new(store)
    } else {
        Arc::new(EventStore::open_in_memory()?)
    };

    let client = NostrClient::new(store, signer);
    client.automatic_authentication(true);

    for url in &relay_urls {
        let _ = client
            .add_relay_with_flags(url.as_str(), FLAG_READ | FLAG_WRITE | FLAG_AUTH)
            .await;
    }
    for url in &discovery_relays {
        let _ = client.add_discovery_relay(url.as_str()).await;
    }

    {
        let mut ur = user_relays_state().write().await;
        *ur = relay_urls;
    }

    if let Some(old_client) = lock.take() {
        old_client.unset_signer().await;
        old_client.shutdown().await;
    }
    *db_path_state().write().await = db_path;
    *lock = Some(client);

    Ok(())
}

pub async fn connect_relays() -> Result<()> {
    let client = get_client().await?;
    client.connect().await;
    Ok(())
}

pub async fn wait_for_ready(timeout_secs: u32) -> Result<u32> {
    let client = get_client().await?;
    let timeout = Duration::from_secs(timeout_secs as u64);
    Ok(client.wait_for_ready(timeout, 2).await)
}

pub async fn disconnect_relays() -> Result<()> {
    let client = get_client().await?;
    client.disconnect().await;
    Ok(())
}

pub async fn shutdown_client() -> Result<()> {
    let client = {
        let mut lock = state().write().await;
        user_relays_state().write().await.clear();
        *db_path_state().write().await = None;
        super::database::set_active_mute_list(Vec::new(), Vec::new());
        primal_socket().discard();
        lock.take()
    };
    if let Some(client) = client {
        client.unset_signer().await;
        client.shutdown().await;
    }
    Ok(())
}

pub async fn update_signer(private_key_hex: String) -> Result<()> {
    let private_key_hex = Secret::new(private_key_hex);
    let client = get_client().await?;
    client.set_signer(Keys::parse(&private_key_hex)?).await;
    Ok(())
}

pub async fn is_client_initialized() -> bool {
    let lock = state().read().await;
    lock.is_some()
}

pub async fn add_relay(url: String) -> Result<bool> {
    let client = get_client().await?;
    let added = client
        .add_relay_with_flags(&url, FLAG_READ | FLAG_WRITE | FLAG_AUTH)
        .await
        .is_ok();
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
    let mut flags = FLAG_AUTH;
    if read {
        flags |= FLAG_READ;
    }
    if write {
        flags |= FLAG_WRITE;
    }

    let added = client
        .add_relay_with_flags(relay_url.as_str(), flags)
        .await
        .is_ok();
    if added {
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
        .filter(|(_, r)| !r.is_discovery_only())
        .map(|(u, _)| u.to_string())
        .collect())
}

pub async fn get_connected_relay_count() -> Result<u32> {
    let client = get_client().await?;
    let relays = client.relays().await;
    let count = relays
        .values()
        .filter(|r| !r.is_discovery_only() && r.status() == RelayStatus::Connected)
        .count();
    Ok(count as u32)
}

pub async fn get_relay_status() -> Result<String> {
    let client = get_client().await?;
    let relays = client.relays().await;

    let mut relay_list = Vec::new();
    for (url, relay) in relays.iter() {
        let status = relay.status();
        let stats = relay.stats();
        let is_discovery = relay.is_discovery_only();

        let relay_info = serde_json::json!({
            "url": url.to_string(),
            "status": status.as_str(),
            "isDiscovery": is_discovery,
            "attempts": stats.attempts.load(std::sync::atomic::Ordering::Relaxed),
            "success": stats.success.load(std::sync::atomic::Ordering::Relaxed),
            "bytesSent": stats.bytes_sent.load(std::sync::atomic::Ordering::Relaxed),
            "bytesReceived": stats.bytes_received.load(std::sync::atomic::Ordering::Relaxed),
            "connectedAt": stats.connected_at_secs.load(std::sync::atomic::Ordering::Relaxed),
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

pub async fn stream_relay_status(sink: StreamSink<String>) -> Result<()> {
    let result: Result<()> = async {
        let mut interval = tokio::time::interval(Duration::from_millis(800));
        loop {
            interval.tick().await;
            let Ok(client) = get_client().await else {
                break;
            };
            let relays = client.relays().await;
            let mut relay_list = Vec::new();
            for (url, relay) in relays.iter() {
                let status = relay.status();
                let stats = relay.stats();
                let is_discovery = relay.is_discovery_only();

                let relay_info = serde_json::json!({
                    "url": url.to_string(),
                    "status": status.as_str(),
                    "isDiscovery": is_discovery,
                    "attempts": stats.attempts.load(std::sync::atomic::Ordering::Relaxed),
                    "success": stats.success.load(std::sync::atomic::Ordering::Relaxed),
                    "bytesSent": stats.bytes_sent.load(std::sync::atomic::Ordering::Relaxed),
                    "bytesReceived": stats.bytes_received.load(std::sync::atomic::Ordering::Relaxed),
                    "connectedAt": stats.connected_at_secs.load(std::sync::atomic::Ordering::Relaxed),
                    "latencyMs": stats.latency_ms(),
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

            if sink.add(result.to_string()).is_err() {
                break;
            }
        }
        Ok(())
    }
    .await;
    if let Err(error) = result {
        let _ = sink.add_error(error);
    }
    Ok(())
}

pub async fn discover_and_connect_outbox_relays(
    pubkeys_hex: Vec<String>,
    max_outbox_relays: usize,
    min_relay_frequency: usize,
) -> Result<String> {
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
        })
        .to_string());
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
            quick_fetch(&client, filter, Duration::from_secs(10))
        })
        .collect();

    let chunk_results = futures::future::join_all(chunk_futures).await;

    for events in chunk_results.into_iter().flatten() {
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
        .filter(|(_, (count, _, _))| *count >= min_relay_frequency)
        .map(|(url, (count, is_outbox, is_inbox))| (url, count, is_outbox, is_inbox))
        .collect();

    candidates.sort_by_key(|candidate| std::cmp::Reverse(candidate.1));
    candidates.truncate(max_outbox_relays);

    let discovered_count = candidates.len() as u32;
    let mut added_count: u32 = 0;

    let pooled: HashSet<RelayUrl> = client.relays().await.into_keys().collect();
    let parsed_candidates: Vec<_> = candidates
        .iter()
        .filter(|(_, _, is_outbox, _)| *is_outbox)
        .filter_map(|(url, _, is_outbox, is_inbox)| {
            RelayUrl::parse(url.as_str())
                .ok()
                .filter(|relay_url| {
                    is_public_secure_relay(relay_url) && !pooled.contains(relay_url)
                })
                .map(|relay_url| (relay_url, *is_outbox, *is_inbox))
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
                relay.remove_flag(FLAG_WRITE);
            }
            let _ = (is_outbox, is_inbox);
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

    let local_events = client.database().query(&filter).unwrap_or_default();
    let local_ids: HashSet<EventId> = local_events.iter().map(|e| e.id).collect();
    let local_count = local_ids.len();

    let fetched = client
        .fetch(filter, Duration::from_secs(8), true)
        .await
        .unwrap_or_default();
    let remote_count = fetched.len();
    let received_count = fetched
        .iter()
        .filter(|e| !local_ids.contains(&e.id))
        .count();

    let result = serde_json::json!({
        "received": received_count,
        "sent": 0,
        "local": local_count,
        "remote": remote_count,
    });

    Ok(result.to_string())
}

pub async fn fetch_events(filter_json: String, timeout_secs: u32) -> Result<String> {
    let client = get_client().await?;
    let filter = Filter::from_json(&filter_json)?;
    let timeout = Duration::from_secs(timeout_secs as u64);

    let events = quick_fetch(&client, filter, timeout)
        .await
        .unwrap_or_default();

    events_to_json(events)
}

const MAX_COUNTING_RELAYS: usize = 8;

async fn select_counting_relays(main_client: &NostrClient) -> Vec<RelayUrl> {
    let main_relays = main_client.relays().await;
    let user_relays: HashSet<String> = user_relays_state().read().await.iter().cloned().collect();

    let mut connected_user: Vec<RelayUrl> = Vec::new();
    let mut connected_other: Vec<RelayUrl> = Vec::new();
    let mut all_candidates: Vec<RelayUrl> = Vec::new();

    for (url, relay) in &main_relays {
        if !relay.has_flag(FLAG_READ) || relay.is_discovery_only() {
            continue;
        }
        let is_user = user_relays.contains(url.as_str());
        if relay.status() == RelayStatus::Connected {
            if is_user {
                connected_user.push(url.clone());
            } else {
                connected_other.push(url.clone());
            }
        }
        if is_user {
            all_candidates.push(url.clone());
        }
    }

    let mut connected = connected_user;
    connected.extend(connected_other);
    if connected.len() >= 2 {
        connected.truncate(MAX_COUNTING_RELAYS);
        return connected;
    }

    for (url, relay) in &main_relays {
        if all_candidates.len() >= MAX_COUNTING_RELAYS {
            break;
        }
        if relay.has_flag(FLAG_READ) && !relay.is_discovery_only() && !all_candidates.contains(url)
        {
            all_candidates.push(url.clone());
        }
    }
    all_candidates.truncate(MAX_COUNTING_RELAYS);
    all_candidates
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

    let counting_urls = select_counting_relays(&main_client).await;

    let filter = Filter::new()
        .kinds([
            Kind::Reaction,
            Kind::Repost,
            Kind::ZapReceipt,
            Kind::TextNote,
        ])
        .events(ids)
        .limit(500);

    let timeout = Duration::from_secs(5);
    let events = if counting_urls.is_empty() {
        main_client
            .quick_fetch(filter, timeout, false)
            .await
            .unwrap_or_default()
    } else {
        main_client
            .fetch_events_from(&counting_urls, filter, timeout, false)
            .await
            .unwrap_or_default()
    };

    let mut counts: HashMap<String, [usize; 4]> = HashMap::new();
    let mut user_reacted: HashMap<String, bool> = HashMap::new();
    let mut user_reposted: HashMap<String, bool> = HashMap::new();
    let mut counted_events: HashMap<String, HashSet<String>> = HashMap::new();

    for nid in &note_ids {
        counts.insert(nid.clone(), [0; 4]);
        user_reacted.insert(nid.clone(), false);
        user_reposted.insert(nid.clone(), false);
        counted_events.insert(nid.clone(), HashSet::new());
    }

    for event in events.iter() {
        let kind = event.kind;
        let event_id_hex = event.id.to_hex();
        let is_user = user_pk.as_ref().is_some_and(|pk| event.pubkey == *pk);
        let zap_sats = if kind == Kind::ZapReceipt {
            super::database::extract_zap_amount_sats(event) as usize
        } else {
            0
        };

        if kind == Kind::TextNote {
            if let Some(parent_id) = super::database::extract_reply_parent_id(event) {
                if let Some(c) = counts.get_mut(&parent_id) {
                    let seen = counted_events.get_mut(&parent_id).unwrap();
                    if seen.insert(event_id_hex.clone()) {
                        c[3] += 1;
                    }
                }
            }
            continue;
        }

        let target = super::database::extract_first_e_tag(event);
        if let Some(target_id) = target {
            if let Some(c) = counts.get_mut(&target_id) {
                let seen = counted_events.get_mut(&target_id).unwrap();
                if seen.insert(event_id_hex) {
                    match kind {
                        Kind::Reaction => {
                            c[0] += 1;
                            if is_user {
                                user_reacted.insert(target_id, true);
                            }
                        }
                        Kind::Repost => {
                            c[1] += 1;
                            if is_user {
                                user_reposted.insert(target_id, true);
                            }
                        }
                        Kind::ZapReceipt => c[2] += zap_sats,
                        _ => {}
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

pub async fn stream_interaction_counts(
    note_ids: Vec<String>,
    user_pubkey_hex: Option<String>,
    sink: StreamSink<String>,
) -> Result<()> {
    let result: Result<()> = async {
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

        let counting_urls = select_counting_relays(&main_client).await;
        let targets = if counting_urls.is_empty() {
            None
        } else {
            Some(counting_urls.as_slice())
        };

        let filter = Filter::new()
            .kinds([
                Kind::Reaction,
                Kind::Repost,
                Kind::ZapReceipt,
                Kind::TextNote,
            ])
            .events(ids);

        let (sub_id, mut notifications, relay_count) = main_client
            .subscribe_on(filter, targets)
            .await
            .map_err(|e| anyhow!("Subscribe failed: {}", e))?;

        let mut counts: HashMap<String, [usize; 4]> = HashMap::new();
        let mut user_reacted: HashMap<String, bool> = HashMap::new();
        let mut user_reposted: HashMap<String, bool> = HashMap::new();
        let mut seen_events: HashSet<String> = HashSet::new();

        for nid in &note_ids {
            counts.insert(nid.clone(), [0; 4]);
            user_reacted.insert(nid.clone(), false);
            user_reposted.insert(nid.clone(), false);
        }

        let mut finished_relays: usize = 0;
        let mut last_emit = std::time::Instant::now();
        let mut has_data = false;

        loop {
            let recv = tokio::time::timeout(Duration::from_secs(3), notifications.recv()).await;

            match recv {
                Ok(Some(notification)) => match notification {
                    SubNotification::Event { event } => {
                        let event_id = event.id.to_hex();
                        if !seen_events.insert(event_id) {
                            continue;
                        }

                        let kind = event.kind;
                        let is_user = user_pk.as_ref().is_some_and(|pk| event.pubkey == *pk);
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
                                            Kind::Reaction => {
                                                c[0] += 1;
                                                if is_user {
                                                    user_reacted.insert(ref_hex, true);
                                                }
                                            }
                                            Kind::Repost => {
                                                c[1] += 1;
                                                if is_user {
                                                    user_reposted.insert(ref_hex, true);
                                                }
                                            }
                                            Kind::ZapReceipt => {
                                                c[2] += zap_sats;
                                            }
                                            Kind::TextNote => {
                                                c[3] += 1;
                                            }
                                            _ => {}
                                        }
                                    }
                                }
                            }
                        }

                        if has_data && last_emit.elapsed() >= Duration::from_millis(250) {
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
                    SubNotification::Eose | SubNotification::Closed { .. } => {
                        finished_relays += 1;
                        if finished_relays >= relay_count {
                            break;
                        }
                    }
                },
                Ok(None) | Err(_) => break,
            }
        }

        if has_data {
            let json = build_counts_json(&counts, &note_ids, &user_reacted, &user_reposted);
            let _ = sink.add(json);
        }

        main_client.unsubscribe(&sub_id).await;
        Ok(())
    }
    .await;
    if let Err(error) = result {
        let _ = sink.add_error(error);
    }
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

    let events = quick_fetch(&client, filter, timeout).await?;

    if let Some(event) = events.into_iter().next() {
        Ok(Some(event.as_json()))
    } else {
        Ok(None)
    }
}

pub async fn fetch_events_by_ids(event_ids: Vec<String>, timeout_secs: u32) -> Result<String> {
    let client = get_client().await?;
    let ids: Vec<EventId> = event_ids
        .iter()
        .filter_map(|id| EventId::from_hex(id).ok())
        .collect();

    if ids.is_empty() {
        return Ok("[]".to_string());
    }

    let filter = Filter::new().ids(ids);
    let timeout = Duration::from_secs(timeout_secs as u64);
    let events = quick_fetch(&client, filter, timeout)
        .await
        .unwrap_or_default();

    events_to_json(events)
}

pub async fn fetch_events_multi_filter(filters_json: String, timeout_secs: u32) -> Result<String> {
    let client = get_client().await?;
    let filters: Vec<Filter> = match serde_json::from_str::<Vec<Filter>>(&filters_json) {
        Ok(f) => f,
        Err(_) => {
            let raw: Vec<serde_json::Value> = serde_json::from_str(&filters_json)?;
            raw.into_iter()
                .filter_map(|v| serde_json::from_value::<Filter>(v).ok())
                .collect()
        }
    };

    if filters.is_empty() {
        return Ok("[]".to_string());
    }

    let timeout = Duration::from_secs(timeout_secs as u64);

    let mut handles = Vec::with_capacity(filters.len());
    for filter in filters {
        let c = client.clone();
        handles.push(tokio::spawn(async move {
            quick_fetch(&c, filter, timeout).await.unwrap_or_default()
        }));
    }

    let mut seen: HashSet<EventId> = HashSet::new();
    let mut events_out: Vec<Event> = Vec::new();

    for handle in handles {
        if let Ok(events) = handle.await {
            for e in events.into_iter() {
                if seen.insert(e.id) {
                    events_out.push(e);
                }
            }
        }
    }

    Ok(serde_json::to_string(&events_out)?)
}

async fn publish_event(
    client: &NostrClient,
    event: &Event,
    targets: Option<&[RelayUrl]>,
) -> Result<PublishOutput> {
    client.publish_event(event, targets).await
}

fn published_event_json(output: PublishOutput) -> Result<String> {
    if output.success.is_empty() {
        return Err(anyhow!("No relay accepted the event: {:?}", output.failed));
    }
    let success: Vec<String> = output.success.iter().map(ToString::to_string).collect();
    let failed: HashMap<String, String> = output
        .failed
        .iter()
        .map(|(url, error)| (url.to_string(), error.to_string()))
        .collect();
    Ok(
        serde_json::json!({ "id": output.id.to_hex(), "success": success, "failed": failed })
            .to_string(),
    )
}

pub async fn send_event(event_json: String) -> Result<String> {
    let client = get_client().await?;
    let event = Event::from_json(&event_json)?;
    let output = publish_event(&client, &event, None).await?;
    published_event_json(output)
}

/// A short-lived client for relays outside the main pool. It holds the account's key so relays
/// that require NIP-42 auth accept what the account is entitled to, under the pool's rules: a
/// relay the account configured is answered whenever it asks, and any other public relay only
/// when it refuses a publish, a relay-hosted group request, or a read of the account's inbox.
async fn temporary_client() -> NostrClient {
    let signer = match get_client().await {
        Ok(main) => main.signer().await.ok(),
        Err(_) => None,
    };
    let client = NostrClient::in_memory(signer);
    client.automatic_authentication(true);
    client
}

async fn add_temporary_relays(client: &NostrClient, urls: &[RelayUrl]) {
    let configured: HashSet<RelayUrl> = user_relays_state()
        .read()
        .await
        .iter()
        .filter_map(|url| RelayUrl::parse(url).ok())
        .collect();
    for url in urls {
        let trust = if configured.contains(url) {
            FLAG_AUTH
        } else {
            0
        };
        let _ = client
            .add_relay_with_flags(url.as_str(), FLAG_READ | FLAG_WRITE | trust)
            .await;
    }
}

/// Forwards a live subscription until the consumer leaves or every relay it reached has
/// refused it.
async fn forward_subscription(
    client: &NostrClient,
    sub_id: &str,
    mut notifications: tokio::sync::mpsc::Receiver<SubNotification>,
    sink: &StreamSink<String>,
    save: bool,
) -> Result<()> {
    let mut refused_by: HashSet<RelayUrl> = HashSet::new();
    let mut liveness = tokio::time::interval(Duration::from_secs(2));
    loop {
        let received = tokio::select! {
            received = notifications.recv() => received,
            _ = liveness.tick() => {
                if sink.is_closed() {
                    return Ok(());
                }
                continue;
            }
        };
        match received {
            Some(SubNotification::Event { event }) => {
                if save {
                    let _ = client.database().save_event(&event);
                }
                if sink.add(event.as_json()).is_err() {
                    return Ok(());
                }
            }
            Some(SubNotification::Closed { relay, message }) => {
                refused_by.insert(relay);
                if refused_by.len() >= client.subscription_relay_count(sub_id).max(1) {
                    let reason = if message.is_empty() {
                        "no reason given".to_string()
                    } else {
                        message
                    };
                    return Err(anyhow!("Subscription closed by relay: {reason}"));
                }
            }
            Some(SubNotification::Eose) => {}
            None => return Ok(()),
        }
    }
}

struct TargetPool {
    main: NostrClient,
    pooled: Vec<RelayUrl>,
    extra: Option<(NostrClient, Vec<RelayUrl>)>,
}

const MAX_TARGET_RELAYS: usize = 12;

impl TargetPool {
    async fn new(main: &NostrClient, urls: &[RelayUrl]) -> TargetPool {
        let existing: HashSet<RelayUrl> = main.relays().await.into_keys().collect();
        let mut pooled = Vec::new();
        let mut fresh = Vec::new();
        for url in urls.iter().take(MAX_TARGET_RELAYS) {
            if existing.contains(url) {
                pooled.push(url.clone());
            } else if url.as_str().starts_with("wss://") {
                fresh.push(url.clone());
            }
        }
        let extra = if fresh.is_empty() {
            None
        } else {
            let temp = temporary_client().await;
            add_temporary_relays(&temp, &fresh).await;
            temp.connect().await;
            temp.wait_for_ready(Duration::from_secs(3), fresh.len().min(2))
                .await;
            Some((temp, fresh))
        };
        TargetPool {
            main: main.clone(),
            pooled,
            extra,
        }
    }

    async fn publish(&self, event: &Event) -> Result<PublishOutput> {
        let mut output = PublishOutput {
            id: event.id,
            success: HashSet::new(),
            failed: HashMap::new(),
        };
        if !self.pooled.is_empty() {
            if let Ok(result) = publish_event(&self.main, event, Some(&self.pooled)).await {
                output.success.extend(result.success);
                output.failed.extend(result.failed);
            }
        }
        if let Some((temp, urls)) = &self.extra {
            if let Ok(result) = publish_event(temp, event, Some(urls)).await {
                output.success.extend(result.success);
                output.failed.extend(result.failed);
            }
        }
        if output.success.is_empty() && output.failed.is_empty() {
            return Err(anyhow!("No publication relays configured"));
        }
        if !output.success.is_empty() {
            let _ = self.main.database().save_event(event);
        }
        Ok(output)
    }

    async fn close(self) {
        if let Some((temp, _)) = self.extra {
            temp.shutdown().await;
        }
    }
}

pub async fn send_event_to(event_json: String, relay_urls: Vec<String>) -> Result<String> {
    let client = get_client().await?;
    let event = Event::from_json(&event_json)?;
    event.verify()?;
    let urls: Vec<RelayUrl> = relay_urls
        .iter()
        .map(|url| RelayUrl::parse(url))
        .collect::<std::result::Result<_, _>>()?;
    let pool = TargetPool::new(&client, &urls).await;
    let output = pool.publish(&event).await;
    pool.close().await;
    published_event_json(output?)
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

    let pool = match target_urls {
        Some(ref urls) => Some(TargetPool::new(&client, urls).await),
        None => None,
    };

    for event_val in &events {
        let event_str = event_val.to_string();
        if let Ok(event) = Event::from_json(&event_str) {
            let send_result = if let Some(ref pool) = pool {
                pool.publish(&event).await
            } else {
                publish_event(&client, &event, None).await
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

    if let Some(pool) = pool {
        pool.close().await;
    }

    let result = serde_json::json!({
        "totalSuccess": total_success,
        "totalFailed": total_failed,
    });

    Ok(result.to_string())
}

pub async fn stream_broadcast_events(
    events_json: String,
    relay_urls: Option<Vec<String>>,
    sink: StreamSink<String>,
) -> Result<()> {
    let result: Result<()> = async {
        let client = get_client().await?;
        let events: Vec<serde_json::Value> = serde_json::from_str(&events_json)?;
        let total = events.len() as u32;

        let target_urls: Option<Vec<RelayUrl>> = relay_urls.map(|urls| {
            urls.iter()
                .filter_map(|u| RelayUrl::parse(u).ok())
                .collect()
        });

        let pool = match target_urls {
            Some(ref urls) => Some(std::sync::Arc::new(TargetPool::new(&client, urls).await)),
            None => None,
        };

        let mut sent = 0u32;
        let mut failed = 0u32;

        const BATCH_SIZE: usize = 50;

        for chunk in events.chunks(BATCH_SIZE) {
            let futures: Vec<_> = chunk
                .iter()
                .map(|event_val| {
                    let client = client.clone();
                    let pool = pool.clone();
                    let event_str = event_val.to_string();
                    async move {
                        let Ok(event) = Event::from_json(&event_str) else {
                            return false;
                        };
                        let result = if let Some(ref pool) = pool {
                            pool.publish(&event).await
                        } else {
                            publish_event(&client, &event, None).await
                        };
                        match result {
                            Ok(output) => !output.success.is_empty(),
                            Err(_) => false,
                        }
                    }
                })
                .collect();

            let results = futures::future::join_all(futures).await;

            for ok in results {
                if ok {
                    sent += 1;
                } else {
                    failed += 1;
                }
            }

            let progress = serde_json::json!({
                "sent": sent,
                "failed": failed,
                "total": total,
                "done": false,
            });
            if sink.add(progress.to_string()).is_err() {
                break;
            }
        }

        if let Some(pool) = pool.and_then(|pool| std::sync::Arc::try_unwrap(pool).ok()) {
            pool.close().await;
        }

        let done = serde_json::json!({
            "sent": sent,
            "failed": failed,
            "total": total,
            "done": true,
        });
        let _ = sink.add(done.to_string());

        Ok(())
    }
    .await;
    if let Err(error) = result {
        let _ = sink.add_error(error);
    }
    Ok(())
}

pub async fn request_to_vanish(relay_urls: Vec<String>, reason: String) -> Result<String> {
    let client = get_client().await?;

    let tags: Vec<Tag> = if relay_urls.len() == 1 && relay_urls[0] == "ALL_RELAYS" {
        vec![Tag::custom(
            TagKind::Custom("relay".into()),
            vec!["ALL_RELAYS"],
        )]
    } else {
        relay_urls
            .iter()
            .map(|url| Tag::custom(TagKind::Custom("relay".into()), vec![url.as_str()]))
            .collect()
    };

    let builder = EventBuilder::new(Kind::from(62), reason).tags(tags);
    let event = client.sign_event_builder(builder).await?;

    let ur = user_relays_state().read().await;
    let urls: Vec<RelayUrl> = if relay_urls.len() == 1 && relay_urls[0] == "ALL_RELAYS" {
        ur.iter().filter_map(|u| RelayUrl::parse(u).ok()).collect()
    } else {
        relay_urls
            .iter()
            .filter_map(|u| RelayUrl::parse(u).ok())
            .collect()
    };
    drop(ur);

    let output = publish_event(&client, &event, Some(&urls)).await?;

    let success_count = output.success.len();
    let failed_count = output.failed.len();

    let result = serde_json::json!({
        "id": output.id.to_hex(),
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
        .map(Tag::event)
        .collect();

    if event_tags.is_empty() {
        return Ok(serde_json::json!({
            "totalSuccess": 0,
            "totalFailed": 0,
        })
        .to_string());
    }

    let builder = EventBuilder::new(Kind::EventDeletion, reason).tags(event_tags);
    let event = client.sign_event_builder(builder).await?;

    let ur = user_relays_state().read().await;
    let urls: Vec<RelayUrl> = ur.iter().filter_map(|u| RelayUrl::parse(u).ok()).collect();
    drop(ur);

    let output = publish_event(&client, &event, Some(&urls)).await?;

    let success_count = output.success.len();
    let failed_count = output.failed.len();

    let result = serde_json::json!({
        "id": output.id.to_hex(),
        "totalSuccess": success_count,
        "totalFailed": failed_count,
    });

    Ok(result.to_string())
}

pub async fn fetch_all_events_for_author(
    author_hex: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let result: Result<()> = async {
        let client = get_client().await?;
        let pubkey = PublicKey::from_hex(&author_hex)?;

        const PAGE_SIZE: usize = 500;
        let mut seen: HashSet<String> = HashSet::new();

        // Collect read-capable relay URLs
        let relay_urls: Vec<RelayUrl> = {
            let relays = client.relays().await;
            relays
                .iter()
                .filter(|(_, r)| !r.is_discovery_only())
                .map(|(u, _)| u.clone())
                .collect()
        };

        if relay_urls.is_empty() {
            return Ok(());
        }

        // Per-relay `until` cursor (unix secs). None = start from now.
        let mut cursors: HashMap<String, u64> = HashMap::new();
        // Relays that returned 0 new events on the last page are done.
        let mut exhausted: HashSet<String> = HashSet::new();

        loop {
            let active: Vec<&RelayUrl> = relay_urls
                .iter()
                .filter(|u| !exhausted.contains(u.as_str()))
                .collect();

            if active.is_empty() {
                break;
            }

            // Query each active relay individually so we can track per-relay cursors.
            for relay_url in active {
                let key = relay_url.to_string();
                let until_ts = cursors.get(&key).copied();

                let mut filter = Filter::new().author(pubkey).limit(PAGE_SIZE);
                if let Some(ts) = until_ts {
                    filter = filter.until(Timestamp::from(ts));
                }

                let events = match client
                    .fetch_events_from(
                        std::slice::from_ref(relay_url),
                        filter,
                        Duration::from_secs(15),
                        false,
                    )
                    .await
                {
                    Ok(e) => e,
                    Err(_) => {
                        exhausted.insert(key);
                        continue;
                    }
                };

                let mut new_count = 0usize;
                let mut oldest_ts: Option<u64> = None;

                for event in events.into_iter() {
                    let id_hex = event.id.to_hex();
                    if seen.contains(&id_hex) {
                        continue;
                    }
                    seen.insert(id_hex);
                    new_count += 1;

                    let ts = event.created_at.as_secs();
                    oldest_ts = Some(match oldest_ts {
                        None => ts,
                        Some(prev) => prev.min(ts),
                    });

                    if sink.add(event.as_json()).is_err() {
                        return Ok(());
                    }
                }

                if new_count == 0 {
                    // Relay truly has nothing older — done with this relay.
                    exhausted.insert(key);
                } else if let Some(oldest) = oldest_ts {
                    if oldest == 0 {
                        exhausted.insert(key);
                    } else {
                        // Advance the cursor back one second and fetch the next page.
                        cursors.insert(key, oldest - 1);
                    }
                } else {
                    exhausted.insert(key);
                }
            }
        }

        Ok(())
    }
    .await;
    if let Err(error) = result {
        let _ = sink.add_error(error);
    }
    Ok(())
}

pub async fn fetch_profile_events(
    author_hex: String,
    kinds_str: String,
    since_timestamp: i64,
    sink: StreamSink<String>,
) -> Result<()> {
    let result: Result<()> = async {
        let client = get_client().await?;
        let pubkey = PublicKey::from_hex(&author_hex)?;

        let kind_list: Vec<Kind> = kinds_str
            .split(',')
            .filter_map(|s| s.trim().parse::<u16>().ok())
            .map(Kind::from)
            .collect();

        if kind_list.is_empty() {
            return Ok(());
        }

        const PAGE_SIZE: usize = 200;
        let max_rounds = if since_timestamp > 0 { 10 } else { 2 };
        let mut round = 0;
        let sink_closed = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
        let seen = std::sync::Arc::new(tokio::sync::Mutex::new(HashSet::<String>::new()));

        let relay_urls: Vec<RelayUrl> = {
            let relays = client.relays().await;
            relays
                .iter()
                .filter(|(_, r)| !r.is_discovery_only())
                .map(|(u, _)| u.clone())
                .collect()
        };

        if relay_urls.is_empty() {
            return Ok(());
        }

        let since_ts = if since_timestamp > 0 {
            Some(Timestamp::from(since_timestamp as u64))
        } else {
            None
        };

        let cursors = std::sync::Arc::new(tokio::sync::Mutex::new(HashMap::<String, u64>::new()));
        let exhausted = std::sync::Arc::new(tokio::sync::Mutex::new(HashSet::<String>::new()));
        let sink = std::sync::Arc::new(sink.clone());

        loop {
            let active: Vec<RelayUrl> = {
                let ex = exhausted.lock().await;
                relay_urls
                    .iter()
                    .filter(|u| !ex.contains(u.as_str()))
                    .cloned()
                    .collect()
            };

            if active.is_empty()
                || round >= max_rounds
                || sink_closed.load(std::sync::atomic::Ordering::Relaxed)
            {
                break;
            }
            round += 1;

            let mut handles = Vec::new();
            for relay_url in active {
                let client = client.clone();
                let kind_list = kind_list.clone();
                let seen = seen.clone();
                let cursors = cursors.clone();
                let exhausted = exhausted.clone();
                let sink = sink.clone();
                let sink_closed = sink_closed.clone();

                handles.push(tokio::spawn(async move {
                    let key = relay_url.to_string();
                    let until_ts = cursors.lock().await.get(&key).copied();

                    let mut filter = Filter::new()
                        .author(pubkey)
                        .kinds(kind_list)
                        .limit(PAGE_SIZE);
                    if let Some(ts) = until_ts {
                        filter = filter.until(Timestamp::from(ts));
                    }
                    if let Some(since) = since_ts {
                        filter = filter.since(since);
                    }

                    let events = match client
                        .fetch_events_from(&[relay_url], filter, Duration::from_secs(15), true)
                        .await
                    {
                        Ok(e) => e,
                        Err(_) => {
                            exhausted.lock().await.insert(key);
                            return false;
                        }
                    };

                    let page_full = events.len() >= PAGE_SIZE;
                    let mut new_count = 0usize;
                    let mut oldest_ts: Option<u64> = None;

                    for event in events.into_iter() {
                        let id_hex = event.id.to_hex();
                        {
                            let mut s = seen.lock().await;
                            if s.contains(&id_hex) {
                                continue;
                            }
                            s.insert(id_hex);
                        }
                        new_count += 1;

                        let ts = event.created_at.as_secs();
                        oldest_ts = Some(match oldest_ts {
                            None => ts,
                            Some(prev) => prev.min(ts),
                        });

                        if sink.add(event.as_json()).is_err() {
                            sink_closed.store(true, std::sync::atomic::Ordering::Relaxed);
                            return false;
                        }
                    }

                    if new_count == 0 || !page_full {
                        exhausted.lock().await.insert(key);
                    } else if let Some(oldest) = oldest_ts {
                        if oldest == 0 {
                            exhausted.lock().await.insert(key);
                        } else {
                            cursors.lock().await.insert(key, oldest - 1);
                        }
                    } else {
                        exhausted.lock().await.insert(key);
                    }

                    true
                }));
            }

            for handle in handles {
                let _ = handle.await;
            }
        }

        Ok(())
    }
    .await;
    if let Err(error) = result {
        let _ = sink.add_error(error);
    }
    Ok(())
}

/// Streams events matching the filter from the given relays only, without saving them locally.
/// Used for relay-scoped chats such as NIP-29 groups.
pub async fn subscribe_to_events_on_relays(
    filter_json: String,
    relay_urls: Vec<String>,
    sink: StreamSink<String>,
) -> Result<()> {
    let result: Result<()> = async {
        let filter = Filter::from_json(&filter_json)?;
        let urls: Vec<RelayUrl> = relay_urls
            .iter()
            .map(|url| RelayUrl::parse(url))
            .collect::<std::result::Result<_, _>>()?;
        let client = temporary_client().await;
        add_temporary_relays(&client, &urls).await;
        client.connect().await;
        client
            .wait_for_ready(Duration::from_secs(3), urls.len().min(2))
            .await;
        let outcome = match client.subscribe_on(filter, None).await {
            Ok((sub_id, notifications, _)) => {
                forward_subscription(&client, &sub_id, notifications, &sink, false).await
            }
            Err(error) => Err(anyhow!("Subscribe failed: {}", error)),
        };
        client.shutdown().await;
        outcome
    }
    .await;
    if let Err(error) = result {
        let _ = sink.add_error(error);
    }
    Ok(())
}

pub async fn subscribe_to_events(filter_json: String, sink: StreamSink<String>) -> Result<()> {
    let result: Result<()> = async {
        let client = get_client().await?;
        let filter = Filter::from_json(&filter_json)?;

        let (sub_id, notifications, _) = client
            .subscribe_on(filter, None)
            .await
            .map_err(|e| anyhow!("Subscribe failed: {}", e))?;

        let outcome = forward_subscription(&client, &sub_id, notifications, &sink, true).await;
        client.unsubscribe(&sub_id).await;
        outcome
    }
    .await;
    if let Err(error) = result {
        let _ = sink.add_error(error);
    }
    Ok(())
}

pub async fn resolve_thread_root(note_id: String) -> Result<String> {
    let client = get_client().await?;
    resolve_thread_root_internal(&client, &note_id).await
}

async fn resolve_thread_root_internal(client: &NostrClient, note_id: &str) -> Result<String> {
    let mut current_id = note_id.to_string();
    let mut visited: HashSet<String> = HashSet::new();

    for _ in 0..15 {
        if visited.contains(&current_id) {
            break;
        }
        visited.insert(current_id.clone());

        let eid = EventId::from_hex(&current_id)?;
        let mut event = client.database().event_by_id(&eid).ok().flatten();

        if event.is_none() {
            let filter = Filter::new().id(eid).limit(1);
            let _ = quick_fetch(client, filter, Duration::from_secs(3)).await;
            event = client.database().event_by_id(&eid).ok().flatten();
            if event.is_none() {
                break;
            }
        }

        let ev = event.unwrap();
        let tags = super::database::tags_from_event(&ev);
        let refs = super::database::extract_note_references(&tags);

        if let Some(ref rid) = refs.root_id {
            if !rid.is_empty() {
                let root_eid = EventId::from_hex(rid)?;
                if client
                    .database()
                    .event_by_id(&root_eid)
                    .ok()
                    .flatten()
                    .is_none()
                {
                    let f = Filter::new().id(root_eid).limit(1);
                    let _ = quick_fetch(client, f, Duration::from_secs(3)).await;
                }
                return Ok(rid.clone());
            }
        }

        if let Some(ref pid) = refs.parent_id {
            if !pid.is_empty() && *pid != current_id {
                current_id = pid.clone();
                continue;
            }
        }

        break;
    }

    Ok(current_id)
}

pub async fn sync_replies_recursive(note_id: String, max_depth: u32) -> Result<u32> {
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

        let events = quick_fetch(&client, filter, Duration::from_secs(8)).await?;

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
                if let Ok(Some(ev)) = client.database().event_by_id(&eid) {
                    pks.insert(ev.pubkey);
                }
            }
        }
        pks
    };

    if !all_pubkeys.is_empty() {
        let pk_list: Vec<PublicKey> = all_pubkeys.into_iter().collect();
        let existing = client
            .database()
            .get_profiles_batch(&pk_list)
            .unwrap_or_default();
        let missing: Vec<PublicKey> = pk_list
            .into_iter()
            .filter(|pk| !existing.contains_key(pk))
            .collect();

        if !missing.is_empty() {
            fetch_unseen_profiles(&client, missing, 200, Duration::from_secs(5)).await;
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
                if *rr == root_id || reply_ids.contains(rr) || notes_map.contains_key(rr) {
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

        children_map.entry(parent).or_default().push(reply.clone());
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

pub async fn fetch_thread_ancestors(event_ids: Vec<String>) -> Result<u32> {
    let client = get_client().await?;
    let mut total_fetched: u32 = 0;
    let mut processed: HashSet<String> = HashSet::new();
    let mut queue: Vec<String> = event_ids;

    while !queue.is_empty() && processed.len() < 50 {
        let mut ancestor_ids: HashSet<String> = HashSet::new();

        for id_hex in &queue {
            if processed.contains(id_hex) {
                continue;
            }
            processed.insert(id_hex.clone());

            let eid = match EventId::from_hex(id_hex) {
                Ok(e) => e,
                Err(_) => continue,
            };

            let event = client.database().event_by_id(&eid).ok().flatten();
            let event = match event {
                Some(e) => e,
                None => {
                    let f = Filter::new().id(eid).limit(1);
                    let fetched = quick_fetch(&client, f, Duration::from_secs(5))
                        .await
                        .unwrap_or_default();
                    total_fetched += fetched.len() as u32;
                    match fetched.into_iter().next() {
                        Some(e) => e,
                        None => continue,
                    }
                }
            };

            let tags = super::database::tags_from_event(&event);
            let refs = super::database::extract_note_references(&tags);

            let ref_ids: Vec<String> = [refs.root_id, refs.parent_id]
                .into_iter()
                .flatten()
                .filter(|id| !id.is_empty() && !processed.contains(id))
                .collect();

            for ref_id in ref_ids {
                if let Ok(ref_eid) = EventId::from_hex(&ref_id) {
                    if !client.database().has_event(&ref_eid).unwrap_or(false) {
                        ancestor_ids.insert(ref_id);
                    }
                }
            }
        }

        if ancestor_ids.is_empty() {
            break;
        }

        let missing_eids: Vec<EventId> = ancestor_ids
            .iter()
            .filter_map(|id| EventId::from_hex(id).ok())
            .collect();

        let filter = Filter::new()
            .ids(missing_eids)
            .kind(Kind::TextNote)
            .limit(ancestor_ids.len());
        let fetched = quick_fetch(&client, filter, Duration::from_secs(6))
            .await
            .unwrap_or_default();

        total_fetched += fetched.len() as u32;

        let mut new_pubkeys: HashSet<PublicKey> = HashSet::new();
        for ev in fetched.iter() {
            new_pubkeys.insert(ev.pubkey);
        }
        if !new_pubkeys.is_empty() {
            let pk_list: Vec<PublicKey> = new_pubkeys.into_iter().collect();
            let existing = client
                .database()
                .get_profiles_batch(&pk_list)
                .unwrap_or_default();
            let missing_pks: Vec<PublicKey> = pk_list
                .into_iter()
                .filter(|pk| !existing.contains_key(pk))
                .collect();
            if !missing_pks.is_empty() {
                fetch_unseen_profiles(&client, missing_pks, 50, Duration::from_secs(4)).await;
            }
        }

        queue = ancestor_ids.into_iter().collect();
    }

    Ok(total_fetched)
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
        let event = match client.database().event_by_id(&eid) {
            Ok(Some(e)) => e,
            _ => continue,
        };

        let tags = super::database::tags_from_event(&event);
        let refs = super::database::extract_note_references(&tags);

        for ref_id in [refs.root_id, refs.parent_id, refs.quoted_note_id]
            .into_iter()
            .flatten()
        {
            if !ref_id.is_empty() && !own_ids.contains(&ref_id) {
                ref_ids.insert(ref_id);
            }
        }

        for tag in &tags {
            if tag.len() >= 2 && (tag[0] == "e" || tag[0] == "q") {
                let ref_id = &tag[1];
                if !ref_id.is_empty() && !own_ids.contains(ref_id) {
                    ref_ids.insert(ref_id.clone());
                }
            }
        }
    }

    if ref_ids.is_empty() {
        return Ok(0);
    }

    let candidate_ids: Vec<EventId> = ref_ids
        .iter()
        .filter_map(|ref_hex| EventId::from_hex(ref_hex).ok())
        .collect();
    if candidate_ids.is_empty() {
        return Ok(0);
    }
    let existing_ids = client
        .database()
        .existing_ids(&candidate_ids)
        .unwrap_or_default();
    let mut missing_ids: Vec<EventId> = candidate_ids
        .into_iter()
        .filter(|id| !existing_ids.contains(id))
        .collect();

    if missing_ids.is_empty() {
        return Ok(0);
    }

    if missing_ids.len() > 30 {
        missing_ids.truncate(30);
    }

    let filter = Filter::new().ids(missing_ids).limit(30);
    let fetched = quick_fetch(&client, filter, Duration::from_secs(5)).await?;

    let fetched_count = fetched.len() as u32;

    if fetched_count > 0 {
        let fetched_pks: Vec<PublicKey> = fetched
            .iter()
            .map(|ev| ev.pubkey)
            .collect::<HashSet<_>>()
            .into_iter()
            .collect();
        let existing_profiles = client
            .database()
            .get_profiles_batch(&fetched_pks)
            .unwrap_or_default();
        let missing_pks: Vec<PublicKey> = fetched_pks
            .into_iter()
            .filter(|pk| !existing_profiles.contains_key(pk))
            .collect();

        if !missing_pks.is_empty() {
            fetch_unseen_profiles(&client, missing_pks, 50, Duration::from_secs(5)).await;
        }
    }

    Ok(fetched_count)
}

pub async fn merge_and_sort_notes(existing_json: String, incoming_json: String) -> Result<String> {
    let existing: Vec<serde_json::Value> = serde_json::from_str(&existing_json)?;
    let incoming: Vec<serde_json::Value> = serde_json::from_str(&incoming_json)?;

    let mut seen: HashSet<String> = HashSet::new();
    let mut merged: Vec<serde_json::Value> = Vec::new();

    for note in incoming.into_iter().chain(existing) {
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

async fn resolve_repost_to_original(client: &NostrClient, note_id: &str) -> String {
    let eid = match EventId::from_hex(note_id) {
        Ok(e) => e,
        Err(_) => return note_id.to_string(),
    };

    let event = match client.database().event_by_id(&eid) {
        Ok(Some(e)) => e,
        _ => {
            let filter = Filter::new().id(eid).limit(1);
            match quick_fetch(client, filter, Duration::from_secs(5)).await {
                Ok(events) => match events.into_iter().next() {
                    Some(e) => e,
                    None => return note_id.to_string(),
                },
                Err(_) => return note_id.to_string(),
            }
        }
    };

    if event.kind != Kind::Repost {
        return note_id.to_string();
    }

    for tag in event.tags.iter() {
        let tag_slice = tag.as_slice();
        if tag_slice.len() >= 2 && tag_slice[0].as_str() == "e" {
            let original_id = tag_slice[1].as_str();
            if !original_id.is_empty() {
                return original_id.to_string();
            }
        }
    }

    note_id.to_string()
}

/// DB-only version of fetch_full_thread — no network calls, returns instantly
/// from local store. Returns None if the root note is not in the DB yet.
pub async fn fetch_full_thread_local(
    note_id: String,
    current_user_pubkey_hex: Option<String>,
    muted_pubkeys: Vec<String>,
    muted_words: Vec<String>,
) -> Result<Option<String>> {
    let client = get_client().await?;

    // Resolve repost without network.
    let resolved_note_id = resolve_repost_to_original_local(&client, &note_id);

    // Resolve root without network.
    let mut root_id = resolve_thread_root_local(&client, &resolved_note_id)?;

    let root_eid = EventId::from_hex(&root_id)?;
    let root_event = match client.database().event_by_id(&root_eid).ok().flatten() {
        Some(e) => e,
        None => {
            // Try the resolved id as root.
            let resolved_eid = EventId::from_hex(&resolved_note_id)?;
            match client.database().event_by_id(&resolved_eid).ok().flatten() {
                Some(e) => {
                    root_id = resolved_note_id.clone();
                    e
                }
                None => return Ok(None),
            }
        }
    };

    // Collect all reply IDs from DB (no network).
    let mut all_thread_ids: HashSet<String> = HashSet::new();
    all_thread_ids.insert(root_id.clone());

    {
        let root_eid = EventId::from_hex(&root_id)?;
        let mut processed_ids: HashSet<String> = HashSet::new();
        processed_ids.insert(root_id.clone());
        let mut pending_ids: Vec<EventId> = vec![root_eid];

        for _ in 0..3u32 {
            if pending_ids.is_empty() {
                break;
            }
            let filter = Filter::new()
                .kind(Kind::TextNote)
                .events(pending_ids.clone())
                .limit(200);
            let events = client.database().query(&filter).unwrap_or_default();
            let mut new_ids: Vec<EventId> = Vec::new();
            for event in events.iter() {
                let eid_hex = event.id.to_hex();
                if !processed_ids.contains(&eid_hex) {
                    processed_ids.insert(eid_hex.clone());
                    all_thread_ids.insert(eid_hex);
                    new_ids.push(event.id);
                }
            }
            pending_ids = new_ids;
            if all_thread_ids.len() > 500 {
                break;
            }
        }
    }

    let all_eids: Vec<EventId> = all_thread_ids
        .iter()
        .filter_map(|id| EventId::from_hex(id).ok())
        .collect();

    let reply_filter = Filter::new()
        .kind(Kind::TextNote)
        .events(all_eids)
        .limit(500);
    let reply_events = client.database().query(&reply_filter).unwrap_or_default();

    let mut all_events: Vec<Event> = Vec::with_capacity(1 + reply_events.len());
    all_events.push(root_event);
    let mut seen_ids: HashSet<String> = HashSet::new();
    seen_ids.insert(root_id.clone());
    let muted = super::database::MutedFilter::new(&muted_pubkeys, &muted_words);
    for ev in reply_events {
        let eid = ev.id.to_hex();
        if !seen_ids.insert(eid) {
            continue;
        }
        if !muted.is_muted(&ev) {
            all_events.push(ev);
        }
    }

    let hydrated_notes = super::database::hydrate_notes_values_pub(
        &client,
        &all_events,
        false,
        current_user_pubkey_hex,
    )
    .await?;

    let result = build_thread_result_json(hydrated_notes, &root_id, &resolved_note_id)?;
    Ok(Some(result))
}

/// Resolve repost to original without network.
fn resolve_repost_to_original_local(client: &NostrClient, note_id: &str) -> String {
    let eid = match EventId::from_hex(note_id) {
        Ok(e) => e,
        Err(_) => return note_id.to_string(),
    };
    let event = match client.database().event_by_id(&eid).ok().flatten() {
        Some(e) => e,
        None => return note_id.to_string(),
    };
    if event.kind != Kind::Repost {
        return note_id.to_string();
    }
    for tag in event.tags.iter() {
        let tag_slice = tag.as_slice();
        if tag_slice.len() >= 2 && tag_slice[0].as_str() == "e" {
            let original_id = tag_slice[1].as_str();
            if !original_id.is_empty() {
                return original_id.to_string();
            }
        }
    }
    note_id.to_string()
}

/// Resolve thread root without any network calls — DB only.
fn resolve_thread_root_local(client: &NostrClient, note_id: &str) -> Result<String> {
    let mut current_id = note_id.to_string();
    let mut visited: HashSet<String> = HashSet::new();

    for _ in 0..15 {
        if visited.contains(&current_id) {
            break;
        }
        visited.insert(current_id.clone());

        let eid = EventId::from_hex(&current_id)?;
        let event = match client.database().event_by_id(&eid).ok().flatten() {
            Some(e) => e,
            None => break,
        };

        let refs = super::database::extract_note_references_from_event(&event);

        if let Some(ref rid) = refs.root_id {
            if !rid.is_empty() {
                return Ok(rid.clone());
            }
        }

        if let Some(ref pid) = refs.parent_id {
            if !pid.is_empty() && *pid != current_id {
                current_id = pid.clone();
                continue;
            }
        }

        break;
    }

    Ok(current_id)
}

/// Shared helper: build the thread result JSON from hydrated notes.
fn build_thread_result_json(
    hydrated_notes: Vec<serde_json::Value>,
    root_id: &str,
    resolved_note_id: &str,
) -> Result<String> {
    let root_note = hydrated_notes
        .iter()
        .find(|n| n["id"].as_str() == Some(root_id))
        .cloned()
        .unwrap_or_else(|| serde_json::json!({}));

    let replies: Vec<serde_json::Value> = hydrated_notes
        .iter()
        .filter(|n| n["id"].as_str() != Some(root_id))
        .cloned()
        .collect();

    let mut children_map: HashMap<String, Vec<serde_json::Value>> = HashMap::new();
    let mut notes_map: HashMap<String, serde_json::Value> = HashMap::new();
    let reply_ids: HashSet<String> = replies
        .iter()
        .filter_map(|r| r["id"].as_str().map(|s| s.to_string()))
        .collect();

    notes_map.insert(root_id.to_string(), root_note.clone());
    for reply in &replies {
        let rid = reply["id"].as_str().unwrap_or("").to_string();
        if !rid.is_empty() {
            notes_map.insert(rid, reply.clone());
        }
    }

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
                if *rr == root_id || reply_ids.contains(rr) || notes_map.contains_key(rr) {
                    parent = Some(rr.clone());
                } else {
                    parent = Some(root_id.to_string());
                }
            }
        }

        let parent = parent.unwrap_or_else(|| root_id.to_string());
        let parent = if parent != root_id
            && !reply_ids.contains(&parent)
            && !notes_map.contains_key(&parent)
        {
            root_id.to_string()
        } else {
            parent
        };

        children_map.entry(parent).or_default().push(reply.clone());
    }

    for children in children_map.values_mut() {
        children.sort_by(|a, b| {
            let at = a["created_at"].as_i64().unwrap_or(0);
            let bt = b["created_at"].as_i64().unwrap_or(0);
            at.cmp(&bt)
        });
    }

    let mut chain_notes: Vec<serde_json::Value> = Vec::new();
    if resolved_note_id != root_id {
        let mut chain_ids: Vec<String> = Vec::new();
        let mut visited: HashSet<String> = HashSet::new();
        let mut current = resolved_note_id.to_string();

        while !current.is_empty() && !visited.contains(&current) {
            visited.insert(current.clone());
            chain_ids.push(current.clone());
            if current == root_id {
                break;
            }
            if let Some(note) = notes_map.get(&current) {
                let pid = note["parentId"]
                    .as_str()
                    .filter(|s| !s.is_empty())
                    .or_else(|| note["rootId"].as_str().filter(|s| !s.is_empty()));
                current = pid.map(|s| s.to_string()).unwrap_or_default();
            } else {
                break;
            }
        }

        chain_ids.reverse();
        if chain_ids.first().map(|s| s.as_str()) != Some(root_id) {
            chain_ids.insert(0, root_id.to_string());
        }

        let mut seen: HashSet<String> = HashSet::new();
        for cid in &chain_ids {
            if seen.insert(cid.clone()) {
                if let Some(note) = notes_map.get(cid) {
                    chain_notes.push(note.clone());
                }
            }
        }
    } else {
        chain_notes.push(root_note.clone());
    }

    let result = serde_json::json!({
        "rootNote": root_note,
        "chainNotes": chain_notes,
        "childrenMap": children_map,
        "notesMap": notes_map,
        "totalReplies": replies.len(),
    });

    Ok(serde_json::to_string(&result)?)
}

pub async fn fetch_full_thread(
    note_id: String,
    current_user_pubkey_hex: Option<String>,
    muted_pubkeys: Vec<String>,
    muted_words: Vec<String>,
) -> Result<String> {
    let client = get_client().await?;

    let resolved_note_id = resolve_repost_to_original(&client, &note_id).await;
    let mut root_id = resolve_thread_root_internal(&client, &resolved_note_id).await?;

    let mut all_thread_ids: HashSet<String> = HashSet::new();
    all_thread_ids.insert(root_id.clone());

    {
        let root_eid = EventId::from_hex(&root_id)?;
        let mut processed_ids: HashSet<String> = HashSet::new();
        processed_ids.insert(root_id.clone());
        let mut pending_ids: Vec<EventId> = vec![root_eid];
        let mut total_fetched: u32 = 0;

        for _ in 0..3u32 {
            if pending_ids.is_empty() {
                break;
            }

            let filter = Filter::new()
                .kind(Kind::TextNote)
                .events(pending_ids.clone())
                .limit(200);
            let events = quick_fetch(&client, filter, Duration::from_secs(4)).await?;

            let mut new_ids: Vec<EventId> = Vec::new();
            for event in events.iter() {
                let eid_hex = event.id.to_hex();
                if !processed_ids.contains(&eid_hex) {
                    processed_ids.insert(eid_hex.clone());
                    all_thread_ids.insert(eid_hex);
                    new_ids.push(event.id);
                    total_fetched += 1;
                }
            }

            pending_ids = new_ids;
            if total_fetched > 500 {
                break;
            }
        }
    }

    let all_eids: Vec<EventId> = all_thread_ids
        .iter()
        .filter_map(|id| EventId::from_hex(id).ok())
        .collect();

    {
        let reply_filter = Filter::new()
            .kind(Kind::TextNote)
            .events(all_eids.clone())
            .limit(500);
        let all_reply_events = client.database().query(&reply_filter)?;

        let mut all_pubkeys: HashSet<PublicKey> = HashSet::new();
        let root_eid = EventId::from_hex(&root_id)?;
        if let Ok(Some(root_ev)) = client.database().event_by_id(&root_eid) {
            all_pubkeys.insert(root_ev.pubkey);
        }
        for ev in all_reply_events.iter() {
            all_pubkeys.insert(ev.pubkey);
        }

        if !all_pubkeys.is_empty() {
            let pk_list: Vec<PublicKey> = all_pubkeys.into_iter().collect();
            let existing = client
                .database()
                .get_profiles_batch(&pk_list)
                .unwrap_or_default();
            let missing: Vec<PublicKey> = pk_list
                .into_iter()
                .filter(|pk| !existing.contains_key(pk))
                .collect();

            if !missing.is_empty() {
                fetch_unseen_profiles(&client, missing, 200, Duration::from_secs(3)).await;
            }
        }
    }

    let root_eid = EventId::from_hex(&root_id)?;
    let root_event = match client.database().event_by_id(&root_eid)? {
        Some(e) => e,
        None => {
            let resolved_eid = EventId::from_hex(&resolved_note_id)?;
            match client.database().event_by_id(&resolved_eid)? {
                Some(e) => {
                    root_id = resolved_note_id.clone();
                    e
                }
                None => return Err(anyhow!("Root note not found")),
            }
        }
    };

    let reply_filter = Filter::new()
        .kind(Kind::TextNote)
        .events(all_eids)
        .limit(500);
    let reply_events = client.database().query(&reply_filter)?;

    let mut all_events: Vec<Event> = Vec::with_capacity(1 + reply_events.len());
    all_events.push(root_event);
    let mut seen_ids: HashSet<String> = HashSet::new();
    seen_ids.insert(root_id.clone());
    let muted = super::database::MutedFilter::new(&muted_pubkeys, &muted_words);
    for ev in reply_events {
        let eid = ev.id.to_hex();
        if !seen_ids.insert(eid) {
            continue;
        }
        if !muted.is_muted(&ev) {
            all_events.push(ev);
        }
    }

    let hydrated_notes = super::database::hydrate_notes_values_pub(
        &client,
        &all_events,
        false,
        current_user_pubkey_hex,
    )
    .await?;

    let result = build_thread_result_json(hydrated_notes, &root_id, &resolved_note_id)?;
    Ok(result)
}

pub async fn get_database_size_mb() -> Result<u64> {
    if let Ok(client) = get_client().await {
        return Ok(client.database().database_size_bytes() / (1024 * 1024));
    }
    let db_path_lock = db_path_state().read().await;
    match db_path_lock.as_ref() {
        Some(path) => Ok(EventStore::database_size_in(Path::new(path)) / (1024 * 1024)),
        None => Ok(0),
    }
}

pub async fn fetch_missing_profiles_for_events(events_json: String) -> Result<u32> {
    let client = get_client().await?;
    let events: Vec<serde_json::Value> = serde_json::from_str(&events_json)?;

    let mut pubkeys: HashSet<PublicKey> = HashSet::new();
    for event in &events {
        if let Some(pk_str) = event["pubkey"].as_str() {
            if let Ok(pk) = PublicKey::from_hex(pk_str) {
                pubkeys.insert(pk);
            }
        }
        let kind = event["kind"].as_u64().unwrap_or(1);
        if kind == 6 {
            if let Some(tags) = event["tags"].as_array() {
                for tag in tags {
                    if let Some(arr) = tag.as_array() {
                        if arr.len() >= 2 && arr[0].as_str() == Some("p") {
                            if let Some(pk_str) = arr[1].as_str() {
                                if let Ok(pk) = PublicKey::from_hex(pk_str) {
                                    pubkeys.insert(pk);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if pubkeys.is_empty() {
        return Ok(0);
    }

    let pk_list: Vec<PublicKey> = pubkeys.into_iter().collect();
    let existing = client
        .database()
        .get_profiles_batch(&pk_list)
        .unwrap_or_default();
    let missing: Vec<PublicKey> = pk_list
        .into_iter()
        .filter(|pk| !existing.contains_key(pk))
        .collect();

    if missing.is_empty() {
        return Ok(0);
    }

    let requested = missing.len();
    let fetched = fetch_unseen_profiles(&client, missing, requested, Duration::from_secs(5)).await;

    Ok(fetched.len() as u32)
}

pub async fn fetch_repost_originals(repost_event_ids_json: String) -> Result<u32> {
    let client = get_client().await?;
    let event_ids: Vec<String> = serde_json::from_str(&repost_event_ids_json)?;

    if event_ids.is_empty() {
        return Ok(0);
    }

    let candidate_ids: Vec<EventId> = event_ids
        .iter()
        .filter_map(|id_hex| EventId::from_hex(id_hex).ok())
        .collect();
    if candidate_ids.is_empty() {
        return Ok(0);
    }
    let existing_ids = client
        .database()
        .existing_ids(&candidate_ids)
        .unwrap_or_default();
    let mut missing_ids: Vec<EventId> = candidate_ids
        .into_iter()
        .filter(|id| !existing_ids.contains(id))
        .collect();

    if missing_ids.is_empty() {
        return Ok(0);
    }

    if missing_ids.len() > 50 {
        missing_ids.truncate(50);
    }

    let filter = Filter::new().ids(missing_ids).limit(50);
    let fetched = quick_fetch(&client, filter, Duration::from_secs(6))
        .await
        .unwrap_or_default();
    let fetched_count = fetched.len() as u32;

    if fetched_count > 0 {
        let fetched_pks: Vec<PublicKey> = fetched
            .iter()
            .map(|ev| ev.pubkey)
            .collect::<HashSet<_>>()
            .into_iter()
            .collect();
        let existing_profiles = client
            .database()
            .get_profiles_batch(&fetched_pks)
            .unwrap_or_default();
        let missing_pks: Vec<PublicKey> = fetched_pks
            .into_iter()
            .filter(|pk| !existing_profiles.contains_key(pk))
            .collect();
        if !missing_pks.is_empty() {
            fetch_unseen_profiles(&client, missing_pks, 50, Duration::from_secs(5)).await;
        }
    }

    Ok(fetched_count)
}

type PrimalWsStream =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

/// The idle connection to the Primal cache. A request takes it and hands it back when done, so
/// nothing waits on a lock while a request is on the network, and signing out never has to wait
/// for one.
struct PrimalSocket {
    idle: std::sync::Mutex<Option<PrimalWsStream>>,
    session: std::sync::atomic::AtomicU64,
}

impl PrimalSocket {
    fn slot(&self) -> std::sync::MutexGuard<'_, Option<PrimalWsStream>> {
        self.idle
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    fn take(&self) -> (Option<PrimalWsStream>, u64) {
        let session = self.session.load(std::sync::atomic::Ordering::Acquire);
        (self.slot().take(), session)
    }

    fn give_back(&self, socket: PrimalWsStream, session: u64) {
        let mut slot = self.slot();
        if slot.is_none() && self.session.load(std::sync::atomic::Ordering::Acquire) == session {
            *slot = Some(socket);
        }
    }

    fn discard(&self) {
        self.session
            .fetch_add(1, std::sync::atomic::Ordering::AcqRel);
        self.slot().take();
    }
}

static PRIMAL_SOCKET: PrimalSocket = PrimalSocket {
    idle: std::sync::Mutex::new(None),
    session: std::sync::atomic::AtomicU64::new(0),
};

fn primal_socket() -> &'static PrimalSocket {
    &PRIMAL_SOCKET
}

async fn query_primal_follower_counts(
    ws: &mut PrimalWsStream,
    sub_id: &str,
    request_text: &str,
) -> Option<serde_json::Map<String, serde_json::Value>> {
    use futures::{SinkExt, StreamExt};
    use tokio_tungstenite::tungstenite::Message;

    if ws
        .send(Message::Text(request_text.to_string()))
        .await
        .is_err()
    {
        return None;
    }

    let mut follower_counts: serde_json::Map<String, serde_json::Value> = serde_json::Map::new();
    let timeout = tokio::time::sleep(Duration::from_secs(5));
    tokio::pin!(timeout);

    loop {
        tokio::select! {
            _ = &mut timeout => return None,
            msg = ws.next() => {
                match msg {
                    Some(Ok(Message::Text(text))) => {
                        if let Ok(decoded) = serde_json::from_str::<serde_json::Value>(&text) {
                            if let Some(arr) = decoded.as_array() {
                                if !arr.is_empty() {
                                    let msg_type = arr[0].as_str().unwrap_or("");
                                    let msg_sub = arr.get(1).and_then(|v| v.as_str()).unwrap_or("");
                                    if !msg_sub.is_empty() && msg_sub != sub_id {
                                        continue;
                                    }
                                    if msg_type == "EOSE" {
                                        let close = serde_json::json!(["CLOSE", sub_id]).to_string();
                                        let _ = ws.send(Message::Text(close)).await;
                                        return Some(follower_counts);
                                    }
                                    if msg_type == "EVENT" && arr.len() >= 3 {
                                        let event = &arr[2];
                                        let kind = event["kind"].as_u64().unwrap_or(0);
                                        if kind == 10000133 {
                                            if let Ok(content) = serde_json::from_str::<serde_json::Map<String, serde_json::Value>>(
                                                event["content"].as_str().unwrap_or("{}")
                                            ) {
                                                for (k, v) in content {
                                                    if v.is_number() {
                                                        follower_counts.insert(k, v);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Some(Ok(Message::Ping(payload))) => {
                        let _ = ws.send(Message::Pong(payload)).await;
                    }
                    Some(Ok(Message::Close(_))) | Some(Err(_)) | None => return None,
                    _ => {}
                }
            }
        }
    }
}

pub async fn fetch_follower_counts(pubkey_hexes: Vec<String>) -> Result<String> {
    use tokio_tungstenite::connect_async_with_config;

    if pubkey_hexes.is_empty() {
        return Ok("{}".to_string());
    }

    let primal_url = "wss://cache2.primal.net/v1";
    let sub_id = format!(
        "primal_fc_{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0)
    );

    let request = serde_json::json!([
        "REQ",
        sub_id,
        {
            "cache": [
                "user_infos",
                {"pubkeys": pubkey_hexes}
            ]
        }
    ])
    .to_string();

    let (mut idle, session) = primal_socket().take();
    for _attempt in 0..2 {
        let mut socket = match idle.take() {
            Some(socket) => socket,
            None => {
                let ws_cfg = crate::pool::hardened_ws_config();
                match tokio::time::timeout(
                    Duration::from_secs(5),
                    connect_async_with_config(primal_url, Some(ws_cfg), true),
                )
                .await
                {
                    Ok(Ok((stream, _))) => stream,
                    _ => return Ok("{}".to_string()),
                }
            }
        };
        if let Some(counts) = query_primal_follower_counts(&mut socket, &sub_id, &request).await {
            primal_socket().give_back(socket, session);
            return Ok(serde_json::to_string(&counts)?);
        }
    }

    Ok("{}".to_string())
}

pub async fn fetch_events_from_relays(
    filter_json: String,
    relay_urls: Vec<String>,
    timeout_secs: u32,
) -> Result<String> {
    let filter = Filter::from_json(&filter_json)?;
    let urls: Vec<RelayUrl> = relay_urls
        .iter()
        .map(|url| RelayUrl::parse(url))
        .collect::<std::result::Result<_, _>>()?;
    let client = temporary_client().await;
    add_temporary_relays(&client, &urls).await;
    client.connect().await;
    let events = client
        .thorough_fetch(filter, Duration::from_secs(timeout_secs as u64), false)
        .await;
    client.shutdown().await;
    events_to_json(events?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pool::test_relay::{mock_relay, relay_with, unreachable_relay, Script};

    static GLOBAL_CLIENT: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

    #[derive(Default)]
    struct Collected {
        items: std::sync::Mutex<Vec<String>>,
        errors: std::sync::Mutex<Vec<String>>,
    }

    impl crate::sink::EventSink for Collected {
        fn on_item(&self, item: String) -> bool {
            self.items.lock().unwrap().push(item);
            true
        }

        fn on_error(&self, message: String) {
            self.errors.lock().unwrap().push(message);
        }

        fn on_done(&self) {}

        fn is_closed(&self) -> bool {
            false
        }
    }

    fn collecting_sink() -> (Arc<Collected>, StreamSink<String>) {
        let collected = Arc::new(Collected::default());
        (collected.clone(), StreamSink::new(collected))
    }

    #[tokio::test]
    async fn a_relay_scoped_fetch_hears_from_every_relay_it_was_pointed_at() {
        let keys = Keys::generate();
        let event = EventBuilder::text_note("only the slower relay has this")
            .sign_with_keys(&keys)
            .unwrap();
        let empty = relay_with(&[], Duration::ZERO).await;
        let slower = relay_with(&[&event], Duration::from_millis(1_150)).await;
        let dead = unreachable_relay().await;
        let filter = Filter::new().author(keys.public_key()).kind(Kind::TextNote);

        let started = std::time::Instant::now();
        let raw = fetch_events_from_relays(
            filter.as_json(),
            vec![dead, empty.url.clone(), slower.url.clone()],
            6,
        )
        .await
        .unwrap();
        let events: Vec<Event> = serde_json::from_str(&raw).unwrap();
        assert_eq!(events, vec![event]);
        assert!(started.elapsed() < Duration::from_secs(4));
        assert!(
            fetch_events_from_relays(filter.as_json(), vec!["not a relay".into()], 1)
                .await
                .is_err()
        );
    }

    #[tokio::test]
    async fn a_stream_reports_an_error_once_every_relay_has_refused_it() {
        let relay = mock_relay(Script {
            refuse_requests: Some("restricted: members only"),
            ..Script::default()
        })
        .await;
        let (collected, sink) = collecting_sink();
        tokio::time::timeout(
            Duration::from_secs(4),
            subscribe_to_events_on_relays(
                Filter::new().kind(Kind::TextNote).as_json(),
                vec![relay.url.clone()],
                sink,
            ),
        )
        .await
        .expect("the stream kept waiting on a subscription its only relay had closed")
        .unwrap();
        let errors = collected.errors.lock().unwrap();
        assert_eq!(errors.len(), 1, "{errors:?}");
        assert!(errors[0].contains("restricted: members only"), "{errors:?}");
        assert!(collected.items.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn a_stream_delivers_events_from_the_relays_that_accept_it() {
        let keys = Keys::generate();
        let event = EventBuilder::text_note("live")
            .sign_with_keys(&keys)
            .unwrap();
        let refusing = mock_relay(Script {
            refuse_requests: Some("restricted: members only"),
            ..Script::default()
        })
        .await;
        let serving = mock_relay(Script {
            live: vec![crate::pool::test_relay::json(&event)],
            ..Script::default()
        })
        .await;
        let (collected, sink) = collecting_sink();
        let stream = tokio::spawn(subscribe_to_events_on_relays(
            Filter::new().kind(Kind::TextNote).as_json(),
            vec![refusing.url.clone(), serving.url.clone()],
            sink,
        ));
        let deadline = std::time::Instant::now() + Duration::from_secs(4);
        while collected.items.lock().unwrap().is_empty() && std::time::Instant::now() < deadline {
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert_eq!(*collected.items.lock().unwrap(), vec![event.as_json()]);
        assert!(collected.errors.lock().unwrap().is_empty());
        assert!(!stream.is_finished());
        stream.abort();
    }

    #[tokio::test]
    async fn late_relays_that_refuse_do_not_end_a_stream_other_relays_serve() {
        let _guard = GLOBAL_CLIENT.lock().await;
        let keys = Keys::generate();
        let serving = relay_with(&[], Duration::ZERO).await;
        init_client(vec![serving.url.clone()], None, None, vec![])
            .await
            .unwrap();
        connect_relays().await.unwrap();
        assert_eq!(wait_for_ready(3).await.unwrap(), 1);

        let (collected, sink) = collecting_sink();
        let stream = tokio::spawn(subscribe_to_events(
            Filter::new().kind(Kind::TextNote).as_json(),
            sink,
        ));
        tokio::time::sleep(Duration::from_millis(150)).await;

        let client = get_client().await.unwrap();
        let mut refusing = Vec::new();
        for _ in 0..3 {
            let relay = mock_relay(Script {
                refuse_requests: Some("auth-required: members only"),
                ..Script::default()
            })
            .await;
            client.add_relay(&relay.url).await.unwrap();
            refusing.push(relay);
        }
        let event = EventBuilder::text_note("from a relay that joined later")
            .sign_with_keys(&keys)
            .unwrap();
        let joining = mock_relay(Script {
            live: vec![crate::pool::test_relay::json(&event)],
            ..Script::default()
        })
        .await;
        client.add_relay(&joining.url).await.unwrap();
        client.connect().await;

        let deadline = std::time::Instant::now() + Duration::from_secs(4);
        while collected.items.lock().unwrap().is_empty() && std::time::Instant::now() < deadline {
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
        tokio::time::sleep(Duration::from_millis(300)).await;
        assert_eq!(*collected.items.lock().unwrap(), vec![event.as_json()]);
        assert!(collected.errors.lock().unwrap().is_empty());
        assert!(!stream.is_finished());
        assert!(client.database().event_by_id(&event.id).unwrap().is_some());

        stream.abort();
        shutdown_client().await.unwrap();
    }

    #[tokio::test]
    async fn signing_out_never_waits_for_a_follower_count_request() {
        use tokio_tungstenite::connect_async_with_config;
        let _guard = GLOBAL_CLIENT.lock().await;
        let relay = relay_with(&[], Duration::ZERO).await;
        let connect = || async {
            connect_async_with_config(
                relay.url.as_str(),
                Some(crate::pool::hardened_ws_config()),
                true,
            )
            .await
            .unwrap()
            .0
        };
        let pool = primal_socket();
        pool.discard();

        let (idle, session) = pool.take();
        assert!(idle.is_none());
        pool.give_back(connect().await, session);
        let (idle, session) = pool.take();
        let in_use = idle.expect("an idle connection is reused by the next request");

        init_client(vec![], None, None, vec![]).await.unwrap();
        tokio::time::timeout(Duration::from_secs(1), shutdown_client())
            .await
            .expect("sign-out waited for a follower-count request")
            .unwrap();
        assert!(!is_client_initialized().await);

        pool.give_back(in_use, session);
        assert!(
            pool.take().0.is_none(),
            "a connection from before sign-out was kept"
        );

        let (_, session) = pool.take();
        pool.give_back(connect().await, session);
        pool.give_back(connect().await, session);
        assert!(pool.take().0.is_some());
        assert!(pool.take().0.is_none());
    }

    #[tokio::test]
    async fn interaction_counts_stop_waiting_for_a_relay_that_refuses_the_request() {
        let _guard = GLOBAL_CLIENT.lock().await;
        let relay = mock_relay(Script {
            refuse_requests: Some("rate-limited: slow down"),
            ..Script::default()
        })
        .await;
        init_client(vec![relay.url.clone()], None, None, vec![])
            .await
            .unwrap();
        connect_relays().await.unwrap();
        assert_eq!(wait_for_ready(3).await.unwrap(), 1);

        let (collected, sink) = collecting_sink();
        let started = std::time::Instant::now();
        stream_interaction_counts(vec!["11".repeat(32)], None, sink)
            .await
            .unwrap();
        assert!(
            started.elapsed() < Duration::from_millis(1_500),
            "waited {:?} for a relay that had already refused",
            started.elapsed()
        );
        assert!(collected.errors.lock().unwrap().is_empty());
        shutdown_client().await.unwrap();
    }

    #[tokio::test]
    async fn relays_the_account_configured_are_trusted_and_discovered_ones_are_not() {
        let _guard = GLOBAL_CLIENT.lock().await;
        init_client(
            vec!["wss://mine.example".into()],
            None,
            None,
            vec!["wss://index.example".into()],
        )
        .await
        .unwrap();
        add_relay("wss://added.example".into()).await.unwrap();
        add_relay_with_flags("wss://readonly.example".into(), true, false)
            .await
            .unwrap();
        let client = get_client().await.unwrap();
        client.add_relay("wss://outbox.example").await.unwrap();
        let relays = client.relays().await;
        let trusted = |url: &str| relays[&RelayUrl::parse(url).unwrap()].has_flag(FLAG_AUTH);
        assert!(trusted("wss://mine.example"));
        assert!(trusted("wss://added.example"));
        assert!(trusted("wss://readonly.example"));
        assert!(!trusted("wss://index.example"));
        assert!(!trusted("wss://outbox.example"));

        let temporary = temporary_client().await;
        let urls: Vec<RelayUrl> = ["wss://mine.example", "wss://hint.example"]
            .iter()
            .map(|url| RelayUrl::parse(url).unwrap())
            .collect();
        add_temporary_relays(&temporary, &urls).await;
        let relays = temporary.relays().await;
        assert!(relays[&urls[0]].has_flag(FLAG_AUTH));
        assert!(!relays[&urls[1]].has_flag(FLAG_AUTH));
        temporary.shutdown().await;
        shutdown_client().await.unwrap();
    }

    async fn fake_relay(answer: Option<Event>) -> String {
        use futures::{SinkExt, StreamExt};
        use tokio_tungstenite::{accept_async, tungstenite::Message};
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("ws://{}", listener.local_addr().unwrap());
        tokio::spawn(async move {
            while let Ok((stream, _)) = listener.accept().await {
                let answer = answer.clone();
                tokio::spawn(async move {
                    let Ok(mut socket) = accept_async(stream).await else {
                        return;
                    };
                    while let Some(Ok(frame)) = socket.next().await {
                        let Message::Text(text) = frame else { continue };
                        let Ok(message) = serde_json::from_str::<serde_json::Value>(&text) else {
                            continue;
                        };
                        if message[0] != "REQ" {
                            continue;
                        }
                        let Some(answer) = answer.clone() else {
                            continue;
                        };
                        let id = message[1].clone();
                        let event: serde_json::Value =
                            serde_json::from_str(&answer.as_json()).unwrap();
                        let _ = socket
                            .send(Message::Text(
                                serde_json::json!(["EVENT", id, event]).to_string(),
                            ))
                            .await;
                        let _ = socket
                            .send(Message::Text(serde_json::json!(["EOSE", id]).to_string()))
                            .await;
                    }
                });
            }
        });
        url
    }

    #[tokio::test]
    async fn quick_fetch_returns_without_waiting_for_silent_relays() {
        let keys = Keys::generate();
        let note = EventBuilder::text_note("hello")
            .sign_with_keys(&keys)
            .unwrap();
        let answering = fake_relay(Some(note.clone())).await;
        let silent = fake_relay(None).await;
        let client = NostrClient::in_memory(None);
        client.add_relay(&answering).await.unwrap();
        client.add_relay(&silent).await.unwrap();
        client.connect().await;
        client.wait_for_ready(Duration::from_secs(3), 2).await;
        let started = std::time::Instant::now();
        let events = quick_fetch(
            &client,
            Filter::new().author(keys.public_key()).limit(1),
            Duration::from_secs(10),
        )
        .await
        .unwrap();
        assert!(events.iter().any(|event| event.id == note.id));
        assert!(
            started.elapsed() < Duration::from_secs(4),
            "took {:?}",
            started.elapsed()
        );
        client.shutdown().await;
    }

    #[test]
    fn publication_requires_at_least_one_relay_acknowledgement() {
        let event = EventBuilder::text_note("hello")
            .sign_with_keys(&Keys::generate())
            .unwrap();
        let url = RelayUrl::parse("wss://relay.example").unwrap();
        let mut output = PublishOutput {
            id: event.id,
            success: HashSet::new(),
            failed: HashMap::from([(url.clone(), "rejected".into())]),
        };
        assert!(published_event_json(output.clone()).is_err());
        output.success.insert(url);
        assert!(published_event_json(output).is_ok());
    }

    #[tokio::test]
    async fn rejected_publications_preserve_persistent_events_until_a_relay_accepts() {
        use futures::{SinkExt, StreamExt};
        use tokio::net::TcpListener;
        use tokio_tungstenite::{accept_async, tungstenite::Message};

        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = RelayUrl::parse(&format!("ws://{}", listener.local_addr().unwrap())).unwrap();
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let mut socket = accept_async(stream).await.unwrap();
            while let Some(Ok(message)) = socket.next().await {
                let Message::Text(text) = message else {
                    continue;
                };
                let message: serde_json::Value = serde_json::from_str(&text).unwrap();
                if message[0] == "EVENT" {
                    let event = Event::from_json(message[1].to_string()).unwrap();
                    let accepted = event.content == "accepted";
                    socket
                        .send(Message::Text(
                            serde_json::json!([
                                "OK",
                                event.id.to_hex(),
                                accepted,
                                if accepted {
                                    ""
                                } else {
                                    "blocked: test rejection"
                                }
                            ])
                            .to_string(),
                        ))
                        .await
                        .unwrap();
                }
            }
        });
        let path = std::env::temp_dir().join(format!("qiqstr-publish-{}", rand::random::<u64>()));
        std::fs::create_dir(&path).unwrap();
        let client = NostrClient::new(Arc::new(EventStore::open(&path).unwrap()), None);
        client.add_relay(url.as_str()).await.unwrap();
        client.connect().await;
        client.wait_for_ready(Duration::from_secs(2), 1).await;
        let targets = [url];
        let mut retained = Vec::new();
        for directed in [false, true] {
            let targets = directed.then_some(targets.as_slice());
            for kind in [
                Kind::ContactList,
                Kind::MuteList,
                Kind::from(10003),
                Kind::from(30000),
            ] {
                let owner = Keys::generate();
                let previous = EventBuilder::new(kind, "previous")
                    .tag(Tag::identifier("list"))
                    .custom_created_at(Timestamp::from(1))
                    .sign_with_keys(&owner)
                    .unwrap();
                let rejected = EventBuilder::new(kind, "rejected")
                    .tag(Tag::identifier("list"))
                    .custom_created_at(Timestamp::from(2))
                    .sign_with_keys(&owner)
                    .unwrap();
                client.database().save_event(&previous).unwrap();
                let output = publish_event(&client, &rejected, targets).await.unwrap();
                assert!(published_event_json(output).is_err());
                assert!(
                    client
                        .database()
                        .event_by_id(&rejected.id)
                        .unwrap()
                        .is_none(),
                    "rejected mutation was cached"
                );
                assert_eq!(
                    client.database().event_by_id(&previous.id).unwrap(),
                    Some(previous.clone()),
                    "previous signed state was lost"
                );
                retained.push(previous.id);
            }
            let owner = Keys::generate();
            let previous = EventBuilder::new(Kind::ContactList, "previous")
                .custom_created_at(Timestamp::from(1))
                .sign_with_keys(&owner)
                .unwrap();
            let accepted = EventBuilder::new(Kind::ContactList, "accepted")
                .custom_created_at(Timestamp::from(2))
                .sign_with_keys(&owner)
                .unwrap();
            client.database().save_event(&previous).unwrap();
            assert!(published_event_json(
                publish_event(&client, &accepted, targets).await.unwrap()
            )
            .is_ok());
            assert!(client
                .database()
                .event_by_id(&previous.id)
                .unwrap()
                .is_none());
            assert_eq!(
                client.database().event_by_id(&accepted.id).unwrap(),
                Some(accepted.clone())
            );
            retained.push(accepted.id);
            let owner = Keys::generate();
            let rejected = EventBuilder::text_note("rejected")
                .sign_with_keys(&owner)
                .unwrap();
            assert!(published_event_json(
                publish_event(&client, &rejected, targets).await.unwrap()
            )
            .is_err());
            assert!(client
                .database()
                .event_by_id(&rejected.id)
                .unwrap()
                .is_none());
            let accepted = EventBuilder::text_note("accepted")
                .sign_with_keys(&owner)
                .unwrap();
            assert!(published_event_json(
                publish_event(&client, &accepted, targets).await.unwrap()
            )
            .is_ok());
            assert_eq!(
                client.database().event_by_id(&accepted.id).unwrap(),
                Some(accepted.clone())
            );
            retained.push(accepted.id);
            let rejected_deletion = EventBuilder::new(Kind::EventDeletion, "rejected")
                .tag(Tag::event(accepted.id))
                .sign_with_keys(&owner)
                .unwrap();
            assert!(published_event_json(
                publish_event(&client, &rejected_deletion, targets)
                    .await
                    .unwrap()
            )
            .is_err());
            assert!(client
                .database()
                .event_by_id(&accepted.id)
                .unwrap()
                .is_some());
        }
        client.shutdown().await;
        drop(client);
        server.await.unwrap();
        let reopened = EventStore::open(&path).unwrap();
        for id in retained {
            assert!(reopened.event_by_id(&id).unwrap().is_some());
        }
        drop(reopened);
        std::fs::remove_dir_all(path).unwrap();
    }

    #[tokio::test]
    async fn client_reinitialization_preserves_valid_configuration_on_error() {
        let _guard = GLOBAL_CLIENT.lock().await;
        init_client(vec![], None, None, vec![]).await.unwrap();
        init_client(vec!["wss://new.example".into()], None, None, vec![])
            .await
            .unwrap();
        assert_eq!(get_relay_list().await.unwrap(), ["wss://new.example"]);
        assert!(
            init_client(vec!["invalid relay".into()], None, None, vec![])
                .await
                .is_err()
        );
        assert_eq!(get_relay_list().await.unwrap(), ["wss://new.example"]);
        add_relay_with_flags("wss://new.example".into(), false, false)
            .await
            .unwrap();
        add_relay_with_flags("wss://new.example".into(), true, true)
            .await
            .unwrap();
        let client = get_client().await.unwrap();
        let relays = client.relays().await;
        let relay = relays.values().next().unwrap();
        assert!(relay.has_flag(FLAG_READ));
        assert!(relay.has_flag(FLAG_WRITE));
        shutdown_client().await.unwrap();
        assert!(!is_client_initialized().await);
        assert!(get_client().await.is_err());
        assert!(db_path_state().read().await.is_none());
    }
}
