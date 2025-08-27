import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/note_model.dart';
import '../services/data_service.dart';
import '../services/hive_manager.dart';

class NoteNotifier extends ChangeNotifier {
  NoteModel _note;

  NoteNotifier(this._note);

  NoteModel get note => _note;

  void updateNote(NoteModel newNote) {
    if (_note.id == newNote.id) {
      if (_note != newNote) {
        _note = newNote;
        notifyListeners();
      }
    }
  }

  void updateInteractionCounts({
    int? reactionCount,
    int? replyCount,
    int? repostCount,
    int? zapAmount,
  }) {
    bool hasChanges = false;
    if (reactionCount != null && _note.reactionCount != reactionCount) {
      _note.reactionCount = reactionCount;
      hasChanges = true;
    }
    if (replyCount != null && _note.replyCount != replyCount) {
      _note.replyCount = replyCount;
      hasChanges = true;
    }
    if (repostCount != null && _note.repostCount != repostCount) {
      _note.repostCount = repostCount;
      hasChanges = true;
    }
    if (zapAmount != null && _note.zapAmount != zapAmount) {
      _note.zapAmount = zapAmount;
      hasChanges = true;
    }

    if (hasChanges) {
      notifyListeners();
    }
  }
}

class NotesProvider extends ChangeNotifier {
  static NotesProvider? _instance;
  static NotesProvider get instance => _instance ??= NotesProvider._internal();

  NotesProvider._internal();

  Timer? _periodicTimer;

  final Map<String, NoteNotifier> _notifiers = {};
  final Map<String, List<String>> _notesByAuthor = {};
  final Map<String, List<String>> _repliesByParent = {};
  final Set<String> _loadingNotes = {};
  bool _isInitialized = false;
  final HiveManager _hiveManager = HiveManager.instance;
  String? _currentNpub;

  bool get isInitialized => _isInitialized;

  Box<NoteModel>? _feedNotesBox;
  Box<NoteModel>? _profileNotesBox;

  final ValueNotifier<int> _newNoteCountNotifier = ValueNotifier<int>(0);
  ValueListenable<int> get newNoteCountNotifier => _newNoteCountNotifier;

  Future<void> initialize(String npub) async {
    if (_isInitialized && _currentNpub == npub) return;

    try {
      if (!_hiveManager.isInitialized) {
        await _hiveManager.initializeBoxes();
      }

      final boxFutures = [
        Hive.openBox<NoteModel>('notes_Feed_$npub'),
        Hive.openBox<NoteModel>('notes_Profile_$npub'),
      ];

      final boxes = await Future.wait(boxFutures);
      _feedNotesBox = boxes[0];
      _profileNotesBox = boxes[1];

      await _loadNotesFromHiveOptimized();

      _currentNpub = npub;
      _isInitialized = true;

      Timer(const Duration(seconds: 1), () {
        notifyListeners();
        _startPeriodicUpdates();
      });
    } catch (e) {
      debugPrint('[NotesProvider] Initialization error: $e');
    }
  }

  Future<void> _loadNotesFromHiveOptimized() async {
    final loadingFutures = <Future>[];

    void processNotes(Iterable<NoteModel> notes) {
      for (final note in notes) {
        _addNoteToCache(note);
      }
    }

    if (_feedNotesBox != null) {
      loadingFutures.add(Future.microtask(() => processNotes(_feedNotesBox!.values)));
    }

    if (_profileNotesBox != null) {
      loadingFutures.add(Future.microtask(() => processNotes(_profileNotesBox!.values)));
    }

    await Future.wait(loadingFutures);
  }

  void _addNoteToCache(NoteModel note) {
    if (_notifiers.containsKey(note.id)) {
      _notifiers[note.id]!.updateNote(note);
    } else {
      _notifiers[note.id] = NoteNotifier(note);

      _notesByAuthor.putIfAbsent(note.author, () => []).add(note.id);
      if (note.isReply && note.parentId != null) {
        _repliesByParent.putIfAbsent(note.parentId!, () => []).add(note.id);
      }
    }
  }

  NoteNotifier? getNote(String noteId) {
    return _notifiers[noteId];
  }

