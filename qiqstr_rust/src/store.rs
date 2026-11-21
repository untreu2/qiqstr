use std::cmp::Reverse;
use std::collections::{BTreeMap, HashMap, HashSet, VecDeque};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Mutex, RwLock};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, Result};
use nostr::prelude::*;
use rusqlite::{params, Connection, ErrorCode, OptionalExtension, ToSql};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SaveStatus {
    Success,
    Duplicate,
    Replaced,
    Deleted,
    Expired,
    Ephemeral,
}

#[derive(Debug, Clone)]
pub struct InteractionRow {
    pub target_id: EventId,
    pub event_id: EventId,
    pub kind: u16,
    pub author: PublicKey,
}

pub fn is_persistent_kind(kind: Kind) -> bool {
    matches!(
        kind,
        Kind::Metadata
            | Kind::ContactList
            | Kind::EventDeletion
            | Kind::MuteList
            | Kind::RelayList
            | Kind::TextNote
            | Kind::Repost
    ) || matches!(
        kind.as_u16(),
        7        // Reaction
            | 1059   // Gift wrap (NIP-17 DM)
            | 9735   // Zap receipt
            | 10001  // Pinned notes
            | 10003  // Bookmarks
            | 30000  // Follow sets / categorized people
            | 30001  // Categorized lists (legacy bookmarks)
            | 30023 // Long-form article
    )
}

#[inline]
fn is_regular_replaceable(kind: u16) -> bool {
    kind == 0 || kind == 3 || (10_000..20_000).contains(&kind)
}

#[inline]
fn is_addressable(kind: u16) -> bool {
    (30_000..40_000).contains(&kind)
}

#[inline]
fn is_ephemeral_protocol_kind(kind: u16) -> bool {
    (20_000..30_000).contains(&kind)
}

