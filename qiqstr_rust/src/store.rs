use std::cmp::Reverse;
use std::collections::{BTreeMap, HashMap, HashSet, VecDeque};
use std::path::{Path, PathBuf};
use std::sync::{Mutex, RwLock};

use anyhow::{anyhow, Result};
use nostr::prelude::*;
use rusqlite::{params, Connection, OptionalExtension, ToSql};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SaveStatus {
    Success,
    Duplicate,
    Replaced,
    Deleted,
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

struct EphemeralStore {
    events: HashMap<EventId, Event>,
    order: VecDeque<EventId>,
    replaceables: HashMap<(PublicKey, u16, String), EventId>,
    deleted: HashMap<EventId, PublicKey>,
}

impl EphemeralStore {
    fn new() -> Self {
        Self {
            events: HashMap::new(),
            order: VecDeque::new(),
            replaceables: HashMap::new(),
            deleted: HashMap::new(),
        }
    }

    fn save(&mut self, event: &Event) -> SaveStatus {
        let k = event.kind.as_u16();
        if is_ephemeral_protocol_kind(k) {
            return SaveStatus::Ephemeral;
        }
        if self.events.contains_key(&event.id) {
            return SaveStatus::Duplicate;
        }
        if self
            .deleted
            .get(&event.id)
            .is_some_and(|pk| *pk == event.pubkey)
        {
            return SaveStatus::Deleted;
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
                    if let Some(old) = self.events.remove(&old_id) {
                        if let Some(d) = replaceable_d_tag(&old) {
                            let key = (old.pubkey, old.kind.as_u16(), d);
                            if self.replaceables.get(&key) == Some(&old_id) {
                                self.replaceables.remove(&key);
                            }
                        }
                    }
                }
            }
        }
        self.events.insert(event.id, event.clone());
        self.order.push_back(event.id);
        SaveStatus::Success
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
            if let Some(old) = self.events.remove(&id) {
                if let Some(d) = replaceable_d_tag(&old) {
                    let key = (old.pubkey, old.kind.as_u16(), d);
                    if self.replaceables.get(&key) == Some(&id) {
                        self.replaceables.remove(&key);
                    }
                }
            }
        }
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
        self.deleted.clear();
    }
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
    }

    fn note_persistent_insert(&mut self, event: &Event) {
        let k = event.kind.as_u16();
        *self.kind_counts.entry(k).or_insert(0) += 1;
        self.total_persistent += 1;
        self.cache_event(event.clone());

        if event.kind == Kind::Metadata {
            if let Ok(meta) = Metadata::from_json(&event.content) {
                let ts = event.created_at.as_secs();
                let should_update = self
                    .profiles
                    .get(&event.pubkey)
                    .is_none_or(|(old_ts, _)| ts >= *old_ts);
                if should_update {
                    if self.profiles.len() >= PROFILE_CACHE_MAX {
                        self.profiles.clear();
                    }
                    self.profiles.insert(event.pubkey, (ts, meta));
                }
            }
        } else if event.kind == Kind::ContactList {
            let ts = event.created_at.as_secs();
            let should_update = self
                .contacts
                .get(&event.pubkey)
                .is_none_or(|(old_ts, _)| ts >= *old_ts);
            if should_update {
                if self.contacts.len() >= CONTACT_CACHE_MAX {
                    self.contacts.clear();
                }
                self.contacts
                    .insert(event.pubkey, (ts, parse_contacts_from_event(event)));
            }
        }
    }

    fn note_persistent_delete(&mut self, id: &EventId, kind: u16, pubkey: &PublicKey) {
        self.event_cache.remove(id);
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
}

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
    id BLOB PRIMARY KEY,
    pubkey BLOB NOT NULL
);
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
    conn.execute_batch(SCHEMA_SQL)?;
    Ok(())
}

impl EventStore {
    pub fn open_in_memory() -> Result<Self> {
        let conn = Connection::open_in_memory()?;
        configure_connection(&conn, false)?;
        Ok(Self {
            conn: Mutex::new(conn),
            hot: RwLock::new(HotCache::new()),
            dir_path: None,
        })
    }

