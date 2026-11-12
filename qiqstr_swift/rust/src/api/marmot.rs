use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use anyhow::{anyhow, Context, Result};
use mdk_core::messages::MessageProcessingResult;
use mdk_core::prelude::*;
use mdk_sqlite_storage::{EncryptionConfig, MdkSqliteStorage};
use mdk_storage_traits::groups::Pagination;
use nostr::nips::nip59;
use nostr::prelude::*;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

const KEY_PACKAGE_KIND: u16 = 30443;
const LEGACY_KEY_PACKAGE_KIND: u16 = 443;
const KEY_PACKAGE_RELAYS_KIND: u16 = 10051;

struct Marmot {
    keys: Keys,
    dir: PathBuf,
    mdk: MDK<MdkSqliteStorage>,
}

static STATE: Mutex<Option<Marmot>> = Mutex::new(None);

fn with_marmot<T>(work: impl FnOnce(&Marmot) -> Result<T>) -> Result<T> {
    let guard = STATE.lock().map_err(|_| anyhow!("Messaging storage is unavailable"))?;
    let marmot = guard.as_ref().ok_or_else(|| anyhow!("Messaging is not ready"))?;
    work(marmot)
}

fn block_on<F: std::future::Future>(future: F) -> Result<F::Output> {
    Ok(futures::executor::block_on(future))
}

fn database_key(keys: &Keys) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(b"qiqstr-marmot-storage-v1");
    hasher.update(keys.secret_key().as_secret_bytes());
    hasher.finalize().into()
}

fn parse_group_id(group_id_hex: &str) -> Result<GroupId> {
    Ok(GroupId::from_slice(&hex::decode(group_id_hex).context("Invalid group id")?))
}

fn parse_relays(relays: &[String]) -> Vec<RelayUrl> {
    let mut seen = BTreeSet::new();
    relays
        .iter()
        .filter_map(|url| RelayUrl::parse(url.trim()).ok())
        .filter(|url| seen.insert(url.to_string()))
        .collect()
}

fn tags_json(tags: &Tags) -> Value {
    Value::Array(
        tags.iter()
            .map(|tag| json!(tag.as_slice().iter().map(|s| s.to_string()).collect::<Vec<_>>()))
            .collect(),
    )
}

fn message_json(message: &message_types::Message) -> Value {
    json!({
        "id": message.id.to_hex(),
        "groupId": hex::encode(message.mls_group_id.as_slice()),
        "pubkey": message.pubkey.to_hex(),
        "kind": message.kind.as_u16(),
        "content": message.content,
        "tags": tags_json(&message.tags),
        "createdAt": message.created_at.as_secs(),
        "state": message.state.to_string(),
        "wrapperId": message.wrapper_event_id.to_hex(),
    })
}

fn group_json(mdk: &MDK<MdkSqliteStorage>, group: &group_types::Group) -> Value {
    let members: Vec<String> = mdk
        .get_members(&group.mls_group_id)
        .map(|set| set.iter().map(|pk| pk.to_hex()).collect())
        .unwrap_or_default();
    let relays: Vec<String> = mdk
        .get_relays(&group.mls_group_id)
        .map(|set| set.iter().map(|url| url.to_string()).collect())
        .unwrap_or_default();
    json!({
        "id": hex::encode(group.mls_group_id.as_slice()),
        "nostrGroupId": hex::encode(group.nostr_group_id),
        "name": group.name,
        "description": group.description,
        "state": group.state.to_string(),
        "epoch": group.epoch,
        "members": members,
        "admins": group.admin_pubkeys.iter().map(|pk| pk.to_hex()).collect::<Vec<_>>(),
        "relays": relays,
        "lastMessageAt": group.last_message_at.map(|t| t.as_secs()),
    })
}

fn signed(keys: &Keys, builder: EventBuilder) -> Result<Event> {
    Ok(builder.sign_with_keys(keys)?)
}

fn key_package_slot(dir: &Path) -> Option<String> {
    std::fs::read_to_string(dir.join("key_package_slot"))
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| s.len() == 64 && s.chars().all(|c| c.is_ascii_hexdigit()))
}

fn key_package_relays(event: &Event) -> Vec<String> {
    event
        .tags
        .iter()
        .filter(|tag| tag.kind() == TagKind::Relays || tag.kind() == TagKind::Relay)
        .flat_map(|tag| tag.as_slice().iter().skip(1).cloned().collect::<Vec<_>>())
        .filter(|url| RelayUrl::parse(url).is_ok())
        .collect()
}

