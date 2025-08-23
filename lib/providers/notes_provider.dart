import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/note_model.dart';
import '../services/data_service.dart';

class NotesProvider extends ChangeNotifier {
  static NotesProvider? _instance;
  static NotesProvider get instance => _instance ??= NotesProvider._internal();

  NotesProvider._internal();

  final Map<String, NoteModel> _notes = {};
  final Map<String, List<String>> _notesByAuthor = {};
  final Map<String, List<String>> _repliesByParent = {};
  final Set<String> _loadingNotes = {};
  bool _isInitialized = false;

  Map<String, NoteModel> get notes => Map.unmodifiable(_notes);
  bool get isInitialized => _isInitialized;

  Box<NoteModel>? _feedNotesBox;
  Box<NoteModel>? _profileNotesBox;

  Future<void> initialize(String npub) async {
    if (_isInitialized) return;

    try {
      final boxFutures = [
        Hive.openBox<NoteModel>('notes_Feed_$npub'),
        Hive.openBox<NoteModel>('notes_Profile_$npub'),
      ];

      final boxes = await Future.wait(boxFutures);
      _feedNotesBox = boxes[0];
      _profileNotesBox = boxes[1];

      await _loadNotesFromHiveOptimized();

      _isInitialized = true;
      notifyListeners();
    } catch (e) {}
  }

  Future<void> _loadNotesFromHiveOptimized() async {
    final loadingFutures = <Future>[];

    if (_feedNotesBox != null) {
      loadingFutures.add(Future.microtask(() {
        final notes = _feedNotesBox!.values.toList();
        for (final note in notes) {
          _addNoteToCache(note);
        }
      }));
    }

    if (_profileNotesBox != null) {
      loadingFutures.add(Future.microtask(() {
        final notes = _profileNotesBox!.values.toList();
        for (final note in notes) {
          _addNoteToCache(note);
        }
      }));
    }

    await Future.wait(loadingFutures);
  }

  void _addNoteToCache(NoteModel note) {
    _notes[note.id] = note;

    _notesByAuthor.putIfAbsent(note.author, () => []);
    if (!_notesByAuthor[note.author]!.contains(note.id)) {
      _notesByAuthor[note.author]!.add(note.id);
    }

    if (note.isReply && note.parentId != null) {
      _repliesByParent.putIfAbsent(note.parentId!, () => []);
      if (!_repliesByParent[note.parentId!]!.contains(note.id)) {
        _repliesByParent[note.parentId!]!.add(note.id);
      }
    }
  }

  NoteModel? getNote(String noteId) {
    return _notes[noteId];
  }

  List<NoteModel> getNotesByAuthor(String authorNpub) {
    final noteIds = _notesByAuthor[authorNpub] ?? [];
    return noteIds.map((id) => _notes[id]).whereType<NoteModel>().toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  List<NoteModel> getRepliesForNote(String noteId) {
    final replyIds = _repliesByParent[noteId] ?? [];
    return replyIds.map((id) => _notes[id]).whereType<NoteModel>().toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  List<NoteModel> getAllNotes() {
    return _notes.values.toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  List<NoteModel> getFeedNotes() {
    return _notes.values.where((note) => !note.isReply || note.isRepost).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  List<NoteModel> getMediaNotes() {
    return _notes.values.where((note) => note.hasMedia && (!note.isReply || note.isRepost)).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Future<void> addNote(NoteModel note, {DataType? dataType}) async {
    final wasNewNote = !_notes.containsKey(note.id);
    _addNoteToCache(note);

    try {
      if (dataType == DataType.feed && _feedNotesBox != null) {
        await _feedNotesBox!.put(note.id, note);
      } else if (dataType == DataType.profile && _profileNotesBox != null) {
        await _profileNotesBox!.put(note.id, note);
      }
    } catch (e) {}

    if (wasNewNote) {
      notifyListeners();
    }
  }

  Future<void> addNotes(List<NoteModel> notes, {DataType? dataType}) async {
    bool hasNewNotes = false;

    for (final note in notes) {
      if (!_notes.containsKey(note.id)) {
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
      notifyListeners();
    }
  }

  void updateNote(NoteModel note) {
    if (_notes.containsKey(note.id)) {
      final oldNote = _notes[note.id]!;
      _notes[note.id] = note;

      if (oldNote.reactionCount != note.reactionCount ||
          oldNote.replyCount != note.replyCount ||
          oldNote.repostCount != note.repostCount ||
          oldNote.zapAmount != note.zapAmount ||
          oldNote.content != note.content) {
        notifyListeners();
      }
    }
  }

  void updateNoteInteractionCounts(
    String noteId, {
    int? reactionCount,
    int? replyCount,
    int? repostCount,
    int? zapAmount,
  }) {
    final note = _notes[noteId];
    if (note != null) {
      bool hasChanges = false;

      if (reactionCount != null && note.reactionCount != reactionCount) {
        note.reactionCount = reactionCount;
        hasChanges = true;
      }
      if (replyCount != null && note.replyCount != replyCount) {
        note.replyCount = replyCount;
        hasChanges = true;
      }
      if (repostCount != null && note.repostCount != repostCount) {
        note.repostCount = repostCount;
        hasChanges = true;
      }
      if (zapAmount != null && note.zapAmount != zapAmount) {
        note.zapAmount = zapAmount;
        hasChanges = true;
      }

      if (hasChanges) {
        notifyListeners();
      }
    }
  }

  void removeNote(String noteId) {
    final note = _notes.remove(noteId);
    if (note != null) {
      _notesByAuthor[note.author]?.remove(noteId);

      if (note.parentId != null) {
        _repliesByParent[note.parentId!]?.remove(noteId);
      }

      notifyListeners();
    }
  }

  void clearCache() {
    _notes.clear();
    _notesByAuthor.clear();
    _repliesByParent.clear();
    _loadingNotes.clear();

    NoteModel.clearParseCache();
    notifyListeners();
  }

  @override
  void dispose() {
    _feedNotesBox?.close();
    _profileNotesBox?.close();

    clearCache();

    super.dispose();
  }
}
