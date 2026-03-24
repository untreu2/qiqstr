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
            max_events: None,
        });
        Self { lmdb, memory }
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
            self.lmdb.wipe().await?;
            Ok(())
        })
    }
}