fn replaceable_d_tag(event: &Event) -> Option<String> {
    let k = event.kind.as_u16();
    if is_regular_replaceable(k) {
        Some(String::new())
    } else if is_addressable(k) {
        let d = event
            .tags
            .iter()
            .find_map(|tag| {
                let s = tag.as_slice();
                (s.len() >= 2 && s[0] == "d").then(|| s[1].clone())
            })
            .unwrap_or_default();
        Some(d)
    } else {
        None
    }
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn expiration_of(event: &Event) -> Option<u64> {
    event.tags.iter().find_map(|tag| {
        let s = tag.as_slice();
        (s.len() >= 2 && s[0] == "expiration")
            .then(|| s[1].trim().parse::<u64>().ok())
            .flatten()
    })
}

#[inline]
fn is_expired_at(event: &Event, now: u64) -> bool {
    expiration_of(event).is_some_and(|at| at < now)
}

fn parse_coordinate(value: &str) -> Option<(u16, PublicKey, String)> {
    let mut parts = value.splitn(3, ':');
    let kind = parts.next()?.parse::<u16>().ok()?;
    let pubkey = PublicKey::from_hex(parts.next()?).ok()?;
    let d_tag = parts.next().unwrap_or("").to_string();
    if is_regular_replaceable(kind) {
        Some((kind, pubkey, String::new()))
    } else if is_addressable(kind) {
        Some((kind, pubkey, d_tag))
    } else {
        None
    }
}

const METADATA_TEXT_FIELDS: [&str; 9] = [
    "name",
    "display_name",
    "about",
    "website",
    "picture",
    "banner",
    "nip05",
    "lud06",
    "lud16",
];

/// Reads a kind-0 content even when some fields have the wrong type, so a profile that exists
/// is never mistaken for one that still has to be fetched.
pub(crate) fn parse_metadata_lenient(content: &str) -> Metadata {
    if let Ok(metadata) = Metadata::from_json(content) {
        return metadata;
    }
    let Ok(serde_json::Value::Object(fields)) = serde_json::from_str::<serde_json::Value>(content)
    else {
        return Metadata::default();
    };
    let usable: serde_json::Map<String, serde_json::Value> = fields
        .into_iter()
        .filter(|(key, value)| {
            !METADATA_TEXT_FIELDS.contains(&key.as_str()) || value.is_string() || value.is_null()
        })
        .collect();
    serde_json::from_value(serde_json::Value::Object(usable)).unwrap_or_default()
}

fn extract_interaction_target(event: &Event) -> Option<EventId> {
    match event.kind {
        Kind::Reaction | Kind::Repost | Kind::ZapReceipt => {
            for tag in event.tags.iter() {
                let s = tag.as_slice();
                if s.len() >= 2 && s[0] == "e" && !s[1].is_empty() {
                    return EventId::from_hex(&s[1]).ok();
                }
            }
            None
        }
        Kind::TextNote => {
            let mut reply_marker: Option<&str> = None;
            let mut root_marker: Option<&str> = None;
            let mut last_positional: Option<&str> = None;
            for tag in event.tags.iter() {
                let s = tag.as_slice();
                if s.len() < 2 || s[0] != "e" || s[1].is_empty() {
                    continue;
                }
                match s.get(3).map(String::as_str).unwrap_or("") {
                    "reply" => reply_marker = Some(s[1].as_str()),
                    "root" => root_marker = Some(s[1].as_str()),
                    "mention" => {}
                    _ => last_positional = Some(s[1].as_str()),
                }
            }
            reply_marker
                .or(root_marker)
                .or(last_positional)
                .and_then(|hex| EventId::from_hex(hex).ok())
        }
        _ => None,
    }
}

fn filter_kinds_all_persistent(filter: &Filter) -> bool {
    match &filter.kinds {
        Some(kinds) if !kinds.is_empty() => kinds.iter().all(|k| is_persistent_kind(*k)),
        _ => false,
    }
}

fn filter_kinds_all_ephemeral(filter: &Filter) -> bool {
    match &filter.kinds {
        Some(kinds) if !kinds.is_empty() => kinds.iter().all(|k| !is_persistent_kind(*k)),
        _ => false,
    }
}

fn filter_is_selective(filter: &Filter) -> bool {
    let has_empty_list = filter.ids.as_ref().is_some_and(|ids| ids.is_empty())
        || filter.authors.as_ref().is_some_and(|a| a.is_empty())
        || filter.kinds.as_ref().is_some_and(|kinds| kinds.is_empty())
        || filter.generic_tags.values().any(|values| values.is_empty());
    let has_condition = filter.ids.is_some()
        || filter.authors.is_some()
        || filter.kinds.is_some()
        || filter.since.is_some()
        || filter.until.is_some()
        || filter.search.as_ref().is_some_and(|s| !s.is_empty())
        || !filter.generic_tags.is_empty();
    has_condition && !has_empty_list
}

fn parse_contacts_from_event(event: &Event) -> Vec<PublicKey> {
    let mut seen = HashSet::new();
    let mut out = Vec::new();
    for tag in event.tags.iter() {
        let s = tag.as_slice();
        if s.len() >= 2 && s[0] == "p" {
            if let Ok(pk) = PublicKey::from_hex(&s[1]) {
                if seen.insert(pk) {
                    out.push(pk);
                }
            }
        }
    }
    out
}

const EPHEMERAL_MAX: usize = 50_000;
const EVENT_CACHE_MAX: usize = 4_096;
const PROFILE_CACHE_MAX: usize = 4_096;
const CONTACT_CACHE_MAX: usize = 1_024;
const ORDER_SLACK: usize = 64;

fn compact_order<T>(order: &mut VecDeque<EventId>, live: &HashMap<EventId, T>) {
    if order.len() > live.len() * 2 + ORDER_SLACK {
        order.retain(|id| live.contains_key(id));
    }
}

struct EphemeralStore {
    events: HashMap<EventId, Event>,
    order: VecDeque<EventId>,
    replaceables: HashMap<(PublicKey, u16, String), EventId>,
}

impl EphemeralStore {
    fn new() -> Self {
        Self {
            events: HashMap::new(),
            order: VecDeque::new(),
            replaceables: HashMap::new(),
        }
    }

    fn compact(&mut self) {
        compact_order(&mut self.order, &self.events);
    }

    fn remove(&mut self, id: &EventId) -> Option<Event> {
        let old = self.events.remove(id)?;
        if let Some(d) = replaceable_d_tag(&old) {
            let key = (old.pubkey, old.kind.as_u16(), d);
            if self.replaceables.get(&key) == Some(id) {
                self.replaceables.remove(&key);
            }
        }
        Some(old)
    }

    fn save(&mut self, event: &Event) -> SaveStatus {
        let k = event.kind.as_u16();
        if is_ephemeral_protocol_kind(k) {
            return SaveStatus::Ephemeral;
        }
        if self.events.contains_key(&event.id) {
            return SaveStatus::Duplicate;
        }
        if let Some(d_tag) = replaceable_d_tag(event) {
            let key = (event.pubkey, k, d_tag);
            if let Some(&old_id) = self.replaceables.get(&key) {
                if let Some(old) = self.events.get(&old_id) {
                    let new_wins = event.created_at > old.created_at
                        || (event.created_at == old.created_at && event.id < old.id);
                    if !new_wins {
                        return SaveStatus::Replaced;
                    }
                    self.events.remove(&old_id);
                }
            }
            self.replaceables.insert(key, event.id);
        }
        if self.events.len() >= EPHEMERAL_MAX {
            let drain = EPHEMERAL_MAX / 4;
            for _ in 0..drain {
                if let Some(old_id) = self.order.pop_front() {
                    self.remove(&old_id);
                }
            }
        }
        self.events.insert(event.id, event.clone());
        self.order.push_back(event.id);
        compact_order(&mut self.order, &self.events);
        SaveStatus::Success
    }

    fn delete_by_id(&mut self, id: &EventId, pubkey: &PublicKey) -> bool {
        match self.events.get(id) {
            Some(event) if event.pubkey == *pubkey && event.kind != Kind::EventDeletion => {
                self.remove(id);
                compact_order(&mut self.order, &self.events);
                true
            }
            _ => false,
        }
    }

    fn delete_coordinate(&mut self, pubkey: &PublicKey, kind: u16, d_tag: &str, at: u64) -> bool {
        let key = (*pubkey, kind, d_tag.to_string());
        let Some(&id) = self.replaceables.get(&key) else {
            return false;
        };
        match self.events.get(&id) {
            Some(event) if event.created_at.as_secs() <= at => {
                self.remove(&id);
                compact_order(&mut self.order, &self.events);
                true
            }
            _ => false,
        }
    }

    fn delete(&mut self, filter: &Filter) -> usize {
        let opts = MatchEventOptions::new();
        let to_remove: Vec<EventId> = self
            .events
            .values()
            .filter(|e| filter.match_event(e, opts))
            .map(|e| e.id)
            .collect();
        let count = to_remove.len();
        for id in to_remove {
            self.remove(&id);
        }
        compact_order(&mut self.order, &self.events);
        count
    }

    fn query(&self, filter: &Filter) -> Vec<Event> {
        let opts = MatchEventOptions::new();
        let mut matched: Vec<Event> = self
            .events
            .values()
            .filter(|e| filter.match_event(e, opts))
            .cloned()
            .collect();
        matched.sort_by(|a, b| {
            b.created_at
                .cmp(&a.created_at)
                .then_with(|| a.id.cmp(&b.id))
        });
        if let Some(limit) = filter.limit {
            matched.truncate(limit);
        }
        matched
    }

    fn count(&self, filter: &Filter) -> usize {
        let opts = MatchEventOptions::new();
        let c = self
            .events
            .values()
            .filter(|e| filter.match_event(e, opts))
            .count();
        match filter.limit {
            Some(limit) => c.min(limit),
            None => c,
        }
    }

    fn wipe(&mut self) {
        self.events.clear();
        self.order.clear();
        self.replaceables.clear();
    }
}

/// A change made to the database, replayed on the in-memory caches in the order it happened.
enum Effect<'a> {
    Inserted(&'a Event),
    Removed {
        id: EventId,
        kind: u16,
        pubkey: PublicKey,
        by_request: bool,
    },
    DeletedId {
        id: EventId,
        pubkey: PublicKey,
    },
    DeletedCoordinate {
        pubkey: PublicKey,
        kind: u16,
        d_tag: String,
        at: u64,
    },
}

struct HotCache {
    event_cache: HashMap<EventId, Event>,
    event_order: VecDeque<EventId>,
    profiles: HashMap<PublicKey, (u64, Metadata)>,
    contacts: HashMap<PublicKey, (u64, Vec<PublicKey>)>,
    kind_counts: HashMap<u16, usize>,
    total_persistent: usize,
    ephemeral: EphemeralStore,
}

impl HotCache {
    fn new() -> Self {
        Self {
            event_cache: HashMap::with_capacity(512),
            event_order: VecDeque::with_capacity(512),
            profiles: HashMap::with_capacity(256),
            contacts: HashMap::with_capacity(128),
            kind_counts: HashMap::new(),
            total_persistent: 0,
            ephemeral: EphemeralStore::new(),
        }
    }

    fn cache_event(&mut self, event: Event) {
        let id = event.id;
        if self.event_cache.contains_key(&id) {
            return;
        }
        if self.event_cache.len() >= EVENT_CACHE_MAX {
            let drain = EVENT_CACHE_MAX / 4;
            for _ in 0..drain {
                if let Some(old) = self.event_order.pop_front() {
                    self.event_cache.remove(&old);
                }
            }
        }
        self.event_order.push_back(id);
        self.event_cache.insert(id, event);
        compact_order(&mut self.event_order, &self.event_cache);
    }

    fn cache_profile(&mut self, pubkey: PublicKey, created_at: u64, metadata: Metadata) {
        if self.profiles.len() >= PROFILE_CACHE_MAX && !self.profiles.contains_key(&pubkey) {
            self.profiles.clear();
        }
        self.profiles.insert(pubkey, (created_at, metadata));
    }

    fn cache_contacts(&mut self, pubkey: PublicKey, created_at: u64, contacts: Vec<PublicKey>) {
        if self.contacts.len() >= CONTACT_CACHE_MAX && !self.contacts.contains_key(&pubkey) {
            self.contacts.clear();
        }
        self.contacts.insert(pubkey, (created_at, contacts));
    }

    fn note_persistent_insert(&mut self, event: &Event) {
        let k = event.kind.as_u16();
        *self.kind_counts.entry(k).or_insert(0) += 1;
        self.total_persistent += 1;
        self.cache_event(event.clone());

        if event.kind == Kind::Metadata {
            let ts = event.created_at.as_secs();
            let should_update = self
                .profiles
                .get(&event.pubkey)
                .is_none_or(|(old_ts, _)| ts >= *old_ts);
            if should_update {
                self.cache_profile(event.pubkey, ts, parse_metadata_lenient(&event.content));
            }
        } else if event.kind == Kind::ContactList {
            let ts = event.created_at.as_secs();
            let should_update = self
                .contacts
                .get(&event.pubkey)
                .is_none_or(|(old_ts, _)| ts >= *old_ts);
            if should_update {
                self.cache_contacts(event.pubkey, ts, parse_contacts_from_event(event));
            }
        }
    }

    fn note_persistent_delete(&mut self, id: &EventId, kind: u16, pubkey: &PublicKey) {
        self.event_cache.remove(id);
        compact_order(&mut self.event_order, &self.event_cache);
        if let Some(cnt) = self.kind_counts.get_mut(&kind) {
            *cnt = cnt.saturating_sub(1);
        }
        self.total_persistent = self.total_persistent.saturating_sub(1);
        if kind == 0 {
            self.profiles.remove(pubkey);
        } else if kind == 3 {
            self.contacts.remove(pubkey);
        }
    }

    /// Replays database changes in order and returns how many events a deletion request removed.
    fn apply(&mut self, effects: Vec<Effect<'_>>) -> usize {
        let mut removed_by_request = 0usize;
        for effect in effects {
            match effect {
                Effect::Inserted(event) => self.note_persistent_insert(event),
                Effect::Removed {
                    id,
                    kind,
                    pubkey,
                    by_request,
                } => {
                    self.note_persistent_delete(&id, kind, &pubkey);
                    if by_request {
                        removed_by_request += 1;
                    }
                }
                Effect::DeletedId { id, pubkey } => {
                    if self.ephemeral.delete_by_id(&id, &pubkey) {
                        removed_by_request += 1;
                    }
                }
                Effect::DeletedCoordinate {
                    pubkey,
                    kind,
                    d_tag,
                    at,
                } => {
                    if self.ephemeral.delete_coordinate(&pubkey, kind, &d_tag, at) {
                        removed_by_request += 1;
                    }
                }
            }
        }
        removed_by_request
    }

    fn clear_all(&mut self) {
        self.event_cache.clear();
        self.event_order.clear();
        self.profiles.clear();
        self.contacts.clear();
        self.kind_counts.clear();
        self.total_persistent = 0;
        self.ephemeral.wipe();
    }
}

pub struct EventStore {
    conn: Mutex<Connection>,
    hot: RwLock<HotCache>,
    dir_path: Option<PathBuf>,
    removed_by_request: AtomicUsize,
    #[cfg(test)]
    pause_before_cache_fill: Mutex<Option<ReadPause>>,
}

/// Lets a test hold a reader between its database read and its cache fill.
#[cfg(test)]
struct ReadPause {
    reached: std::sync::mpsc::Sender<()>,
    resume: std::sync::mpsc::Receiver<()>,
}

const SCHEMA_VERSION: i64 = 2;
const DATABASE_FILES: [&str; 3] = ["events.sqlite", "events.sqlite-wal", "events.sqlite-shm"];
const LEGACY_LMDB_FILES: [&str; 2] = ["data.mdb", "lock.mdb"];

const SCHEMA_SQL: &str = "
CREATE TABLE IF NOT EXISTS events (
    seq INTEGER PRIMARY KEY,
    id BLOB NOT NULL UNIQUE,
    pubkey BLOB NOT NULL,
    kind INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    d_tag TEXT,
    content TEXT NOT NULL,
    raw_json TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_events_kind_time ON events(kind, created_at DESC, id ASC);
CREATE INDEX IF NOT EXISTS idx_events_author_kind_time ON events(pubkey, kind, created_at DESC, id ASC);
CREATE INDEX IF NOT EXISTS idx_events_time ON events(created_at DESC, id ASC);
CREATE INDEX IF NOT EXISTS idx_events_replaceable ON events(pubkey, kind, d_tag) WHERE d_tag IS NOT NULL;

CREATE TABLE IF NOT EXISTS event_tags (
    tag_name TEXT NOT NULL,
    tag_value TEXT NOT NULL,
    kind INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    event_seq INTEGER NOT NULL REFERENCES events(seq) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_tags_time ON event_tags(tag_name, tag_value, created_at DESC, event_seq);
CREATE INDEX IF NOT EXISTS idx_tags_lookup ON event_tags(tag_name, tag_value, kind, created_at DESC, event_seq);
CREATE INDEX IF NOT EXISTS idx_tags_seq ON event_tags(event_seq);

CREATE TABLE IF NOT EXISTS interactions (
    event_seq INTEGER PRIMARY KEY REFERENCES events(seq) ON DELETE CASCADE,
    target_id BLOB NOT NULL,
    event_id BLOB NOT NULL,
    kind INTEGER NOT NULL,
    author BLOB NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_interactions_target ON interactions(target_id);

CREATE TABLE IF NOT EXISTS deleted_ids (
    id BLOB NOT NULL,
    pubkey BLOB NOT NULL,
    PRIMARY KEY (id, pubkey)
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS deleted_coordinates (
    pubkey BLOB NOT NULL,
    kind INTEGER NOT NULL,
    d_tag TEXT NOT NULL,
    deleted_at INTEGER NOT NULL,
    PRIMARY KEY (pubkey, kind, d_tag)
) WITHOUT ROWID;
";

const REBUILD_TOMBSTONES_SQL: &str = "
ALTER TABLE deleted_ids RENAME TO deleted_ids_legacy;
CREATE TABLE deleted_ids (
    id BLOB NOT NULL,
    pubkey BLOB NOT NULL,
    PRIMARY KEY (id, pubkey)
) WITHOUT ROWID;
INSERT OR IGNORE INTO deleted_ids (id, pubkey) SELECT id, pubkey FROM deleted_ids_legacy;
DROP TABLE deleted_ids_legacy;
";

fn configure_connection(conn: &Connection, persistent: bool) -> Result<()> {
    if persistent {
        conn.pragma_update(None, "journal_mode", "WAL")?;
        conn.pragma_update(None, "synchronous", "NORMAL")?;
        conn.pragma_update(None, "mmap_size", 67_108_864i64)?;
    }
    conn.pragma_update(None, "foreign_keys", "ON")?;
    conn.pragma_update(None, "temp_store", "MEMORY")?;
    conn.pragma_update(None, "cache_size", -16_384i64)?;
    conn.pragma_update(None, "busy_timeout", 5_000i64)?;
    Ok(())
}

fn migrate_schema(conn: &mut Connection) -> Result<()> {
    let version: i64 = conn.query_row("PRAGMA user_version", [], |row| row.get(0))?;
    if version >= SCHEMA_VERSION {
        return Ok(());
    }
    let tx = conn.transaction()?;
    let tombstone_key_columns: i64 = tx.query_row(
        "SELECT COUNT(*) FROM pragma_table_info('deleted_ids') WHERE pk > 0",
        [],
        |row| row.get(0),
    )?;
    if tombstone_key_columns == 1 {
        tx.execute_batch(REBUILD_TOMBSTONES_SQL)?;
    }
    tx.execute_batch(SCHEMA_SQL)?;
    {
        let mut unindexed = tx.prepare(
            "SELECT seq, kind, created_at, raw_json FROM events
             WHERE d_tag = '' AND kind >= 30000 AND kind < 40000
               AND NOT EXISTS (SELECT 1 FROM event_tags t
                               WHERE t.event_seq = events.seq AND t.tag_name = 'd' AND t.tag_value = '')",
        )?;
        let rows: Vec<(i64, i64, i64, String)> = unindexed
            .query_map([], |row| {
                Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
            })?
            .filter_map(|row| row.ok())
            .collect();
        let mut index_tag = tx.prepare(
            "INSERT INTO event_tags (tag_name, tag_value, kind, created_at, event_seq) VALUES ('d', '', ?1, ?2, ?3)",
        )?;
        for (seq, kind, created_at, raw_json) in rows {
            let has_empty_identifier = Event::from_json(&raw_json).is_ok_and(|event| {
                event.tags.iter().any(|tag| {
                    let s = tag.as_slice();
                    s.len() >= 2 && s[0] == "d" && s[1].is_empty()
                })
            });
            if has_empty_identifier {
                index_tag.execute(params![kind, created_at, seq])?;
            }
        }
    }
    {
        let requests: Vec<Event> = {
            let mut stored = tx.prepare("SELECT raw_json FROM events WHERE kind = 5")?;
            let rows = stored.query_map([], |row| row.get::<_, String>(0))?;
            rows.flatten()
                .filter_map(|json| Event::from_json(&json).ok())
                .collect()
        };
        let mut effects = Vec::new();
        for request in &requests {
            apply_deletion_request(&tx, request, &mut effects)?;
        }
    }
    tx.pragma_update(None, "user_version", SCHEMA_VERSION)?;
    tx.commit()?;
    Ok(())
}

fn is_corruption(error: &anyhow::Error) -> bool {
    matches!(
        error.downcast_ref::<rusqlite::Error>(),
        Some(rusqlite::Error::SqliteFailure(failure, _))
            if matches!(failure.code, ErrorCode::DatabaseCorrupt | ErrorCode::NotADatabase)
    )
}

fn open_connection(db_file: &Path) -> Result<(Connection, Vec<(u16, usize)>)> {
    let mut conn = Connection::open(db_file)?;
    configure_connection(&conn, true)?;
    migrate_schema(&mut conn)?;
    let counts = {
        let mut stmt = conn.prepare("SELECT kind, COUNT(*) FROM events GROUP BY kind")?;
        let rows = stmt.query_map([], |row| {
            Ok((row.get::<_, u16>(0)?, row.get::<_, usize>(1)?))
        })?;
        rows.collect::<rusqlite::Result<Vec<_>>>()?
    };
    Ok((conn, counts))
}

fn is_tombstoned(conn: &Connection, event: &Event) -> Result<bool> {
    if event.kind == Kind::EventDeletion {
        return Ok(false);
    }
    let pubkey = event.pubkey.as_bytes().as_slice();
    let mut by_id =
        conn.prepare_cached("SELECT 1 FROM deleted_ids WHERE id = ?1 AND pubkey = ?2 LIMIT 1")?;
    if by_id
        .query_row(params![event.id.as_bytes().as_slice(), pubkey], |_| Ok(()))
        .optional()?
        .is_some()
    {
        return Ok(true);
    }
    let Some(d_tag) = replaceable_d_tag(event) else {
        return Ok(false);
    };
    let mut by_coordinate = conn.prepare_cached(
        "SELECT deleted_at FROM deleted_coordinates WHERE pubkey = ?1 AND kind = ?2 AND d_tag = ?3",
    )?;
    let deleted_at: Option<i64> = by_coordinate
        .query_row(params![pubkey, event.kind.as_u16(), d_tag], |row| {
            row.get(0)
        })
        .optional()?;
    Ok(deleted_at.is_some_and(|at| at >= event.created_at.as_secs() as i64))
}

/// Applies the `e` and `a` targets of a NIP-09 deletion request signed by `event.pubkey`.
fn apply_deletion_request<'a>(
    tx: &Connection,
    event: &Event,
    effects: &mut Vec<Effect<'a>>,
) -> Result<()> {
    let author = event.pubkey.as_bytes().as_slice();
    let requested_at = event.created_at.as_secs();
    let mut add_id_tombstone =
        tx.prepare_cached("INSERT OR IGNORE INTO deleted_ids (id, pubkey) VALUES (?1, ?2)")?;
    let mut find_by_id =
        tx.prepare_cached("SELECT seq, kind FROM events WHERE id = ?1 AND pubkey = ?2 LIMIT 1")?;
    let mut add_coordinate_tombstone = tx.prepare_cached(
        "INSERT INTO deleted_coordinates (pubkey, kind, d_tag, deleted_at) VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT (pubkey, kind, d_tag) DO UPDATE SET deleted_at = MAX(deleted_at, excluded.deleted_at)",
    )?;
    let mut find_by_coordinate = tx.prepare_cached(
        "SELECT seq, id FROM events WHERE pubkey = ?1 AND kind = ?2 AND d_tag = ?3 AND created_at <= ?4",
    )?;
    let mut remove = tx.prepare_cached("DELETE FROM events WHERE seq = ?1")?;

    for tag in event.tags.iter() {
        let slice = tag.as_slice();
        if slice.len() < 2 {
            continue;
        }
        if slice[0] == "e" {
            let Ok(target) = EventId::from_hex(&slice[1]) else {
                continue;
            };
            let target_bytes = target.as_bytes().as_slice();
            add_id_tombstone.execute(params![target_bytes, author])?;
            let stored: Option<(i64, u16)> = find_by_id
                .query_row(params![target_bytes, author], |row| {
                    Ok((row.get(0)?, row.get(1)?))
                })
                .optional()?;
            if let Some((seq, kind)) = stored {
                if kind != Kind::EventDeletion.as_u16() {
                    remove.execute([seq])?;
                    effects.push(Effect::Removed {
                        id: target,
                        kind,
                        pubkey: event.pubkey,
                        by_request: true,
                    });
                }
            }
            effects.push(Effect::DeletedId {
                id: target,
                pubkey: event.pubkey,
            });
        } else if slice[0] == "a" {
            let Some((kind, owner, d_tag)) = parse_coordinate(&slice[1]) else {
                continue;
            };
            if owner != event.pubkey {
                continue;
            }
            add_coordinate_tombstone.execute(params![author, kind, d_tag, requested_at as i64])?;
            let stored: Vec<(i64, Vec<u8>)> = find_by_coordinate
                .query_map(params![author, kind, d_tag, requested_at as i64], |row| {
                    Ok((row.get(0)?, row.get(1)?))
                })?
                .filter_map(|row| row.ok())
                .collect();
            for (seq, id_bytes) in stored {
                remove.execute([seq])?;
                if let Ok(id) = EventId::from_slice(&id_bytes) {
                    effects.push(Effect::Removed {
                        id,
                        kind,
                        pubkey: event.pubkey,
                        by_request: true,
                    });
                }
            }
            effects.push(Effect::DeletedCoordinate {
                pubkey: event.pubkey,
                kind,
                d_tag,
                at: requested_at,
            });
        }
    }
    Ok(())
}

impl EventStore {
    fn from_parts(conn: Connection, hot: HotCache, dir_path: Option<PathBuf>) -> Self {
        Self {
            conn: Mutex::new(conn),
            hot: RwLock::new(hot),
            dir_path,
            removed_by_request: AtomicUsize::new(0),
            #[cfg(test)]
            pause_before_cache_fill: Mutex::new(None),
        }
    }

    #[cfg(test)]
    fn pause_if_a_test_asked(&self) {
        let pause = self.pause_before_cache_fill.lock().unwrap().take();
        if let Some(pause) = pause {
            let _ = pause.reached.send(());
            let _ = pause.resume.recv();
        }
    }

    pub fn open_in_memory() -> Result<Self> {
        let mut conn = Connection::open_in_memory()?;
        configure_connection(&conn, false)?;
        migrate_schema(&mut conn)?;
        Ok(Self::from_parts(conn, HotCache::new(), None))
    }

    pub fn open(dir: &Path) -> Result<Self> {
        std::fs::create_dir_all(dir)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = std::fs::set_permissions(dir, std::fs::Permissions::from_mode(0o700));
        }
        let db_file = dir.join(DATABASE_FILES[0]);
        let (conn, counts) = match open_connection(&db_file) {
            Ok(opened) => opened,
            Err(error) if is_corruption(&error) => {
                for name in DATABASE_FILES {
                    let _ = std::fs::remove_file(dir.join(name));
                }
                open_connection(&db_file)?
            }
            Err(error) => return Err(error),
        };
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            for name in DATABASE_FILES {
                let p = dir.join(name);
                if p.exists() {
                    let _ = std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o600));
                }
            }
        }
        for name in LEGACY_LMDB_FILES {
            let _ = std::fs::remove_file(dir.join(name));
        }

        let mut hot = HotCache::new();
        for (kind, count) in counts {
            hot.kind_counts.insert(kind, count);
            hot.total_persistent += count;
        }
        Ok(Self::from_parts(conn, hot, Some(dir.to_path_buf())))
    }

    pub fn database_size_in(dir: &Path) -> u64 {
        DATABASE_FILES
            .iter()
            .filter_map(|name| std::fs::metadata(dir.join(name)).ok())
            .map(|meta| meta.len())
            .sum()
    }

    pub fn database_size_bytes(&self) -> u64 {
        self.dir_path
            .as_deref()
            .map(Self::database_size_in)
            .unwrap_or(0)
    }

    fn insert_persistent_in_tx<'a>(
        tx: &Connection,
        event: &'a Event,
        now: u64,
        effects: &mut Vec<Effect<'a>>,
    ) -> Result<SaveStatus> {
        let k = event.kind.as_u16();
        if is_ephemeral_protocol_kind(k) {
            return Ok(SaveStatus::Ephemeral);
        }
        if is_expired_at(event, now) {
            return Ok(SaveStatus::Expired);
        }

        let id_bytes = event.id.as_bytes().as_slice();
        let pk_bytes = event.pubkey.as_bytes().as_slice();
        let created_at = event.created_at.as_secs() as i64;

        {
            let mut stmt = tx.prepare_cached("SELECT 1 FROM events WHERE id = ?1 LIMIT 1")?;
            if stmt.query_row([id_bytes], |_| Ok(())).optional()?.is_some() {
                return Ok(SaveStatus::Duplicate);
            }
        }

        if is_tombstoned(tx, event)? {
            return Ok(SaveStatus::Deleted);
        }

        let d_tag = replaceable_d_tag(event);
        if let Some(ref d) = d_tag {
            let mut stmt = tx.prepare_cached(
                "SELECT seq, id, created_at FROM events WHERE pubkey = ?1 AND kind = ?2 AND d_tag = ?3",
            )?;
            let existing: Vec<(i64, Vec<u8>, i64)> = stmt
                .query_map(params![pk_bytes, k, d], |row| {
                    Ok((row.get(0)?, row.get(1)?, row.get(2)?))
                })?
                .filter_map(|r| r.ok())
                .collect();

            for &(_, ref old_id_bytes, old_created) in &existing {
                let new_wins = created_at > old_created
                    || (created_at == old_created && id_bytes < old_id_bytes.as_slice());
                if !new_wins {
                    return Ok(SaveStatus::Replaced);
                }
            }

            if !existing.is_empty() {
                let mut del_stmt = tx.prepare_cached("DELETE FROM events WHERE seq = ?1")?;
                for (seq, old_id_bytes, _) in existing {
                    del_stmt.execute([seq])?;
                    if let Ok(old_eid) = EventId::from_slice(&old_id_bytes) {
                        effects.push(Effect::Removed {
                            id: old_eid,
                            kind: k,
                            pubkey: event.pubkey,
                            by_request: false,
                        });
                    }
                }
            }
        }

        let raw_json = event.as_json();
        {
            let mut stmt = tx.prepare_cached(
                "INSERT INTO events (id, pubkey, kind, created_at, d_tag, content, raw_json) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            )?;
            stmt.execute(params![
                id_bytes,
                pk_bytes,
                k,
                created_at,
                d_tag.as_deref(),
                event.content.as_str(),
                raw_json.as_str(),
            ])?;
        }
        let seq = tx.last_insert_rowid();

        let mut seen_tags: HashSet<(&str, &str)> = HashSet::new();
        {
            let mut tag_stmt = tx.prepare_cached(
                "INSERT INTO event_tags (tag_name, tag_value, kind, created_at, event_seq) VALUES (?1, ?2, ?3, ?4, ?5)",
            )?;
            for tag in event.tags.iter() {
                let slice = tag.as_slice();
                if slice.len() >= 2 {
                    let name = slice[0].as_str();
                    let val = slice[1].as_str();
                    if name.len() == 1
                        && name.as_bytes()[0].is_ascii_alphabetic()
                        && (!val.is_empty() || name == "d")
                        && seen_tags.insert((name, val))
                    {
                        tag_stmt.execute(params![name, val, k, created_at, seq])?;
                    }
                }
            }
        }

        if let Some(target_id) = extract_interaction_target(event) {
            let mut int_stmt = tx.prepare_cached(
                "INSERT OR IGNORE INTO interactions (event_seq, target_id, event_id, kind, author) VALUES (?1, ?2, ?3, ?4, ?5)",
            )?;
            int_stmt.execute(params![
                seq,
                target_id.as_bytes().as_slice(),
                id_bytes,
                k,
                pk_bytes,
            ])?;
        }

        effects.push(Effect::Inserted(event));
        if event.kind == Kind::EventDeletion {
            apply_deletion_request(tx, event, effects)?;
        }

        Ok(SaveStatus::Success)
    }

    fn apply_effects(&self, hot: &mut HotCache, effects: Vec<Effect<'_>>) {
        let removed = hot.apply(effects);
        if removed > 0 {
            self.removed_by_request
                .fetch_add(removed, Ordering::Relaxed);
        }
    }

    pub fn save_event(&self, event: &Event) -> Result<SaveStatus> {
        let now = now_secs();
        let mut conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;

        if !is_persistent_kind(event.kind) {
            if is_ephemeral_protocol_kind(event.kind.as_u16()) {
                return Ok(SaveStatus::Ephemeral);
            }
            if is_expired_at(event, now) {
                return Ok(SaveStatus::Expired);
            }
            if is_tombstoned(&conn, event)? {
                return Ok(SaveStatus::Deleted);
            }
            let mut hot = self
                .hot
                .write()
                .map_err(|_| anyhow!("store lock poisoned"))?;
            return Ok(hot.ephemeral.save(event));
        }

        let tx = conn.transaction()?;
        let mut effects = Vec::new();
        let status = Self::insert_persistent_in_tx(&tx, event, now, &mut effects)?;
        if status != SaveStatus::Success {
            return Ok(status);
        }
        tx.commit()?;
        let mut hot = self
            .hot
            .write()
            .map_err(|_| anyhow!("store lock poisoned"))?;
        self.apply_effects(&mut hot, effects);
        Ok(status)
    }

    /// Saves a batch in one transaction and returns the number of newly stored events.
    pub fn save_events(&self, events: &[Event]) -> Result<usize> {
        if events.is_empty() {
            return Ok(0);
        }
        let now = now_secs();
        let mut conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
        let mut effects: Vec<Effect<'_>> = Vec::new();
        let mut saved_count = 0usize;

        if events.iter().any(|ev| is_persistent_kind(ev.kind)) {
            let tx = conn.transaction()?;
            for ev in events.iter().filter(|ev| is_persistent_kind(ev.kind)) {
                if Self::insert_persistent_in_tx(&tx, ev, now, &mut effects)? == SaveStatus::Success
                {
                    saved_count += 1;
                }
            }
            tx.commit()?;
        }

        let mut in_memory: Vec<&Event> = Vec::new();
        for ev in events.iter().filter(|ev| !is_persistent_kind(ev.kind)) {
            if !is_ephemeral_protocol_kind(ev.kind.as_u16())
                && !is_expired_at(ev, now)
                && !is_tombstoned(&conn, ev)?
            {
                in_memory.push(ev);
            }
        }
        if effects.is_empty() && in_memory.is_empty() {
            return Ok(saved_count);
        }

        let mut hot = self
            .hot
            .write()
            .map_err(|_| anyhow!("store lock poisoned"))?;
        self.apply_effects(&mut hot, effects);
        for ev in in_memory {
            if hot.ephemeral.save(ev) == SaveStatus::Success {
                saved_count += 1;
            }
        }
        Ok(saved_count)
    }

    /// Reports how many events deletion requests have removed since the previous call. The
    /// requests themselves are applied as they are saved.
    pub fn take_removed_by_request(&self) -> usize {
        self.removed_by_request.swap(0, Ordering::AcqRel)
    }

    fn remove_ids(&self, ids: &[EventId]) -> Result<()> {
        if ids.is_empty() {
            return Ok(());
        }
        let mut conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
        let tx = conn.transaction()?;
        let mut removed: Vec<(EventId, u16, PublicKey)> = Vec::new();
        {
            let mut find = tx.prepare_cached("SELECT kind, pubkey FROM events WHERE id = ?1")?;
            let mut remove = tx.prepare_cached("DELETE FROM events WHERE id = ?1")?;
            for id in ids {
                let id_bytes = id.as_bytes().as_slice();
                let stored: Option<(u16, Vec<u8>)> = find
                    .query_row([id_bytes], |row| Ok((row.get(0)?, row.get(1)?)))
                    .optional()?;
                if let Some((kind, pubkey)) = stored {
                    remove.execute([id_bytes])?;
                    if let Ok(pubkey) = PublicKey::from_slice(&pubkey) {
                        removed.push((*id, kind, pubkey));
                    }
                }
            }
        }
        tx.commit()?;
        let mut hot = self
            .hot
            .write()
            .map_err(|_| anyhow!("store lock poisoned"))?;
        for (id, kind, pubkey) in removed {
            hot.note_persistent_delete(&id, kind, &pubkey);
        }
        for id in ids {
            hot.ephemeral.remove(id);
        }
        hot.ephemeral.compact();
        Ok(())
    }

    fn without_expired(&self, events: Vec<Event>, now: u64) -> Vec<Event> {
        if !events.iter().any(|event| is_expired_at(event, now)) {
            return events;
        }
        let (expired, live): (Vec<Event>, Vec<Event>) = events
            .into_iter()
            .partition(|event| is_expired_at(event, now));
        let ids: Vec<EventId> = expired.iter().map(|event| event.id).collect();
        let _ = self.remove_ids(&ids);
        live
    }

    fn stored_event(&self, id: &EventId) -> Result<Option<Event>> {
        {
            let hot = self
                .hot
                .read()
                .map_err(|_| anyhow!("store lock poisoned"))?;
            if let Some(ev) = hot.ephemeral.events.get(id) {
                return Ok(Some(ev.clone()));
            }
            if let Some(ev) = hot.event_cache.get(id) {
                return Ok(Some(ev.clone()));
            }
        }
        let conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
        let raw: Option<String> = {
            let mut stmt =
                conn.prepare_cached("SELECT raw_json FROM events WHERE id = ?1 LIMIT 1")?;
            stmt.query_row([id.as_bytes().as_slice()], |row| row.get(0))
                .optional()?
        };
        let Some(event) = raw.and_then(|json| Event::from_json(&json).ok()) else {
            return Ok(None);
        };
        #[cfg(test)]
        self.pause_if_a_test_asked();
        if let Ok(mut hot) = self.hot.write() {
            hot.cache_event(event.clone());
        }
        Ok(Some(event))
    }

    pub fn event_by_id(&self, id: &EventId) -> Result<Option<Event>> {
        let event = self.stored_event(id)?;
        Ok(self
            .without_expired(event.into_iter().collect(), now_secs())
            .pop())
    }

    /// Returns the stored copies of the given events, whichever store holds them.
    pub fn events_by_ids(&self, ids: &[EventId]) -> Result<Vec<Event>> {
        if ids.is_empty() {
            return Ok(Vec::new());
        }
        let mut found = Vec::new();
        let mut missing = Vec::new();
        {
            let hot = self
                .hot
                .read()
                .map_err(|_| anyhow!("store lock poisoned"))?;
            for id in ids {
                match hot
                    .ephemeral
                    .events
                    .get(id)
                    .or_else(|| hot.event_cache.get(id))
                {
                    Some(event) => found.push(event.clone()),
                    None => missing.push(*id),
                }
            }
        }
        if !missing.is_empty() {
            let conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
            for chunk in missing.chunks(500) {
                let placeholders = vec!["?"; chunk.len()].join(",");
                let sql = format!("SELECT raw_json FROM events WHERE id IN ({placeholders})");
                let mut stmt = conn.prepare(&sql)?;
                let params_vec: Vec<&[u8]> =
                    chunk.iter().map(|id| id.as_bytes().as_slice()).collect();
                let rows = stmt.query_map(rusqlite::params_from_iter(params_vec), |row| {
                    row.get::<_, String>(0)
                })?;
                found.extend(
                    rows.flatten()
                        .filter_map(|json| Event::from_json(&json).ok()),
                );
            }
        }
        Ok(self.without_expired(found, now_secs()))
    }

    pub fn has_event(&self, id: &EventId) -> Result<bool> {
        {
            let hot = self
                .hot
                .read()
                .map_err(|_| anyhow!("store lock poisoned"))?;
            if hot.ephemeral.events.contains_key(id) || hot.event_cache.contains_key(id) {
                return Ok(true);
            }
        }
        let conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
        let mut stmt = conn.prepare_cached("SELECT 1 FROM events WHERE id = ?1 LIMIT 1")?;
        Ok(stmt
            .query_row([id.as_bytes().as_slice()], |_| Ok(()))
            .optional()?
            .is_some())
    }

    pub fn existing_ids(&self, ids: &[EventId]) -> Result<HashSet<EventId>> {
        if ids.is_empty() {
            return Ok(HashSet::new());
        }
        let mut found = HashSet::with_capacity(ids.len());
        let mut missing = Vec::new();
        {
            let hot = self
                .hot
                .read()
                .map_err(|_| anyhow!("store lock poisoned"))?;
            for &id in ids {
                if hot.ephemeral.events.contains_key(&id) || hot.event_cache.contains_key(&id) {
                    found.insert(id);
                } else {
                    missing.push(id);
                }
            }
        }
        if missing.is_empty() {
            return Ok(found);
        }
        let conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
        for chunk in missing.chunks(500) {
            let placeholders = vec!["?"; chunk.len()].join(",");
            let sql = format!("SELECT id FROM events WHERE id IN ({placeholders})");
            let mut stmt = conn.prepare(&sql)?;
            let params_vec: Vec<&[u8]> = chunk.iter().map(|id| id.as_bytes().as_slice()).collect();
            let rows = stmt.query_map(rusqlite::params_from_iter(params_vec), |row| {
                row.get::<_, Vec<u8>>(0)
            })?;
            for bytes in rows.flatten() {
                if let Ok(eid) = EventId::from_slice(&bytes) {
                    found.insert(eid);
                }
            }
        }
        Ok(found)
    }

    pub fn metadata(&self, pk: PublicKey) -> Result<Option<Metadata>> {
        {
            let hot = self
                .hot
                .read()
                .map_err(|_| anyhow!("store lock poisoned"))?;
            if let Some((_, meta)) = hot.profiles.get(&pk) {
                return Ok(Some(meta.clone()));
            }
        }
        let conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
        let row: Option<(i64, String)> = {
            let mut stmt = conn.prepare_cached(
                "SELECT created_at, content FROM events WHERE pubkey = ?1 AND kind = 0 ORDER BY created_at DESC, id ASC LIMIT 1",
            )?;
            stmt.query_row([pk.as_bytes().as_slice()], |row| {
                Ok((row.get(0)?, row.get(1)?))
            })
            .optional()?
        };
        let Some((ts, content)) = row else {
            return Ok(None);
        };
        let meta = parse_metadata_lenient(&content);
        if let Ok(mut hot) = self.hot.write() {
            hot.cache_profile(pk, ts as u64, meta.clone());
        }
        Ok(Some(meta))
    }

    pub fn get_profiles_batch(&self, pks: &[PublicKey]) -> Result<HashMap<PublicKey, Metadata>> {
        if pks.is_empty() {
            return Ok(HashMap::new());
        }
        let mut out = HashMap::with_capacity(pks.len());
        let mut misses = Vec::new();
        {
            let hot = self
                .hot
                .read()
                .map_err(|_| anyhow!("store lock poisoned"))?;
            for &pk in pks {
                if let Some((_, meta)) = hot.profiles.get(&pk) {
                    out.insert(pk, meta.clone());
                } else {
                    misses.push(pk);
                }
            }
        }
        if misses.is_empty() {
            return Ok(out);
        }
        let mut fetched: HashMap<PublicKey, (u64, Metadata)> = HashMap::new();
        let conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
        for chunk in misses.chunks(500) {
            let placeholders = vec!["?"; chunk.len()].join(",");
            let sql = format!(
                "SELECT pubkey, created_at, content FROM events WHERE kind = 0 AND pubkey IN ({placeholders})"
            );
            let mut stmt = conn.prepare(&sql)?;
            let params_vec: Vec<&[u8]> = chunk.iter().map(|pk| pk.as_bytes().as_slice()).collect();
            let rows = stmt.query_map(rusqlite::params_from_iter(params_vec), |row| {
                Ok((
                    row.get::<_, Vec<u8>>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, String>(2)?,
                ))
            })?;
            for row in rows.flatten() {
                let Ok(pk) = PublicKey::from_slice(&row.0) else {
                    continue;
                };
                let ts = row.1 as u64;
                if fetched.get(&pk).is_none_or(|(known, _)| ts > *known) {
                    fetched.insert(pk, (ts, parse_metadata_lenient(&row.2)));
                }
            }
        }
        if !fetched.is_empty() {
            if let Ok(mut hot) = self.hot.write() {
                for (pk, (ts, meta)) in &fetched {
                    hot.cache_profile(*pk, *ts, meta.clone());
                }
            }
            for (pk, (_, meta)) in fetched {
                out.insert(pk, meta);
            }
        }
        Ok(out)
    }

    pub fn contacts_public_keys(&self, pk: PublicKey) -> Result<Vec<PublicKey>> {
        {
            let hot = self
                .hot
                .read()
                .map_err(|_| anyhow!("store lock poisoned"))?;
            if let Some((_, list)) = hot.contacts.get(&pk) {
                return Ok(list.clone());
            }
        }
        let conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
        let row: Option<(i64, String)> = {
            let mut stmt = conn.prepare_cached(
                "SELECT created_at, raw_json FROM events WHERE pubkey = ?1 AND kind = 3 ORDER BY created_at DESC, id ASC LIMIT 1",
            )?;
            stmt.query_row([pk.as_bytes().as_slice()], |row| {
                Ok((row.get(0)?, row.get(1)?))
            })
            .optional()?
        };
        if let Some((ts, raw)) = row {
            if let Ok(ev) = Event::from_json(&raw) {
                let list = parse_contacts_from_event(&ev);
                if let Ok(mut hot) = self.hot.write() {
                    hot.cache_contacts(pk, ts as u64, list.clone());
                }
                return Ok(list);
            }
        }
        Ok(Vec::new())
    }

    pub fn get_contacts_batch(
        &self,
        pks: &[PublicKey],
    ) -> Result<HashMap<PublicKey, Vec<PublicKey>>> {
        if pks.is_empty() {
            return Ok(HashMap::new());
        }
        let mut out = HashMap::with_capacity(pks.len());
        let mut misses = Vec::new();
        {
            let hot = self
                .hot
                .read()
                .map_err(|_| anyhow!("store lock poisoned"))?;
            for &pk in pks {
                if let Some((_, list)) = hot.contacts.get(&pk) {
                    out.insert(pk, list.clone());
                } else {
                    misses.push(pk);
                }
            }
        }
        if misses.is_empty() {
            return Ok(out);
        }
        let mut fetched: HashMap<PublicKey, (u64, Vec<PublicKey>)> = HashMap::new();
        let conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
        for chunk in misses.chunks(500) {
            let placeholders = vec!["?"; chunk.len()].join(",");
            let sql = format!(
                "SELECT pubkey, created_at, raw_json FROM events WHERE kind = 3 AND pubkey IN ({placeholders})"
            );
            let mut stmt = conn.prepare(&sql)?;
            let params_vec: Vec<&[u8]> = chunk.iter().map(|pk| pk.as_bytes().as_slice()).collect();
            let rows = stmt.query_map(rusqlite::params_from_iter(params_vec), |row| {
                Ok((
                    row.get::<_, Vec<u8>>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, String>(2)?,
                ))
            })?;
            for row in rows.flatten() {
                let (Ok(pk), Ok(ev)) = (PublicKey::from_slice(&row.0), Event::from_json(&row.2))
                else {
                    continue;
                };
                let ts = row.1 as u64;
                if fetched.get(&pk).is_none_or(|(known, _)| ts > *known) {
                    fetched.insert(pk, (ts, parse_contacts_from_event(&ev)));
                }
            }
        }
        if !fetched.is_empty() {
            if let Ok(mut hot) = self.hot.write() {
                for (pk, (ts, list)) in &fetched {
                    hot.cache_contacts(*pk, *ts, list.clone());
                }
            }
            for (pk, (_, list)) in fetched {
                out.insert(pk, list);
            }
        }
        Ok(out)
    }

    /// Fast indexed interaction lookup without deserializing full event JSON.
    pub fn batch_interaction_rows(&self, target_ids: &[EventId]) -> Result<Vec<InteractionRow>> {
        if target_ids.is_empty() {
            return Ok(Vec::new());
        }
        let conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
        let mut out = Vec::new();
        for chunk in target_ids.chunks(500) {
            let placeholders = vec!["?"; chunk.len()].join(",");
            let sql = format!(
                "SELECT target_id, event_id, kind, author FROM interactions WHERE target_id IN ({placeholders})"
            );
            let mut stmt = conn.prepare(&sql)?;
            let params_vec: Vec<&[u8]> = chunk.iter().map(|id| id.as_bytes().as_slice()).collect();
            let rows = stmt.query_map(rusqlite::params_from_iter(params_vec), |row| {
                Ok((
                    row.get::<_, Vec<u8>>(0)?,
                    row.get::<_, Vec<u8>>(1)?,
                    row.get::<_, u16>(2)?,
                    row.get::<_, Vec<u8>>(3)?,
                ))
            })?;
            for row in rows.flatten() {
                if let (Ok(target_id), Ok(event_id), Ok(author)) = (
                    EventId::from_slice(&row.0),
                    EventId::from_slice(&row.1),
                    PublicKey::from_slice(&row.3),
                ) {
                    out.push(InteractionRow {
                        target_id,
                        event_id,
                        kind: row.2,
                        author,
                    });
                }
            }
        }
        Ok(out)
    }

    pub fn kind_stats(&self) -> Result<(usize, HashMap<u16, usize>)> {
        let hot = self
            .hot
            .read()
            .map_err(|_| anyhow!("store lock poisoned"))?;
        let mut counts = hot.kind_counts.clone();
        let mut total = hot.total_persistent;
        for ev in hot.ephemeral.events.values() {
            *counts.entry(ev.kind.as_u16()).or_insert(0) += 1;
            total += 1;
        }
        Ok((total, counts))
    }

    fn query_sqlite(&self, filter: &Filter) -> Result<Vec<Event>> {
        if filter.limit == Some(0) {
            return Ok(Vec::new());
        }
        // Fast path: pure ID lookup hits in-memory event cache first!
        if filter.ids.as_ref().is_some_and(|s| !s.is_empty())
            && filter.authors.is_none()
            && filter.since.is_none()
            && filter.until.is_none()
            && filter.search.is_none()
            && filter.generic_tags.is_empty()
        {
            let ids = filter.ids.as_ref().unwrap();
            let mut results = Vec::with_capacity(ids.len());
            let mut misses = Vec::new();
            {
                let hot = self
                    .hot
                    .read()
                    .map_err(|_| anyhow!("store lock poisoned"))?;
                for id in ids {
                    if let Some(ev) = hot.event_cache.get(id) {
                        if filter.kinds.as_ref().is_none_or(|ks| ks.contains(&ev.kind)) {
                            results.push(ev.clone());
                        }
                    } else {
                        misses.push(*id);
                    }
                }
            }
            if !misses.is_empty() {
                let conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
                for chunk in misses.chunks(500) {
                    let ph = vec!["?"; chunk.len()].join(",");
                    let sql = format!("SELECT raw_json FROM events WHERE id IN ({ph})");
                    let mut stmt = conn.prepare(&sql)?;
                    let params_vec: Vec<&[u8]> =
                        chunk.iter().map(|id| id.as_bytes().as_slice()).collect();
                    let rows = stmt.query_map(rusqlite::params_from_iter(params_vec), |row| {
                        row.get::<_, String>(0)
                    })?;
                    for json in rows.flatten() {
                        if let Ok(ev) = Event::from_json(&json) {
                            if filter.kinds.as_ref().is_none_or(|ks| ks.contains(&ev.kind)) {
                                results.push(ev);
                            }
                        }
                    }
                }
            }
            results.sort_by(|a, b| {
                b.created_at
                    .cmp(&a.created_at)
                    .then_with(|| a.id.cmp(&b.id))
            });
            if let Some(limit) = filter.limit {
                results.truncate(limit);
            }
            return Ok(results);
        }

        // If any IN-list is very large (> 500), chunk along that dimension
        if let Some(ref authors) = filter.authors {
            if authors.len() > 500 {
                let all_authors: Vec<PublicKey> = authors.iter().copied().collect();
                let mut combined: Vec<Event> = Vec::new();
                let mut seen: HashSet<EventId> = HashSet::new();
                for chunk in all_authors.chunks(500) {
                    let mut sub = filter.clone();
                    sub.authors = Some(chunk.iter().copied().collect());
                    for ev in self.query_sqlite(&sub)? {
                        if seen.insert(ev.id) {
                            combined.push(ev);
                        }
                    }
                }
                combined.sort_by(|a, b| {
                    b.created_at
                        .cmp(&a.created_at)
                        .then_with(|| a.id.cmp(&b.id))
                });
                if let Some(limit) = filter.limit {
                    combined.truncate(limit);
                }
                return Ok(combined);
            }
        }

        let conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
        let mut sql = String::new();
        let mut where_clauses: Vec<String> = Vec::new();
        let mut params_owned: Vec<SqlParam> = Vec::new();

        // Pick primary tag table join if generic_tags is present and ids/authors are absent
        let tag_entries: Vec<(String, Vec<String>)> = filter
            .generic_tags
            .iter()
            .filter(|(_, vals)| !vals.is_empty())
            .map(|(k, vals)| (k.as_str().to_string(), vals.iter().cloned().collect()))
            .collect();

        let drive_from_tag = !tag_entries.is_empty()
            && filter.ids.as_ref().is_none_or(|s| s.is_empty())
            && filter.authors.as_ref().is_none_or(|s| s.is_empty());

        if drive_from_tag {
            let (ref tag_name, ref tag_vals) = tag_entries[0];
            let single_tag_val = tag_vals.len() == 1;
            if single_tag_val {
                sql.push_str(
                    "SELECT e.id, t0.created_at, e.raw_json FROM event_tags t0 JOIN events e ON e.seq = t0.event_seq",
                );
            } else {
                sql.push_str(
                    "SELECT DISTINCT e.id, t0.created_at, e.raw_json FROM event_tags t0 JOIN events e ON e.seq = t0.event_seq",
                );
            }
            where_clauses.push("t0.tag_name = ?".to_string());
            params_owned.push(SqlParam::Text(tag_name.clone()));

            if single_tag_val {
                where_clauses.push("t0.tag_value = ?".to_string());
                params_owned.push(SqlParam::Text(tag_vals[0].clone()));
            } else {
                let ph = vec!["?"; tag_vals.len()].join(",");
                where_clauses.push(format!("t0.tag_value IN ({ph})"));
                for v in tag_vals {
                    params_owned.push(SqlParam::Text(v.clone()));
                }
            }
            if let Some(ref kinds) = filter.kinds {
                if !kinds.is_empty() {
                    let ph = vec!["?"; kinds.len()].join(",");
                    where_clauses.push(format!("t0.kind IN ({ph})"));
                    for k in kinds {
                        params_owned.push(SqlParam::Int(k.as_u16() as i64));
                    }
                }
            }
            if let Some(since) = filter.since {
                where_clauses.push("t0.created_at >= ?".to_string());
                params_owned.push(SqlParam::Int(since.as_secs() as i64));
            }
            if let Some(until) = filter.until {
                where_clauses.push("t0.created_at <= ?".to_string());
                params_owned.push(SqlParam::Int(until.as_secs() as i64));
            }
            for (tag_name, tag_vals) in tag_entries.iter().skip(1) {
                let ph = vec!["?"; tag_vals.len()].join(",");
                where_clauses.push(format!(
                    "EXISTS (SELECT 1 FROM event_tags tx WHERE tx.event_seq = e.seq AND tx.tag_name = ? AND tx.tag_value IN ({ph}))"
                ));
                params_owned.push(SqlParam::Text(tag_name.clone()));
                for v in tag_vals {
                    params_owned.push(SqlParam::Text(v.clone()));
                }
            }
        } else {
            sql.push_str("SELECT e.id, e.created_at, e.raw_json FROM events e");
            if let Some(ref ids) = filter.ids {
                if !ids.is_empty() {
                    let ph = vec!["?"; ids.len()].join(",");
                    where_clauses.push(format!("e.id IN ({ph})"));
                    for id in ids {
                        params_owned.push(SqlParam::Blob(id.as_bytes().to_vec()));
                    }
                }
            }
            if let Some(ref authors) = filter.authors {
                if !authors.is_empty() {
                    let ph = vec!["?"; authors.len()].join(",");
                    where_clauses.push(format!("e.pubkey IN ({ph})"));
                    for pk in authors {
                        params_owned.push(SqlParam::Blob(pk.as_bytes().to_vec()));
                    }
                }
            }
            if let Some(ref kinds) = filter.kinds {
                if !kinds.is_empty() {
                    let ph = vec!["?"; kinds.len()].join(",");
                    where_clauses.push(format!("e.kind IN ({ph})"));
                    for k in kinds {
                        params_owned.push(SqlParam::Int(k.as_u16() as i64));
                    }
                }
            }
            if let Some(since) = filter.since {
                where_clauses.push("e.created_at >= ?".to_string());
                params_owned.push(SqlParam::Int(since.as_secs() as i64));
            }
            if let Some(until) = filter.until {
                where_clauses.push("e.created_at <= ?".to_string());
                params_owned.push(SqlParam::Int(until.as_secs() as i64));
            }
            for (tag_name, tag_vals) in &tag_entries {
                let ph = vec!["?"; tag_vals.len()].join(",");
                where_clauses.push(format!(
                    "EXISTS (SELECT 1 FROM event_tags tx WHERE tx.event_seq = e.seq AND tx.tag_name = ? AND tx.tag_value IN ({ph}))"
                ));
                params_owned.push(SqlParam::Text(tag_name.clone()));
                for v in tag_vals {
                    params_owned.push(SqlParam::Text(v.clone()));
                }
            }
        }

        if let Some(ref search) = filter.search {
            if !search.is_empty() {
                where_clauses.push("INSTR(LOWER(e.content), LOWER(?)) > 0".to_string());
                params_owned.push(SqlParam::Text(search.clone()));
            }
        }

        if !where_clauses.is_empty() {
            sql.push_str(" WHERE ");
            sql.push_str(&where_clauses.join(" AND "));
        }
        if drive_from_tag {
            sql.push_str(" ORDER BY t0.created_at DESC, t0.event_seq ASC");
        } else {
            sql.push_str(" ORDER BY e.created_at DESC, e.id ASC");
        }
        if let Some(limit) = filter.limit {
            sql.push_str(" LIMIT ?");
            params_owned.push(SqlParam::Int(limit as i64));
        }

        let refs: Vec<&dyn ToSql> = params_owned.iter().map(|p| p as &dyn ToSql).collect();
        let mut stmt = conn.prepare(&sql)?;
        let rows = stmt.query_map(refs.as_slice(), |row| {
            Ok((row.get::<_, Vec<u8>>(0)?, row.get::<_, String>(2)?))
        })?;

        let mut events = Vec::new();
        let mut seen = HashSet::new();
        let hot_read = self.hot.read().ok();
        for row in rows.flatten() {
            if let Ok(eid) = EventId::from_slice(&row.0) {
                if !seen.insert(eid) {
                    continue;
                }
                if let Some(ref hot) = hot_read {
                    if let Some(cached) = hot.event_cache.get(&eid) {
                        events.push(cached.clone());
                        continue;
                    }
                }
                if let Ok(ev) = Event::from_json(&row.1) {
                    events.push(ev);
                }
            }
        }
        Ok(events)
    }

    pub fn query(&self, filter: &Filter) -> Result<Vec<Event>> {
        let events = self.query_stored(filter)?;
        Ok(self.without_expired(events, now_secs()))
    }

    fn query_stored(&self, filter: &Filter) -> Result<Vec<Event>> {
        if filter_kinds_all_persistent(filter) {
            return self.query_sqlite(filter);
        }
        if filter_kinds_all_ephemeral(filter) {
            let hot = self
                .hot
                .read()
                .map_err(|_| anyhow!("store lock poisoned"))?;
            return Ok(hot.ephemeral.query(filter));
        }
        let mut events = {
            let hot = self
                .hot
                .read()
                .map_err(|_| anyhow!("store lock poisoned"))?;
            hot.ephemeral.query(filter)
        };
        let persistent = self.query_sqlite(filter)?;
        if events.is_empty() {
            return Ok(persistent);
        }
        let mut seen: HashSet<EventId> = events.iter().map(|e| e.id).collect();
        for ev in persistent {
            if seen.insert(ev.id) {
                events.push(ev);
            }
        }
        events.sort_by(|a, b| {
            b.created_at
                .cmp(&a.created_at)
                .then_with(|| a.id.cmp(&b.id))
        });
        if let Some(limit) = filter.limit {
            events.truncate(limit);
        }
        Ok(events)
    }

    pub fn count(&self, filter: &Filter) -> Result<usize> {
        // Ultra-fast O(1) path for unfiltered or kind-only counts!
        if filter.ids.is_none()
            && filter.authors.is_none()
            && filter.since.is_none()
            && filter.until.is_none()
            && filter.search.is_none()
            && filter.generic_tags.is_empty()
        {
            let (total, by_kind) = self.kind_stats()?;
            let count = match &filter.kinds {
                None => total,
                Some(kinds) if kinds.is_empty() => total,
                Some(kinds) => kinds
                    .iter()
                    .map(|k| by_kind.get(&k.as_u16()).copied().unwrap_or(0))
                    .sum(),
            };
            return Ok(match filter.limit {
                Some(limit) => count.min(limit),
                None => count,
            });
        }

        // Fast cache check for single-author profile or contact list existence
        if filter.limit == Some(1)
            && filter.ids.is_none()
            && filter.since.is_none()
            && filter.until.is_none()
            && filter.search.is_none()
            && filter.generic_tags.is_empty()
        {
            if let (Some(authors), Some(kinds)) = (&filter.authors, &filter.kinds) {
                if authors.len() == 1 && kinds.len() == 1 {
                    let pk = *authors.iter().next().unwrap();
                    let kind = *kinds.iter().next().unwrap();
                    if kind == Kind::Metadata {
                        let hot = self
                            .hot
                            .read()
                            .map_err(|_| anyhow!("store lock poisoned"))?;
                        if hot.profiles.contains_key(&pk) {
                            return Ok(1);
                        }
                    } else if kind == Kind::ContactList {
                        let hot = self
                            .hot
                            .read()
                            .map_err(|_| anyhow!("store lock poisoned"))?;
                        if hot.contacts.contains_key(&pk) {
                            return Ok(1);
                        }
                    }
                }
            }
        }

        if filter_kinds_all_ephemeral(filter) {
            let hot = self
                .hot
                .read()
                .map_err(|_| anyhow!("store lock poisoned"))?;
            return Ok(hot.ephemeral.count(filter));
        }

        let events = self.query(filter)?;
        Ok(events.len())
    }

    /// Deletes the events a filter selects. A filter that selects nothing in particular (no
    /// conditions, or an empty list of ids, authors, kinds or tag values) deletes nothing; use
    /// [`EventStore::wipe`] to clear the store.
    pub fn delete(&self, filter: &Filter) -> Result<usize> {
        if !filter_is_selective(filter) {
            return Ok(0);
        }
        let mut deleted_total = 0usize;
        if !filter_kinds_all_persistent(filter) {
            let mut hot = self
                .hot
                .write()
                .map_err(|_| anyhow!("store lock poisoned"))?;
            deleted_total += hot.ephemeral.delete(filter);
        }
        if filter_kinds_all_ephemeral(filter) {
            return Ok(deleted_total);
        }

        let matching = self.query_sqlite(filter)?;
        if matching.is_empty() {
            return Ok(deleted_total);
        }

        let mut conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
        let tx = conn.transaction()?;
        let mut removed: Vec<&Event> = Vec::with_capacity(matching.len());
        {
            let mut stmt = tx.prepare_cached("DELETE FROM events WHERE id = ?1")?;
            for ev in &matching {
                if stmt.execute([ev.id.as_bytes().as_slice()])? > 0 {
                    removed.push(ev);
                }
            }
        }
        tx.commit()?;

        let mut hot = self
            .hot
            .write()
            .map_err(|_| anyhow!("store lock poisoned"))?;
        for ev in &removed {
            hot.note_persistent_delete(&ev.id, ev.kind.as_u16(), &ev.pubkey);
        }
        deleted_total += removed.len();
        Ok(deleted_total)
    }

    pub fn wipe(&self) -> Result<()> {
        let mut conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
        let tx = conn.transaction()?;
        tx.execute_batch(
            "DELETE FROM interactions; DELETE FROM event_tags; DELETE FROM events; DELETE FROM deleted_ids; DELETE FROM deleted_coordinates;",
        )?;
        tx.commit()?;
        let mut hot = self
            .hot
            .write()
            .map_err(|_| anyhow!("store lock poisoned"))?;
        hot.clear_all();
        self.removed_by_request.store(0, Ordering::Relaxed);
        Ok(())
    }

    pub fn remove_invalid_replaceable_events(&self) -> Result<()> {
        let events =
            self.query(&Filter::new().kinds([Kind::Metadata, Kind::ContactList, Kind::MuteList]))?;
        let invalid: Vec<EventId> = events
            .into_iter()
            .filter(|e| e.verify().is_err())
            .map(|e| e.id)
            .collect();
        if !invalid.is_empty() {
            self.delete(&Filter::new().ids(invalid))?;
        }
        Ok(())
    }
}