pub fn marmot_open(data_dir: String, private_key_hex: String) -> Result<String> {
    let keys = Keys::new(SecretKey::parse(&private_key_hex)?);
    let pubkey = keys.public_key().to_hex();
    let mut guard = STATE.lock().map_err(|_| anyhow!("Messaging storage is unavailable"))?;
    if let Some(existing) = guard.as_ref() {
        if existing.keys.public_key() == keys.public_key() {
            return Ok(pubkey);
        }
    }
    *guard = None;
    let dir = PathBuf::from(data_dir).join(&pubkey);
    std::fs::create_dir_all(&dir)?;
    let storage = MdkSqliteStorage::new_with_key(
        dir.join("mls.sqlite"),
        EncryptionConfig::new(database_key(&keys)),
    )
    .map_err(|e| anyhow!("Failed to open messaging storage: {e}"))?;
    *guard = Some(Marmot {
        keys,
        dir,
        mdk: MDK::new(storage),
    });
    Ok(pubkey)
}

pub fn marmot_close() {
    if let Ok(mut guard) = STATE.lock() {
        *guard = None;
    }
}

pub fn marmot_key_package_event(relays: Vec<String>) -> Result<String> {
    with_marmot(|m| {
        let relay_urls = parse_relays(&relays);
        if relay_urls.is_empty() {
            return Err(anyhow!("No relays for the key package"));
        }
        let data = m
            .mdk
            .create_key_package_for_event(&m.keys.public_key(), relay_urls)?;
        let slot = key_package_slot(&m.dir).unwrap_or_else(|| data.d_tag.clone());
        std::fs::write(m.dir.join("key_package_slot"), &slot)?;
        let tags: Vec<Tag> = data
            .tags_30443
            .into_iter()
            .map(|tag| {
                if tag.kind() == TagKind::d() {
                    Tag::identifier(slot.clone())
                } else {
                    tag
                }
            })
            .collect();
        let event = signed(
            &m.keys,
            EventBuilder::new(Kind::Custom(KEY_PACKAGE_KIND), data.content).tags(tags),
        )?;
        Ok(event.as_json())
    })
}

pub fn marmot_key_package_relays_event(relays: Vec<String>) -> Result<String> {
    with_marmot(|m| {
        let tags: Vec<Tag> = parse_relays(&relays)
            .into_iter()
            .map(|url| Tag::custom(TagKind::Relay, [url.to_string()]))
            .collect();
        let event = signed(
            &m.keys,
            EventBuilder::new(Kind::Custom(KEY_PACKAGE_RELAYS_KIND), "").tags(tags),
        )?;
        Ok(event.as_json())
    })
}

pub fn marmot_pick_key_package(events_json: String, pubkey_hex: String) -> Result<Option<String>> {
    let owner = PublicKey::parse(&pubkey_hex)?;
    let events: Vec<Value> = serde_json::from_str(&events_json)?;
    with_marmot(|m| {
        let mut candidates: Vec<Event> = events
            .iter()
            .filter_map(|value| Event::from_json(value.to_string()).ok())
            .filter(|event| {
                event.pubkey == owner
                    && matches!(event.kind.as_u16(), KEY_PACKAGE_KIND | LEGACY_KEY_PACKAGE_KIND)
                    && event.verify().is_ok()
            })
            .collect();
        candidates.sort_by_key(|event| {
            (
                event.kind.as_u16() == KEY_PACKAGE_KIND,
                event.created_at.as_secs(),
            )
        });
        Ok(candidates
            .into_iter()
            .rev()
            .find(|event| m.mdk.parse_key_package(event).is_ok())
            .map(|event| event.as_json()))
    })
}

pub fn marmot_create_chat(peer_key_package_json: String, relays: Vec<String>) -> Result<String> {
    let key_package = Event::from_json(&peer_key_package_json)?;
    key_package.verify()?;
    with_marmot(|m| {
        let me = m.keys.public_key();
        let peer = key_package.pubkey;
        if peer == me {
            return Err(anyhow!("You can't start a chat with yourself"));
        }
        let mut group_relays = relays.clone();
        group_relays.extend(key_package_relays(&key_package));
        let relay_urls = parse_relays(&group_relays);
        if relay_urls.is_empty() {
            return Err(anyhow!("No relays for the chat"));
        }
        let config = NostrGroupConfigData::new(
            String::new(),
            String::new(),
            None,
            None,
            None,
            relay_urls.into_iter().take(6).collect(),
            vec![me, peer],
        );
        let result = m.mdk.create_group(&me, vec![key_package.clone()], config)?;
        let mut welcomes = Vec::new();
        for rumor in result.welcome_rumors {
            let wrap = block_on(EventBuilder::gift_wrap(&m.keys, &peer, rumor, []))??;
            welcomes.push(json!(wrap.as_json()));
        }
        let mut welcome_relays = key_package_relays(&key_package);
        if welcome_relays.is_empty() {
            welcome_relays = relays;
        }
        Ok(json!({
            "group": group_json(&m.mdk, &result.group),
            "welcomes": welcomes,
            "welcomeRelays": welcome_relays,
        })
        .to_string())
    })
}