  List<NoteNotifier> getNotesByAuthor(String authorNpub) {
    final noteIds = _notesByAuthor[authorNpub] ?? [];
    return noteIds.map((id) => _notifiers[id]).whereType<NoteNotifier>().toList()
      ..sort((a, b) => b.note.timestamp.compareTo(a.note.timestamp));
  }

  List<NoteNotifier> getRepliesForNote(String noteId) {
    final replyIds = _repliesByParent[noteId] ?? [];
    return replyIds.map((id) => _notifiers[id]).whereType<NoteNotifier>().toList()
      ..sort((a, b) => a.note.timestamp.compareTo(b.note.timestamp));
  }

  List<NoteNotifier> getAllNotes() {
    return _notifiers.values.toList()..sort((a, b) => b.note.timestamp.compareTo(a.note.timestamp));
  }

  List<NoteNotifier> getFeedNotes() {
    return _notifiers.values.where((notifier) => !notifier.note.isReply || notifier.note.isRepost).toList()
      ..sort((a, b) => b.note.timestamp.compareTo(a.note.timestamp));
  }

  List<NoteNotifier> getMediaNotes() {
    return _notifiers.values.where((notifier) => notifier.note.hasMedia && (!notifier.note.isReply || notifier.note.isRepost)).toList()
      ..sort((a, b) => b.note.timestamp.compareTo(a.note.timestamp));
  }

  Future<void> addNote(NoteModel note, {DataType? dataType}) async {
    final wasNewNote = !_notifiers.containsKey(note.id);
    _addNoteToCache(note);

    try {
      if (dataType == DataType.feed && _feedNotesBox != null) {
        await _feedNotesBox!.put(note.id, note);
      } else if (dataType == DataType.profile && _profileNotesBox != null) {
        await _profileNotesBox!.put(note.id, note);
      }
    } catch (e) {}

    if (wasNewNote) {
      _newNoteCountNotifier.value++;
    }
  }

  Future<void> addNotes(List<NoteModel> notes, {DataType? dataType}) async {
    bool hasNewNotes = false;

    for (final note in notes) {
      if (!_notifiers.containsKey(note.id)) {
        hasNewNotes = true;
      }
      _addNoteToCache(note);
    }

    try {
      if (dataType == DataType.feed && _feedNotesBox != null) {
        final notesMap = {for (var note in notes) note.id: note};
        await _feedNotesBox!.putAll(notesMap);
      } else if (dataType == DataType.profile && _profileNotesBox != null) {
        final notesMap = {for (var note in notes) note.id: note};
        await _profileNotesBox!.putAll(notesMap);
      }
    } catch (e) {}

    if (hasNewNotes) {
      _newNoteCountNotifier.value += notes.length;
    }
  }

  void updateNote(NoteModel note) {
    getNote(note.id)?.updateNote(note);
  }

  void updateNoteInteractionCounts(
    String noteId, {
    int? reactionCount,
    int? replyCount,
    int? repostCount,
    int? zapAmount,
  }) {
    getNote(noteId)?.updateInteractionCounts(
      reactionCount: reactionCount,
      replyCount: replyCount,
      repostCount: repostCount,
      zapAmount: zapAmount,
    );
  }

  void removeNote(String noteId) {
    final noteNotifier = _notifiers.remove(noteId);
    if (noteNotifier != null) {
      final note = noteNotifier.note;
      _notesByAuthor[note.author]?.remove(noteId);

      if (note.parentId != null) {
        _repliesByParent[note.parentId!]?.remove(noteId);
      }

      notifyListeners();
    }
  }

  void clearCache() {
    _notifiers.clear();
    _notesByAuthor.clear();
    _repliesByParent.clear();
    _loadingNotes.clear();

    NoteModel.clearParseCache();
    notifyListeners();
  }

  void _startPeriodicUpdates() {
    _periodicTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();

    _feedNotesBox?.close();
    _profileNotesBox?.close();

    _notifiers.values.forEach((notifier) => notifier.dispose());
    _newNoteCountNotifier.dispose();

    clearCache();
    super.dispose();
  }
}
