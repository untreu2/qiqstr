import 'package:flutter/foundation.dart';
import '../../models/note_model.dart';
import 'nostr_data_service.dart';

class InteractionBatchLoader {
  final NostrDataService _nostrService;
  final Map<String, DateTime> _lastFetchTime = {};
  static const _fetchCooldown = Duration(minutes: 2);

  InteractionBatchLoader(this._nostrService);

  Future<void> loadInteractionsForNotes(List<NoteModel> visibleNotes) async {
    if (visibleNotes.isEmpty) return;

    final now = DateTime.now();
    final notesToFetch = <NoteModel>[];

    for (final note in visibleNotes) {
      final lastFetch = _lastFetchTime[note.id];
      if (lastFetch == null || now.difference(lastFetch) > _fetchCooldown) {
        notesToFetch.add(note);
        _lastFetchTime[note.id] = now;
      }
    }

    if (notesToFetch.isEmpty) return;

    final noteIds = notesToFetch.map((n) => n.id).toList();
    
    debugPrint('[InteractionBatchLoader] Fetching interactions for ${noteIds.length} notes');
    
    await _nostrService.fetchInteractionsForNotes(noteIds, forceLoad: false);

    if (_lastFetchTime.length > 500) {
      final cutoff = now.subtract(const Duration(hours: 1));
      _lastFetchTime.removeWhere((key, time) => time.isBefore(cutoff));
    }
  }

  Future<void> loadInteractionsForNotesRelayBased(
    List<NoteModel> visibleNotes,
    Map<String, Set<String>> Function(List<NoteModel>) relayHintsExtractor,
  ) async {
    if (visibleNotes.isEmpty) return;

    final now = DateTime.now();
    final notesToFetch = <NoteModel>[];

    for (final note in visibleNotes) {
      final lastFetch = _lastFetchTime[note.id];
      if (lastFetch == null || now.difference(lastFetch) > _fetchCooldown) {
        notesToFetch.add(note);
        _lastFetchTime[note.id] = now;
      }
    }

    if (notesToFetch.isEmpty) return;

    final perRelayNoteIds = relayHintsExtractor(notesToFetch);
    
    debugPrint('[InteractionBatchLoader] Relay-based loading for ${notesToFetch.length} notes across ${perRelayNoteIds.length} relays');

    final noteIds = notesToFetch.map((n) => n.id).toList();
    await _nostrService.fetchInteractionsForNotes(noteIds, forceLoad: false);

    if (_lastFetchTime.length > 500) {
      final cutoff = now.subtract(const Duration(hours: 1));
      _lastFetchTime.removeWhere((key, time) => time.isBefore(cutoff));
    }
  }

  void clear() {
    _lastFetchTime.clear();
  }
}

