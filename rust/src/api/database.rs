use std::collections::HashMap;

use anyhow::Result;
use nostr_sdk::prelude::*;

use super::relay::get_client_pub;

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

pub async fn db_get_feed_notes(authors_hex: Vec<String>, limit: u32) -> Result<String> {
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
        .filter_map(|e| serde_json::from_str(&e.as_json()).ok())
        .collect();
    Ok(serde_json::to_string(&json)?)
}

pub async fn db_get_profile_notes(pubkey_hex: String, limit: u32) -> Result<String> {
    let client = get_client_pub().await?;
    let pk = PublicKey::from_hex(&pubkey_hex)?;

    let filter = Filter::new()
        .author(pk)
        .kinds([Kind::TextNote, Kind::Repost])
        .limit(limit as usize);
    let events = client.database().query(filter).await?;

    let json: Vec<serde_json::Value> = events
        .into_iter()
        .filter_map(|e| serde_json::from_str(&e.as_json()).ok())
        .collect();
    Ok(serde_json::to_string(&json)?)
}

pub async fn db_get_hashtag_notes(hashtag: String, limit: u32) -> Result<String> {
    let client = get_client_pub().await?;

    let filter = Filter::new()
        .kind(Kind::TextNote)
        .hashtag(hashtag)
        .limit(limit as usize);
    let events = client.database().query(filter).await?;

    let json: Vec<serde_json::Value> = events
        .into_iter()
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

pub async fn db_get_replies(note_id: String, limit: u32) -> Result<String> {
    let client = get_client_pub().await?;
    let id = EventId::from_hex(&note_id)?;

    let filter = Filter::new()
        .kind(Kind::TextNote)
        .event(id)
        .limit(limit as usize);
    let events = client.database().query(filter).await?;

    let json: Vec<serde_json::Value> = events
        .into_iter()
        .filter_map(|e| serde_json::from_str(&e.as_json()).ok())
        .collect();
    Ok(serde_json::to_string(&json)?)
}

pub async fn db_get_notifications(user_pubkey_hex: String, limit: u32) -> Result<String> {
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

pub async fn db_get_articles(limit: u32) -> Result<String> {
    let client = get_client_pub().await?;
    let filter = Filter::new()
        .kind(Kind::LongFormTextNote)
        .limit(limit as usize);
    let events = client.database().query(filter).await?;
    
    let mut events_vec: Vec<Event> = events.into_iter().collect();
    events_vec.sort_by(|a, b| b.created_at.cmp(&a.created_at));

    let json: Vec<serde_json::Value> = events_vec
        .into_iter()
        .filter_map(|e| serde_json::from_str(&e.as_json()).ok())
        .collect();
    Ok(serde_json::to_string(&json)?)
}

pub async fn db_get_articles_by_authors(authors_hex: Vec<String>, limit: u32) -> Result<String> {
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
    
    let mut events_vec: Vec<Event> = events.into_iter().collect();
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