pub fn marmot_send_message(
    group_id_hex: String,
    kind: u16,
    content: String,
    tags_json: String,
) -> Result<String> {
    let group_id = parse_group_id(&group_id_hex)?;
    let raw_tags: Vec<Vec<String>> = if tags_json.trim().is_empty() {
        Vec::new()
    } else {
        serde_json::from_str(&tags_json)?
    };
    let tags: Vec<Tag> = raw_tags
        .into_iter()
        .filter(|values| !values.is_empty())
        .map(Tag::parse)
        .collect::<std::result::Result<_, _>>()?;
    with_marmot(|m| {
        let rumor = EventBuilder::new(Kind::Custom(kind), content)
            .tags(tags)
            .build(m.keys.public_key());
        let event = m.mdk.create_message(&group_id, rumor, None)?;
        let message = m
            .mdk
            .get_messages(&group_id, Some(Pagination::new(Some(20), Some(0))))?
            .into_iter()
            .find(|message| message.wrapper_event_id == event.id)
            .map(|message| message_json(&message));
        Ok(json!({ "event": event.as_json(), "message": message }).to_string())
    })
}

fn process_gift_wrap(m: &Marmot, event: &Event) -> Result<Value> {
    let unwrapped = block_on(nip59::UnwrappedGift::from_gift_wrap(&m.keys, event))??;
    if unwrapped.rumor.kind != Kind::MlsWelcome {
        return Ok(json!({ "type": "ignored" }));
    }
    let welcome = m.mdk.process_welcome(&event.id, &unwrapped.rumor)?;
    let group_id = hex::encode(welcome.mls_group_id.as_slice());
    let accepted = welcome.state == welcome_types::WelcomeState::Accepted;
    if !accepted && welcome.state == welcome_types::WelcomeState::Pending {
        m.mdk.accept_welcome(&welcome)?;
    }
    let group = m
        .mdk
        .get_group(&welcome.mls_group_id)?
        .map(|group| group_json(&m.mdk, &group));
    Ok(json!({
        "type": "welcome",
        "groupId": group_id,
        "isNew": !accepted,
        "inviter": unwrapped.sender.to_hex(),
        "group": group,
    }))
}

fn process_group_message(m: &Marmot, event: &Event) -> Result<Value> {
    let result = m.mdk.process_message(event)?;
    Ok(match result {
        MessageProcessingResult::ApplicationMessage(message) => json!({
            "type": "message",
            "groupId": hex::encode(message.mls_group_id.as_slice()),
            "message": message_json(&message),
        }),
        MessageProcessingResult::Commit { mls_group_id } => json!({
            "type": "commit",
            "groupId": hex::encode(mls_group_id.as_slice()),
        }),
        MessageProcessingResult::Proposal(update) => json!({
            "type": "proposal",
            "groupId": hex::encode(update.mls_group_id.as_slice()),
            "evolutionEvent": update.evolution_event.as_json(),
        }),
        MessageProcessingResult::PendingProposal { mls_group_id }
        | MessageProcessingResult::ExternalJoinProposal { mls_group_id } => json!({
            "type": "pending",
            "groupId": hex::encode(mls_group_id.as_slice()),
        }),
        MessageProcessingResult::IgnoredProposal { mls_group_id, .. }
        | MessageProcessingResult::Unprocessable { mls_group_id } => json!({
            "type": "ignored",
            "groupId": hex::encode(mls_group_id.as_slice()),
        }),
        MessageProcessingResult::PreviouslyFailed => json!({ "type": "ignored" }),
    })
}

pub fn marmot_process_event(event_json: String) -> Result<String> {
    let event = Event::from_json(&event_json)?;
    event.verify()?;
    with_marmot(|m| {
        let result = match event.kind {
            Kind::GiftWrap => process_gift_wrap(m, &event)?,
            Kind::MlsGroupMessage => process_group_message(m, &event)?,
            _ => json!({ "type": "ignored" }),
        };
        Ok(result.to_string())
    })
}

