use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use anyhow::{anyhow, Context, Result};
use mdk_core::messages::MessageProcessingResult;
use mdk_core::prelude::*;
use mdk_sqlite_storage::{EncryptionConfig, MdkSqliteStorage};
use mdk_storage_traits::groups::Pagination;
use mdk_storage_traits::messages::MessageStorage;
use nostr::nips::nip59;
use nostr::prelude::*;

use super::crypto::Secret;
use openmls::prelude::OpenMlsProvider;
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
    let guard = STATE
        .lock()
        .map_err(|_| anyhow!("Messaging storage is unavailable"))?;
    let marmot = guard
        .as_ref()
        .ok_or_else(|| anyhow!("Messaging is not ready"))?;
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
    Ok(GroupId::from_slice(
        &hex::decode(group_id_hex).context("Invalid group id")?,
    ))
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
            .map(|tag| {
                json!(tag
                    .as_slice()
                    .iter()
                    .map(|s| s.to_string())
                    .collect::<Vec<_>>())
            })
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

fn remember_media_secret(m: &Marmot, group_id: &GroupId) {
    use mdk_storage_traits::groups::GroupStorage;
    let storage = m.mdk.provider.storage();
    let mls_id = openmls::group::GroupId::from_slice(group_id.as_slice());
    let Ok(Some(group)) = openmls::group::MlsGroup::load(storage, &mls_id) else {
        return;
    };
    let epoch = group.epoch().as_u64();
    if matches!(
        storage.get_group_mip04_exporter_secret(group_id, epoch),
        Ok(Some(_))
    ) {
        return;
    }
    let Ok(secret) = group.export_secret(m.mdk.provider.crypto(), "marmot", b"encrypted-media", 32)
    else {
        return;
    };
    let Ok(secret): std::result::Result<[u8; 32], _> = secret.try_into() else {
        return;
    };
    let _ = storage.save_group_mip04_exporter_secret(group_types::GroupExporterSecret {
        mls_group_id: group_id.clone(),
        epoch,
        secret: mdk_storage_traits::Secret::new(secret),
    });
}

fn signed(keys: &Keys, builder: EventBuilder) -> Result<Event> {
    Ok(builder.sign_with_keys(keys)?)
}

fn rejected_groups(dir: &Path) -> std::collections::HashSet<String> {
    std::fs::read_to_string(dir.join("rejected_groups"))
        .map(|s| {
            s.lines()
                .map(|line| line.trim().to_string())
                .filter(|line| !line.is_empty())
                .collect()
        })
        .unwrap_or_default()
}

fn reject_group(dir: &Path, group_id: &str) {
    let mut set = rejected_groups(dir);
    if set.insert(group_id.to_string()) {
        let mut list: Vec<String> = set.into_iter().collect();
        list.sort();
        let _ = std::fs::write(dir.join("rejected_groups"), list.join("\n"));
    }
}

fn welcome_is_authentic(
    members: &std::collections::BTreeSet<PublicKey>,
    me: &PublicKey,
    sender: &PublicKey,
) -> bool {
    if sender == me || !members.contains(me) || !members.contains(sender) {
        return false;
    }
    let others: Vec<&PublicKey> = members.iter().filter(|member| *member != me).collect();
    others.len() != 1 || others[0] == sender
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
    let private_key_hex = Secret::new(private_key_hex);
    open_with_keys(data_dir, Keys::new(SecretKey::parse(&private_key_hex)?))
}

/// Opens messaging for the signed-in account, using the key the core already holds.
pub fn marmot_open_session(data_dir: String) -> Result<String> {
    open_with_keys(data_dir, super::session::session_keys()?)
}

