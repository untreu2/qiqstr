import '../local/cache_config.dart';
import '../services/isar_database_service.dart';
import '../../models/event_model.dart';

class ReplacementHandler {
  final IsarDatabaseService _db;

  ReplacementHandler(this._db);

  Future<SaveDecision> shouldSave(EventModel incoming) async {
    final kind = incoming.kind;

    if (CacheConfig.isRegularEvent(kind)) {
      final exists = await _eventExists(incoming.eventId);
      return exists ? const SkipDecision() : const InsertDecision();
    }

    if (CacheConfig.isReplaceable(kind)) {
      return await _checkReplaceable(incoming);
    }

    if (CacheConfig.isParameterizedReplaceable(kind)) {
      return await _checkParameterizedReplaceable(incoming);
    }

    final exists = await _eventExists(incoming.eventId);
    return exists ? const SkipDecision() : const InsertDecision();
  }

  Future<SaveDecision> _checkReplaceable(EventModel incoming) async {
    final existing = await _db.getLatestByPubkeyAndKind(
      incoming.pubkey,
      incoming.kind,
    );

    if (existing == null) return const InsertDecision();
    if (incoming.createdAt > existing.createdAt) {
      return ReplaceDecision(existing.id);
    }
    return const SkipDecision();
  }

  Future<SaveDecision> _checkParameterizedReplaceable(
      EventModel incoming) async {
    final dTag = incoming.dTag ?? '';
    final existing = await _db.getLatestByPubkeyKindAndDTag(
      incoming.pubkey,
      incoming.kind,
      dTag,
    );

    if (existing == null) return const InsertDecision();
    if (incoming.createdAt > existing.createdAt) {
      return ReplaceDecision(existing.id);
    }
    return const SkipDecision();
  }

  Future<bool> _eventExists(String eventId) async {
    return await _db.eventExists(eventId);
  }
}

sealed class SaveDecision {
  const SaveDecision();
}

class SkipDecision extends SaveDecision {
  const SkipDecision();
}

class InsertDecision extends SaveDecision {
  const InsertDecision();
}

class ReplaceDecision extends SaveDecision {
  final int existingId;
  const ReplaceDecision(this.existingId);
}