pub fn marmot_groups() -> Result<String> {
    with_marmot(|m| {
        let groups: Vec<Value> = m
            .mdk
            .get_groups()?
            .iter()
            .map(|group| group_json(&m.mdk, group))
            .collect();
        Ok(Value::Array(groups).to_string())
    })
}

pub fn marmot_messages(group_id_hex: String, limit: u32) -> Result<String> {
    let group_id = parse_group_id(&group_id_hex)?;
    with_marmot(|m| {
        let messages: Vec<Value> = m
            .mdk
            .get_messages(
                &group_id,
                Some(Pagination::new(Some(limit.clamp(1, 1000) as usize), Some(0))),
            )?
            .iter()
            .map(message_json)
            .collect();
        Ok(Value::Array(messages).to_string())
    })
}

pub fn marmot_groups_needing_self_update(threshold_secs: u64) -> Result<Vec<String>> {
    with_marmot(|m| {
        Ok(m.mdk
            .groups_needing_self_update(threshold_secs)?
            .iter()
            .map(|id| hex::encode(id.as_slice()))
            .collect())
    })
}

pub fn marmot_self_update(group_id_hex: String) -> Result<String> {
    let group_id = parse_group_id(&group_id_hex)?;
    with_marmot(|m| Ok(m.mdk.self_update(&group_id)?.evolution_event.as_json()))
}

pub fn marmot_merge_pending_commit(group_id_hex: String) -> Result<()> {
    let group_id = parse_group_id(&group_id_hex)?;
    with_marmot(|m| Ok(m.mdk.merge_pending_commit(&group_id)?))
}

pub fn marmot_clear_pending_commit(group_id_hex: String) -> Result<()> {
    let group_id = parse_group_id(&group_id_hex)?;
    with_marmot(|m| Ok(m.mdk.clear_pending_commit(&group_id)?))
}

pub fn marmot_encrypt_media(
    group_id_hex: String,
    data: Vec<u8>,
    mime_type: String,
    filename: String,
    output_path: String,
) -> Result<String> {
    let group_id = parse_group_id(&group_id_hex)?;
    with_marmot(|m| {
        let manager = m.mdk.media_manager(group_id);
        let upload = manager
            .encrypt_for_upload(&data, &mime_type, &filename)
            .map_err(|e| anyhow!("{e}"))?;
        std::fs::write(&output_path, &upload.encrypted_data)?;
        let imeta: Vec<String> = manager
            .create_imeta_tag(&upload, "")
            .as_slice()
            .iter()
            .skip(1)
            .filter(|value| !value.starts_with("url"))
            .cloned()
            .collect();
        Ok(json!({
            "encryptedHash": hex::encode(upload.encrypted_hash),
            "originalHash": hex::encode(upload.original_hash),
            "mimeType": upload.mime_type,
            "filename": upload.filename,
            "size": upload.encrypted_size,
            "imeta": imeta,
        })
        .to_string())
    })
}

