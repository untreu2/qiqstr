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

  // Getters
  Map<String, NoteModel> get notes => Map.unmodifiable(_notes);
  bool get isInitialized => _isInitialized;

  // Hive boxes
  Box<NoteModel>? _feedNotesBox;
  Box<NoteModel>? _profileNotesBox;

  Future<void> initialize(String npub) async {
    if (_isInitialized) return;

    try {
      // Open Hive boxes in parallel for faster initialization
      final boxFutures = [
        Hive.openBox<NoteModel>('notes_Feed_$npub'),
        Hive.openBox<NoteModel>('notes_Profile_$npub'),
      ];

      final boxes = await Future.wait(boxFutures);
      _feedNotesBox = boxes[0] as Box<NoteModel>;
      _profileNotesBox = boxes[1] as Box<NoteModel>;

      // Load existing notes from Hive in parallel
      await _loadNotesFromHiveOptimized();

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[NotesProvider] Initialization error: $e');
    }
  }

  Future<void> _loadNotesFromHiveOptimized() async {
    final loadingFutures = <Future>[];

    // Load from feed box in background
    if (_feedNotesBox != null) {
      loadingFutures.add(Future.microtask(() {
        final notes = _feedNotesBox!.values.toList();
        for (final note in notes) {
          _addNoteToCache(note);
        }
      }));
    }

    // Load from profile box in background
    if (_profileNotesBox != null) {
      loadingFutures.add(Future.microtask(() {
        final notes = _profileNotesBox!.values.toList();
        for (final note in notes) {
          _addNoteToCache(note);
        }
      }));
    }

    // Wait for all loading operations to complete
    await Future.wait(loadingFutures);
  }

  void _addNoteToCache(NoteModel note) {
    _notes[note.id] = note;

    // Index by author
    _notesByAuthor.putIfAbsent(note.author, () => []);
    if (!_notesByAuthor[note.author]!.contains(note.id)) {
      _notesByAuthor[note.author]!.add(note.id);
    }

    // Index replies
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
    _addNoteToCache(note);

    // Save to appropriate Hive box
    try {
      if (dataType == DataType.feed && _feedNotesBox != null) {
        await _feedNotesBox!.put(note.id, note);
      } else if (dataType == DataType.profile && _profileNotesBox != null) {
        await _profileNotesBox!.put(note.id, note);
      }
    } catch (e) {
      debugPrint('[NotesProvider] Error saving note to Hive: $e');
    }

    notifyListeners();
  }

  Future<void> addNotes(List<NoteModel> notes, {DataType? dataType}) async {
    for (final note in notes) {
      _addNoteToCache(note);
    }

    // Batch save to Hive
    try {
      if (dataType == DataType.feed && _feedNotesBox != null) {
        final notesMap = {for (var note in notes) note.id: note};
        await _feedNotesBox!.putAll(notesMap);
      } else if (dataType == DataType.profile && _profileNotesBox != null) {
        final notesMap = {for (var note in notes) note.id: note};
        await _profileNotesBox!.putAll(notesMap);
      }
    } catch (e) {
      debugPrint('[NotesProvider] Error batch saving notes to Hive: $e');
    }

    notifyListeners();
  }

  void updateNote(NoteModel note) {
    if (_notes.containsKey(note.id)) {
      _notes[note.id] = note;
      notifyListeners();
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
      final updatedNote = NoteModel(
        id: note.id,
        content: note.content,
        author: note.author,
        timestamp: note.timestamp,
        isRepost: note.isRepost,
        repostedBy: note.repostedBy,
        repostTimestamp: note.repostTimestamp,
        repostCount: repostCount ?? note.repostCount,
        rawWs: note.rawWs,
        reactionCount: reactionCount ?? note.reactionCount,
        replyCount: replyCount ?? note.replyCount,
        parsedContent: note.parsedContent,
        hasMedia: note.hasMedia,
        estimatedHeight: note.estimatedHeight,
        isVideo: note.isVideo,
        videoUrl: note.videoUrl,
        zapAmount: zapAmount ?? note.zapAmount,
        isReply: note.isReply,
        parentId: note.parentId,
        rootId: note.rootId,
        replyIds: note.replyIds,
      );

      _notes[noteId] = updatedNote;
      notifyListeners();
    }
  }

  void removeNote(String noteId) {
    final note = _notes.remove(noteId);
    if (note != null) {
      // Remove from author index
      _notesByAuthor[note.author]?.remove(noteId);

      // Remove from replies index
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
    notifyListeners();
  }

  Map<String, dynamic> getStats() {
    return {
      'totalNotes': _notes.length,
      'notesByAuthor': _notesByAuthor.length,
      'repliesIndexed': _repliesByParent.length,
      'loadingNotes': _loadingNotes.length,
      'isInitialized': _isInitialized,
    };
  }

  @override
  void dispose() {
    _feedNotesBox?.close();
    _profileNotesBox?.close();
    super.dispose();
  }
}
