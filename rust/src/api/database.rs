use std::collections::{HashMap, HashSet};

use anyhow::Result;
use nostr_sdk::prelude::*;

use super::relay::get_client_pub;

fn is_event_muted(event: &Event, muted_pubkeys: &[String], muted_words: &[String]) -> bool {
    if muted_pubkeys.is_empty() && muted_words.is_empty() {
        return false;
    }

    let pubkey_hex = event.pubkey.to_hex();
    if muted_pubkeys.iter().any(|p| p == &pubkey_hex) {
        return true;
    }

    if !muted_words.is_empty() {
        let content_lower = event.content.to_lowercase();
        for word in muted_words {
            if content_lower.contains(&word.to_lowercase()) {
                return true;
            }
        }
    }

    if event.kind == Kind::Repost {
        for tag in event.tags.iter() {
            let tag_kind = tag.kind();
            if matches!(tag_kind, TagKind::SingleLetter(SingleLetterTag { character: Alphabet::P, .. })) {
                if let Some(original_author) = tag.content() {
                    let author_str = original_author.to_string();
                    if muted_pubkeys.iter().any(|p| p == &author_str) {
                        return true;
                    }
                }
            }
        }
    }

    false
}

fn extract_bolt11_amount_sats(bolt11: &str) -> Option<u64> {
    let lower = bolt11.to_lowercase();
    let sep_pos = lower.rfind('1')?;
    let hr_part = &lower[..sep_pos];

    let after_prefix = if hr_part.starts_with("lnbcrt") {
        &hr_part[6..]
    } else if hr_part.starts_with("lnbc") {
        &hr_part[4..]
    } else if hr_part.starts_with("lntbs") {
        &hr_part[5..]
    } else if hr_part.starts_with("lntb") {
        &hr_part[4..]
    } else {
        return None;
    };

    if after_prefix.is_empty() {
        return None;
    }

    let chars: Vec<char> = after_prefix.chars().collect();
    let mut i = 0;
    while i < chars.len() && chars[i].is_ascii_digit() {
        i += 1;
    }

    if i == 0 {
        return None;
    }

    let amount: u64 = after_prefix[..i].parse().ok()?;

    let msats = if i < chars.len() {
        match chars[i] {
            'm' => amount.checked_mul(100_000_000)?,
            'u' => amount.checked_mul(100_000)?,
            'n' => amount.checked_mul(100)?,
            'p' => amount / 10,
            _ => return None,
        }
    } else {
        amount.checked_mul(100_000_000_000)?
    };

    Some(msats / 1000)
}

