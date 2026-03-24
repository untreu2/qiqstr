use std::collections::{HashMap, HashSet};
use std::sync::OnceLock;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::Result;
use nostr_sdk::prelude::*;
use regex::Regex;

use super::relay::get_client_pub;

fn is_future_dated(event: &Event) -> bool {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    event.created_at.as_secs() > now
}

pub(crate) fn is_event_muted(event: &Event, muted_pubkeys: &[String], muted_words: &[String]) -> bool {
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

    if event.kind == Kind::ZapReceipt {
        if let Some(sender) = extract_zap_sender(event) {
            if muted_pubkeys.iter().any(|p| p == &sender) {
                return true;
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

pub(crate) fn extract_zap_amount_sats(event: &Event) -> u64 {
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

pub(crate) struct NoteReferences {
    pub root_id: Option<String>,
    pub parent_id: Option<String>,
    pub is_reply: bool,
    pub is_quote: bool,
    pub quoted_note_id: Option<String>,
}

pub(crate) fn extract_note_references(tags: &[Vec<String>]) -> NoteReferences {
    let mut root_id: Option<String> = None;
    let mut parent_id: Option<String> = None;
    let mut is_quote = false;
    let mut quoted_note_id: Option<String> = None;
    let mut e_tags: Vec<String> = Vec::new();

    for tag in tags {
        if tag.len() < 2 {
            continue;
        }
        match tag[0].as_str() {
            "q" => {
                is_quote = true;
                if quoted_note_id.is_none() {
                    quoted_note_id = Some(tag[1].clone());
                }
            }
            "e" => {
                if tag.len() >= 4 {
                    match tag[3].as_str() {
                        "root" => root_id = Some(tag[1].clone()),
                        "reply" => parent_id = Some(tag[1].clone()),
                        "mention" => {}
                        _ => e_tags.push(tag[1].clone()),
                    }
                } else {
                    e_tags.push(tag[1].clone());
                }
            }
            _ => {}
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

    let is_reply = (root_id.is_some() || parent_id.is_some()) && !is_quote;

    NoteReferences {
        root_id,
        parent_id,
        is_reply,
        is_quote,
        quoted_note_id,
    }
}

pub(crate) fn tags_from_event(event: &Event) -> Vec<Vec<String>> {
    event.tags.iter().map(|tag| tag.clone().to_vec()).collect()
}

fn json_tags_to_vecs(tags: &[serde_json::Value]) -> Vec<Vec<String>> {
    tags.iter()
        .filter_map(|tag| {
            tag.as_array().map(|arr| {
                arr.iter()
                    .filter_map(|v| v.as_str().map(String::from))
                    .collect()
            })
        })
        .collect()
}

fn extract_content_references(content: &str) -> (Vec<String>, Vec<(String, String)>) {
    let mut event_ids: Vec<String> = Vec::new();
    let mut naddr_refs: Vec<(String, String)> = Vec::new();

    if !content.contains("nostr:") {
        return (event_ids, naddr_refs);
    }

    let mut search_start = 0;
    while let Some(pos) = content[search_start..].find("nostr:") {
        let abs_pos = search_start + pos;
        let after = &content[abs_pos + 6..];
        let end = after
            .find(|c: char| !c.is_alphanumeric())
            .unwrap_or(after.len());
        let bech32 = &after[..end];

        if bech32.len() >= 10 {
            if bech32.starts_with("note1") {
                if let Ok(id) = EventId::from_bech32(bech32) {
                    event_ids.push(id.to_hex());
                }
            } else if bech32.starts_with("nevent1") {
                if let Ok(nevent) = Nip19Event::from_bech32(bech32) {
                    event_ids.push(nevent.event_id.to_hex());
                }
            } else if bech32.starts_with("naddr1") {
                if let Ok(coord) = Coordinate::from_bech32(bech32) {
                    if coord.kind == Kind::LongFormTextNote {
                        naddr_refs.push((
                            coord.public_key.to_hex(),
                            coord.identifier.clone(),
                        ));
                    }
                }
            }
        }

        search_start = abs_pos + 6 + end;
    }

    (event_ids, naddr_refs)
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
        .filter(|e| !is_future_dated(e) && !is_event_muted(e, &muted_pubkeys, &muted_words))
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
        .filter(|e| !is_future_dated(e) && !is_event_muted(e, &muted_pubkeys, &muted_words))
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
        .filter(|e| !is_future_dated(e) && !is_event_muted(e, &muted_pubkeys, &muted_words))
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
    let status = client.database().check_id(&id).await?;
    Ok(matches!(status, DatabaseEventStatus::Saved))
}

#[allow(dead_code)]
pub async fn db_events_exist_batch(event_ids: Vec<String>) -> Result<Vec<bool>> {
    let client = get_client_pub().await?;
    let mut results = Vec::with_capacity(event_ids.len());
    for id_hex in &event_ids {
        let exists = if let Ok(id) = EventId::from_hex(id_hex) {
            let status = client.database().check_id(&id).await;
            matches!(status, Ok(DatabaseEventStatus::Saved))
        } else {
            false
        };
        results.push(exists);
    }
    Ok(results)
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

    for val in &events {
        if let Some(id_str) = val.get("id").and_then(|v| v.as_str()) {
            if let Ok(id) = EventId::from_hex(id_str) {
                if let Ok(DatabaseEventStatus::Saved) = client.database().check_id(&id).await {
                    continue;
                }
            }
        }

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

pub async fn db_delete_events_by_ids(event_ids: Vec<String>) -> Result<u32> {
    let client = get_client_pub().await?;
    let ids: Vec<EventId> = event_ids
        .iter()
        .filter_map(|id| EventId::from_hex(id).ok())
        .collect();

    if ids.is_empty() {
        return Ok(0);
    }

    let filter = Filter::new().ids(ids.clone());
    client.database().delete(filter).await?;

    Ok(ids.len() as u32)
}

pub async fn db_process_deletion_events() -> Result<u32> {
    let client = get_client_pub().await?;

    let filter = Filter::new().kind(Kind::EventDeletion);
    let deletion_events = client.database().query(filter).await?;

    let mut candidate_ids: Vec<EventId> = Vec::new();
    let mut del_author_map: HashMap<EventId, PublicKey> = HashMap::new();

    for del_event in deletion_events {
        for tag in del_event.tags.iter() {
            let tag_kind = tag.kind();
            if matches!(tag_kind, TagKind::SingleLetter(SingleLetterTag { character: Alphabet::E, .. })) {
                if let Some(ref_id_str) = tag.content() {
                    if let Ok(ref_id) = EventId::from_hex(ref_id_str) {
                        candidate_ids.push(ref_id);
                        del_author_map.insert(ref_id, del_event.pubkey);
                    }
                }
            }
        }
    }

    if candidate_ids.is_empty() {
        return Ok(0);
    }

    let batch_filter = Filter::new().ids(candidate_ids);
    let referenced_events = client.database().query(batch_filter).await?;

    let mut ids_to_delete: Vec<EventId> = Vec::new();
    for event in referenced_events {
        if let Some(expected_author) = del_author_map.get(&event.id) {
            if event.pubkey == *expected_author {
                ids_to_delete.push(event.id);
            }
        }
    }

    if ids_to_delete.is_empty() {
        return Ok(0);
    }

    let deleted_count = ids_to_delete.len() as u32;
    let del_filter = Filter::new().ids(ids_to_delete);
    let _ = client.database().delete(del_filter).await;

    Ok(deleted_count)
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

pub async fn db_save_profiles_batch(profiles_json: String) -> Result<u32> {
    let client = get_client_pub().await?;
    let profiles: serde_json::Map<String, serde_json::Value> =
        serde_json::from_str(&profiles_json)?;
    let mut saved: u32 = 0;

    for (pubkey_hex, profile_data) in &profiles {
        let pk = match PublicKey::from_hex(pubkey_hex) {
            Ok(pk) => pk,
            Err(_) => continue,
        };
        let profile_str = profile_data.to_string();
        let keys = Keys::generate();
        let event = match EventBuilder::new(Kind::Metadata, &profile_str)
            .custom_created_at(Timestamp::now())
            .sign_with_keys(&keys)
        {
            Ok(e) => e,
            Err(_) => continue,
        };
        let raw: serde_json::Value = match serde_json::from_str(&event.as_json()) {
            Ok(v) => v,
            Err(_) => continue,
        };
        let mut raw = raw;
        raw["pubkey"] = serde_json::Value::String(pk.to_hex());
        if let Ok(patched) = Event::from_json(raw.to_string()) {
            if client.database().save_event(&patched).await.is_ok() {
                saved += 1;
            }
        }
    }
    Ok(saved)
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

pub async fn db_wipe_directory() -> Result<()> {
    use super::relay::db_path_state;

    let db_path_lock = db_path_state().read().await;
    if let Some(path) = db_path_lock.as_ref() {
        let db_dir = std::path::Path::new(path);
        if db_dir.exists() {
            std::fs::remove_dir_all(db_dir)
                .map_err(|e| anyhow::anyhow!("Failed to wipe database directory: {}", e))?;
        }
    }
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
            Kind::LongFormTextNote,
        ])
        .until(cutoff_ts);
    
    let events = client.database().query(filter.clone()).await?;
    let count = events.len() as u32;
    
    if count > 0 {
        client.database().delete(filter).await?;
    }
    
    Ok(count)
}

pub async fn db_cleanup_by_kind(kind_num: u16, days_to_keep: u32) -> Result<u32> {
    let client = get_client_pub().await?;
    let now = Timestamp::now();
    let cutoff = now.as_secs() - (days_to_keep as u64 * 86400);
    let cutoff_ts = Timestamp::from(cutoff);

    let filter = Filter::new()
        .kind(Kind::from(kind_num))
        .until(cutoff_ts);

    let events = client.database().query(filter.clone()).await?;
    let count = events.len() as u32;

    if count > 0 {
        client.database().delete(filter).await?;
    }

    Ok(count)
}

pub async fn db_cleanup_foreign_contact_lists(own_pubkey_hex: String) -> Result<u32> {
    let client = get_client_pub().await?;
    let own_pk = PublicKey::from_hex(&own_pubkey_hex)?;

    let filter = Filter::new().kind(Kind::ContactList);
    let events = client.database().query(filter).await?;

    let own_follows: HashSet<String> = client
        .database()
        .contacts_public_keys(own_pk)
        .await?
        .into_iter()
        .map(|pk| pk.to_hex())
        .collect();

    let mut to_delete_authors: Vec<PublicKey> = Vec::new();
    let own_hex = own_pk.to_hex();

    for event in events.iter() {
        let author_hex = event.pubkey.to_hex();
        if author_hex == own_hex {
            continue;
        }
        if !own_follows.contains(&author_hex) {
            to_delete_authors.push(event.pubkey);
        }
    }

    let count = to_delete_authors.len() as u32;

    for author in &to_delete_authors {
        let del_filter = Filter::new().author(*author).kind(Kind::ContactList);
        let _ = client.database().delete(del_filter).await;
    }

    Ok(count)
}

pub async fn db_smart_cleanup(
    own_pubkey_hex: String,
    interaction_days: u32,
    note_days: u32,
) -> Result<String> {
    let mut total_deleted: u32 = 0;

    let reactions = db_cleanup_by_kind(7, interaction_days).await.unwrap_or(0);
    total_deleted += reactions;

    let zaps = db_cleanup_by_kind(9735, interaction_days).await.unwrap_or(0);
    total_deleted += zaps;

    let reposts = db_cleanup_by_kind(6, interaction_days).await.unwrap_or(0);
    total_deleted += reposts;

    let notes = db_cleanup_by_kind(1, note_days).await.unwrap_or(0);
    total_deleted += notes;

    let articles = db_cleanup_by_kind(30023, note_days).await.unwrap_or(0);
    total_deleted += articles;

    let contacts = db_cleanup_foreign_contact_lists(own_pubkey_hex).await.unwrap_or(0);
    total_deleted += contacts;

    let result = serde_json::json!({
        "totalDeleted": total_deleted,
        "reactions": reactions,
        "zaps": zaps,
        "reposts": reposts,
        "notes": notes,
        "articles": articles,
        "foreignContacts": contacts,
    });

    Ok(result.to_string())
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
    current_user_pubkey_hex: Option<String>,
) -> Result<String> {
    if events.is_empty() {
        return Ok("[]".to_string());
    }

    let mut repost_lookup_ids: Vec<EventId> = Vec::new();
    for event in events {
        if event.kind != Kind::Repost {
            continue;
        }
        let has_embedded = serde_json::from_str::<serde_json::Value>(&event.content)
            .map(|p| p.get("content").is_some() && p.get("pubkey").is_some())
            .unwrap_or(false);
        if has_embedded {
            continue;
        }
        for tag in event.tags.iter() {
            let tag_vec: Vec<String> = tag.clone().to_vec();
            if tag_vec.len() >= 2 && tag_vec[0] == "e" {
                if let Ok(eid) = EventId::from_hex(&tag_vec[1]) {
                    repost_lookup_ids.push(eid);
                }
                break;
            }
        }
    }

    let mut repost_cache: HashMap<String, serde_json::Value> = HashMap::new();
    if !repost_lookup_ids.is_empty() {
        let db_filter = Filter::new()
            .ids(repost_lookup_ids.clone())
            .kind(Kind::TextNote);
        if let Ok(db_results) = client.database().query(db_filter).await {
            for ev in db_results {
                let ev_tags: Vec<serde_json::Value> = ev.tags.iter()
                    .map(|t| serde_json::Value::Array(
                        t.clone().to_vec().iter().map(|s| serde_json::json!(s)).collect()
                    ))
                    .collect();
                repost_cache.insert(ev.id.to_hex(), serde_json::json!({
                    "content": ev.content,
                    "pubkey": ev.pubkey.to_hex(),
                    "created_at": ev.created_at.as_secs(),
                    "tags": ev_tags,
                }));
            }
        }

        let missing: Vec<EventId> = repost_lookup_ids.into_iter()
            .filter(|eid| !repost_cache.contains_key(&eid.to_hex()))
            .collect();
        if !missing.is_empty() {
            let relay_filter = Filter::new().ids(missing).kind(Kind::TextNote);
            let timeout = Duration::from_secs(3);
            if let Ok(fetched) = client.fetch_events(relay_filter, timeout).await {
                for ev in fetched {
                    let ev_tags: Vec<serde_json::Value> = ev.tags.iter()
                        .map(|t| serde_json::Value::Array(
                            t.clone().to_vec().iter().map(|s| serde_json::json!(s)).collect()
                        ))
                        .collect();
                    repost_cache.insert(ev.id.to_hex(), serde_json::json!({
                        "content": ev.content,
                        "pubkey": ev.pubkey.to_hex(),
                        "created_at": ev.created_at.as_secs(),
                        "tags": ev_tags,
                    }));
                }
            }
        }
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
        let mut repost_event_id: Option<String> = None;

        let tags: Vec<Vec<String>> = event.tags.iter()
            .map(|tag| tag.clone().to_vec())
            .collect();

        let refs = extract_note_references(&tags);
        let mut root_id = refs.root_id;
        let mut parent_id = refs.parent_id;
        let mut is_quote = refs.is_quote;
        let mut quoted_note_id = refs.quoted_note_id;
        let mut is_reply = refs.is_reply;

        if is_repost {
            repost_event_id = Some(id.clone());
            reposted_by = Some(pubkey.clone());
            repost_created_at = Some(created_at);

            root_id = None;
            parent_id = None;
            is_reply = false;
            is_quote = false;
            quoted_note_id = None;

            let mut repost_original_id: Option<String> = None;
            let mut repost_extra_e_tags: Vec<(String, Option<String>)> = Vec::new();
            for tag in tags.iter() {
                if tag.is_empty() || tag[0] != "e" || tag.len() < 2 {
                    continue;
                }
                if repost_original_id.is_none() {
                    repost_original_id = Some(tag[1].clone());
                } else {
                    let marker = tag.get(3).map(|s| s.as_str()).and_then(|m| {
                        if m == "root" || m == "reply" { Some(m.to_string()) } else { None }
                    });
                    repost_extra_e_tags.push((tag[1].clone(), marker));
                }
            }

            if let Some(orig_id) = repost_original_id {
                id = orig_id;
            }

            for (ref_id, marker) in &repost_extra_e_tags {
                match marker.as_deref() {
                    Some("root") => { root_id = Some(ref_id.clone()); }
                    Some("reply") => { parent_id = Some(ref_id.clone()); }
                    _ => {}
                }
            }

            for tag in tags.iter() {
                if !tag.is_empty() && tag[0] == "p" && tag.len() > 1 {
                    pubkey = tag[1].clone();
                    break;
                }
            }

            let embedded_json: Option<serde_json::Value> =
                if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&content) {
                    if parsed.get("content").is_some() && parsed.get("pubkey").is_some() {
                        Some(parsed)
                    } else {
                        None
                    }
                } else {
                    None
                };

            let embedded_json: Option<serde_json::Value> = if embedded_json.is_some() {
                embedded_json
            } else {
                repost_cache.get(&id).cloned()
            };

            if let Some(parsed) = embedded_json {
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
                    let embedded_tags = json_tags_to_vecs(parsed_tags);
                    let embedded_refs = extract_note_references(&embedded_tags);
                    root_id = embedded_refs.root_id;
                    parent_id = embedded_refs.parent_id;
                    is_quote = embedded_refs.is_quote;
                    quoted_note_id = embedded_refs.quoted_note_id;
                    is_reply = embedded_refs.is_reply;
                }
            }

            if content.trim().is_empty() {
                continue;
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
            "repostEventId": repost_event_id,
            "repostedBy": reposted_by,
            "repostCreatedAt": repost_created_at,
            "isReply": is_reply,
            "isQuote": is_quote,
            "quotedNoteId": quoted_note_id,
            "rootId": root_id,
            "parentId": parent_id,
            "authorName": serde_json::Value::Null,
            "authorImage": serde_json::Value::Null,
            "authorNip05": serde_json::Value::Null,
            "reactionCount": 0,
            "repostCount": 0,
            "replyCount": 0,
            "zapCount": 0,
            "hasReacted": false,
            "hasReposted": false,
            "hasZapped": false,
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
        let user_pk = current_user_pubkey_hex.as_ref()
            .and_then(|h| if h.is_empty() { None } else { PublicKey::from_hex(h).ok() });

        let local_filter = Filter::new()
            .kinds([Kind::TextNote, Kind::Reaction, Kind::Repost, Kind::ZapReceipt])
            .events(ids);
        let local_events = client.database().query(local_filter).await?;

        let mut reply_counts: HashMap<String, usize> = HashMap::new();
        let mut reaction_counts: HashMap<String, usize> = HashMap::new();
        let mut repost_counts: HashMap<String, usize> = HashMap::new();
        let mut zap_counts: HashMap<String, usize> = HashMap::new();
        let mut has_reacted: HashSet<String> = HashSet::new();
        let mut has_reposted: HashSet<String> = HashSet::new();
        let mut has_zapped: HashSet<String> = HashSet::new();

        for nid in &note_ids {
            reply_counts.insert(nid.clone(), 0);
            reaction_counts.insert(nid.clone(), 0);
            repost_counts.insert(nid.clone(), 0);
            zap_counts.insert(nid.clone(), 0);
        }

        for ev in local_events.iter() {
            let is_user = user_pk.as_ref().map_or(false, |pk| ev.pubkey == *pk);
            let is_zap_sender = if ev.kind == Kind::ZapReceipt {
                user_pk.as_ref().map_or(false, |pk| {
                    extract_zap_sender(ev)
                        .map_or(false, |sender| sender == pk.to_hex())
                })
            } else {
                false
            };
            let zap_sats = if ev.kind == Kind::ZapReceipt {
                extract_zap_amount_sats(ev) as usize
            } else {
                0
            };

            let mut counted_for: HashSet<String> = HashSet::new();
            for tag in ev.tags.iter() {
                let tag_kind = tag.kind();
                if matches!(tag_kind, TagKind::SingleLetter(SingleLetterTag { character: Alphabet::E, .. })) {
                    if let Some(ref_id) = tag.content() {
                        let ref_hex = ref_id.to_string();
                        if counted_for.contains(&ref_hex) { continue; }
                        if reply_counts.contains_key(&ref_hex) {
                            counted_for.insert(ref_hex.clone());
                            match ev.kind {
                                k if k == Kind::TextNote => {
                                    if let Some(c) = reply_counts.get_mut(&ref_hex) {
                                        *c += 1;
                                    }
                                }
                                k if k == Kind::Reaction => {
                                    if let Some(c) = reaction_counts.get_mut(&ref_hex) {
                                        *c += 1;
                                    }
                                    if is_user { has_reacted.insert(ref_hex); }
                                }
                                k if k == Kind::Repost => {
                                    if let Some(c) = repost_counts.get_mut(&ref_hex) {
                                        *c += 1;
                                    }
                                    if is_user { has_reposted.insert(ref_hex); }
                                }
                                k if k == Kind::ZapReceipt => {
                                    if let Some(c) = zap_counts.get_mut(&ref_hex) {
                                        *c += zap_sats;
                                    }
                                    if is_zap_sender { has_zapped.insert(ref_hex); }
                                }
                                _ => {}
                            }
                        }
                    }
                }
            }
        }

        for note in notes.iter_mut() {
            let nid = note["id"].as_str().map(|s| s.to_string());
            if let Some(ref nid) = nid {
                note["reactionCount"] = serde_json::json!(reaction_counts.get(nid).copied().unwrap_or(0));
                note["repostCount"] = serde_json::json!(repost_counts.get(nid).copied().unwrap_or(0));
                note["zapCount"] = serde_json::json!(zap_counts.get(nid).copied().unwrap_or(0));
                note["replyCount"] = serde_json::json!(reply_counts.get(nid).copied().unwrap_or(0));
                note["hasReacted"] = serde_json::json!(has_reacted.contains(nid));
                note["hasReposted"] = serde_json::json!(has_reposted.contains(nid));
                note["hasZapped"] = serde_json::json!(has_zapped.contains(nid));
            }
        }
    }

    let mut all_ref_event_ids: HashSet<String> = HashSet::new();
    let mut all_naddr_refs: Vec<(String, String)> = Vec::new();

    for note in &notes {
        if let Some(qid) = note["quotedNoteId"].as_str() {
            if !qid.is_empty() {
                all_ref_event_ids.insert(qid.to_string());
            }
        }
        if let Some(content) = note["content"].as_str() {
            let (event_refs, naddr_refs) = extract_content_references(content);
            for eid in event_refs {
                all_ref_event_ids.insert(eid);
            }
            all_naddr_refs.extend(naddr_refs);
        }
    }

    let own_ids: HashSet<String> = note_ids.iter().cloned().collect();
    all_ref_event_ids.retain(|id| !own_ids.contains(id));

    if !all_ref_event_ids.is_empty() {
        let ref_eids: Vec<EventId> = all_ref_event_ids
            .iter()
            .filter_map(|id| EventId::from_hex(id).ok())
            .collect();

        if !ref_eids.is_empty() {
            let ref_filter = Filter::new().ids(ref_eids);
            let ref_events = client
                .database()
                .query(ref_filter)
                .await
                .unwrap_or_default();

            let mut ref_notes_map: HashMap<String, serde_json::Value> = HashMap::new();
            let mut ref_pubkeys: HashSet<String> = HashSet::new();

            for ev in ref_events {
                let ev_id = ev.id.to_hex();
                let ev_pubkey = ev.pubkey.to_hex();
                ref_pubkeys.insert(ev_pubkey.clone());

                let ev_tags = tags_from_event(&ev);
                let ev_refs = extract_note_references(&ev_tags);

                ref_notes_map.insert(
                    ev_id.clone(),
                    serde_json::json!({
                        "id": ev_id,
                        "pubkey": ev_pubkey,
                        "content": ev.content,
                        "created_at": ev.created_at.as_secs(),
                        "kind": ev.kind.as_u16(),
                        "isReply": ev_refs.is_reply,
                        "isQuote": ev_refs.is_quote,
                        "rootId": ev_refs.root_id,
                        "parentId": ev_refs.parent_id,
                        "authorName": serde_json::Value::Null,
                        "authorImage": serde_json::Value::Null,
                    }),
                );
            }

            if !ref_pubkeys.is_empty() {
                let ref_authors: Vec<PublicKey> = ref_pubkeys
                    .iter()
                    .filter_map(|h| PublicKey::from_hex(h).ok())
                    .collect();
                let ref_profile_filter =
                    Filter::new().authors(ref_authors).kind(Kind::Metadata);
                if let Ok(ref_profiles) =
                    client.database().query(ref_profile_filter).await
                {
                    let mut profiles: HashMap<String, (String, String)> = HashMap::new();
                    for pe in ref_profiles {
                        if let Ok(m) = Metadata::from_json(&pe.content) {
                            let name = m
                                .name
                                .clone()
                                .or_else(|| m.display_name.clone())
                                .unwrap_or_default();
                            let picture = m.picture.clone().unwrap_or_default();
                            profiles.insert(pe.pubkey.to_hex(), (name, picture));
                        }
                    }
                    for ref_note in ref_notes_map.values_mut() {
                        if let Some(pk) = ref_note["pubkey"].as_str() {
                            if let Some((name, picture)) = profiles.get(pk) {
                                ref_note["authorName"] = serde_json::json!(name);
                                ref_note["authorImage"] = serde_json::json!(picture);
                            }
                        }
                    }
                }
            }

            for note in notes.iter_mut() {
                if let Some(qid) = note["quotedNoteId"]
                    .as_str()
                    .map(|s| s.to_string())
                {
                    if let Some(quoted) = ref_notes_map.get(&qid) {
                        note["quotedNote"] = quoted.clone();
                    }
                }

                if let Some(content) =
                    note["content"].as_str().map(|s| s.to_string())
                {
                    let (content_event_ids, _) = extract_content_references(&content);
                    if !content_event_ids.is_empty() {
                        let mut embedded = serde_json::Map::new();
                        for eid in &content_event_ids {
                            if let Some(ref_note) = ref_notes_map.get(eid) {
                                embedded.insert(eid.clone(), ref_note.clone());
                            }
                        }
                        if !embedded.is_empty() {
                            note["embeddedNotes"] =
                                serde_json::Value::Object(embedded);
                        }
                    }
                }
            }
        }
    }

    if !all_naddr_refs.is_empty() {
        let unique_naddrs: Vec<(String, String)> = {
            let mut seen: HashSet<(String, String)> = HashSet::new();
            all_naddr_refs
                .into_iter()
                .filter(|pair| seen.insert(pair.clone()))
                .collect()
        };

        let mut articles_map: HashMap<String, serde_json::Value> = HashMap::new();
        let mut article_pubkeys: HashSet<String> = HashSet::new();

        for (pubkey_hex, d_tag) in &unique_naddrs {
            let filter_json = serde_json::json!({
                "kinds": [30023],
                "authors": [pubkey_hex],
                "#d": [d_tag],
                "limit": 1,
            });
            if let Ok(filter) = Filter::from_json(&filter_json.to_string()) {
                if let Ok(events) = client.database().query(filter).await {
                    if let Some(ev) = events.into_iter().next() {
                        let ev_tags = tags_from_event(&ev);
                        let mut title = String::new();
                        let mut image: Option<String> = None;
                        let mut summary: Option<String> = None;
                        let mut actual_d_tag = String::new();

                        for tag in &ev_tags {
                            if tag.len() < 2 {
                                continue;
                            }
                            match tag[0].as_str() {
                                "d" => actual_d_tag = tag[1].clone(),
                                "title" => title = tag[1].clone(),
                                "image" if !tag[1].is_empty() => {
                                    image = Some(tag[1].clone())
                                }
                                "summary" if !tag[1].is_empty() => {
                                    summary = Some(tag[1].clone())
                                }
                                _ => {}
                            }
                        }

                        article_pubkeys.insert(pubkey_hex.clone());
                        let key = format!("{}:{}", pubkey_hex, d_tag);
                        articles_map.insert(
                            key,
                            serde_json::json!({
                                "id": ev.id.to_hex(),
                                "pubkey": pubkey_hex,
                                "title": title,
                                "image": image,
                                "summary": summary,
                                "dTag": actual_d_tag,
                                "created_at": ev.created_at.as_secs(),
                                "authorName": serde_json::Value::Null,
                                "authorImage": serde_json::Value::Null,
                            }),
                        );
                    }
                }
            }
        }

        if !article_pubkeys.is_empty() {
            let art_authors: Vec<PublicKey> = article_pubkeys
                .iter()
                .filter_map(|h| PublicKey::from_hex(h).ok())
                .collect();
            let art_profile_filter =
                Filter::new().authors(art_authors).kind(Kind::Metadata);
            if let Ok(art_profiles) =
                client.database().query(art_profile_filter).await
            {
                let mut profiles: HashMap<String, (String, String)> = HashMap::new();
                for pe in art_profiles {
                    if let Ok(m) = Metadata::from_json(&pe.content) {
                        let name = m
                            .name
                            .clone()
                            .or_else(|| m.display_name.clone())
                            .unwrap_or_default();
                        let picture = m.picture.clone().unwrap_or_default();
                        profiles.insert(pe.pubkey.to_hex(), (name, picture));
                    }
                }
                for article in articles_map.values_mut() {
                    if let Some(pk) = article["pubkey"].as_str() {
                        if let Some((name, picture)) = profiles.get(pk) {
                            article["authorName"] = serde_json::json!(name);
                            article["authorImage"] = serde_json::json!(picture);
                        }
                    }
                }
            }
        }

        if !articles_map.is_empty() {
            for note in notes.iter_mut() {
                if let Some(content) =
                    note["content"].as_str().map(|s| s.to_string())
                {
                    let (_, naddr_refs) = extract_content_references(&content);
                    if !naddr_refs.is_empty() {
                        let mut embedded = serde_json::Map::new();
                        for (pk, dt) in &naddr_refs {
                            let key = format!("{}:{}", pk, dt);
                            if let Some(article) = articles_map.get(&key) {
                                embedded.insert(key, article.clone());
                            }
                        }
                        if !embedded.is_empty() {
                            note["embeddedArticles"] =
                                serde_json::Value::Object(embedded);
                        }
                    }
                }
            }
        }
    }

    Ok(serde_json::to_string(&notes)?)
}

pub async fn db_get_hydrated_feed_notes(
    user_pubkey_hex: String,
    authors_hex: Option<Vec<String>>,
    limit: u32,
    muted_pubkeys: Vec<String>,
    muted_words: Vec<String>,
    filter_replies: bool,
    current_user_pubkey_hex: Option<String>,
) -> Result<String> {
    let client = get_client_pub().await?;

    let resolved_authors: Vec<String> = match authors_hex {
        Some(list) => list,
        None => {
            let pk = PublicKey::from_hex(&user_pubkey_hex)?;
            let contacts = client.database().contacts_public_keys(pk).await?;
            contacts.into_iter().map(|k| k.to_hex()).collect()
        }
    };

    let authors: Vec<PublicKey> = resolved_authors.iter()
        .filter_map(|h| PublicKey::from_hex(h).ok())
        .collect();

    let filter = Filter::new()
        .authors(authors)
        .kinds([Kind::TextNote, Kind::Repost])
        .limit(limit as usize);
    let events = client.database().query(filter).await?;

    let filtered: Vec<Event> = events.into_iter()
        .filter(|e| !is_future_dated(e) && !is_event_muted(e, &muted_pubkeys, &muted_words))
        .collect();

    hydrate_notes(&client, &filtered, filter_replies, current_user_pubkey_hex).await
}

pub async fn db_get_hydrated_profile_notes(
    pubkey_hex: String,
    limit: u32,
    muted_pubkeys: Vec<String>,
    muted_words: Vec<String>,
    filter_replies: bool,
    current_user_pubkey_hex: Option<String>,
    until_timestamp: Option<i64>,
) -> Result<String> {
    let client = get_client_pub().await?;
    let pk = PublicKey::from_hex(&pubkey_hex)?;

    let mut filter = Filter::new()
        .author(pk)
        .kinds([Kind::TextNote, Kind::Repost])
        .limit(limit as usize);
    if let Some(until) = until_timestamp {
        if until > 0 {
            filter = filter.until(Timestamp::from(until as u64));
        }
    }
    let events = client.database().query(filter).await?;

    let filtered: Vec<Event> = events.into_iter()
        .filter(|e| !is_future_dated(e) && !is_event_muted(e, &muted_pubkeys, &muted_words))
        .collect();

    hydrate_notes(&client, &filtered, filter_replies, current_user_pubkey_hex).await
}

pub async fn db_get_hydrated_hashtag_notes(
    hashtag: String,
    limit: u32,
    muted_pubkeys: Vec<String>,
    muted_words: Vec<String>,
    current_user_pubkey_hex: Option<String>,
) -> Result<String> {
    let client = get_client_pub().await?;

    let filter = Filter::new()
        .kind(Kind::TextNote)
        .hashtag(hashtag)
        .limit(limit as usize);
    let events = client.database().query(filter).await?;

    let filtered: Vec<Event> = events.into_iter()
        .filter(|e| !is_future_dated(e) && !is_event_muted(e, &muted_pubkeys, &muted_words))
        .collect();

    hydrate_notes(&client, &filtered, true, current_user_pubkey_hex).await
}

pub async fn db_get_hydrated_notes_by_ids(
    event_ids: Vec<String>,
    muted_pubkeys: Vec<String>,
    muted_words: Vec<String>,
    current_user_pubkey_hex: Option<String>,
) -> Result<String> {
    if event_ids.is_empty() {
        return Ok("[]".to_string());
    }
    let client = get_client_pub().await?;

    let eids: Vec<EventId> = event_ids
        .iter()
        .filter_map(|id| EventId::from_hex(id).ok())
        .collect();

    if eids.is_empty() {
        return Ok("[]".to_string());
    }

    let filter = Filter::new().ids(eids).limit(event_ids.len());
    let events = client.database().query(filter).await?;

    let filtered: Vec<Event> = events
        .into_iter()
        .filter(|e| !is_event_muted(e, &muted_pubkeys, &muted_words))
        .collect();

    let hydrated_json =
        hydrate_notes(&client, &filtered, false, current_user_pubkey_hex).await?;

    let hydrated: Vec<serde_json::Value> = serde_json::from_str(&hydrated_json)?;

    let id_order: HashMap<String, usize> = event_ids
        .iter()
        .enumerate()
        .map(|(i, id)| (id.clone(), i))
        .collect();

    let mut ordered = hydrated;
    ordered.sort_by_key(|n| {
        let id = n["id"].as_str().unwrap_or("");
        id_order.get(id).copied().unwrap_or(usize::MAX)
    });

    Ok(serde_json::to_string(&ordered)?)
}

pub async fn db_get_hydrated_profile_replies(
    pubkey_hex: String,
    limit: u32,
    muted_pubkeys: Vec<String>,
    muted_words: Vec<String>,
    current_user_pubkey_hex: Option<String>,
    until_timestamp: Option<i64>,
) -> Result<String> {
    let client = get_client_pub().await?;
    let pk = PublicKey::from_hex(&pubkey_hex)?;

    let mut filter = Filter::new()
        .author(pk)
        .kind(Kind::TextNote)
        .limit(limit as usize * 3);
    if let Some(until) = until_timestamp {
        if until > 0 {
            filter = filter.until(Timestamp::from(until as u64));
        }
    }
    let events = client.database().query(filter).await?;

    let mut reply_events: Vec<Event> = Vec::new();
    for e in events {
        if is_future_dated(&e) || is_event_muted(&e, &muted_pubkeys, &muted_words) {
            continue;
        }
        let tags: Vec<Vec<String>> = e.tags.iter().map(|tag| tag.clone().to_vec()).collect();
        let refs = extract_note_references(&tags);
        if refs.is_reply {
            reply_events.push(e);
            if reply_events.len() >= limit as usize {
                break;
            }
        }
    }

    hydrate_notes(&client, &reply_events, false, current_user_pubkey_hex).await
}

pub async fn db_get_hydrated_replies(
    note_id: String,
    limit: u32,
    muted_pubkeys: Vec<String>,
    muted_words: Vec<String>,
    current_user_pubkey_hex: Option<String>,
) -> Result<String> {
    let client = get_client_pub().await?;
    let id = EventId::from_hex(&note_id)?;

    let filter = Filter::new()
        .kind(Kind::TextNote)
        .event(id)
        .limit(limit as usize);
    let events = client.database().query(filter).await?;

    let filtered: Vec<Event> = events.into_iter()
        .filter(|e| !is_future_dated(e) && !is_event_muted(e, &muted_pubkeys, &muted_words))
        .collect();

    hydrate_notes(&client, &filtered, false, current_user_pubkey_hex).await
}

pub async fn db_get_hydrated_note(
    event_id: String,
    current_user_pubkey_hex: Option<String>,
) -> Result<Option<String>> {
    let client = get_client_pub().await?;
    let id = EventId::from_hex(&event_id)?;
    let event = client.database().event_by_id(&id).await?;

    match event {
        Some(e) => {
            let result = hydrate_notes(&client, &[e], false, current_user_pubkey_hex).await?;
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

    struct PendingItem {
        event_id: String,
        notification_type: String,
        from_pubkey: String,
        target_note_id: Option<String>,
        content: String,
        created_at: u64,
        zap_amount: Option<u64>,
        needs_author_check: bool,
    }

    let mut pending: Vec<PendingItem> = Vec::new();
    let mut pubkeys_needed: HashSet<String> = HashSet::new();
    let mut target_ids_to_check: HashSet<String> = HashSet::new();

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

        let notification_type;
        let mut target_note_id: Option<String> = None;
        let mut zap_amount: Option<u64> = None;
        let mut from_pubkey = pubkey.clone();
        let mut needs_author_check = false;

        match kind_num {
            1 => {
                let mut has_q_tag = false;
                let mut q_target_id: Option<String> = None;
                let mut has_reply_marker = false;
                let mut first_e_id: Option<String> = None;

                for tag in &tags {
                    if tag.len() >= 2 && tag[0] == "q" {
                        has_q_tag = true;
                        q_target_id = Some(tag[1].clone());
                    } else if tag.len() >= 2 && tag[0] == "e" {
                        if first_e_id.is_none() {
                            first_e_id = Some(tag[1].clone());
                        }
                        if tag.len() >= 4 && (tag[3] == "reply" || tag[3] == "root") {
                            has_reply_marker = true;
                            target_note_id = Some(tag[1].clone());
                        }
                    }
                }

                if has_q_tag && !has_reply_marker {
                    notification_type = "quote".to_string();
                    target_note_id = q_target_id;
                } else if has_reply_marker {
                    notification_type = "reply".to_string();
                    needs_author_check = true;
                    if let Some(ref tid) = target_note_id {
                        target_ids_to_check.insert(tid.clone());
                    }
                } else if first_e_id.is_some() {
                    notification_type = "mention".to_string();
                    target_note_id = first_e_id;
                } else {
                    notification_type = "mention".to_string();
                }
            }
            6 => {
                notification_type = "repost".to_string();
                for tag in &tags {
                    if tag.len() >= 2 && tag[0] == "e" {
                        target_note_id = Some(tag[1].clone());
                        break;
                    }
                }
                needs_author_check = true;
                if let Some(ref tid) = target_note_id {
                    target_ids_to_check.insert(tid.clone());
                }
            }
            7 => {
                notification_type = "reaction".to_string();
                for tag in &tags {
                    if tag.len() >= 2 && tag[0] == "e" {
                        target_note_id = Some(tag[1].clone());
                        break;
                    }
                }
                needs_author_check = true;
                if let Some(ref tid) = target_note_id {
                    target_ids_to_check.insert(tid.clone());
                }
            }
            9735 => {
                notification_type = "zap".to_string();
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
                notification_type = "mention".to_string();
            }
        }

        pubkeys_needed.insert(from_pubkey.clone());

        pending.push(PendingItem {
            event_id,
            notification_type,
            from_pubkey,
            target_note_id,
            content,
            created_at,
            zap_amount,
            needs_author_check,
        });
    }

    let mut target_note_authors: HashMap<String, String> = HashMap::new();
    if !target_ids_to_check.is_empty() {
        let ids: Vec<EventId> = target_ids_to_check
            .iter()
            .filter_map(|id| EventId::from_hex(id).ok())
            .collect();
        if !ids.is_empty() {
            let filter = Filter::new().ids(ids).kind(Kind::TextNote);
            let target_events = client.database().query(filter).await?;
            for te in target_events {
                target_note_authors.insert(te.id.to_hex(), te.pubkey.to_hex());
            }
        }
    }

    let mut items: Vec<serde_json::Value> = Vec::new();

    for mut item in pending {
        if item.needs_author_check {
            if let Some(ref tid) = item.target_note_id {
                let author = target_note_authors.get(tid).map(|s| s.as_str()).unwrap_or("");
                if author != user_pubkey_hex {
                    item.notification_type = "mention".to_string();
                }
            }
        }

        items.push(serde_json::json!({
            "id": item.event_id,
            "type": item.notification_type,
            "fromPubkey": item.from_pubkey,
            "targetNoteId": item.target_note_id,
            "content": item.content,
            "createdAt": item.created_at,
            "fromName": serde_json::Value::Null,
            "fromImage": serde_json::Value::Null,
            "zapAmount": item.zap_amount,
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
    authors_hex: Option<Vec<String>>,
    limit: u32,
    muted_pubkeys: Vec<String>,
    muted_words: Vec<String>,
) -> Result<String> {
    let client = get_client_pub().await?;

    let filter = match authors_hex {
        Some(list) if !list.is_empty() => {
            let authors: Vec<PublicKey> = list.iter()
                .filter_map(|h| PublicKey::from_hex(h).ok())
                .collect();
            Filter::new()
                .kind(Kind::LongFormTextNote)
                .authors(authors)
                .limit(limit as usize)
        }
        _ => Filter::new()
            .kind(Kind::LongFormTextNote)
            .limit(limit as usize),
    };

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

pub async fn db_get_hydrated_article_by_naddr(
    pubkey_hex: String,
    d_tag: String,
) -> Result<Option<String>> {
    let client = get_client_pub().await?;
    let filter_json = serde_json::json!({
        "kinds": [30023],
        "authors": [pubkey_hex],
        "#d": [d_tag],
        "limit": 1,
    });
    let filter = Filter::from_json(&filter_json.to_string())?;
    let events = client.database().query(filter).await?;

    match events.into_iter().next() {
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

pub(crate) async fn hydrate_notes_pub(
    client: &Client,
    events: &[Event],
    filter_replies: bool,
    current_user_pubkey_hex: Option<String>,
) -> Result<String> {
    hydrate_notes(client, events, filter_replies, current_user_pubkey_hex).await
}

fn content_media_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"(?i)https?://\S+\.(?:jpg|jpeg|png|webp|gif|mp4|mov)").unwrap()
    })
}

fn content_link_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"(?i)https?://\S+").unwrap())
}

fn content_quote_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"(?i)(?:nostr:)?(note1[0-9a-z]+|nevent1[0-9a-z]+)").unwrap()
    })
}

fn content_article_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"(?i)(?:nostr:)?(naddr1[0-9a-z]+)").unwrap())
}

fn content_mention_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| {
        Regex::new(r"(?i)nostr:(npub1[0-9a-z]+|nprofile1[0-9a-z]+)").unwrap()
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn parse_note_content(content: String) -> String {
    let media_re = content_media_re();
    let link_re = content_link_re();
    let quote_re = content_quote_re();
    let article_re = content_article_re();
    let mention_re = content_mention_re();

    let media_urls: Vec<String> = media_re
        .find_iter(&content)
        .map(|m| m.as_str().to_string())
        .collect();

    let media_set: HashSet<&str> = media_urls.iter().map(|s| s.as_str()).collect();
    let link_urls: Vec<String> = link_re
        .find_iter(&content)
        .map(|m| m.as_str().to_string())
        .filter(|u| {
            let lower = u.to_lowercase();
            !media_set.contains(u.as_str())
                && !lower.ends_with(".mp4")
                && !lower.ends_with(".mov")
        })
        .collect();

    let quote_ids: Vec<String> = quote_re
        .captures_iter(&content)
        .filter_map(|c| c.get(1).map(|m| m.as_str().to_string()))
        .collect();

    let article_ids: Vec<String> = article_re
        .captures_iter(&content)
        .filter_map(|c| c.get(1).map(|m| m.as_str().to_string()))
        .collect();

    let mut to_remove: Vec<String> = Vec::new();
    for m in media_re.find_iter(&content) {
        to_remove.push(m.as_str().to_string());
    }
    for c in quote_re.captures_iter(&content) {
        to_remove.push(c.get(0).unwrap().as_str().to_string());
    }
    for c in article_re.captures_iter(&content) {
        to_remove.push(c.get(0).unwrap().as_str().to_string());
    }

    let mut cleaned = content.clone();
    for s in &to_remove {
        if let Some(pos) = cleaned.find(s.as_str()) {
            cleaned.replace_range(pos..pos + s.len(), "");
        }
    }
    let cleaned = cleaned.trim();

    let mut text_parts: Vec<serde_json::Value> = Vec::new();
    let mut last_end = 0;

    for caps in mention_re.captures_iter(cleaned) {
        let full_match = caps.get(0).unwrap();
        let id = caps.get(1).unwrap().as_str();

        if full_match.start() > last_end {
            text_parts.push(serde_json::json!({
                "type": "text",
                "text": &cleaned[last_end..full_match.start()],
            }));
        }

        text_parts.push(serde_json::json!({
            "type": "mention",
            "id": id,
        }));

        last_end = full_match.end();
    }

    if last_end < cleaned.len() {
        text_parts.push(serde_json::json!({
            "type": "text",
            "text": &cleaned[last_end..],
        }));
    }

    serde_json::json!({
        "textParts": text_parts,
        "mediaUrls": media_urls,
        "linkUrls": link_urls,
        "quoteIds": quote_ids,
        "articleIds": article_ids,
    })
    .to_string()
}

#[flutter_rust_bridge::frb(sync)]
pub fn extract_embedded_ids_batch(contents: Vec<String>) -> String {
    let quote_re = content_quote_re();
    let article_re = content_article_re();

    let mut quote_event_ids: HashSet<String> = HashSet::new();
    let mut article_author_pubkeys: HashSet<String> = HashSet::new();

    for content in &contents {
        for caps in quote_re.captures_iter(content) {
            if let Some(m) = caps.get(1) {
                let bech32 = m.as_str();
                if bech32.starts_with("note1") {
                    if let Ok(id) = EventId::from_bech32(bech32) {
                        quote_event_ids.insert(id.to_hex());
                    }
                } else if bech32.starts_with("nevent1") {
                    if let Ok(nevent) = Nip19Event::from_bech32(bech32) {
                        quote_event_ids.insert(nevent.event_id.to_hex());
                    }
                }
            }
        }

        for caps in article_re.captures_iter(content) {
            if let Some(m) = caps.get(1) {
                let bech32 = m.as_str();
                if let Ok(coord) = Coordinate::from_bech32(bech32) {
                    if coord.kind == Kind::LongFormTextNote {
                        article_author_pubkeys.insert(coord.public_key.to_hex());
                    }
                }
            }
        }
    }

    serde_json::json!({
        "quoteEventIds": quote_event_ids.into_iter().collect::<Vec<_>>(),
        "articleAuthorPubkeys": article_author_pubkeys.into_iter().collect::<Vec<_>>(),
    })
    .to_string()
}

pub async fn db_get_hydrated_reaction_notes(
    pubkey_hex: String,
    limit: u32,
    muted_pubkeys: Vec<String>,
    muted_words: Vec<String>,
    current_user_pubkey_hex: Option<String>,
) -> Result<String> {
    let client = get_client_pub().await?;
    let pk = PublicKey::from_hex(&pubkey_hex)?;

    let reaction_filter = Filter::new()
        .author(pk)
        .kind(Kind::Reaction)
        .limit(limit as usize);
    let reaction_events = client.database().query(reaction_filter).await?;

    let mut note_ids: Vec<String> = Vec::new();
    let mut seen: HashSet<String> = HashSet::new();

    for event in reaction_events.iter() {
        if is_event_muted(event, &muted_pubkeys, &muted_words) {
            continue;
        }
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
                    if !ref_hex.is_empty() && seen.insert(ref_hex.clone()) {
                        note_ids.push(ref_hex);
                    }
                }
                break;
            }
        }
    }

    if note_ids.is_empty() {
        return Ok("[]".to_string());
    }

    let event_ids: Vec<EventId> = note_ids
        .iter()
        .filter_map(|id| EventId::from_hex(id).ok())
        .collect();

    if event_ids.is_empty() {
        return Ok("[]".to_string());
    }

    let note_filter = Filter::new().ids(event_ids).kind(Kind::TextNote);
    let note_events = client.database().query(note_filter).await?;

    let filtered: Vec<Event> = note_events
        .into_iter()
        .filter(|e| !is_event_muted(e, &muted_pubkeys, &muted_words))
        .collect();

    let mut event_map: HashMap<String, Event> = HashMap::new();
    for ev in filtered {
        event_map.insert(ev.id.to_hex(), ev);
    }

    let mut ordered: Vec<Event> = Vec::new();
    for nid in &note_ids {
        if let Some(ev) = event_map.remove(nid) {
            ordered.push(ev);
        }
    }

    hydrate_notes(&client, &ordered, false, current_user_pubkey_hex).await
}

pub async fn db_calculate_follow_score(
    current_user_hex: String,
    target_hex: String,
) -> Result<String> {
    let client = get_client_pub().await?;
    let current_pk = PublicKey::from_hex(&current_user_hex)?;
    let target_pk = PublicKey::from_hex(&target_hex)?;
    let target_hex_str = target_pk.to_hex();

    let my_follows: Vec<PublicKey> = client
        .database()
        .contacts_public_keys(current_pk)
        .await?
        .into_iter()
        .filter(|pk| *pk != current_pk && *pk != target_pk)
        .collect();

    if my_follows.is_empty() {
        return Ok(serde_json::json!({"count": 0, "avatarUrls": []}).to_string());
    }

    let mut matching_pubkeys: Vec<PublicKey> = Vec::new();
    for follow_pk in &my_follows {
        let their_follows = client
            .database()
            .contacts_public_keys(*follow_pk)
            .await
            .unwrap_or_default();
        if their_follows.iter().any(|pk| pk.to_hex() == target_hex_str) {
            matching_pubkeys.push(*follow_pk);
        }
    }

    if matching_pubkeys.is_empty() {
        return Ok(serde_json::json!({"count": 0, "avatarUrls": []}).to_string());
    }

    let count = matching_pubkeys.len();

    let profile_filter = Filter::new()
        .authors(matching_pubkeys)
        .kind(Kind::Metadata);
    let profile_events = client.database().query(profile_filter).await?;

    let mut avatar_urls: Vec<String> = Vec::new();
    for pe in profile_events {
        if let Ok(m) = Metadata::from_json(&pe.content) {
            if let Some(ref picture) = m.picture {
                if !picture.is_empty() {
                    avatar_urls.push(picture.clone());
                }
            }
        }
    }

    Ok(serde_json::json!({"count": count, "avatarUrls": avatar_urls}).to_string())
}

pub async fn db_get_follow_sets(
    authors_hex: Vec<String>,
    limit: u32,
    hidden_d_tags: Vec<String>,
) -> Result<String> {
    let client = get_client_pub().await?;
    let authors: Vec<PublicKey> = authors_hex
        .iter()
        .filter_map(|h| PublicKey::from_hex(h).ok())
        .collect();

    if authors.is_empty() {
        return Ok("[]".to_string());
    }

    let filter = Filter::new()
        .kind(Kind::from(30000u16))
        .authors(authors)
        .limit(limit as usize);
    let events = client.database().query(filter).await?;

    let mut events_vec: Vec<Event> = events.into_iter().collect();
    events_vec.sort_by(|a, b| b.created_at.cmp(&a.created_at));

    let hidden: HashSet<&str> = hidden_d_tags.iter().map(|s| s.as_str()).collect();
    let mut seen_keys: HashSet<String> = HashSet::new();
    let mut results: Vec<serde_json::Value> = Vec::new();

    for event in &events_vec {
        let tags = tags_from_event(event);
        let mut d_tag = String::new();
        let mut title = String::new();
        let mut description = String::new();
        let mut image = String::new();
        let mut pubkeys: Vec<String> = Vec::new();

        for tag in &tags {
            if tag.len() < 2 {
                continue;
            }
            match tag[0].as_str() {
                "d" => d_tag = tag[1].clone(),
                "title" => title = tag[1].clone(),
                "description" => description = tag[1].clone(),
                "image" => image = tag[1].clone(),
                "p" if !tag[1].is_empty() => pubkeys.push(tag[1].clone()),
                _ => {}
            }
        }

        if d_tag.is_empty() || hidden.contains(d_tag.as_str()) {
            continue;
        }

        let unique_key = format!("{}:{}", event.pubkey.to_hex(), d_tag);
        if !seen_keys.insert(unique_key) {
            continue;
        }

        results.push(serde_json::json!({
            "id": event.id.to_hex(),
            "pubkey": event.pubkey.to_hex(),
            "dTag": d_tag,
            "title": title,
            "description": description,
            "image": image,
            "pubkeys": pubkeys,
            "createdAt": event.created_at.as_secs(),
        }));
    }

    Ok(serde_json::to_string(&results)?)
}