fn open_with_keys(data_dir: String, keys: Keys) -> Result<String> {
    let pubkey = keys.public_key().to_hex();
    let mut guard = STATE
        .lock()
        .map_err(|_| anyhow!("Messaging storage is unavailable"))?;
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
    let marmot = Marmot {
        keys,
        dir,
        mdk: MDK::new(storage),
    };
    if let Ok(groups) = marmot.mdk.get_groups() {
        for group in groups {
            remember_media_secret(&marmot, &group.mls_group_id);
        }
    }
    *guard = Some(marmot);
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
                    && matches!(
                        event.kind.as_u16(),
                        KEY_PACKAGE_KIND | LEGACY_KEY_PACKAGE_KIND
                    )
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
        remember_media_secret(m, &result.group.mls_group_id);
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

fn parse_key_packages(m: &Marmot, events_json: &[String]) -> Result<Vec<Event>> {
    let me = m.keys.public_key();
    let mut seen = BTreeSet::new();
    let mut packages = Vec::new();
    for raw in events_json {
        let event = Event::from_json(raw)?;
        event.verify()?;
        if event.pubkey == me || !seen.insert(event.pubkey) {
            continue;
        }
        packages.push(event);
    }
    if packages.is_empty() {
        return Err(anyhow!("Add at least one other person"));
    }
    Ok(packages)
}

fn wrap_welcomes(m: &Marmot, rumors: Vec<UnsignedEvent>, packages: &[Event]) -> Result<Vec<Value>> {
    let mut welcomes = Vec::new();
    for rumor in rumors {
        let package = rumor
            .tags
            .iter()
            .find_map(|tag| match tag.as_standardized() {
                Some(TagStandard::Event { event_id, .. }) => {
                    packages.iter().find(|event| event.id == *event_id)
                }
                _ => None,
            })
            .ok_or_else(|| anyhow!("Welcome without a matching member"))?;
        let wrap = block_on(EventBuilder::gift_wrap(&m.keys, &package.pubkey, rumor, []))??;
        welcomes.push(json!({
            "pubkey": package.pubkey.to_hex(),
            "wrap": wrap.as_json(),
            "relays": key_package_relays(package),
        }));
    }
    Ok(welcomes)
}

fn is_admin(m: &Marmot, group_id: &GroupId) -> Result<bool> {
    let group = m
        .mdk
        .get_group(group_id)?
        .ok_or_else(|| anyhow!("Group not found"))?;
    Ok(group.admin_pubkeys.contains(&m.keys.public_key()))
}

/// Creates a named group chat with the given members' key packages.
///
/// Returns JSON `{ "group", "welcomes": [ { "pubkey", "wrap", "relays" } ] }`.
pub fn marmot_create_group(
    key_packages_json: Vec<String>,
    name: String,
    description: String,
    relays: Vec<String>,
) -> Result<String> {
    let name = name.trim().to_string();
    if name.is_empty() {
        return Err(anyhow!("Give the group a name"));
    }
    with_marmot(|m| {
        let me = m.keys.public_key();
        let packages = parse_key_packages(m, &key_packages_json)?;
        let mut group_relays = relays.clone();
        for package in &packages {
            group_relays.extend(key_package_relays(package));
        }
        let relay_urls: Vec<RelayUrl> = parse_relays(&group_relays).into_iter().take(6).collect();
        if relay_urls.is_empty() {
            return Err(anyhow!("No relays for the group"));
        }
        let config = NostrGroupConfigData::new(
            name,
            description.trim().to_string(),
            None,
            None,
            None,
            relay_urls,
            vec![me],
        );
        let result = m.mdk.create_group(&me, packages.clone(), config)?;
        remember_media_secret(m, &result.group.mls_group_id);
        let welcomes = wrap_welcomes(m, result.welcome_rumors, &packages)?;
        Ok(json!({
            "group": group_json(&m.mdk, &result.group),
            "welcomes": welcomes,
        })
        .to_string())
    })
}

/// Adds members to a group. Publish `evolutionEvent`, merge the pending commit, then send the welcomes.
///
/// Returns JSON `{ "evolutionEvent", "welcomes": [ { "pubkey", "wrap", "relays" } ] }`.
pub fn marmot_add_members(group_id_hex: String, key_packages_json: Vec<String>) -> Result<String> {
    let group_id = parse_group_id(&group_id_hex)?;
    with_marmot(|m| {
        let members = m.mdk.get_members(&group_id)?;
        let packages: Vec<Event> = parse_key_packages(m, &key_packages_json)?
            .into_iter()
            .filter(|event| !members.contains(&event.pubkey))
            .collect();
        if packages.is_empty() {
            return Err(anyhow!("Everyone you picked is already in the group"));
        }
        let result = m.mdk.add_members(&group_id, &packages)?;
        let welcomes = wrap_welcomes(m, result.welcome_rumors.unwrap_or_default(), &packages)?;
        Ok(json!({
            "evolutionEvent": result.evolution_event.as_json(),
            "welcomes": welcomes,
        })
        .to_string())
    })
}

/// Removes members from a group (admins only). Returns the commit event to publish before merging.
pub fn marmot_remove_members(group_id_hex: String, pubkeys_hex: Vec<String>) -> Result<String> {
    let group_id = parse_group_id(&group_id_hex)?;
    let pubkeys: Vec<PublicKey> = pubkeys_hex
        .iter()
        .map(|pk| PublicKey::from_hex(pk))
        .collect::<std::result::Result<_, _>>()?;
    with_marmot(|m| {
        Ok(m.mdk
            .remove_members(&group_id, &pubkeys)?
            .evolution_event
            .as_json())
    })
}

/// Renames a group (admins only). Returns the commit event to publish before merging.
pub fn marmot_rename_group(group_id_hex: String, name: String) -> Result<String> {
    let group_id = parse_group_id(&group_id_hex)?;
    let name = name.trim().to_string();
    if name.is_empty() {
        return Err(anyhow!("Give the group a name"));
    }
    with_marmot(|m| {
        Ok(m.mdk
            .update_group_data(&group_id, NostrGroupDataUpdate::new().name(name))?
            .evolution_event
            .as_json())
    })
}

/// Returns the next step for leaving a group.
///
/// JSON `{ "event": String?, "isCommit": bool, "done": bool }`. Publish `event`; when `isCommit`, merge the
/// pending commit and call again. When `done`, publish the event (if any) and then call `marmot_delete_group`.
pub fn marmot_leave_step(group_id_hex: String) -> Result<String> {
    let group_id = parse_group_id(&group_id_hex)?;
    with_marmot(|m| {
        let me = m.keys.public_key();
        let others: Vec<PublicKey> = m
            .mdk
            .get_members(&group_id)?
            .into_iter()
            .filter(|pk| *pk != me)
            .collect();
        if others.is_empty() {
            return Ok(json!({ "event": null, "isCommit": false, "done": true }).to_string());
        }
        if !is_admin(m, &group_id)? {
            let event = m.mdk.leave_group(&group_id)?.evolution_event.as_json();
            return Ok(json!({ "event": event, "isCommit": false, "done": true }).to_string());
        }
        let group = m
            .mdk
            .get_group(&group_id)?
            .ok_or_else(|| anyhow!("Group not found"))?;
        let other_admins = group
            .admin_pubkeys
            .iter()
            .any(|pk| *pk != me && others.contains(pk));
        let update = if other_admins {
            m.mdk.self_demote(&group_id)?
        } else {
            m.mdk
                .update_group_data(&group_id, NostrGroupDataUpdate::new().admins(others))?
        };
        Ok(
            json!({ "event": update.evolution_event.as_json(), "isCommit": true, "done": false })
                .to_string(),
        )
    })
}

/// Deletes a group and its messages from this device.
pub fn marmot_delete_group(group_id_hex: String) -> Result<()> {
    let group_id = parse_group_id(&group_id_hex)?;
    with_marmot(|m| {
        let _ = m.mdk.delete_messages_for_group(&group_id);
        m.mdk.delete_group(&group_id)?;
        reject_group(&m.dir, &group_id_hex);
        Ok(())
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
    if rejected_groups(&m.dir).contains(&group_id) {
        return Ok(json!({ "type": "ignored" }));
    }
    let accepted = welcome.state == welcome_types::WelcomeState::Accepted;
    if !accepted && welcome.state == welcome_types::WelcomeState::Pending {
        m.mdk.accept_welcome(&welcome)?;
    }
    remember_media_secret(m, &welcome.mls_group_id);
    let members = m.mdk.get_members(&welcome.mls_group_id).unwrap_or_default();
    if !welcome_is_authentic(&members, &m.keys.public_key(), &unwrapped.sender) {
        reject_group(&m.dir, &group_id);
        return Ok(json!({ "type": "ignored" }));
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
    let rejected = rejected_groups(&m.dir);
    let group_of = |id: &GroupId| rejected.contains(&hex::encode(id.as_slice()));
    let is_rejected = match &result {
        MessageProcessingResult::ApplicationMessage(message) => group_of(&message.mls_group_id),
        MessageProcessingResult::Commit { mls_group_id }
        | MessageProcessingResult::PendingProposal { mls_group_id }
        | MessageProcessingResult::ExternalJoinProposal { mls_group_id }
        | MessageProcessingResult::IgnoredProposal { mls_group_id, .. }
        | MessageProcessingResult::Unprocessable { mls_group_id } => group_of(mls_group_id),
        MessageProcessingResult::Proposal(update) => group_of(&update.mls_group_id),
        _ => false,
    };
    if is_rejected {
        return Ok(json!({ "type": "ignored" }));
    }
    Ok(match result {
        MessageProcessingResult::ApplicationMessage(message) => json!({
            "type": "message",
            "groupId": hex::encode(message.mls_group_id.as_slice()),
            "message": message_json(&message),
        }),
        MessageProcessingResult::Commit { mls_group_id } => json!({
            "type": "commit",
            "groupId": hex::encode(mls_group_id.as_slice()),
            "retry": retryable_after_commit(m, &mls_group_id),
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

fn retryable_after_commit(m: &Marmot, group_id: &GroupId) -> Vec<String> {
    let storage = m.mdk.provider.storage();
    storage
        .find_failed_messages_for_retry(group_id)
        .unwrap_or_default()
        .into_iter()
        .filter(|event_id| storage.mark_processed_message_retryable(event_id).is_ok())
        .map(|event_id| event_id.to_hex())
        .collect()
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
        let rejected = rejected_groups(&m.dir);
        let groups: Vec<Value> = m
            .mdk
            .get_groups()?
            .iter()
            .filter(|group| !rejected.contains(&hex::encode(group.mls_group_id.as_slice())))
            .map(|group| group_json(&m.mdk, group))
            .collect();
        Ok(Value::Array(groups).to_string())
    })
}

pub fn marmot_messages(group_id_hex: String, limit: u32) -> Result<String> {
    marmot_messages_page(group_id_hex, limit, 0)
}

pub fn marmot_messages_page(group_id_hex: String, limit: u32, offset: u32) -> Result<String> {
    let group_id = parse_group_id(&group_id_hex)?;
    with_marmot(|m| {
        let messages: Vec<Value> = m
            .mdk
            .get_messages(
                &group_id,
                Some(Pagination::new(
                    Some(limit.clamp(1, 1000) as usize),
                    Some(offset as usize),
                )),
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
        remember_media_secret(m, &group_id);
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

pub fn marmot_decrypt_media(
    group_id_hex: String,
    imeta: Vec<String>,
    data: Vec<u8>,
) -> Result<Vec<u8>> {
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

    #[test]
    fn welcomes_must_come_from_the_claimed_peer() {
        let me = Keys::generate().public_key();
        let sender = Keys::generate().public_key();
        let victim = Keys::generate().public_key();
        let pair = |a: PublicKey, b: PublicKey| {
            [a, b]
                .into_iter()
                .collect::<std::collections::BTreeSet<_>>()
        };
        assert!(welcome_is_authentic(&pair(me, sender), &me, &sender));
        assert!(!welcome_is_authentic(&pair(me, victim), &me, &sender));
        assert!(!welcome_is_authentic(&pair(sender, victim), &me, &sender));
        assert!(!welcome_is_authentic(&pair(me, sender), &me, &me));
        let group: std::collections::BTreeSet<_> = [me, sender, victim].into_iter().collect();
        assert!(welcome_is_authentic(&group, &me, &sender));
    }

    #[test]
    fn rejected_groups_persist() {
        let dir = std::env::temp_dir().join(format!("qiqstr-rejected-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        reject_group(&dir, "aa");
        reject_group(&dir, "bb");
        reject_group(&dir, "aa");
        let set = rejected_groups(&dir);
        assert_eq!(set.len(), 2);
        assert!(set.contains("aa") && set.contains("bb"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    fn temp_dir(name: &str) -> String {
        let dir = std::env::temp_dir().join(format!(
            "qiqstr-marmot-{name}-{}",
            Keys::generate().public_key().to_hex()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        dir.to_string_lossy().to_string()
    }

    static SERIAL: std::sync::Mutex<()> = std::sync::Mutex::new(());

    fn process(event: String) -> Value {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        serde_json::from_str(
            &runtime
                .block_on(async { marmot_process_event(event) })
                .unwrap(),
        )
        .unwrap()
    }

    #[test]
    fn three_people_share_a_group() {
        let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        let relays = vec!["wss://relay.example.com".to_string()];
        let (alice, bob, carol) = (Keys::generate(), Keys::generate(), Keys::generate());
        let (alice_dir, bob_dir, carol_dir) = (temp_dir("ga"), temp_dir("gb"), temp_dir("gc"));

        marmot_open(bob_dir.clone(), bob.secret_key().to_secret_hex()).unwrap();
        let bob_package = marmot_key_package_event(relays.clone()).unwrap();
        marmot_open(carol_dir.clone(), carol.secret_key().to_secret_hex()).unwrap();
        let carol_package = marmot_key_package_event(relays.clone()).unwrap();

        marmot_open(alice_dir.clone(), alice.secret_key().to_secret_hex()).unwrap();
        assert!(marmot_create_group(
            vec![bob_package.clone()],
            "  ".into(),
            String::new(),
            relays.clone()
        )
        .is_err());
        let created: Value = serde_json::from_str(
            &marmot_create_group(
                vec![bob_package],
                "Weekend".into(),
                String::new(),
                relays.clone(),
            )
            .unwrap(),
        )
        .unwrap();
        let group_id = created["group"]["id"].as_str().unwrap().to_string();
        assert_eq!(created["group"]["name"], "Weekend");
        let bob_welcome = created["welcomes"][0]["wrap"].as_str().unwrap().to_string();
        assert_eq!(created["welcomes"][0]["pubkey"], bob.public_key().to_hex());

        let added: Value = serde_json::from_str(
            &marmot_add_members(group_id.clone(), vec![carol_package]).unwrap(),
        )
        .unwrap();
        let add_commit = added["evolutionEvent"].as_str().unwrap().to_string();
        marmot_merge_pending_commit(group_id.clone()).unwrap();
        let carol_welcome = added["welcomes"][0]["wrap"].as_str().unwrap().to_string();
        let hello: Value = serde_json::from_str(
            &marmot_send_message(group_id.clone(), 9, "hello all".into(), "[]".into()).unwrap(),
        )
        .unwrap();
        let hello_event = hello["event"].as_str().unwrap().to_string();
        let hello_id = hello["message"]["id"].as_str().unwrap().to_string();

        marmot_open(bob_dir.clone(), bob.secret_key().to_secret_hex()).unwrap();
        assert_eq!(process(bob_welcome)["type"], "welcome");
        assert_eq!(process(add_commit)["type"], "commit");
        assert_eq!(
            process(hello_event.clone())["message"]["content"],
            "hello all"
        );
        let reaction: Value = serde_json::from_str(
            &marmot_send_message(
                group_id.clone(),
                7,
                "🔥".into(),
                serde_json::to_string(&vec![vec!["e".to_string(), hello_id.clone()]]).unwrap(),
            )
            .unwrap(),
        )
        .unwrap();
        let reaction_event = reaction["event"].as_str().unwrap().to_string();
        let leave: Value =
            serde_json::from_str(&marmot_leave_step(group_id.clone()).unwrap()).unwrap();
        assert_eq!(leave["done"], true);
        assert_eq!(leave["isCommit"], false);
        let leave_event = leave["event"].as_str().unwrap().to_string();
        marmot_delete_group(group_id.clone()).unwrap();
        let groups: Value = serde_json::from_str(&marmot_groups().unwrap()).unwrap();
        assert!(groups.as_array().unwrap().is_empty());

        marmot_open(carol_dir, carol.secret_key().to_secret_hex()).unwrap();
        let joined = process(carol_welcome);
        assert_eq!(joined["type"], "welcome");
        let groups: Value = serde_json::from_str(&marmot_groups().unwrap()).unwrap();
        assert_eq!(groups[0]["members"].as_array().unwrap().len(), 3);
        assert_eq!(groups[0]["name"], "Weekend");
        let got = process(reaction_event);
        assert_eq!(got["message"]["kind"], 7);
        assert_eq!(got["message"]["content"], "🔥");

        marmot_open(alice_dir, alice.secret_key().to_secret_hex()).unwrap();
        let proposal = process(leave_event);
        assert_eq!(proposal["type"], "proposal");
        assert!(proposal["evolutionEvent"].is_string());
        marmot_merge_pending_commit(group_id.clone()).unwrap();
        let groups: Value = serde_json::from_str(&marmot_groups().unwrap()).unwrap();
        assert_eq!(groups[0]["members"].as_array().unwrap().len(), 2);
        let step: Value =
            serde_json::from_str(&marmot_leave_step(group_id.clone()).unwrap()).unwrap();
        assert_eq!(step["isCommit"], true);
        assert!(marmot_rename_group(group_id.clone(), "".into()).is_err());
        marmot_close();
    }

    #[test]
    fn media_survives_a_self_update() {
        let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        let relays = vec!["wss://relay.example.com".to_string()];
        let (alice, bob) = (Keys::generate(), Keys::generate());
        let (alice_dir, bob_dir) = (temp_dir("ma"), temp_dir("mb"));
        marmot_open(bob_dir.clone(), bob.secret_key().to_secret_hex()).unwrap();
        let kp = marmot_key_package_event(relays.clone()).unwrap();
        marmot_open(alice_dir, alice.secret_key().to_secret_hex()).unwrap();
        let chat: Value =
            serde_json::from_str(&marmot_create_chat(kp, relays.clone()).unwrap()).unwrap();
        let gid = chat["group"]["id"].as_str().unwrap().to_string();
        let welcome = chat["welcomes"][0].as_str().unwrap().to_string();
        let out =
            std::env::temp_dir().join(format!("{}.enc", Keys::generate().public_key().to_hex()));
        let up: Value = serde_json::from_str(
            &marmot_encrypt_media(
                gid.clone(),
                b"voice bytes".to_vec(),
                "audio/mp4".into(),
                "v.m4a".into(),
                out.to_string_lossy().to_string(),
            )
            .unwrap(),
        )
        .unwrap();
        let mut imeta = vec!["url https://media.example.com/a".to_string()];
        imeta.extend(
            up["imeta"]
                .as_array()
                .unwrap()
                .iter()
                .map(|v| v.as_str().unwrap().to_string()),
        );
        let mut tag = vec!["imeta".to_string()];
        tag.extend(imeta.iter().cloned());
        let sent: Value = serde_json::from_str(
            &marmot_send_message(
                gid.clone(),
                9,
                String::new(),
                serde_json::to_string(&vec![tag]).unwrap(),
            )
            .unwrap(),
        )
        .unwrap();
        let enc = std::fs::read(&out).unwrap();

        marmot_open(bob_dir, bob.secret_key().to_secret_hex()).unwrap();
        assert_eq!(process(welcome)["type"], "welcome");
        process(sent["event"].as_str().unwrap().to_string());
        marmot_self_update(gid.clone()).unwrap();
        marmot_merge_pending_commit(gid.clone()).unwrap();
        let plain = marmot_decrypt_media(gid, imeta, enc).unwrap();
        assert_eq!(plain, b"voice bytes".to_vec());
        marmot_close();
    }

    #[test]
    fn two_users_exchange_messages() {
        let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        let relays = vec!["wss://relay.example.com".to_string()];
        let alice = Keys::generate();
        let bob = Keys::generate();
        let alice_dir = temp_dir("alice");
        let bob_dir = temp_dir("bob");

        marmot_open(bob_dir.clone(), bob.secret_key().to_secret_hex()).unwrap();
        let key_package = marmot_key_package_event(relays.clone()).unwrap();
        let again = marmot_key_package_event(relays.clone()).unwrap();
        let slot = |raw: &str| {
            Event::from_json(raw)
                .unwrap()
                .tags
                .identifier()
                .map(|s| s.to_string())
        };
        assert_eq!(slot(&key_package), slot(&again));

        marmot_open(alice_dir.clone(), alice.secret_key().to_secret_hex()).unwrap();
        let events =
            serde_json::to_string(&vec![serde_json::from_str::<Value>(&key_package).unwrap()])
                .unwrap();
        let picked = marmot_pick_key_package(events, bob.public_key().to_hex())
            .unwrap()
            .unwrap();
        let chat: Value =
            serde_json::from_str(&marmot_create_chat(picked, relays.clone()).unwrap()).unwrap();
        let group_id = chat["group"]["id"].as_str().unwrap().to_string();
        let welcome = chat["welcomes"][0].as_str().unwrap().to_string();
        let sent: Value = serde_json::from_str(
            &marmot_send_message(group_id.clone(), 9, "hi bob".into(), "[]".into()).unwrap(),
        )
        .unwrap();
        assert_eq!(sent["message"]["content"], "hi bob");
        let outer = sent["event"].as_str().unwrap().to_string();

        let media = b"plain text attachment".to_vec();
        let output =
            std::env::temp_dir().join(format!("{}.enc", Keys::generate().public_key().to_hex()));
        let upload: Value = serde_json::from_str(
            &marmot_encrypt_media(
                group_id.clone(),
                media.clone(),
                "text/plain".into(),
                "note.txt".into(),
                output.to_string_lossy().to_string(),
            )
            .unwrap(),
        )
        .unwrap();
        let mut imeta = vec![
            "imeta".to_string(),
            "url https://blossom.example.com/x".to_string(),
        ];
        imeta.extend(
            upload["imeta"]
                .as_array()
                .unwrap()
                .iter()
                .map(|v| v.as_str().unwrap().to_string()),
        );
        let media_event: Value = serde_json::from_str(
            &marmot_send_message(
                group_id.clone(),
                9,
                String::new(),
                serde_json::to_string(&vec![imeta.clone()]).unwrap(),
            )
            .unwrap(),
        )
        .unwrap();
        let encrypted = std::fs::read(&output).unwrap();

        marmot_open(bob_dir.clone(), bob.secret_key().to_secret_hex()).unwrap();
        let runtime = tokio::runtime::Builder::new_current_thread()
            .build()
            .unwrap();
        let joined: Value = serde_json::from_str(
            &runtime
                .block_on(async { marmot_process_event(welcome) })
                .unwrap(),
        )
        .unwrap();
        assert_eq!(joined["type"], "welcome");
        assert_eq!(joined["groupId"], group_id.as_str());
        let received: Value = serde_json::from_str(&marmot_process_event(outer).unwrap()).unwrap();
        assert_eq!(received["type"], "message");
        assert_eq!(received["message"]["content"], "hi bob");
        assert_eq!(received["message"]["pubkey"], alice.public_key().to_hex());
        let media_received: Value = serde_json::from_str(
            &marmot_process_event(media_event["event"].as_str().unwrap().to_string()).unwrap(),
        )
        .unwrap();
        assert_eq!(media_received["type"], "message");
        let decrypted =
            marmot_decrypt_media(group_id.clone(), imeta[1..].to_vec(), encrypted).unwrap();
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
        let reply_event = reply["event"].as_str().unwrap().to_string();
        let reply_id = Event::from_json(&reply_event).unwrap().id.to_hex();
        let early = marmot_process_event(reply_event.clone())
            .ok()
            .and_then(|raw| serde_json::from_str::<Value>(&raw).ok())
            .unwrap_or(Value::Null);
        assert_ne!(early["type"], "message");
        let processed: Value =
            serde_json::from_str(&marmot_process_event(commit).unwrap()).unwrap();
        assert_eq!(processed["type"], "commit");
        assert!(processed["retry"]
            .as_array()
            .unwrap()
            .iter()
            .any(|id| id == &Value::String(reply_id.clone())));
        let reply_received: Value =
            serde_json::from_str(&marmot_process_event(reply_event).unwrap()).unwrap();
        assert_eq!(reply_received["message"]["content"], "hi alice");
        let history: Value =
            serde_json::from_str(&marmot_messages(group_id.clone(), 50).unwrap()).unwrap();
        assert_eq!(history.as_array().unwrap().len(), 3);
        let older: Value =
            serde_json::from_str(&marmot_messages_page(group_id, 2, 2).unwrap()).unwrap();
        assert_eq!(older.as_array().unwrap().len(), 1);
        marmot_close();
    }
}