enum SqlParam {
    Blob(Vec<u8>),
    Text(String),
    Int(i64),
}

impl ToSql for SqlParam {
    fn to_sql(&self) -> rusqlite::Result<rusqlite::types::ToSqlOutput<'_>> {
        match self {
            SqlParam::Blob(b) => b.to_sql(),
            SqlParam::Text(t) => t.to_sql(),
            SqlParam::Int(i) => i.to_sql(),
        }
    }
}

#[allow(dead_code)]
pub fn sort_events_desc(events: &mut [Event]) {
    events.sort_by(|a, b| {
        Reverse(a.created_at)
            .cmp(&Reverse(b.created_at))
            .then_with(|| a.id.cmp(&b.id))
    });
}

#[allow(dead_code)]
pub fn dedup_events_sorted(events: Vec<Event>) -> Vec<Event> {
    let mut map: BTreeMap<(Reverse<Timestamp>, EventId), Event> = BTreeMap::new();
    for ev in events {
        map.entry((Reverse(ev.created_at), ev.id)).or_insert(ev);
    }
    map.into_values().collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicBool;

    #[test]
    fn mixed_queries_preserve_order_and_limit_and_wipe_allows_reuse() {
        let path = std::env::temp_dir().join(format!("qiqstr-store-{}", rand::random::<u64>()));
        std::fs::create_dir(&path).unwrap();
        let db = EventStore::open(&path).unwrap();
        let keys = Keys::generate();

        for (kind, timestamp) in [
            (Kind::TextNote, 1),
            (Kind::from(2), 2),
            (Kind::TextNote, 3),
            (Kind::from(2), 4),
        ] {
            let event = EventBuilder::new(kind, "test")
                .custom_created_at(Timestamp::from(timestamp))
                .sign_with_keys(&keys)
                .unwrap();
            db.save_event(&event).unwrap();
        }
        let events = db.query(&Filter::new().limit(2)).unwrap();
        assert_eq!(events.len(), 2);
        assert_eq!(
            events
                .iter()
                .map(|event| event.created_at.as_secs())
                .collect::<Vec<_>>(),
            [4, 3]
        );

        let legitimate = EventBuilder::new(Kind::Metadata, "{}")
            .custom_created_at(Timestamp::from(100))
            .sign_with_keys(&keys)
            .unwrap();
        let fake = EventBuilder::new(Kind::Metadata, "{}")
            .custom_created_at(Timestamp::from(200))
            .sign_with_keys(&Keys::generate())
            .unwrap();
        let mut raw: serde_json::Value = serde_json::from_str(&fake.as_json()).unwrap();
        raw["pubkey"] = serde_json::json!(keys.public_key().to_hex());
        let fake = Event::from_json(raw.to_string()).unwrap();
        db.save_event(&fake).unwrap();
        assert_eq!(db.save_event(&legitimate).unwrap(), SaveStatus::Replaced);
        db.remove_invalid_replaceable_events().unwrap();
        assert_eq!(db.save_event(&legitimate).unwrap(), SaveStatus::Success);
        assert!(db.event_by_id(&fake.id).unwrap().is_none());

        db.wipe().unwrap();
        assert_eq!(db.count(&Filter::new()).unwrap(), 0);
        let event = EventBuilder::text_note("after wipe")
            .sign_with_keys(&keys)
            .unwrap();
        assert_eq!(db.save_event(&event).unwrap(), SaveStatus::Success);
        assert!(db.event_by_id(&event.id).unwrap().is_some());

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let dir_mode = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
            let db_mode = std::fs::metadata(path.join("events.sqlite"))
                .unwrap()
                .permissions()
                .mode()
                & 0o777;
            assert_eq!(dir_mode, 0o700);
            assert_eq!(db_mode, 0o600);
        }

        drop(db);
        std::fs::remove_dir_all(path).unwrap();
    }

    fn temp_dir(label: &str) -> PathBuf {
        let path = std::env::temp_dir().join(format!("qiqstr-{label}-{}", rand::random::<u64>()));
        std::fs::create_dir_all(&path).unwrap();
        path
    }

    fn note(keys: &Keys, content: &str, at: u64) -> Event {
        EventBuilder::text_note(content)
            .custom_created_at(Timestamp::from(at))
            .sign_with_keys(keys)
            .unwrap()
    }

    fn deletion(keys: &Keys, tags: Vec<Tag>, at: u64) -> Event {
        EventBuilder::new(Kind::EventDeletion, "")
            .tags(tags)
            .custom_created_at(Timestamp::from(at))
            .sign_with_keys(keys)
            .unwrap()
    }

    fn addressable(keys: &Keys, kind: u16, identifier: &str, content: &str, at: u64) -> Event {
        EventBuilder::new(Kind::from(kind), content)
            .tag(Tag::identifier(identifier))
            .custom_created_at(Timestamp::from(at))
            .sign_with_keys(keys)
            .unwrap()
    }

    fn coordinate_tag(keys: &Keys, kind: u16, identifier: &str) -> Tag {
        Tag::parse([
            "a".to_string(),
            format!("{kind}:{}:{identifier}", keys.public_key().to_hex()),
        ])
        .unwrap()
    }

    #[test]
    fn a_batch_updates_the_caches_in_the_order_it_was_saved() {
        let keys = Keys::generate();

        let db = EventStore::open_in_memory().unwrap();
        let deleted = note(&keys, "to be deleted", 100);
        let request = deletion(&keys, vec![Tag::event(deleted.id)], 200);
        assert_eq!(
            db.save_events(&[deleted.clone(), request.clone()]).unwrap(),
            2
        );
        assert!(db.event_by_id(&deleted.id).unwrap().is_none());
        assert!(db.query(&Filter::new().id(deleted.id)).unwrap().is_empty());
        assert!(db.existing_ids(&[deleted.id]).unwrap().is_empty());
        assert!(!db.has_event(&deleted.id).unwrap());
        assert_eq!(db.count(&Filter::new().kind(Kind::TextNote)).unwrap(), 0);
        assert_eq!(
            db.count(&Filter::new().kind(Kind::EventDeletion)).unwrap(),
            1
        );
        assert!(db.event_by_id(&request.id).unwrap().is_some());

        let db = EventStore::open_in_memory().unwrap();
        let old = EventBuilder::new(Kind::Metadata, r#"{"name":"old"}"#)
            .custom_created_at(Timestamp::from(100))
            .sign_with_keys(&keys)
            .unwrap();
        let new = EventBuilder::new(Kind::Metadata, r#"{"name":"new"}"#)
            .custom_created_at(Timestamp::from(200))
            .sign_with_keys(&keys)
            .unwrap();
        assert_eq!(db.save_events(&[old.clone(), new.clone()]).unwrap(), 2);
        assert_eq!(db.count(&Filter::new().kind(Kind::Metadata)).unwrap(), 1);
        assert_eq!(db.count(&Filter::new()).unwrap(), 1);
        assert!(db.event_by_id(&old.id).unwrap().is_none());
        assert!(db.existing_ids(&[old.id]).unwrap().is_empty());
        assert_eq!(
            db.metadata(keys.public_key()).unwrap().unwrap().name,
            Some("new".to_string())
        );

        let db = EventStore::open_in_memory().unwrap();
        assert_eq!(db.save_events(&[new.clone(), old.clone()]).unwrap(), 1);
        assert_eq!(db.count(&Filter::new().kind(Kind::Metadata)).unwrap(), 1);
        assert_eq!(
            db.metadata(keys.public_key()).unwrap().unwrap().name,
            Some("new".to_string())
        );
    }

    #[test]
    fn another_account_cannot_block_an_authors_tombstone() {
        let author = Keys::generate();
        let attacker = Keys::generate();
        let victim_note = note(&author, "victim note", 100);
        let bogus = deletion(&attacker, vec![Tag::event(victim_note.id)], 150);
        let genuine = deletion(&author, vec![Tag::event(victim_note.id)], 200);

        let db = EventStore::open_in_memory().unwrap();
        db.save_event(&bogus).unwrap();
        assert_eq!(db.save_event(&victim_note).unwrap(), SaveStatus::Success);
        db.save_event(&genuine).unwrap();
        assert!(db.event_by_id(&victim_note.id).unwrap().is_none());
        assert_eq!(db.save_event(&victim_note).unwrap(), SaveStatus::Deleted);

        let db = EventStore::open_in_memory().unwrap();
        db.save_event(&victim_note).unwrap();
        db.save_event(&bogus).unwrap();
        assert!(db.event_by_id(&victim_note.id).unwrap().is_some());
    }

    #[test]
    fn opening_a_store_from_the_first_schema_keeps_data_and_rebuilds_tombstones() {
        let path = temp_dir("legacy-schema");
        let author = Keys::generate();
        let attacker = Keys::generate();
        let kept = note(&author, "kept across the upgrade", 50);
        let deleted = note(&author, "deleted before the upgrade", 60);
        let unlabelled = EventBuilder::new(Kind::LongFormTextNote, "empty identifier")
            .tag(Tag::identifier(""))
            .custom_created_at(Timestamp::from(70))
            .sign_with_keys(&author)
            .unwrap();
        let withdrawn = addressable(&author, 30023, "withdrawn", "deleted by address", 40);
        let withdrawal = deletion(
            &author,
            vec![coordinate_tag(&author, 30023, "withdrawn")],
            45,
        );
        {
            let conn = Connection::open(path.join("events.sqlite")).unwrap();
            conn.execute_batch(
                "CREATE TABLE events (
                    seq INTEGER PRIMARY KEY, id BLOB NOT NULL UNIQUE, pubkey BLOB NOT NULL,
                    kind INTEGER NOT NULL, created_at INTEGER NOT NULL, d_tag TEXT,
                    content TEXT NOT NULL, raw_json TEXT NOT NULL);
                 CREATE TABLE event_tags (
                    tag_name TEXT NOT NULL, tag_value TEXT NOT NULL, kind INTEGER NOT NULL,
                    created_at INTEGER NOT NULL,
                    event_seq INTEGER NOT NULL REFERENCES events(seq) ON DELETE CASCADE);
                 CREATE TABLE interactions (
                    event_seq INTEGER PRIMARY KEY REFERENCES events(seq) ON DELETE CASCADE,
                    target_id BLOB NOT NULL, event_id BLOB NOT NULL, kind INTEGER NOT NULL,
                    author BLOB NOT NULL);
                 CREATE TABLE deleted_ids (id BLOB PRIMARY KEY, pubkey BLOB NOT NULL);",
            )
            .unwrap();
            for (event, d_tag) in [
                (&kept, None),
                (&unlabelled, Some("")),
                (&withdrawn, Some("withdrawn")),
                (&withdrawal, None),
            ] {
                conn.execute(
                    "INSERT INTO events (id, pubkey, kind, created_at, d_tag, content, raw_json) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                    params![
                        event.id.as_bytes().as_slice(),
                        event.pubkey.as_bytes().as_slice(),
                        event.kind.as_u16(),
                        event.created_at.as_secs() as i64,
                        d_tag,
                        event.content.as_str(),
                        event.as_json(),
                    ],
                )
                .unwrap();
            }
            conn.execute(
                "INSERT INTO deleted_ids (id, pubkey) VALUES (?1, ?2)",
                params![
                    deleted.id.as_bytes().as_slice(),
                    attacker.public_key().as_bytes().as_slice()
                ],
            )
            .unwrap();
        }

        let db = EventStore::open(&path).unwrap();
        assert_eq!(db.event_by_id(&kept.id).unwrap(), Some(kept.clone()));
        assert!(db.event_by_id(&withdrawn.id).unwrap().is_none());
        assert_eq!(db.save_event(&withdrawn).unwrap(), SaveStatus::Deleted);
        assert_eq!(db.count(&Filter::new()).unwrap(), 3);
        let found = db
            .query(
                &Filter::new()
                    .kind(Kind::LongFormTextNote)
                    .author(author.public_key())
                    .identifier(""),
            )
            .unwrap();
        assert_eq!(found, vec![unlabelled.clone()]);
        db.save_event(&deletion(&author, vec![Tag::event(deleted.id)], 80))
            .unwrap();
        assert_eq!(db.save_event(&deleted).unwrap(), SaveStatus::Deleted);
        drop(db);

        let conn = Connection::open(path.join("events.sqlite")).unwrap();
        let version: i64 = conn
            .query_row("PRAGMA user_version", [], |row| row.get(0))
            .unwrap();
        assert_eq!(version, SCHEMA_VERSION);
        let tombstones: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM deleted_ids WHERE id = ?1",
                [deleted.id.as_bytes().as_slice()],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(tombstones, 2);
        drop(conn);

        let reopened = EventStore::open(&path).unwrap();
        assert_eq!(reopened.event_by_id(&kept.id).unwrap(), Some(kept));
        drop(reopened);
        std::fs::remove_dir_all(path).unwrap();
    }

    #[test]
    fn address_deletions_remove_older_versions_and_block_their_return() {
        let author = Keys::generate();
        let stranger = Keys::generate();
        let db = EventStore::open_in_memory().unwrap();

        let article = addressable(&author, 30023, "post", "first draft", 1_000);
        db.save_event(&article).unwrap();
        db.save_event(&deletion(
            &stranger,
            vec![coordinate_tag(&author, 30023, "post")],
            1_500,
        ))
        .unwrap();
        assert!(db.event_by_id(&article.id).unwrap().is_some());

        db.save_event(&deletion(
            &author,
            vec![coordinate_tag(&author, 30023, "post")],
            2_000,
        ))
        .unwrap();
        assert!(db.event_by_id(&article.id).unwrap().is_none());
        assert_eq!(
            db.count(&Filter::new().kind(Kind::LongFormTextNote))
                .unwrap(),
            0
        );
        assert_eq!(db.save_event(&article).unwrap(), SaveStatus::Deleted);
        let older_edit = addressable(&author, 30023, "post", "edit before deletion", 1_800);
        assert_eq!(db.save_event(&older_edit).unwrap(), SaveStatus::Deleted);
        let other_article = addressable(&author, 30023, "other", "untouched", 1_000);
        assert_eq!(db.save_event(&other_article).unwrap(), SaveStatus::Success);
        let republished = addressable(&author, 30023, "post", "published again", 3_000);
        assert_eq!(db.save_event(&republished).unwrap(), SaveStatus::Success);
        assert!(db.event_by_id(&republished.id).unwrap().is_some());

        let relays = EventBuilder::new(Kind::RelayList, "")
            .custom_created_at(Timestamp::from(1_000))
            .sign_with_keys(&author)
            .unwrap();
        db.save_event(&relays).unwrap();
        db.save_event(&deletion(
            &author,
            vec![coordinate_tag(&author, 10002, "")],
            2_000,
        ))
        .unwrap();
        assert!(db.event_by_id(&relays.id).unwrap().is_none());
    }

    #[test]
    fn deletion_requests_reach_events_kept_in_memory() {
        let author = Keys::generate();
        let stranger = Keys::generate();
        let db = EventStore::open_in_memory().unwrap();

        let poll = EventBuilder::new(Kind::from(1068), "a poll")
            .custom_created_at(Timestamp::from(100))
            .sign_with_keys(&author)
            .unwrap();
        assert!(!is_persistent_kind(poll.kind));
        assert_eq!(db.save_event(&poll).unwrap(), SaveStatus::Success);
        db.save_event(&deletion(&stranger, vec![Tag::event(poll.id)], 150))
            .unwrap();
        assert!(db.event_by_id(&poll.id).unwrap().is_some());
        db.save_event(&deletion(&author, vec![Tag::event(poll.id)], 200))
            .unwrap();
        assert!(db.event_by_id(&poll.id).unwrap().is_none());
        assert!(db
            .query(&Filter::new().kind(Kind::from(1068)))
            .unwrap()
            .is_empty());
        assert_eq!(db.save_event(&poll).unwrap(), SaveStatus::Deleted);
        assert_eq!(db.save_events(std::slice::from_ref(&poll)).unwrap(), 0);

        let voice = EventBuilder::new(Kind::from(1222), "a voice note")
            .custom_created_at(Timestamp::from(300))
            .sign_with_keys(&author)
            .unwrap();
        let request = deletion(&author, vec![Tag::event(voice.id)], 400);
        assert_eq!(db.save_events(&[voice.clone(), request]).unwrap(), 1);
        assert!(db.event_by_id(&voice.id).unwrap().is_none());

        let status = addressable(&author, 30315, "general", "working", 500);
        assert!(!is_persistent_kind(status.kind));
        db.save_event(&status).unwrap();
        db.save_event(&deletion(
            &author,
            vec![coordinate_tag(&author, 30315, "general")],
            600,
        ))
        .unwrap();
        assert!(db.event_by_id(&status.id).unwrap().is_none());
        assert_eq!(db.save_event(&status).unwrap(), SaveStatus::Deleted);
        let later = addressable(&author, 30315, "general", "back", 700);
        assert_eq!(db.save_event(&later).unwrap(), SaveStatus::Success);
    }

    #[test]
    fn a_deletion_request_cannot_delete_another_deletion_request() {
        let author = Keys::generate();
        let db = EventStore::open_in_memory().unwrap();
        let target = note(&author, "gone", 100);
        db.save_event(&target).unwrap();
        let first = deletion(&author, vec![Tag::event(target.id)], 200);
        db.save_event(&first).unwrap();
        db.save_event(&deletion(&author, vec![Tag::event(first.id)], 300))
            .unwrap();
        assert!(db.event_by_id(&first.id).unwrap().is_some());
        assert_eq!(db.save_event(&target).unwrap(), SaveStatus::Deleted);
    }

    #[test]
    fn removals_made_by_deletion_requests_are_reported_once() {
        let author = Keys::generate();
        let db = EventStore::open_in_memory().unwrap();
        let article = addressable(&author, 30023, "post", "body", 1_000);
        let first = note(&author, "first", 1_000);
        let poll = EventBuilder::new(Kind::from(1068), "poll")
            .custom_created_at(Timestamp::from(1_000))
            .sign_with_keys(&author)
            .unwrap();
        let survivor = note(&author, "stays", 1_000);
        let replaced = EventBuilder::new(Kind::Metadata, "{}")
            .custom_created_at(Timestamp::from(1_000))
            .sign_with_keys(&author)
            .unwrap();
        db.save_events(&[
            article.clone(),
            first.clone(),
            poll.clone(),
            survivor.clone(),
            replaced,
        ])
        .unwrap();
        assert_eq!(db.take_removed_by_request(), 0);

        let newer_profile = EventBuilder::new(Kind::Metadata, "{}")
            .custom_created_at(Timestamp::from(2_000))
            .sign_with_keys(&author)
            .unwrap();
        db.save_event(&newer_profile).unwrap();
        assert_eq!(db.take_removed_by_request(), 0);

        db.save_event(&deletion(
            &author,
            vec![
                coordinate_tag(&author, 30023, "post"),
                Tag::event(first.id),
                Tag::event(poll.id),
                Tag::event(EventId::all_zeros()),
            ],
            2_000,
        ))
        .unwrap();
        assert_eq!(db.take_removed_by_request(), 3);
        assert_eq!(db.take_removed_by_request(), 0);
        assert!(db.event_by_id(&survivor.id).unwrap().is_some());
    }

    #[test]
    fn expired_events_are_refused_and_hidden_once_their_time_passes() {
        let keys = Keys::generate();
        let db = EventStore::open_in_memory().unwrap();
        let now = now_secs();

        let already_expired = EventBuilder::text_note("expired")
            .tag(Tag::expiration(Timestamp::from(1)))
            .sign_with_keys(&keys)
            .unwrap();
        assert_eq!(
            db.save_event(&already_expired).unwrap(),
            SaveStatus::Expired
        );
        assert_eq!(
            db.save_events(std::slice::from_ref(&already_expired))
                .unwrap(),
            0
        );
        let expired_in_memory = EventBuilder::new(Kind::from(1068), "expired poll")
            .tag(Tag::expiration(Timestamp::from(1)))
            .sign_with_keys(&keys)
            .unwrap();
        assert_eq!(
            db.save_event(&expired_in_memory).unwrap(),
            SaveStatus::Expired
        );
        assert_eq!(db.count(&Filter::new()).unwrap(), 0);

        let short_lived = EventBuilder::text_note("short lived")
            .tag(Tag::expiration(Timestamp::from(now + 3_600)))
            .sign_with_keys(&keys)
            .unwrap();
        let short_lived_poll = EventBuilder::new(Kind::from(1068), "short lived poll")
            .tag(Tag::expiration(Timestamp::from(now + 3_600)))
            .sign_with_keys(&keys)
            .unwrap();
        let lasting = note(&keys, "lasting", now);
        db.save_events(&[
            short_lived.clone(),
            short_lived_poll.clone(),
            lasting.clone(),
        ])
        .unwrap();
        assert_eq!(db.query(&Filter::new()).unwrap().len(), 3);
        assert!(db.event_by_id(&short_lived.id).unwrap().is_some());

        let everything = db.query_stored(&Filter::new()).unwrap();
        let visible_later = db.without_expired(everything, now + 7_200);
        assert_eq!(visible_later, vec![lasting.clone()]);
        assert!(db.stored_event(&short_lived.id).unwrap().is_none());
        assert!(db.stored_event(&short_lived_poll.id).unwrap().is_none());
        assert!(db.existing_ids(&[short_lived.id]).unwrap().is_empty());
        assert_eq!(db.count(&Filter::new()).unwrap(), 1);
    }

    #[test]
    fn legacy_database_files_are_removed_and_never_counted() {
        let path = temp_dir("legacy-lmdb");
        std::fs::write(path.join("data.mdb"), vec![0u8; 3 * 1024 * 1024]).unwrap();
        std::fs::write(path.join("lock.mdb"), vec![0u8; 8192]).unwrap();
        assert_eq!(EventStore::database_size_in(&path), 0);

        let db = EventStore::open(&path).unwrap();
        assert!(!path.join("data.mdb").exists());
        assert!(!path.join("lock.mdb").exists());
        assert!(db.database_size_bytes() < 1024 * 1024);
        assert_eq!(
            db.database_size_bytes(),
            EventStore::database_size_in(&path)
        );
        drop(db);
        std::fs::remove_dir_all(path).unwrap();
    }

    #[test]
    fn a_corrupt_database_is_replaced_instead_of_failing_forever() {
        let path = temp_dir("corrupt");
        std::fs::write(
            path.join("events.sqlite"),
            b"this is not a sqlite database at all, just bytes".repeat(64),
        )
        .unwrap();
        let db = EventStore::open(&path).unwrap();
        let keys = Keys::generate();
        let event = note(&keys, "after recovery", 10);
        assert_eq!(db.save_event(&event).unwrap(), SaveStatus::Success);
        drop(db);
        let reopened = EventStore::open(&path).unwrap();
        assert_eq!(reopened.event_by_id(&event.id).unwrap(), Some(event));
        drop(reopened);
        std::fs::remove_dir_all(path).unwrap();
    }

    #[test]
    fn deleting_with_an_unselective_filter_removes_nothing() {
        let keys = Keys::generate();
        let db = EventStore::open_in_memory().unwrap();
        for i in 0..5u64 {
            db.save_event(&note(&keys, &format!("n{i}"), 10 + i))
                .unwrap();
        }
        let poll = EventBuilder::new(Kind::from(1068), "poll")
            .sign_with_keys(&keys)
            .unwrap();
        db.save_event(&poll).unwrap();

        for filter in [
            Filter::new(),
            Filter::new().ids(Vec::<EventId>::new()),
            Filter::new().authors(Vec::<PublicKey>::new()),
            Filter::new().kinds(Vec::<Kind>::new()),
            Filter::new()
                .kind(Kind::TextNote)
                .ids(Vec::<EventId>::new()),
            Filter::new().limit(3),
        ] {
            assert_eq!(db.delete(&filter).unwrap(), 0, "{filter:?}");
        }
        assert_eq!(db.count(&Filter::new()).unwrap(), 6);

        assert_eq!(db.delete(&Filter::new().kind(Kind::TextNote)).unwrap(), 5);
        assert_eq!(db.delete(&Filter::new().id(poll.id)).unwrap(), 1);
        assert_eq!(db.count(&Filter::new()).unwrap(), 0);
    }

    #[test]
    fn an_empty_identifier_can_be_queried() {
        let keys = Keys::generate();
        let db = EventStore::open_in_memory().unwrap();
        let unlabelled = addressable(&keys, 30023, "", "empty identifier", 100);
        let labelled = addressable(&keys, 30023, "post", "labelled", 200);
        let untagged = EventBuilder::new(Kind::LongFormTextNote, "no identifier tag")
            .custom_created_at(Timestamp::from(300))
            .sign_with_keys(&Keys::generate())
            .unwrap();
        db.save_events(&[unlabelled.clone(), labelled, untagged])
            .unwrap();
        let found = db
            .query(&Filter::new().kind(Kind::LongFormTextNote).identifier(""))
            .unwrap();
        assert_eq!(found, vec![unlabelled.clone()]);
        let found = db
            .query(
                &Filter::new()
                    .kind(Kind::LongFormTextNote)
                    .author(keys.public_key())
                    .identifier(""),
            )
            .unwrap();
        assert_eq!(found, vec![unlabelled]);
    }

    #[test]
    fn a_profile_with_malformed_fields_still_counts_as_present() {
        let keys = Keys::generate();
        let garbled = Keys::generate();
        let db = EventStore::open_in_memory().unwrap();
        let odd = EventBuilder::new(
            Kind::Metadata,
            r#"{"name":123,"about":"still readable","picture":["x"],"nip05":null,"pronouns":{"a":1}}"#,
        )
        .sign_with_keys(&keys)
        .unwrap();
        let not_json = EventBuilder::new(Kind::Metadata, "definitely not json")
            .sign_with_keys(&garbled)
            .unwrap();
        db.save_events(&[odd, not_json]).unwrap();

        for fresh_cache in [false, true] {
            if fresh_cache {
                db.hot.write().unwrap().profiles.clear();
            }
            let batch = db
                .get_profiles_batch(&[keys.public_key(), garbled.public_key()])
                .unwrap();
            assert_eq!(batch.len(), 2);
            let profile = &batch[&keys.public_key()];
            assert_eq!(profile.name, None);
            assert_eq!(profile.about.as_deref(), Some("still readable"));
            assert_eq!(profile.picture, None);
            assert_eq!(batch[&garbled.public_key()], Metadata::default());
        }
        db.hot.write().unwrap().profiles.clear();
        assert!(db.metadata(garbled.public_key()).unwrap().is_some());
        assert_eq!(
            parse_metadata_lenient(r#"{"name":"ok","lud16":"a@b.c"}"#)
                .lud16
                .as_deref(),
            Some("a@b.c")
        );
    }

    #[test]
    fn replaced_events_do_not_accumulate_in_the_eviction_queues() {
        let keys = Keys::generate();
        let db = EventStore::open_in_memory().unwrap();
        for i in 0..3_000u64 {
            db.save_event(&addressable(
                &keys,
                30315,
                "general",
                &format!("s{i}"),
                1_000 + i,
            ))
            .unwrap();
            let relays = EventBuilder::new(Kind::RelayList, "")
                .custom_created_at(Timestamp::from(1_000 + i))
                .sign_with_keys(&keys)
                .unwrap();
            db.save_event(&relays).unwrap();
        }
        let hot = db.hot.read().unwrap();
        assert_eq!(hot.ephemeral.events.len(), 1);
        assert_eq!(hot.event_cache.len(), 1);
        assert_eq!(hot.total_persistent, 1);
        assert!(hot.ephemeral.order.len() <= ORDER_SLACK + 2);
        assert!(hot.event_order.len() <= ORDER_SLACK + 2);
    }

    #[test]
    fn a_reader_cannot_cache_an_event_that_is_deleted_while_it_reads() {
        let db = std::sync::Arc::new(EventStore::open_in_memory().unwrap());
        let keys = Keys::generate();
        let event = note(&keys, "read while being deleted", 1_000);
        db.save_event(&event).unwrap();
        db.hot.write().unwrap().event_cache.clear();

        let (reached_tx, reached_rx) = std::sync::mpsc::channel();
        let (resume_tx, resume_rx) = std::sync::mpsc::channel();
        *db.pause_before_cache_fill.lock().unwrap() = Some(ReadPause {
            reached: reached_tx,
            resume: resume_rx,
        });

        let reader = {
            let db = db.clone();
            let id = event.id;
            std::thread::spawn(move || db.event_by_id(&id).unwrap())
        };
        reached_rx
            .recv_timeout(std::time::Duration::from_secs(5))
            .expect("the reader never reached the database");

        let deleted = std::sync::Arc::new(AtomicBool::new(false));
        let deleter = {
            let db = db.clone();
            let deleted = deleted.clone();
            let author = keys.public_key();
            std::thread::spawn(move || {
                let removed = db.delete(&Filter::new().author(author)).unwrap();
                deleted.store(true, Ordering::SeqCst);
                removed
            })
        };
        std::thread::sleep(std::time::Duration::from_millis(150));
        assert!(
            !deleted.load(Ordering::SeqCst),
            "the event was deleted between a reader's database read and its cache fill"
        );

        resume_tx.send(()).unwrap();
        assert_eq!(reader.join().unwrap(), Some(event.clone()));
        assert_eq!(deleter.join().unwrap(), 1);
        assert!(!db.hot.read().unwrap().event_cache.contains_key(&event.id));
        assert!(db.event_by_id(&event.id).unwrap().is_none());
        assert!(db.existing_ids(&[event.id]).unwrap().is_empty());
        assert!(!db.has_event(&event.id).unwrap());
    }

    #[test]
    fn readers_never_leave_a_deleted_event_in_the_cache() {
        let db = std::sync::Arc::new(EventStore::open_in_memory().unwrap());
        let keys = Keys::generate();
        let events: Vec<Event> = (0..40u64)
            .map(|i| note(&keys, &format!("n{i}"), 1_000 + i))
            .collect();
        let profile = EventBuilder::new(Kind::Metadata, r#"{"name":"cached"}"#)
            .custom_created_at(Timestamp::from(1_000))
            .sign_with_keys(&keys)
            .unwrap();
        let stop = std::sync::Arc::new(AtomicBool::new(false));

        let readers: Vec<_> = (0..4)
            .map(|_| {
                let db = db.clone();
                let stop = stop.clone();
                let ids: Vec<EventId> = events.iter().map(|e| e.id).collect();
                let pubkey = keys.public_key();
                std::thread::spawn(move || {
                    while !stop.load(Ordering::Relaxed) {
                        for id in &ids {
                            let _ = db.event_by_id(id);
                        }
                        let _ = db.metadata(pubkey);
                        let _ = db.get_profiles_batch(&[pubkey]);
                    }
                })
            })
            .collect();

        for _ in 0..150 {
            db.save_events(&events).unwrap();
            db.save_event(&profile).unwrap();
            db.hot.write().unwrap().event_cache.clear();
            db.hot.write().unwrap().profiles.clear();
            db.delete(&Filter::new().author(keys.public_key())).unwrap();
        }
        stop.store(true, Ordering::Relaxed);
        for reader in readers {
            reader.join().unwrap();
        }

        for event in &events {
            assert!(db.event_by_id(&event.id).unwrap().is_none());
        }
        assert!(db.metadata(keys.public_key()).unwrap().is_none());
        assert!(db
            .get_profiles_batch(&[keys.public_key()])
            .unwrap()
            .is_empty());
        assert!(db.existing_ids(&[events[0].id]).unwrap().is_empty());
    }
}
