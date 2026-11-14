use std::fmt;

use nostr_database::{
    Backend, DatabaseError, DatabaseEventStatus, Events, MemoryDatabase, MemoryDatabaseOptions,
    NostrDatabase, SaveEventStatus,
};
pub use nostr_lmdb::NostrLMDB;
use nostr_sdk::prelude::*;

fn is_persistent_kind(kind: Kind) -> bool {
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

pub struct HybridDatabase {
    lmdb: NostrLMDB,
    memory: MemoryDatabase,
}

impl fmt::Debug for HybridDatabase {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("HybridDatabase")
            .field("lmdb", &"NostrLMDB")
            .field("memory", &self.memory)
            .finish()
    }
}

impl HybridDatabase {
    pub(crate) fn new(lmdb: NostrLMDB) -> Self {
        let memory = MemoryDatabase::with_opts(MemoryDatabaseOptions {
            events: true,
            max_events: Some(50000),
        });
        Self { lmdb, memory }
    }

    pub(crate) async fn remove_invalid_replaceable_events(&self) -> Result<(), DatabaseError> {
        let events = self
            .lmdb
            .query(Filter::new().kinds([Kind::Metadata, Kind::ContactList, Kind::MuteList]))
            .await?;
        let invalid: Vec<EventId> = events
            .into_iter()
            .filter(|event| event.verify().is_err())
            .map(|event| event.id)
            .collect();
        if !invalid.is_empty() {
            self.lmdb.delete(Filter::new().ids(invalid)).await?;
        }
        Ok(())
    }
}

impl NostrDatabase for HybridDatabase {
    fn backend(&self) -> Backend {
        Backend::Custom("HybridLmdbMemory".to_string())
    }

    fn save_event<'a>(
        &'a self,
        event: &'a Event,
    ) -> BoxedFuture<'a, Result<SaveEventStatus, DatabaseError>> {
        Box::pin(async move {
            if is_persistent_kind(event.kind) {
                self.lmdb.save_event(event).await
            } else {
                self.memory.save_event(event).await
            }
        })
    }

    fn check_id<'a>(
        &'a self,
        event_id: &'a EventId,
    ) -> BoxedFuture<'a, Result<DatabaseEventStatus, DatabaseError>> {
        Box::pin(async move {
            let mem_status = self.memory.check_id(event_id).await?;
            if mem_status != DatabaseEventStatus::NotExistent {
                return Ok(mem_status);
            }
            self.lmdb.check_id(event_id).await
        })
    }

    fn event_by_id<'a>(
        &'a self,
        event_id: &'a EventId,
    ) -> BoxedFuture<'a, Result<Option<Event>, DatabaseError>> {
        Box::pin(async move {
            if let Some(event) = self.memory.event_by_id(event_id).await? {
                return Ok(Some(event));
            }
            self.lmdb.event_by_id(event_id).await
        })
    }

    fn count(&self, filter: Filter) -> BoxedFuture<'_, Result<usize, DatabaseError>> {
        Box::pin(async move {
            if filter_kinds_all_persistent(&filter) {
                return self.lmdb.count(filter).await;
            }
            if filter_kinds_all_ephemeral(&filter) {
                return self.memory.count(filter).await;
            }
            let mem = self.memory.count(filter.clone()).await?;
            let lmdb = self.lmdb.count(filter).await?;
            Ok(mem + lmdb)
        })
    }

    fn query(&self, filter: Filter) -> BoxedFuture<'_, Result<Events, DatabaseError>> {
        Box::pin(async move {
            if filter_kinds_all_persistent(&filter) {
                return self.lmdb.query(filter).await;
            }
            if filter_kinds_all_ephemeral(&filter) {
                return self.memory.query(filter).await;
            }
            let mut events = self.memory.query(filter.clone()).await?;
            let lmdb_events = self.lmdb.query(filter).await?;
            for event in lmdb_events {
                events.insert(event);
            }
            Ok(events)
        })
    }

    fn negentropy_items(
        &self,
        filter: Filter,
    ) -> BoxedFuture<'_, Result<Vec<(EventId, Timestamp)>, DatabaseError>> {
        Box::pin(async move {
            if filter_kinds_all_persistent(&filter) {
                return self.lmdb.negentropy_items(filter).await;
            }
            if filter_kinds_all_ephemeral(&filter) {
                return self.memory.negentropy_items(filter).await;
            }
            let mut items = self.memory.negentropy_items(filter.clone()).await?;
            let lmdb_items = self.lmdb.negentropy_items(filter).await?;
            items.extend(lmdb_items);
            Ok(items)
        })
    }

    fn delete(&self, filter: Filter) -> BoxedFuture<'_, Result<(), DatabaseError>> {
        Box::pin(async move {
            self.memory.delete(filter.clone()).await?;
            self.lmdb.delete(filter).await?;
            Ok(())
        })
    }

    fn wipe(&self) -> BoxedFuture<'_, Result<(), DatabaseError>> {
        Box::pin(async move {
            self.memory.wipe().await?;
            // nostr-lmdb 0.44 clears the unnamed database during wipe, invalidating
            // its named database handles. Delete event batches to preserve the schema.
            loop {
                let events = self.lmdb.query(Filter::new().limit(500)).await?;
                if events.is_empty() {
                    break;
                }
                let ids: Vec<EventId> = events.into_iter().map(|event| event.id).collect();
                self.lmdb.delete(Filter::new().ids(ids)).await?;
            }
            Ok(())
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn mixed_queries_preserve_order_and_limit_and_wipe_allows_reuse() {
        let path = std::env::temp_dir().join(format!("qiqstr-lmdb-{}", rand::random::<u64>()));
        std::fs::create_dir(&path).unwrap();
        let db = HybridDatabase::new(
            NostrLMDB::builder(&path)
                .map_size(16 * 1024 * 1024)
                .build()
                .unwrap(),
        );
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
            db.save_event(&event).await.unwrap();
        }
        let events = db.query(Filter::new().limit(2)).await.unwrap();
        assert_eq!(events.len(), 2);
        assert_eq!(
            events
                .into_iter()
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
        db.save_event(&fake).await.unwrap();
        assert!(matches!(
            db.save_event(&legitimate).await.unwrap(),
            SaveEventStatus::Rejected(_)
        ));
        db.remove_invalid_replaceable_events().await.unwrap();
        assert!(matches!(
            db.save_event(&legitimate).await.unwrap(),
            SaveEventStatus::Success
        ));
        assert!(db.event_by_id(&fake.id).await.unwrap().is_none());
        db.wipe().await.unwrap();
        assert_eq!(db.count(Filter::new()).await.unwrap(), 0);
        let event = EventBuilder::text_note("after wipe")
            .sign_with_keys(&keys)
            .unwrap();
        assert!(matches!(
            db.save_event(&event).await.unwrap(),
            SaveEventStatus::Success
        ));
        assert!(db.event_by_id(&event.id).await.unwrap().is_some());
        drop(db);
        std::fs::remove_dir_all(path).unwrap();
    }
}