fn extract_zap_amount_sats(event: &Event) -> u64 {
    for tag in event.tags.iter() {
        if tag.kind() == TagKind::Bolt11 {
            if let Some(bolt11) = tag.content() {
                if let Some(sats) = extract_bolt11_amount_sats(bolt11) {
                    return sats;
                }
            }
        }
    }

    for tag in event.tags.iter() {
        if tag.kind() == TagKind::Description {
            if let Some(desc_str) = tag.content() {
                if let Ok(zap_req) = serde_json::from_str::<serde_json::Value>(desc_str) {
                    if let Some(tags) = zap_req["tags"].as_array() {
                        for t in tags {
                            if let Some(arr) = t.as_array() {
                                if arr.len() >= 2 && arr[0].as_str() == Some("amount") {
                                    if let Some(amount_str) = arr[1].as_str() {
                                        if let Ok(millisats) = amount_str.parse::<u64>() {
                                            return millisats / 1000;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    0
}

fn extract_zap_sender(event: &Event) -> Option<String> {
    for tag in event.tags.iter() {
        if tag.kind() == TagKind::Description {
            if let Some(desc_str) = tag.content() {
                if let Ok(zap_req) = serde_json::from_str::<serde_json::Value>(desc_str) {
                    if let Some(pubkey) = zap_req["pubkey"].as_str() {
                        return Some(pubkey.to_string());
                    }
                }
            }
        }
    }
    None
}

fn extract_zap_comment(event: &Event) -> String {
    for tag in event.tags.iter() {
        if tag.kind() == TagKind::Description {
            if let Some(desc_str) = tag.content() {
                if let Ok(zap_req) = serde_json::from_str::<serde_json::Value>(desc_str) {
                    if let Some(content) = zap_req["content"].as_str() {
                        if !content.is_empty() {
                            return content.to_string();
                        }
                    }
                }
            }
        }
    }
    String::new()
}

fn metadata_to_flat_json(event: &Event, m: &Metadata) -> serde_json::Value {
    let location = m.custom.get("location")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    serde_json::json!({
        "pubkey": event.pubkey.to_hex(),
        "pubkeyHex": event.pubkey.to_hex(),
        "name": m.name.as_deref().unwrap_or(""),
        "display_name": m.display_name.as_deref().unwrap_or(""),
        "about": m.about.as_deref().unwrap_or(""),
        "picture": m.picture.as_deref().unwrap_or(""),
        "profileImage": m.picture.as_deref().unwrap_or(""),
        "banner": m.banner.as_deref().unwrap_or(""),
        "nip05": m.nip05.as_deref().unwrap_or(""),
        "lud16": m.lud16.as_deref().unwrap_or(""),
        "website": m.website.as_deref().unwrap_or(""),
        "location": location,
    })
}

pub async fn db_get_profile(pubkey_hex: String) -> Result<Option<String>> {
    let client = get_client_pub().await?;
    let pk = PublicKey::from_hex(&pubkey_hex)?;
    let metadata = client.database().metadata(pk).await?;
    match metadata {
        Some(m) => Ok(Some(m.as_json())),
        None => Ok(None),
    }
}

pub async fn db_get_profiles(pubkeys_hex: Vec<String>) -> Result<String> {
    let client = get_client_pub().await?;
    let authors: Vec<PublicKey> = pubkeys_hex
        .iter()
        .filter_map(|h| PublicKey::from_hex(h).ok())
        .collect();

    if authors.is_empty() {
        return Ok("{}".to_string());
    }

    let filter = Filter::new().authors(authors.clone()).kind(Kind::Metadata);
    let events = client.database().query(filter).await?;

    let mut result = serde_json::Map::new();
    for event in events.into_iter() {
        if let Ok(m) = Metadata::from_json(&event.content) {
            result.insert(event.pubkey.to_hex(), serde_json::from_str(&m.as_json())?);
        }
    }
    Ok(serde_json::to_string(&result)?)
}

pub async fn db_has_profile(pubkey_hex: String) -> Result<bool> {
    let client = get_client_pub().await?;
    let pk = PublicKey::from_hex(&pubkey_hex)?;
    let filter = Filter::new().author(pk).kind(Kind::Metadata).limit(1);
    let count = client.database().count(filter).await?;
    Ok(count > 0)
}

pub async fn db_search_profiles(query: String, limit: u32) -> Result<String> {
    let client = get_client_pub().await?;
    let filter = Filter::new().kind(Kind::Metadata).limit(2000);
    let events = client.database().query(filter).await?;

    let query_lower = query.to_lowercase();
    let mut results: Vec<serde_json::Value> = Vec::new();

    for event in events.into_iter() {
        if let Ok(m) = Metadata::from_json(&event.content) {
            let name = m.name.as_deref().unwrap_or("").to_lowercase();
            let display = m.display_name.as_deref().unwrap_or("").to_lowercase();
            let nip05 = m.nip05.as_deref().unwrap_or("").to_lowercase();

            if name.contains(&query_lower)
                || display.contains(&query_lower)
                || nip05.contains(&query_lower)
            {
                results.push(metadata_to_flat_json(&event, &m));
                if results.len() >= limit as usize {
                    break;
                }
            }
        }
    }

    Ok(serde_json::to_string(&results)?)
}

pub async fn db_get_following_list(pubkey_hex: String) -> Result<Vec<String>> {
    let client = get_client_pub().await?;
    let pk = PublicKey::from_hex(&pubkey_hex)?;
    let contacts = client.database().contacts_public_keys(pk).await?;
    Ok(contacts.into_iter().map(|pk| pk.to_hex()).collect())
}

pub async fn db_has_following_list(pubkey_hex: String) -> Result<bool> {
    let client = get_client_pub().await?;
    let pk = PublicKey::from_hex(&pubkey_hex)?;
    let filter = Filter::new().author(pk).kind(Kind::ContactList).limit(1);
    let count = client.database().count(filter).await?;
    Ok(count > 0)
}

pub async fn db_get_mute_list(pubkey_hex: String) -> Result<Vec<String>> {
    let client = get_client_pub().await?;
    let pk = PublicKey::from_hex(&pubkey_hex)?;
    let filter = Filter::new().author(pk).kind(Kind::MuteList).limit(1);
    let events = client.database().query(filter).await?;

    match events.first_owned() {
        Some(event) => Ok(event
            .tags
            .public_keys()
            .map(|pk| pk.to_hex())
            .collect()),
        None => Ok(Vec::new()),
    }
}

pub async fn db_has_mute_list(pubkey_hex: String) -> Result<bool> {
    let client = get_client_pub().await?;
    let pk = PublicKey::from_hex(&pubkey_hex)?;
    let filter = Filter::new().author(pk).kind(Kind::MuteList).limit(1);
    let count = client.database().count(filter).await?;
    Ok(count > 0)
}

pub async fn db_save_following_list(pubkey_hex: String, follows_hex: Vec<String>) -> Result<()> {
    let client = get_client_pub().await?;
    let pk = PublicKey::from_hex(&pubkey_hex)?;
    let tags: Vec<Tag> = follows_hex
        .iter()
        .filter_map(|h| PublicKey::from_hex(h).ok())
        .map(|pk| Tag::public_key(pk))
        .collect();

    let event = EventBuilder::new(Kind::ContactList, "")
        .tags(tags)
        .custom_created_at(Timestamp::now())
        .sign_with_keys(&Keys::generate())?;

    let unsigned = event.as_json();
    let patched: serde_json::Value = serde_json::from_str(&unsigned)?;
    let mut patched = patched;
    patched["pubkey"] = serde_json::Value::String(pk.to_hex());
    let patched_event = Event::from_json(patched.to_string())?;

    let _ = client.database().save_event(&patched_event).await;
    Ok(())
}

pub async fn db_delete_following_list(pubkey_hex: String) -> Result<()> {
    let client = get_client_pub().await?;
    let pk = PublicKey::from_hex(&pubkey_hex)?;
    let filter = Filter::new().author(pk).kind(Kind::ContactList);
    client.database().delete(filter).await?;
    Ok(())
}

pub async fn db_save_mute_list(pubkey_hex: String, muted_hex: Vec<String>) -> Result<()> {
    let client = get_client_pub().await?;
    let pk = PublicKey::from_hex(&pubkey_hex)?;
    let tags: Vec<Tag> = muted_hex
        .iter()
        .filter_map(|h| PublicKey::from_hex(h).ok())
        .map(|pk| Tag::public_key(pk))
        .collect();

    let event = EventBuilder::new(Kind::MuteList, "")
        .tags(tags)
        .custom_created_at(Timestamp::now())
        .sign_with_keys(&Keys::generate())?;

    let patched: serde_json::Value = serde_json::from_str(&event.as_json())?;
    let mut patched = patched;
    patched["pubkey"] = serde_json::Value::String(pk.to_hex());
    let patched_event = Event::from_json(patched.to_string())?;

    let _ = client.database().save_event(&patched_event).await;
    Ok(())
}

pub async fn db_delete_mute_list(pubkey_hex: String) -> Result<()> {
    let client = get_client_pub().await?;
    let pk = PublicKey::from_hex(&pubkey_hex)?;
    let filter = Filter::new().author(pk).kind(Kind::MuteList);
    client.database().delete(filter).await?;
    Ok(())
}

pub async fn db_get_feed_notes(authors_hex: Vec<String>, limit: u32, muted_pubkeys: Vec<String>, muted_words: Vec<String>) -> Result<String> {
    let client = get_client_pub().await?;
    let authors: Vec<PublicKey> = authors_hex
        .iter()
        .filter_map(|h| PublicKey::from_hex(h).ok())
        .collect();

    let filter = Filter::new()
        .authors(authors)
        .kinds([Kind::TextNote, Kind::Repost])
        .limit(limit as usize);
    let events = client.database().query(filter).await?;

    let json: Vec<serde_json::Value> = events
        .into_iter()
        .filter(|e| !is_event_muted(e, &muted_pubkeys, &muted_words))
        .filter_map(|e| serde_json::from_str(&e.as_json()).ok())
        .collect();
    Ok(serde_json::to_string(&json)?)
}

pub async fn db_get_profile_notes(pubkey_hex: String, limit: u32, muted_pubkeys: Vec<String>, muted_words: Vec<String>) -> Result<String> {
    let client = get_client_pub().await?;
    let pk = PublicKey::from_hex(&pubkey_hex)?;

    let filter = Filter::new()
        .author(pk)
        .kinds([Kind::TextNote, Kind::Repost])
        .limit(limit as usize);
    let events = client.database().query(filter).await?;

    let json: Vec<serde_json::Value> = events
        .into_iter()
        .filter(|e| !is_event_muted(e, &muted_pubkeys, &muted_words))
        .filter_map(|e| serde_json::from_str(&e.as_json()).ok())
        .collect();
    Ok(serde_json::to_string(&json)?)
}

pub async fn db_get_hashtag_notes(hashtag: String, limit: u32, muted_pubkeys: Vec<String>, muted_words: Vec<String>) -> Result<String> {
    let client = get_client_pub().await?;

    let filter = Filter::new()
        .kind(Kind::TextNote)
        .hashtag(hashtag)
        .limit(limit as usize);
    let events = client.database().query(filter).await?;

    let json: Vec<serde_json::Value> = events
        .into_iter()
        .filter(|e| !is_event_muted(e, &muted_pubkeys, &muted_words))
        .filter_map(|e| serde_json::from_str(&e.as_json()).ok())
        .collect();
    Ok(serde_json::to_string(&json)?)
}

pub async fn db_get_event(event_id: String) -> Result<Option<String>> {
    let client = get_client_pub().await?;
    let id = EventId::from_hex(&event_id)?;
    let event = client.database().event_by_id(&id).await?;
    match event {
        Some(e) => Ok(Some(e.as_json())),
        None => Ok(None),
    }
}

pub async fn db_event_exists(event_id: String) -> Result<bool> {
    let client = get_client_pub().await?;
    let id = EventId::from_hex(&event_id)?;
    let event = client.database().event_by_id(&id).await?;
    Ok(event.is_some())
}

pub async fn db_save_event(event_json: String) -> Result<bool> {
    let client = get_client_pub().await?;
    let event = Event::from_json(&event_json)?;
    let status = client.database().save_event(&event).await?;
    Ok(matches!(status, SaveEventStatus::Success))
}

pub async fn db_save_events(events_json: String) -> Result<u32> {
    let client = get_client_pub().await?;
    let events: Vec<serde_json::Value> = serde_json::from_str(&events_json)?;
    let mut saved: u32 = 0;

    for val in events {
        if let Ok(event) = Event::from_json(val.to_string()) {
            if let Ok(status) = client.database().save_event(&event).await {
                if matches!(status, SaveEventStatus::Success) {
                    saved += 1;
                }
            }
        }
    }
    Ok(saved)
}

pub async fn db_query_events(filter_json: String, limit: u32) -> Result<String> {
    let client = get_client_pub().await?;
    let mut filter = Filter::from_json(&filter_json)?;
    if limit > 0 {
        filter = filter.limit(limit as usize);
    }
    let events = client.database().query(filter).await?;

    let json: Vec<serde_json::Value> = events
        .into_iter()
        .filter_map(|e| serde_json::from_str(&e.as_json()).ok())
        .collect();
    Ok(serde_json::to_string(&json)?)
}

pub async fn db_get_replies(note_id: String, limit: u32, muted_pubkeys: Vec<String>, muted_words: Vec<String>) -> Result<String> {
    let client = get_client_pub().await?;
    let id = EventId::from_hex(&note_id)?;

    let filter = Filter::new()
        .kind(Kind::TextNote)
        .event(id)
        .limit(limit as usize);
    let events = client.database().query(filter).await?;

    let json: Vec<serde_json::Value> = events
        .into_iter()
        .filter(|e| !is_event_muted(e, &muted_pubkeys, &muted_words))
        .filter_map(|e| serde_json::from_str(&e.as_json()).ok())
        .collect();
    Ok(serde_json::to_string(&json)?)
}

pub async fn db_get_notifications(user_pubkey_hex: String, limit: u32, muted_pubkeys: Vec<String>, muted_words: Vec<String>) -> Result<String> {
    let client = get_client_pub().await?;
    let pk = PublicKey::from_hex(&user_pubkey_hex)?;

    let filter = Filter::new()
        .pubkey(pk)
        .kinds([Kind::TextNote, Kind::Repost, Kind::Reaction, Kind::ZapReceipt])
        .limit(limit as usize);
    let events = client.database().query(filter).await?;

    let json: Vec<serde_json::Value> = events
        .into_iter()
        .filter(|e| e.pubkey.to_hex() != user_pubkey_hex)
        .filter(|e| !is_event_muted(e, &muted_pubkeys, &muted_words))
        .filter_map(|e| serde_json::from_str(&e.as_json()).ok())
        .collect();
    Ok(serde_json::to_string(&json)?)
}

pub async fn db_get_interaction_counts(note_id: String) -> Result<String> {
    let result = db_get_batch_interaction_counts(vec![note_id.clone()]).await?;
    let map: serde_json::Value = serde_json::from_str(&result)?;
    if let Some(val) = map.get(&note_id) {
        return Ok(val.to_string());
    }
    Ok(serde_json::json!({"reactions":0,"reposts":0,"zaps":0,"replies":0}).to_string())
}

pub async fn db_get_batch_interaction_counts(note_ids: Vec<String>) -> Result<String> {
    let client = get_client_pub().await?;

    let ids: Vec<EventId> = note_ids
        .iter()
        .filter_map(|id| EventId::from_hex(id).ok())
        .collect();

    if ids.is_empty() {
        return Ok("{}".to_string());
    }

    let filter = Filter::new()
        .kinds([Kind::Reaction, Kind::Repost, Kind::ZapReceipt, Kind::TextNote])
        .events(ids);
    let events = client.database().query(filter).await?;

    let mut counts: HashMap<String, [usize; 4]> = HashMap::new();
    for nid in &note_ids {
        counts.insert(nid.clone(), [0; 4]);
    }

    for event in events.iter() {
        let kind = event.kind;
        let zap_sats = if kind == Kind::ZapReceipt {
            extract_zap_amount_sats(event) as usize
        } else {
            0
        };

        let mut counted_for: std::collections::HashSet<String> = std::collections::HashSet::new();
        for tag in event.tags.iter() {
            let tag_kind = tag.kind();
            if matches!(tag_kind, TagKind::SingleLetter(SingleLetterTag { character: Alphabet::E, .. })) {
                if let Some(ref_id) = tag.content() {
                    let ref_hex = ref_id.to_string();
                    if counted_for.contains(&ref_hex) {
                        continue;
                    }
                    if let Some(c) = counts.get_mut(&ref_hex) {
                        counted_for.insert(ref_hex);
                        match kind {
                            k if k == Kind::Reaction => c[0] += 1,
                            k if k == Kind::Repost => c[1] += 1,
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
            }),
        );
    }
    Ok(serde_json::to_string(&result)?)
}

pub async fn db_get_batch_interaction_data(
    note_ids: Vec<String>,
    user_pubkey_hex: String,
) -> Result<String> {
    let client = get_client_pub().await?;

    let ids: Vec<EventId> = note_ids
        .iter()
        .filter_map(|id| EventId::from_hex(id).ok())
        .collect();

    if ids.is_empty() {
        return Ok("{}".to_string());
    }

    let user_pk = PublicKey::from_hex(&user_pubkey_hex).ok();

    let filter = Filter::new()
        .kinds([Kind::Reaction, Kind::Repost, Kind::ZapReceipt, Kind::TextNote])
        .events(ids);
    let events = client.database().query(filter).await?;

    let mut counts: HashMap<String, [usize; 4]> = HashMap::new();
    let mut user_reacted: HashMap<String, bool> = HashMap::new();
    let mut user_reposted: HashMap<String, bool> = HashMap::new();
    let mut user_zapped: HashMap<String, bool> = HashMap::new();

    for nid in &note_ids {
        counts.insert(nid.clone(), [0; 4]);
        user_reacted.insert(nid.clone(), false);
        user_reposted.insert(nid.clone(), false);
        user_zapped.insert(nid.clone(), false);
    }

    for event in events.iter() {
        let kind = event.kind;
        let is_user = user_pk.as_ref().map_or(false, |pk| event.pubkey == *pk);

        let zap_sats = if kind == Kind::ZapReceipt {
            extract_zap_amount_sats(event) as usize
        } else {
            0
        };

        let is_zap_sender = if kind == Kind::ZapReceipt {
            user_pk.as_ref().map_or(false, |pk| {
                extract_zap_sender(event)
                    .map_or(false, |sender| sender == pk.to_hex())
            })
        } else {
            false
        };

        let mut counted_for: std::collections::HashSet<String> = std::collections::HashSet::new();
        for tag in event.tags.iter() {
            let tag_kind = tag.kind();
            if matches!(tag_kind, TagKind::SingleLetter(SingleLetterTag { character: Alphabet::E, .. })) {
                if let Some(ref_id) = tag.content() {
                    let ref_hex = ref_id.to_string();
                    if counted_for.contains(&ref_hex) {
                        continue;
                    }
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
                            k if k == Kind::ZapReceipt => {
                                c[2] += zap_sats;
                                if is_zap_sender {
                                    user_zapped.insert(ref_hex, true);
                                }
                            }
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
                "hasZapped": user_zapped.get(nid).copied().unwrap_or(false),
            }),
        );
    }
    Ok(serde_json::to_string(&result)?)
}

pub async fn db_has_user_reacted(note_id: String, user_pubkey_hex: String) -> Result<bool> {
    let client = get_client_pub().await?;
    let id = EventId::from_hex(&note_id)?;
    let pk = PublicKey::from_hex(&user_pubkey_hex)?;

    let filter = Filter::new().author(pk).kind(Kind::Reaction).event(id).limit(1);
    let count = client.database().count(filter).await?;
    Ok(count > 0)
}

pub async fn db_has_user_reposted(note_id: String, user_pubkey_hex: String) -> Result<bool> {
    let client = get_client_pub().await?;
    let id = EventId::from_hex(&note_id)?;
    let pk = PublicKey::from_hex(&user_pubkey_hex)?;

    let filter = Filter::new().author(pk).kind(Kind::Repost).event(id).limit(1);
    let count = client.database().count(filter).await?;
    Ok(count > 0)
}

pub async fn db_get_detailed_interactions(note_id: String) -> Result<String> {
    let client = get_client_pub().await?;
    let id = EventId::from_hex(&note_id)?;

    let filter = Filter::new()
        .kinds([Kind::Reaction, Kind::Repost, Kind::ZapReceipt])
        .event(id);
    let events = client.database().query(filter).await?;

    let mut results: Vec<serde_json::Value> = Vec::new();

    for event in events.iter() {
        match event.kind {
            k if k == Kind::Reaction => {
                results.push(serde_json::json!({
                    "type": "reaction",
                    "pubkey": event.pubkey.to_hex(),
                    "content": event.content,
                    "createdAt": event.created_at.as_secs(),
                }));
            }
            k if k == Kind::Repost => {
                results.push(serde_json::json!({
                    "type": "repost",
                    "pubkey": event.pubkey.to_hex(),
                    "content": "",
                    "createdAt": event.created_at.as_secs(),
                }));
            }
            k if k == Kind::ZapReceipt => {
                let amount = extract_zap_amount_sats(event);
                let sender = extract_zap_sender(event).unwrap_or_default();
                let comment = extract_zap_comment(event);
                results.push(serde_json::json!({
                    "type": "zap",
                    "pubkey": sender,
                    "content": comment,
                    "zapAmount": amount,
                    "createdAt": event.created_at.as_secs(),
                }));
            }
            _ => {}
        }
    }

    Ok(serde_json::to_string(&results)?)
}

pub async fn db_get_articles(limit: u32, muted_pubkeys: Vec<String>, muted_words: Vec<String>) -> Result<String> {
    let client = get_client_pub().await?;
    let filter = Filter::new()
        .kind(Kind::LongFormTextNote)
        .limit(limit as usize);
    let events = client.database().query(filter).await?;
    
    let mut events_vec: Vec<Event> = events
        .into_iter()
        .filter(|e| !is_event_muted(e, &muted_pubkeys, &muted_words))
        .collect();
    events_vec.sort_by(|a, b| b.created_at.cmp(&a.created_at));

    let json: Vec<serde_json::Value> = events_vec
        .into_iter()
        .filter_map(|e| serde_json::from_str(&e.as_json()).ok())
        .collect();
    Ok(serde_json::to_string(&json)?)
}

pub async fn db_get_articles_by_authors(authors_hex: Vec<String>, limit: u32, muted_pubkeys: Vec<String>, muted_words: Vec<String>) -> Result<String> {
    let client = get_client_pub().await?;
    
    let authors: Vec<PublicKey> = authors_hex
        .iter()
        .filter_map(|h| PublicKey::from_hex(h).ok())
        .collect();

    if authors.is_empty() {
        return Ok("[]".to_string());
    }

    let filter = Filter::new()
        .kind(Kind::LongFormTextNote)
        .authors(authors)
        .limit(limit as usize);
    let events = client.database().query(filter).await?;
    
    let mut events_vec: Vec<Event> = events
        .into_iter()
        .filter(|e| !is_event_muted(e, &muted_pubkeys, &muted_words))
        .collect();
    events_vec.sort_by(|a, b| b.created_at.cmp(&a.created_at));

    let json: Vec<serde_json::Value> = events_vec
        .into_iter()
        .filter_map(|e| serde_json::from_str(&e.as_json()).ok())
        .collect();
    Ok(serde_json::to_string(&json)?)
}

pub async fn db_find_user_repost_event_id(
    user_pubkey_hex: String,
    note_id: String,
) -> Result<Option<String>> {
    let client = get_client_pub().await?;
    let pk = PublicKey::from_hex(&user_pubkey_hex)?;
    let id = EventId::from_hex(&note_id)?;

    let filter = Filter::new().author(pk).kind(Kind::Repost).event(id).limit(1);
    let events = client.database().query(filter).await?;

    Ok(events.first_owned().map(|e| e.id.to_hex()))
}

pub async fn db_get_random_profiles(limit: u32) -> Result<String> {
    let client = get_client_pub().await?;
    let filter = Filter::new().kind(Kind::Metadata).limit(limit as usize * 3);
    let events = client.database().query(filter).await?;

    let mut results: Vec<serde_json::Value> = Vec::new();
    for event in events.into_iter() {
        if let Ok(m) = Metadata::from_json(&event.content) {
            if m.picture.is_some() {
                results.push(metadata_to_flat_json(&event, &m));
                if results.len() >= limit as usize {
                    break;
                }
            }
        }
    }
    Ok(serde_json::to_string(&results)?)
}

pub async fn db_save_profile(pubkey_hex: String, profile_json: String) -> Result<()> {
    let client = get_client_pub().await?;
    let pk = PublicKey::from_hex(&pubkey_hex)?;

    let keys = Keys::generate();
    let event = EventBuilder::new(Kind::Metadata, &profile_json)
        .custom_created_at(Timestamp::now())
        .sign_with_keys(&keys)?;

    let raw: serde_json::Value = serde_json::from_str(&event.as_json())?;
    let mut raw = raw;
    raw["pubkey"] = serde_json::Value::String(pk.to_hex());
    if let Ok(patched) = Event::from_json(raw.to_string()) {
        let _ = client.database().save_event(&patched).await;
    }
    Ok(())
}

pub async fn db_count_events(filter_json: String) -> Result<u32> {
    let client = get_client_pub().await?;
    let filter = Filter::from_json(&filter_json)?;
    let count = client.database().count(filter).await?;
    Ok(count as u32)
}

pub async fn db_wipe() -> Result<()> {
    let client = get_client_pub().await?;
    client.database().wipe().await?;
    Ok(())
}

pub async fn db_search_notes(query: String, limit: u32) -> Result<String> {
    let client = get_client_pub().await?;
    let filter = Filter::new().kind(Kind::TextNote).limit(500);
    let events = client.database().query(filter).await?;

    let query_lower = query.to_lowercase();
    let mut results: Vec<serde_json::Value> = Vec::new();

    for event in events.into_iter() {
        if event.content.to_lowercase().contains(&query_lower) {
            if let Ok(val) = serde_json::from_str::<serde_json::Value>(&event.as_json()) {
                results.push(val);
                if results.len() >= limit as usize {
                    break;
                }
            }
        }
    }
    Ok(serde_json::to_string(&results)?)
}

pub async fn db_get_oldest_events(limit: u32) -> Result<String> {
    let client = get_client_pub().await?;
    let filter = Filter::new().limit(limit as usize);
    let events = client.database().query(filter).await?;
    
    let mut events_vec: Vec<Event> = events.into_iter().collect();
    events_vec.sort_by(|a, b| a.created_at.cmp(&b.created_at));
    
    let json: Vec<serde_json::Value> = events_vec
        .into_iter()
        .filter_map(|e| serde_json::from_str(&e.as_json()).ok())
        .collect();
    Ok(serde_json::to_string(&json)?)
}

pub async fn db_cleanup_old_events(days_to_keep: u32) -> Result<u32> {
    let client = get_client_pub().await?;
    let now = Timestamp::now();
    let cutoff = now.as_secs() - (days_to_keep as u64 * 86400);
    let cutoff_ts = Timestamp::from(cutoff);
    
    let filter = Filter::new()
        .kinds([
            Kind::TextNote,
            Kind::Repost,
            Kind::Reaction,
            Kind::ZapReceipt,
        ])
        .until(cutoff_ts);
    
    let events = client.database().query(filter.clone()).await?;
    let count = events.len() as u32;
    
    if count > 0 {
        client.database().delete(filter).await?;
    }
    
    Ok(count)
}

pub async fn db_get_database_stats() -> Result<String> {
    let client = get_client_pub().await?;
    
    let text_notes = client.database().count(Filter::new().kind(Kind::TextNote)).await?;
    let metadata = client.database().count(Filter::new().kind(Kind::Metadata)).await?;
    let contacts = client.database().count(Filter::new().kind(Kind::ContactList)).await?;
    let reactions = client.database().count(Filter::new().kind(Kind::Reaction)).await?;
    let reposts = client.database().count(Filter::new().kind(Kind::Repost)).await?;
    let zaps = client.database().count(Filter::new().kind(Kind::ZapReceipt)).await?;
    let articles = client.database().count(Filter::new().kind(Kind::LongFormTextNote)).await?;
    
    let all_events = client.database().count(Filter::new()).await?;
    
    let stats = serde_json::json!({
        "totalEvents": all_events,
        "textNotes": text_notes,
        "metadata": metadata,
        "contacts": contacts,
        "reactions": reactions,
        "reposts": reposts,
        "zaps": zaps,
        "articles": articles,
    });
    
    Ok(stats.to_string())
}

async fn hydrate_notes(
    client: &Client,
    events: &[Event],
    filter_replies: bool,
) -> Result<String> {
    if events.is_empty() {
        return Ok("[]".to_string());
    }

    let mut notes: Vec<serde_json::Value> = Vec::new();
    let mut pubkeys_needed: HashSet<String> = HashSet::new();
    let mut note_ids: Vec<String> = Vec::new();

    for event in events {
        let is_repost = event.kind == Kind::Repost;

        let mut id = event.id.to_hex();
        let mut pubkey = event.pubkey.to_hex();
        let mut content = event.content.clone();
        let mut created_at = event.created_at.as_secs();
        let mut reposted_by: Option<String> = None;
        let mut repost_created_at: Option<u64> = None;

        let tags: Vec<Vec<String>> = event.tags.iter()
            .map(|tag| tag.clone().to_vec())
            .collect();

        let mut root_id: Option<String> = None;
        let mut parent_id: Option<String> = None;
        let mut is_quote = false;
        let mut e_tags: Vec<String> = Vec::new();

        for tag in tags.iter() {
            if tag.len() < 2 { continue; }
            if tag[0] == "q" {
                is_quote = true;
                continue;
            }
            if tag[0] == "e" {
                let ref_id = &tag[1];
                if tag.len() >= 4 {
                    match tag[3].as_str() {
                        "root" => root_id = Some(ref_id.clone()),
                        "reply" => parent_id = Some(ref_id.clone()),
                        "mention" => continue,
                        _ => e_tags.push(ref_id.clone()),
                    }
                } else {
                    e_tags.push(ref_id.clone());
                }
            }
        }

        if root_id.is_none() && parent_id.is_none() && !e_tags.is_empty() && !is_quote {
            if e_tags.len() == 1 {
                root_id = Some(e_tags[0].clone());
                parent_id = Some(e_tags[0].clone());
            } else {
                root_id = Some(e_tags.first().unwrap().clone());
                parent_id = Some(e_tags.last().unwrap().clone());
            }
        } else if root_id.is_some() && parent_id.is_none() && !is_quote {
            parent_id = root_id.clone();
        }

        let mut is_reply = (root_id.is_some() || parent_id.is_some()) && !is_quote;

        if is_repost {
            reposted_by = Some(pubkey.clone());
            repost_created_at = Some(created_at);

            for tag in tags.iter() {
                if !tag.is_empty() && tag[0] == "e" && tag.len() > 1 {
                    id = tag[1].clone();
                    break;
                }
            }

            for tag in tags.iter() {
                if !tag.is_empty() && tag[0] == "p" && tag.len() > 1 {
                    pubkey = tag[1].clone();
                    break;
                }
            }

            if !content.is_empty() {
                if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(c) = parsed["content"].as_str() {
                        content = c.to_string();
                    }
                    if let Some(p) = parsed["pubkey"].as_str() {
                        pubkey = p.to_string();
                    }
                    if let Some(ca) = parsed["created_at"].as_u64() {
                        created_at = ca;
                    }

                    if let Some(parsed_tags) = parsed["tags"].as_array() {
                        root_id = None;
                        parent_id = None;
                        let mut repost_e_tags: Vec<String> = Vec::new();

                        for tag in parsed_tags {
                            if let Some(arr) = tag.as_array() {
                                if arr.len() >= 2 && arr[0].as_str() == Some("e") {
                                    if let Some(ref_id) = arr[1].as_str() {
                                        repost_e_tags.push(ref_id.to_string());
                                        if arr.len() >= 4 {
                                            match arr[3].as_str() {
                                                Some("root") => root_id = Some(ref_id.to_string()),
                                                Some("reply") => parent_id = Some(ref_id.to_string()),
                                                _ => {}
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        if root_id.is_none() && parent_id.is_none() && !repost_e_tags.is_empty() {
                            if repost_e_tags.len() == 1 {
                                root_id = Some(repost_e_tags[0].clone());
                                parent_id = Some(repost_e_tags[0].clone());
                            } else {
                                root_id = Some(repost_e_tags.first().unwrap().clone());
                                parent_id = Some(repost_e_tags.last().unwrap().clone());
                            }
                        } else if root_id.is_some() && parent_id.is_none() {
                            parent_id = root_id.clone();
                        }
                        is_reply = root_id.is_some() || parent_id.is_some();
                    }
                }
            }
        }

        if filter_replies && is_reply && !is_repost {
            continue;
        }

        if !pubkey.is_empty() {
            pubkeys_needed.insert(pubkey.clone());
        }
        if !id.is_empty() {
            note_ids.push(id.clone());
        }

        let json_tags: Vec<serde_json::Value> = tags.iter()
            .map(|t: &Vec<String>| serde_json::Value::Array(
                t.iter().map(|s| serde_json::json!(s)).collect()
            ))
            .collect();

        notes.push(serde_json::json!({
            "id": id,
            "pubkey": pubkey,
            "author": pubkey,
            "content": content,
            "created_at": created_at,
            "tags": json_tags,
            "isRepost": is_repost,
            "repostedBy": reposted_by,
            "repostCreatedAt": repost_created_at,
            "isReply": is_reply,
            "rootId": root_id,
            "parentId": parent_id,
            "authorName": serde_json::Value::Null,
            "authorImage": serde_json::Value::Null,
            "authorNip05": serde_json::Value::Null,
            "reactionCount": 0,
            "repostCount": 0,
            "replyCount": 0,
            "zapCount": 0,
        }));
    }

    if notes.is_empty() {
        return Ok("[]".to_string());
    }

    let authors: Vec<PublicKey> = pubkeys_needed.iter()
        .filter_map(|h| PublicKey::from_hex(h).ok())
        .collect();

    if !authors.is_empty() {
        let filter = Filter::new().authors(authors).kind(Kind::Metadata);
        let profile_events = client.database().query(filter).await?;
        let mut profiles: HashMap<String, (String, String, String)> = HashMap::new();

        for pe in profile_events {
            if let Ok(m) = Metadata::from_json(&pe.content) {
                let name = m.name.clone()
                    .or_else(|| m.display_name.clone())
                    .unwrap_or_default();
                let picture = m.picture.clone().unwrap_or_default();
                let nip05 = m.nip05.clone().unwrap_or_default();
                profiles.insert(pe.pubkey.to_hex(), (name, picture, nip05));
            }
        }

        for note in notes.iter_mut() {
            if let Some(pk) = note["pubkey"].as_str() {
                if let Some((name, picture, nip05)) = profiles.get(pk) {
                    note["authorName"] = serde_json::json!(name);
                    note["authorImage"] = serde_json::json!(picture);
                    note["authorNip05"] = serde_json::json!(nip05);
                }
            }
        }
    }

    let ids: Vec<EventId> = note_ids.iter()
        .filter_map(|id| EventId::from_hex(id).ok())
        .collect();

    if !ids.is_empty() {
        let mut counts: HashMap<String, [usize; 4]> = HashMap::new();
        for nid in &note_ids {
            counts.insert(nid.clone(), [0; 4]);
        }

        let count_filter = Filter::new()
            .kinds([Kind::Reaction, Kind::Repost, Kind::ZapReceipt, Kind::TextNote])
            .events(ids);
        let count_events = client.database().query(count_filter).await?;

        for ce in count_events.iter() {
            let kind = ce.kind;
            let zap_sats = if kind == Kind::ZapReceipt {
                extract_zap_amount_sats(ce) as usize
            } else { 0 };

            let mut counted_for: HashSet<String> = HashSet::new();
            for tag in ce.tags.iter() {
                let tag_kind = tag.kind();
                if matches!(tag_kind, TagKind::SingleLetter(SingleLetterTag { character: Alphabet::E, .. })) {
                    if let Some(ref_id) = tag.content() {
                        let ref_hex = ref_id.to_string();
                        if counted_for.contains(&ref_hex) { continue; }
                        if let Some(c) = counts.get_mut(&ref_hex) {
                            counted_for.insert(ref_hex);
                            match kind {
                                k if k == Kind::Reaction => c[0] += 1,
                                k if k == Kind::Repost => c[1] += 1,
                                k if k == Kind::ZapReceipt => c[2] += zap_sats,
                                k if k == Kind::TextNote => c[3] += 1,
                                _ => {}
                            }
                        }
                    }
                }
            }
        }

        for note in notes.iter_mut() {
            if let Some(nid) = note["id"].as_str() {
                if let Some(c) = counts.get(nid) {
                    note["reactionCount"] = serde_json::json!(c[0]);
                    note["repostCount"] = serde_json::json!(c[1]);
                    note["zapCount"] = serde_json::json!(c[2]);
                    note["replyCount"] = serde_json::json!(c[3]);
                }
            }
        }
    }

    Ok(serde_json::to_string(&notes)?)
}

pub async fn db_get_hydrated_feed_notes(
    authors_hex: Vec<String>,
    limit: u32,
    muted_pubkeys: Vec<String>,
    muted_words: Vec<String>,
    filter_replies: bool,
) -> Result<String> {
    let client = get_client_pub().await?;
    let authors: Vec<PublicKey> = authors_hex.iter()
        .filter_map(|h| PublicKey::from_hex(h).ok())
        .collect();

    let filter = Filter::new()
        .authors(authors)
        .kinds([Kind::TextNote, Kind::Repost])
        .limit(limit as usize);
    let events = client.database().query(filter).await?;

    let filtered: Vec<Event> = events.into_iter()
        .filter(|e| !is_event_muted(e, &muted_pubkeys, &muted_words))
        .collect();

    hydrate_notes(&client, &filtered, filter_replies).await
}

pub async fn db_get_hydrated_profile_notes(
    pubkey_hex: String,
    limit: u32,
    muted_pubkeys: Vec<String>,
    muted_words: Vec<String>,
    filter_replies: bool,
) -> Result<String> {
    let client = get_client_pub().await?;
    let pk = PublicKey::from_hex(&pubkey_hex)?;

    let filter = Filter::new()
        .author(pk)
        .kinds([Kind::TextNote, Kind::Repost])
        .limit(limit as usize);
    let events = client.database().query(filter).await?;

    let filtered: Vec<Event> = events.into_iter()
        .filter(|e| !is_event_muted(e, &muted_pubkeys, &muted_words))
        .collect();

    hydrate_notes(&client, &filtered, filter_replies).await
}

pub async fn db_get_hydrated_hashtag_notes(
    hashtag: String,
    limit: u32,
    muted_pubkeys: Vec<String>,
    muted_words: Vec<String>,
) -> Result<String> {
    let client = get_client_pub().await?;

    let filter = Filter::new()
        .kind(Kind::TextNote)
        .hashtag(hashtag)
        .limit(limit as usize);
    let events = client.database().query(filter).await?;

    let filtered: Vec<Event> = events.into_iter()
        .filter(|e| !is_event_muted(e, &muted_pubkeys, &muted_words))
        .collect();

    hydrate_notes(&client, &filtered, true).await
}

pub async fn db_get_hydrated_replies(
    note_id: String,
    limit: u32,
    muted_pubkeys: Vec<String>,
    muted_words: Vec<String>,
) -> Result<String> {
    let client = get_client_pub().await?;
    let id = EventId::from_hex(&note_id)?;

    let filter = Filter::new()
        .kind(Kind::TextNote)
        .event(id)
        .limit(limit as usize);
    let events = client.database().query(filter).await?;

    let filtered: Vec<Event> = events.into_iter()
        .filter(|e| !is_event_muted(e, &muted_pubkeys, &muted_words))
        .collect();

    hydrate_notes(&client, &filtered, false).await
}

pub async fn db_get_hydrated_note(event_id: String) -> Result<Option<String>> {
    let client = get_client_pub().await?;
    let id = EventId::from_hex(&event_id)?;
    let event = client.database().event_by_id(&id).await?;

    match event {
        Some(e) => {
            let result = hydrate_notes(&client, &[e], false).await?;
            let arr: Vec<serde_json::Value> = serde_json::from_str(&result)?;
            if arr.is_empty() {
                Ok(None)
            } else {
                Ok(Some(arr[0].to_string()))
            }
        }
        None => Ok(None),
    }
}

async fn hydrate_notification_events(
    client: &Client,
    events: &[Event],
    user_pubkey_hex: &str,
) -> Result<String> {
    if events.is_empty() {
        return Ok("[]".to_string());
    }

    let mut items: Vec<serde_json::Value> = Vec::new();
    let mut pubkeys_needed: HashSet<String> = HashSet::new();

    for event in events {
        if event.pubkey.to_hex() == user_pubkey_hex {
            continue;
        }

        let kind_num = event.kind.as_u16();
        let event_id = event.id.to_hex();
        let pubkey = event.pubkey.to_hex();
        let content = event.content.clone();
        let created_at = event.created_at.as_secs();

        let tags: Vec<Vec<String>> = event.tags.iter()
            .map(|tag| tag.clone().to_vec())
            .collect();

        let mut notification_type: &str;
        let mut target_note_id: Option<String> = None;
        let mut zap_amount: Option<u64> = None;
        let mut from_pubkey = pubkey.clone();

        match kind_num {
            1 => {
                let mut has_mention = false;
                notification_type = "reply";
                for tag in &tags {
                    if tag.len() >= 2 && tag[0] == "e" {
                        target_note_id = Some(tag[1].clone());
                        if tag.len() >= 4 && (tag[3] == "reply" || tag[3] == "root") {
                            notification_type = "reply";
                            has_mention = false;
                            break;
                        }
                        has_mention = true;
                    }
                }
                if has_mention {
                    notification_type = "mention";
                }
            }
            6 => {
                notification_type = "repost";
                for tag in &tags {
                    if tag.len() >= 2 && tag[0] == "e" {
                        target_note_id = Some(tag[1].clone());
                        break;
                    }
                }
            }
            7 => {
                notification_type = "reaction";
                for tag in &tags {
                    if tag.len() >= 2 && tag[0] == "e" {
                        target_note_id = Some(tag[1].clone());
                        break;
                    }
                }
            }
            9735 => {
                notification_type = "zap";
                let sats = extract_zap_amount_sats(event);
                if sats > 0 {
                    zap_amount = Some(sats);
                }
                if let Some(sender) = extract_zap_sender(event) {
                    from_pubkey = sender;
                }
                for tag in &tags {
                    if tag.len() >= 2 && tag[0] == "e" {
                        target_note_id = Some(tag[1].clone());
                        break;
                    }
                }
            }
            _ => {
                notification_type = "mention";
            }
        }

        pubkeys_needed.insert(from_pubkey.clone());

        items.push(serde_json::json!({
            "id": event_id,
            "type": notification_type,
            "fromPubkey": from_pubkey,
            "targetNoteId": target_note_id,
            "content": content,
            "createdAt": created_at,
            "fromName": serde_json::Value::Null,
            "fromImage": serde_json::Value::Null,
            "zapAmount": zap_amount,
        }));
    }

    if items.is_empty() {
        return Ok("[]".to_string());
    }

    let authors: Vec<PublicKey> = pubkeys_needed.iter()
        .filter_map(|h| PublicKey::from_hex(h).ok())
        .collect();

    if !authors.is_empty() {
        let filter = Filter::new().authors(authors).kind(Kind::Metadata);
        let profile_events = client.database().query(filter).await?;
        let mut profiles: HashMap<String, (String, String)> = HashMap::new();

        for pe in profile_events {
            if let Ok(m) = Metadata::from_json(&pe.content) {
                let name = m.name.clone()
                    .or_else(|| m.display_name.clone())
                    .unwrap_or_default();
                let picture = m.picture.clone().unwrap_or_default();
                profiles.insert(pe.pubkey.to_hex(), (name, picture));
            }
        }

        for item in items.iter_mut() {
            if let Some(pk) = item["fromPubkey"].as_str() {
                if let Some((name, picture)) = profiles.get(pk) {
                    item["fromName"] = serde_json::json!(name);
                    item["fromImage"] = serde_json::json!(picture);
                }
            }
        }
    }

    Ok(serde_json::to_string(&items)?)
}

pub async fn db_get_hydrated_notifications(
    user_pubkey_hex: String,
    limit: u32,
    muted_pubkeys: Vec<String>,
    muted_words: Vec<String>,
) -> Result<String> {
    let client = get_client_pub().await?;
    let pk = PublicKey::from_hex(&user_pubkey_hex)?;

    let filter = Filter::new()
        .pubkey(pk)
        .kinds([Kind::TextNote, Kind::Repost, Kind::Reaction, Kind::ZapReceipt])
        .limit(limit as usize);
    let events = client.database().query(filter).await?;

    let filtered: Vec<Event> = events.into_iter()
        .filter(|e| !is_event_muted(e, &muted_pubkeys, &muted_words))
        .collect();

    hydrate_notification_events(&client, &filtered, &user_pubkey_hex).await
}

async fn hydrate_article_events(
    client: &Client,
    events: &[Event],
) -> Result<String> {
    if events.is_empty() {
        return Ok("[]".to_string());
    }

    let mut articles: Vec<serde_json::Value> = Vec::new();
    let mut pubkeys_needed: HashSet<String> = HashSet::new();

    for event in events {
        let event_id = event.id.to_hex();
        let pubkey = event.pubkey.to_hex();
        let content = event.content.clone();
        let created_at = event.created_at.as_secs();

        let tags: Vec<Vec<String>> = event.tags.iter()
            .map(|tag| tag.clone().to_vec())
            .collect();

        let mut title = String::new();
        let mut image: Option<String> = None;
        let mut summary: Option<String> = None;
        let mut d_tag = String::new();
        let mut published_at: Option<u64> = None;
        let mut hashtags: Vec<String> = Vec::new();

        for tag in &tags {
            if tag.is_empty() { continue; }
            let tag_name = &tag[0];
            let tag_value = if tag.len() > 1 { &tag[1] } else { &String::new() };

            match tag_name.as_str() {
                "d" => d_tag = tag_value.clone(),
                "title" => title = tag_value.clone(),
                "image" => image = Some(tag_value.clone()),
                "summary" => summary = Some(tag_value.clone()),
                "published_at" => published_at = tag_value.parse::<u64>().ok(),
                "t" => {
                    if !tag_value.is_empty() {
                        hashtags.push(tag_value.clone());
                    }
                }
                _ => {}
            }
        }

        pubkeys_needed.insert(pubkey.clone());

        articles.push(serde_json::json!({
            "id": event_id,
            "pubkey": pubkey,
            "title": title,
            "content": content,
            "image": image,
            "summary": summary,
            "dTag": d_tag,
            "publishedAt": published_at.unwrap_or(created_at),
            "created_at": created_at,
            "hashtags": hashtags,
            "authorName": serde_json::Value::Null,
            "authorImage": serde_json::Value::Null,
        }));
    }

    if articles.is_empty() {
        return Ok("[]".to_string());
    }

    let authors: Vec<PublicKey> = pubkeys_needed.iter()
        .filter_map(|h| PublicKey::from_hex(h).ok())
        .collect();

    if !authors.is_empty() {
        let filter = Filter::new().authors(authors).kind(Kind::Metadata);
        let profile_events = client.database().query(filter).await?;
        let mut profiles: HashMap<String, (String, String)> = HashMap::new();

        for pe in profile_events {
            if let Ok(m) = Metadata::from_json(&pe.content) {
                let name = m.name.clone()
                    .or_else(|| m.display_name.clone())
                    .unwrap_or_default();
                let picture = m.picture.clone().unwrap_or_default();
                profiles.insert(pe.pubkey.to_hex(), (name, picture));
            }
        }

        for article in articles.iter_mut() {
            if let Some(pk) = article["pubkey"].as_str() {
                if let Some((name, picture)) = profiles.get(pk) {
                    article["authorName"] = serde_json::json!(name);
                    article["authorImage"] = serde_json::json!(picture);
                }
            }
        }
    }

    Ok(serde_json::to_string(&articles)?)
}

pub async fn db_get_hydrated_articles(
    limit: u32,
    muted_pubkeys: Vec<String>,
    muted_words: Vec<String>,
) -> Result<String> {
    let client = get_client_pub().await?;
    let filter = Filter::new()
        .kind(Kind::LongFormTextNote)
        .limit(limit as usize);
    let events = client.database().query(filter).await?;

    let mut filtered: Vec<Event> = events.into_iter()
        .filter(|e| !is_event_muted(e, &muted_pubkeys, &muted_words))
        .collect();
    filtered.sort_by(|a, b| b.created_at.cmp(&a.created_at));

    hydrate_article_events(&client, &filtered).await
}

pub async fn db_get_hydrated_articles_by_authors(
    authors_hex: Vec<String>,
    limit: u32,
    muted_pubkeys: Vec<String>,
    muted_words: Vec<String>,
) -> Result<String> {
    let client = get_client_pub().await?;
    let authors: Vec<PublicKey> = authors_hex.iter()
        .filter_map(|h| PublicKey::from_hex(h).ok())
        .collect();

    if authors.is_empty() {
        return Ok("[]".to_string());
    }

    let filter = Filter::new()
        .kind(Kind::LongFormTextNote)
        .authors(authors)
        .limit(limit as usize);
    let events = client.database().query(filter).await?;

    let mut filtered: Vec<Event> = events.into_iter()
        .filter(|e| !is_event_muted(e, &muted_pubkeys, &muted_words))
        .collect();
    filtered.sort_by(|a, b| b.created_at.cmp(&a.created_at));

    hydrate_article_events(&client, &filtered).await
}

pub async fn db_get_hydrated_article(event_id: String) -> Result<Option<String>> {
    let client = get_client_pub().await?;
    let id = EventId::from_hex(&event_id)?;
    let event = client.database().event_by_id(&id).await?;

    match event {
        Some(e) => {
            let result = hydrate_article_events(&client, &[e]).await?;
            let arr: Vec<serde_json::Value> = serde_json::from_str(&result)?;
            if arr.is_empty() {
                Ok(None)
            } else {
                Ok(Some(arr[0].to_string()))
            }
        }
        None => Ok(None),
    }
}