pub fn marmot_decrypt_media(group_id_hex: String, imeta: Vec<String>, data: Vec<u8>) -> Result<Vec<u8>> {
    let group_id = parse_group_id(&group_id_hex)?;
    let mut values = vec!["imeta".to_string()];
    values.extend(imeta);
    let tag = Tag::parse(values)?;
    with_marmot(|m| {
        let manager = m.mdk.media_manager(group_id);
        let reference = manager.parse_imeta_tag(&tag).map_err(|e| anyhow!("{e}"))?;
        manager
            .decrypt_from_download(&data, &reference)
            .map_err(|e| anyhow!("{e}"))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(name: &str) -> String {
        let dir = std::env::temp_dir().join(format!("qiqstr-marmot-{name}-{}", Keys::generate().public_key().to_hex()));
        std::fs::create_dir_all(&dir).unwrap();
        dir.to_string_lossy().to_string()
    }

    #[test]
    fn two_users_exchange_messages() {
        let relays = vec!["wss://relay.example.com".to_string()];
        let alice = Keys::generate();
        let bob = Keys::generate();
        let alice_dir = temp_dir("alice");
        let bob_dir = temp_dir("bob");

        marmot_open(bob_dir.clone(), bob.secret_key().to_secret_hex()).unwrap();
        let key_package = marmot_key_package_event(relays.clone()).unwrap();
        let again = marmot_key_package_event(relays.clone()).unwrap();
        let slot = |raw: &str| Event::from_json(raw).unwrap().tags.identifier().map(|s| s.to_string());
        assert_eq!(slot(&key_package), slot(&again));

        marmot_open(alice_dir.clone(), alice.secret_key().to_secret_hex()).unwrap();
        let events = serde_json::to_string(&vec![
            serde_json::from_str::<Value>(&key_package).unwrap(),
        ])
        .unwrap();
        let picked = marmot_pick_key_package(events, bob.public_key().to_hex()).unwrap().unwrap();
        let chat: Value = serde_json::from_str(&marmot_create_chat(picked, relays.clone()).unwrap()).unwrap();
        let group_id = chat["group"]["id"].as_str().unwrap().to_string();
        let welcome = chat["welcomes"][0].as_str().unwrap().to_string();
        let sent: Value = serde_json::from_str(
            &marmot_send_message(group_id.clone(), 9, "hi bob".into(), "[]".into()).unwrap(),
        )
        .unwrap();
        assert_eq!(sent["message"]["content"], "hi bob");
        let outer = sent["event"].as_str().unwrap().to_string();

        let media = b"plain text attachment".to_vec();
        let output = std::env::temp_dir().join(format!("{}.enc", Keys::generate().public_key().to_hex()));
        let upload: Value = serde_json::from_str(
            &marmot_encrypt_media(group_id.clone(), media.clone(), "text/plain".into(), "note.txt".into(), output.to_string_lossy().to_string()).unwrap(),
        )
        .unwrap();
        let mut imeta = vec!["imeta".to_string(), "url https://blossom.example.com/x".to_string()];
        imeta.extend(upload["imeta"].as_array().unwrap().iter().map(|v| v.as_str().unwrap().to_string()));
        let media_event: Value = serde_json::from_str(
            &marmot_send_message(group_id.clone(), 9, String::new(), serde_json::to_string(&vec![imeta.clone()]).unwrap()).unwrap(),
        )
        .unwrap();
        let encrypted = std::fs::read(&output).unwrap();

        marmot_open(bob_dir.clone(), bob.secret_key().to_secret_hex()).unwrap();
        let runtime = tokio::runtime::Builder::new_current_thread().build().unwrap();
        let joined: Value = serde_json::from_str(&runtime.block_on(async { marmot_process_event(welcome) }).unwrap()).unwrap();
        assert_eq!(joined["type"], "welcome");
        assert_eq!(joined["groupId"], group_id.as_str());
        let received: Value = serde_json::from_str(&marmot_process_event(outer).unwrap()).unwrap();
        assert_eq!(received["type"], "message");
        assert_eq!(received["message"]["content"], "hi bob");
        assert_eq!(received["message"]["pubkey"], alice.public_key().to_hex());
        let media_received: Value =
            serde_json::from_str(&marmot_process_event(media_event["event"].as_str().unwrap().to_string()).unwrap()).unwrap();
        assert_eq!(media_received["type"], "message");
        let decrypted = marmot_decrypt_media(group_id.clone(), imeta[1..].to_vec(), encrypted).unwrap();
        assert_eq!(decrypted, media);

        let needing = marmot_groups_needing_self_update(86_400).unwrap();
        assert_eq!(needing, vec![group_id.clone()]);
        let commit = marmot_self_update(group_id.clone()).unwrap();
        marmot_merge_pending_commit(group_id.clone()).unwrap();
        let reply: Value = serde_json::from_str(
            &marmot_send_message(group_id.clone(), 9, "hi alice".into(), "[]".into()).unwrap(),
        )
        .unwrap();
        let groups: Value = serde_json::from_str(&marmot_groups().unwrap()).unwrap();
        assert_eq!(groups[0]["members"].as_array().unwrap().len(), 2);

        marmot_open(alice_dir, alice.secret_key().to_secret_hex()).unwrap();
        let processed: Value = serde_json::from_str(&marmot_process_event(commit).unwrap()).unwrap();
        assert_eq!(processed["type"], "commit");
        let reply_received: Value =
            serde_json::from_str(&marmot_process_event(reply["event"].as_str().unwrap().to_string()).unwrap()).unwrap();
        assert_eq!(reply_received["message"]["content"], "hi alice");
        let history: Value = serde_json::from_str(&marmot_messages(group_id, 50).unwrap()).unwrap();
        assert_eq!(history.as_array().unwrap().len(), 3);
        marmot_close();
    }
}
