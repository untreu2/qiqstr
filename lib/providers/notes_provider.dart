import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/note_model.dart';
import '../services/data_service.dart';
import '../services/hive_manager.dart';
import 'base_provider.dart';

class OptimizedNoteStorage {
  final SplayTreeSet<NoteNotifier> _sortedNotes;
  final Map<String, SplayTreeSet<NoteNotifier>> _authorIndex;
  final Map<String, SplayTreeSet<NoteNotifier>> _replyIndex;

  OptimizedNoteStorage(int Function(NoteNotifier, NoteNotifier) compare)
      : _sortedNotes = SplayTreeSet(compare),
        _authorIndex = {},
        _replyIndex = {};

  void add(NoteNotifier notifier) {
    _sortedNotes.add(notifier);

    final note = notifier.note;
    _authorIndex.putIfAbsent(note.author, () => SplayTreeSet(_compareNotesDesc)).add(notifier);

    if (note.isReply && note.parentId != null) {
      _replyIndex.putIfAbsent(note.parentId!, () => SplayTreeSet(_compareNotesAsc)).add(notifier);
    }
  }

  bool remove(NoteNotifier notifier) {
    final removed = _sortedNotes.remove(notifier);
    if (removed) {
      final note = notifier.note;
      _authorIndex[note.author]?.remove(notifier);
      if (_authorIndex[note.author]?.isEmpty ?? false) {
        _authorIndex.remove(note.author);
      }

      if (note.parentId != null) {
        _replyIndex[note.parentId!]?.remove(notifier);
        if (_replyIndex[note.parentId!]?.isEmpty ?? false) {
          _replyIndex.remove(note.parentId!);
        }
      }
    }
    return removed;
  }

  void clear() {
    _sortedNotes.clear();
    _authorIndex.clear();
    _replyIndex.clear();
  }

  List<NoteNotifier> get allNotes => _sortedNotes.toList();
  List<NoteNotifier> notesByAuthor(String author) => _authorIndex[author]?.toList() ?? [];
  List<NoteNotifier> repliesForNote(String noteId) => _replyIndex[noteId]?.toList() ?? [];

  static int _compareNotesDesc(NoteNotifier a, NoteNotifier b) => b.note.timestamp.compareTo(a.note.timestamp);
  static int _compareNotesAsc(NoteNotifier a, NoteNotifier b) => a.note.timestamp.compareTo(b.note.timestamp);
}

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

class NotesProvider extends BaseProvider with CacheMixin<List<NoteNotifier>> {
  static NotesProvider? _instance;
  static NotesProvider get instance => _instance ??= NotesProvider._internal();

  NotesProvider._internal() {
    _storage = OptimizedNoteStorage(_compareNotesDesc);
  }

  final Map<String, NoteNotifier> _notifiers = {};
  late final OptimizedNoteStorage _storage;
  final Set<String> _loadingNotes = {};
  bool _isInitialized = false;
  final HiveManager _hiveManager = HiveManager.instance;
  String? _currentNpub;

  int _dataVersion = 0;

  bool get isInitialized => _isInitialized;

  static int _compareNotesDesc(NoteNotifier a, NoteNotifier b) => b.note.timestamp.compareTo(a.note.timestamp);
  static int _compareNotesAsc(NoteNotifier a, NoteNotifier b) => a.note.timestamp.compareTo(b.note.timestamp);

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

      createTimer(const Duration(seconds: 1), () {
        safeNotifyListeners();
      });
    } catch (e) {
      handleError('initialization', e);
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
    bool cacheNeedsInvalidation = false;

    if (_notifiers.containsKey(note.id)) {
      final notifier = _notifiers[note.id]!;
      final oldNote = notifier.note;

      final needsReSort = oldNote.timestamp != note.timestamp || oldNote.author != note.author || oldNote.parentId != note.parentId;

      if (needsReSort) {
        _storage.remove(notifier);
        cacheNeedsInvalidation = true;
      }

      notifier.updateNote(note);

      if (needsReSort) {
        _storage.add(notifier);
      }
    } else {
      final notifier = NoteNotifier(note);
      _notifiers[note.id] = notifier;
      _storage.add(notifier);
      cacheNeedsInvalidation = true;
    }

    if (cacheNeedsInvalidation) {
      _dataVersion++;
      invalidateCache();
    }
  }

  NoteNotifier? getNote(String noteId) {
    return _notifiers[noteId];
  }

  List<NoteNotifier> getNotesByAuthor(String authorNpub) {
    return _storage.notesByAuthor(authorNpub);
  }

  List<NoteNotifier> getRepliesForNote(String noteId) {
    return _storage.repliesForNote(noteId);
  }

  List<NoteNotifier> getAllNotes() {
    return getCachedData(_dataVersion, () => _storage.allNotes);
  }

  List<NoteNotifier> getFeedNotes() {
    return getCachedData(
        _dataVersion, () => _storage.allNotes.where((notifier) => !notifier.note.isReply || notifier.note.isRepost).toList());
  }

  List<NoteNotifier> getMediaNotes() {
    return getCachedData(_dataVersion,
        () => _storage.allNotes.where((notifier) => notifier.note.hasMedia && (!notifier.note.isReply || notifier.note.isRepost)).toList());
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
    } catch (e) {
      handleError('saving note to Hive', e);
    }

    if (wasNewNote) {
      _newNoteCountNotifier.value++;
    }
  }

  Future<void> addNotes(List<NoteModel> notes, {DataType? dataType}) async {
    int newNotesCount = 0;

    for (final note in notes) {
      if (!_notifiers.containsKey(note.id)) {
        newNotesCount++;
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
    } catch (e) {
      handleError('saving notes to Hive', e);
    }

    if (newNotesCount > 0) {
      _newNoteCountNotifier.value += newNotesCount;
    }
  }

  void updateNote(NoteModel note) {
    _addNoteToCache(note);
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
      _storage.remove(noteNotifier);
      _dataVersion++;
      invalidateCache();
      safeNotifyListeners();
    }
  }

  void clearCache() {
    _notifiers.clear();
    _storage.clear();
    _loadingNotes.clear();
    _dataVersion++;
    invalidateCache();

    NoteModel.clearParseCache();
    safeNotifyListeners();
  }

  @override
  void dispose() {
    _feedNotesBox?.close();
    _profileNotesBox?.close();

    _notifiers.values.forEach((notifier) => notifier.dispose());
    _newNoteCountNotifier.dispose();

    clearCache();
    super.dispose();
  }
}