    pub fn open(dir: &Path) -> Result<Self> {
        std::fs::create_dir_all(dir)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = std::fs::set_permissions(dir, std::fs::Permissions::from_mode(0o700));
        }
        let db_file = dir.join("events.sqlite");
        let conn = Connection::open(&db_file)?;
        configure_connection(&conn, true)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            for name in ["events.sqlite", "events.sqlite-wal", "events.sqlite-shm"] {
                let p = dir.join(name);
                if p.exists() {
                    let _ = std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o600));
                }
            }
        }

        let mut hot = HotCache::new();
        {
            let mut stmt = conn.prepare("SELECT kind, COUNT(*) FROM events GROUP BY kind")?;
            let rows = stmt.query_map([], |row| {
                let kind: u16 = row.get(0)?;
                let count: usize = row.get(1)?;
                Ok((kind, count))
            })?;
            for row in rows.flatten() {
                hot.kind_counts.insert(row.0, row.1);
                hot.total_persistent += row.1;
            }
        }

        Ok(Self {
            conn: Mutex::new(conn),
            hot: RwLock::new(hot),
            dir_path: Some(dir.to_path_buf()),
        })
    }

    pub fn database_size_bytes(&self) -> u64 {
        let Some(ref dir) = self.dir_path else {
            return 0;
        };
        let mut total = 0u64;
        for name in ["events.sqlite", "events.sqlite-wal", "data.mdb"] {
            if let Ok(meta) = std::fs::metadata(dir.join(name)) {
                total += meta.len();
            }
        }
        total
    }

    fn insert_persistent_in_tx(
        tx: &Connection,
        event: &Event,
        deleted_records: &mut Vec<(EventId, u16, PublicKey)>,
    ) -> Result<SaveStatus> {
        let k = event.kind.as_u16();
        if is_ephemeral_protocol_kind(k) {
            return Ok(SaveStatus::Ephemeral);
        }

        let id_bytes = event.id.as_bytes().as_slice();
        let pk_bytes = event.pubkey.as_bytes().as_slice();
        let created_at = event.created_at.as_secs() as i64;

        // 1. Duplicate check
        {
            let mut stmt = tx.prepare_cached("SELECT 1 FROM events WHERE id = ?1 LIMIT 1")?;
            if stmt.query_row([id_bytes], |_| Ok(())).optional()?.is_some() {
                return Ok(SaveStatus::Duplicate);
            }
        }

        // 2. Previously deleted check (NIP-09)
        if event.kind != Kind::EventDeletion {
            let mut stmt = tx.prepare_cached(
                "SELECT 1 FROM deleted_ids WHERE id = ?1 AND pubkey = ?2 LIMIT 1",
            )?;
            if stmt
                .query_row(params![id_bytes, pk_bytes], |_| Ok(()))
                .optional()?
                .is_some()
            {
                return Ok(SaveStatus::Deleted);
            }
        }

        // 3. Replaceable / Addressable check
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
                        deleted_records.push((old_eid, k, event.pubkey));
                    }
                }
            }
        }

        // 4. Insert event
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

        // 5. Index single-letter tags (deduped per event)
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
                        && !val.is_empty()
                        && seen_tags.insert((name, val))
                    {
                        tag_stmt.execute(params![name, val, k, created_at, seq])?;
                    }
                }
            }
        }

        // 6. Materialize interaction target
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

        // 7. Process NIP-09 deletion immediately
        if event.kind == Kind::EventDeletion {
            let mut ins_del = tx
                .prepare_cached("INSERT OR IGNORE INTO deleted_ids (id, pubkey) VALUES (?1, ?2)")?;
            let mut find_target = tx.prepare_cached(
                "SELECT seq, kind FROM events WHERE id = ?1 AND pubkey = ?2 LIMIT 1",
            )?;
            let mut del_target = tx.prepare_cached("DELETE FROM events WHERE seq = ?1")?;
            for tag in event.tags.iter() {
                let slice = tag.as_slice();
                if slice.len() >= 2 && slice[0] == "e" {
                    if let Ok(target_eid) = EventId::from_hex(&slice[1]) {
                        let tbytes = target_eid.as_bytes().as_slice();
                        ins_del.execute(params![tbytes, pk_bytes])?;
                        if let Some((tseq, tkind)) = find_target
                            .query_row(params![tbytes, pk_bytes], |row| {
                                Ok((row.get::<_, i64>(0)?, row.get::<_, u16>(1)?))
                            })
                            .optional()?
                        {
                            del_target.execute([tseq])?;
                            deleted_records.push((target_eid, tkind, event.pubkey));
                        }
                    }
                }
            }
        }

        Ok(SaveStatus::Success)
    }

    pub fn save_event(&self, event: &Event) -> Result<SaveStatus> {
        if !is_persistent_kind(event.kind) {
            let mut hot = self
                .hot
                .write()
                .map_err(|_| anyhow!("store lock poisoned"))?;
            return Ok(hot.ephemeral.save(event));
        }

        let mut conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
        let tx = conn.transaction()?;
        let mut deleted_records = Vec::new();
        let status = Self::insert_persistent_in_tx(&tx, event, &mut deleted_records)?;
        if status == SaveStatus::Success {
            tx.commit()?;
            let mut hot = self
                .hot
                .write()
                .map_err(|_| anyhow!("store lock poisoned"))?;
            for (old_id, old_kind, old_pk) in deleted_records {
                hot.note_persistent_delete(&old_id, old_kind, &old_pk);
            }
            hot.note_persistent_insert(event);
        }
        Ok(status)
    }

    /// True single-transaction batch save! Returns number of newly saved events.
    pub fn save_events(&self, events: &[Event]) -> Result<usize> {
        if events.is_empty() {
            return Ok(0);
        }
        let mut persistent: Vec<&Event> = Vec::new();
        let mut ephemeral: Vec<&Event> = Vec::new();
        for ev in events {
            if is_persistent_kind(ev.kind) {
                persistent.push(ev);
            } else {
                ephemeral.push(ev);
            }
        }

        let mut saved_count = 0usize;

        if !persistent.is_empty() {
            let mut conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
            let tx = conn.transaction()?;
            let mut inserted: Vec<&Event> = Vec::with_capacity(persistent.len());
            let mut deleted_records: Vec<(EventId, u16, PublicKey)> = Vec::new();

            for ev in persistent {
                if Self::insert_persistent_in_tx(&tx, ev, &mut deleted_records)?
                    == SaveStatus::Success
                {
                    inserted.push(ev);
                }
            }
            tx.commit()?;

            let mut hot = self
                .hot
                .write()
                .map_err(|_| anyhow!("store lock poisoned"))?;
            for (old_id, old_kind, old_pk) in deleted_records {
                hot.note_persistent_delete(&old_id, old_kind, &old_pk);
            }
            for ev in inserted {
                hot.note_persistent_insert(ev);
                saved_count += 1;
            }
            for ev in ephemeral {
                if hot.ephemeral.save(ev) == SaveStatus::Success {
                    saved_count += 1;
                }
            }
        } else if !ephemeral.is_empty() {
            let mut hot = self
                .hot
                .write()
                .map_err(|_| anyhow!("store lock poisoned"))?;
            for ev in ephemeral {
                if hot.ephemeral.save(ev) == SaveStatus::Success {
                    saved_count += 1;
                }
            }
        }

        Ok(saved_count)
    }

    pub fn event_by_id(&self, id: &EventId) -> Result<Option<Event>> {
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
        let raw: Option<String> = {
            let conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
            let mut stmt =
                conn.prepare_cached("SELECT raw_json FROM events WHERE id = ?1 LIMIT 1")?;
            stmt.query_row([id.as_bytes().as_slice()], |row| row.get(0))
                .optional()?
        };
        if let Some(json) = raw {
            if let Ok(ev) = Event::from_json(&json) {
                if let Ok(mut hot) = self.hot.write() {
                    hot.cache_event(ev.clone());
                }
                return Ok(Some(ev));
            }
        }
        Ok(None)
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
        let row: Option<(i64, String)> = {
            let conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
            let mut stmt = conn.prepare_cached(
                "SELECT created_at, content FROM events WHERE pubkey = ?1 AND kind = 0 ORDER BY created_at DESC, id ASC LIMIT 1",
            )?;
            stmt.query_row([pk.as_bytes().as_slice()], |row| {
                Ok((row.get(0)?, row.get(1)?))
            })
            .optional()?
        };
        if let Some((ts, content)) = row {
            if let Ok(meta) = Metadata::from_json(&content) {
                if let Ok(mut hot) = self.hot.write() {
                    if hot.profiles.len() >= PROFILE_CACHE_MAX {
                        hot.profiles.clear();
                    }
                    hot.profiles.insert(pk, (ts as u64, meta.clone()));
                }
                return Ok(Some(meta));
            }
        }
        Ok(None)
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
        let mut fetched: Vec<(PublicKey, u64, Metadata)> = Vec::new();
        {
            let conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
            for chunk in misses.chunks(500) {
                let placeholders = vec!["?"; chunk.len()].join(",");
                let sql = format!(
                    "SELECT pubkey, created_at, content FROM events WHERE kind = 0 AND pubkey IN ({placeholders})"
                );
                let mut stmt = conn.prepare(&sql)?;
                let params_vec: Vec<&[u8]> =
                    chunk.iter().map(|pk| pk.as_bytes().as_slice()).collect();
                let rows = stmt.query_map(rusqlite::params_from_iter(params_vec), |row| {
                    Ok((
                        row.get::<_, Vec<u8>>(0)?,
                        row.get::<_, i64>(1)?,
                        row.get::<_, String>(2)?,
                    ))
                })?;
                for row in rows.flatten() {
                    if let (Ok(pk), Ok(meta)) =
                        (PublicKey::from_slice(&row.0), Metadata::from_json(&row.2))
                    {
                        fetched.push((pk, row.1 as u64, meta));
                    }
                }
            }
        }
        if !fetched.is_empty() {
            if let Ok(mut hot) = self.hot.write() {
                for (pk, ts, meta) in &fetched {
                    if hot.profiles.len() >= PROFILE_CACHE_MAX {
                        hot.profiles.clear();
                    }
                    hot.profiles.insert(*pk, (*ts, meta.clone()));
                }
            }
            for (pk, _, meta) in fetched {
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
        let row: Option<(i64, String)> = {
            let conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
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
                    if hot.contacts.len() >= CONTACT_CACHE_MAX {
                        hot.contacts.clear();
                    }
                    hot.contacts.insert(pk, (ts as u64, list.clone()));
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
        let mut fetched: Vec<(PublicKey, u64, Vec<PublicKey>)> = Vec::new();
        {
            let conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
            for chunk in misses.chunks(500) {
                let placeholders = vec!["?"; chunk.len()].join(",");
                let sql = format!(
                    "SELECT pubkey, created_at, raw_json FROM events WHERE kind = 3 AND pubkey IN ({placeholders})"
                );
                let mut stmt = conn.prepare(&sql)?;
                let params_vec: Vec<&[u8]> =
                    chunk.iter().map(|pk| pk.as_bytes().as_slice()).collect();
                let rows = stmt.query_map(rusqlite::params_from_iter(params_vec), |row| {
                    Ok((
                        row.get::<_, Vec<u8>>(0)?,
                        row.get::<_, i64>(1)?,
                        row.get::<_, String>(2)?,
                    ))
                })?;
                for row in rows.flatten() {
                    if let (Ok(pk), Ok(ev)) =
                        (PublicKey::from_slice(&row.0), Event::from_json(&row.2))
                    {
                        fetched.push((pk, row.1 as u64, parse_contacts_from_event(&ev)));
                    }
                }
            }
        }
        if !fetched.is_empty() {
            if let Ok(mut hot) = self.hot.write() {
                for (pk, ts, list) in &fetched {
                    if hot.contacts.len() >= CONTACT_CACHE_MAX {
                        hot.contacts.clear();
                    }
                    hot.contacts.insert(*pk, (*ts, list.clone()));
                }
            }
            for (pk, _, list) in fetched {
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

    pub fn delete(&self, filter: &Filter) -> Result<usize> {
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

        {
            let mut conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
            let tx = conn.transaction()?;
            {
                let mut stmt = tx.prepare_cached("DELETE FROM events WHERE id = ?1")?;
                for ev in &matching {
                    stmt.execute([ev.id.as_bytes().as_slice()])?;
                }
            }
            tx.commit()?;
        }

        let mut hot = self
            .hot
            .write()
            .map_err(|_| anyhow!("store lock poisoned"))?;
        for ev in &matching {
            hot.note_persistent_delete(&ev.id, ev.kind.as_u16(), &ev.pubkey);
        }
        deleted_total += matching.len();
        Ok(deleted_total)
    }

    pub fn wipe(&self) -> Result<()> {
        {
            let mut conn = self.conn.lock().map_err(|_| anyhow!("db lock poisoned"))?;
            let tx = conn.transaction()?;
            tx.execute_batch(
                "DELETE FROM interactions; DELETE FROM event_tags; DELETE FROM events; DELETE FROM deleted_ids;",
            )?;
            tx.commit()?;
        }
        let mut hot = self
            .hot
            .write()
            .map_err(|_| anyhow!("store lock poisoned"))?;
        hot.clear_all();
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
}
