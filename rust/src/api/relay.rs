use std::collections::HashMap;
use std::sync::OnceLock;
use std::time::Duration;

use anyhow::{anyhow, Result};
use flutter_rust_bridge::frb;
use nostr_lmdb::NostrLMDB;
use nostr_sdk::prelude::*;
use tokio::sync::RwLock;

use crate::frb_generated::StreamSink;

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

fn state() -> &'static RwLock<Option<Client>> {
    CLIENT.get_or_init(|| RwLock::new(None))
}

fn user_relays_state() -> &'static RwLock<Vec<String>> {
    USER_RELAYS.get_or_init(|| RwLock::new(Vec::new()))
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
        let database = NostrLMDB::open(path)?;
        builder = builder.database(database);
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

    let ur = user_relays_state().read().await;
    let urls: Vec<RelayUrl> = ur
        .iter()
        .filter_map(|u| RelayUrl::parse(u).ok())
        .collect();
    drop(ur);

    let output = if urls.is_empty() {
        client.send_event(&event).await?
    } else {
        client.send_event_to(urls, &event).await?
    };

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
