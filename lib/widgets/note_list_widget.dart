import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/models/reaction_model.dart';
import 'package:qiqstr/models/reply_model.dart';
import 'package:qiqstr/models/repost_model.dart';
import 'package:qiqstr/services/qiqstr_service.dart';
import 'package:qiqstr/widgets/note_widget.dart';

class NoteListWidget extends StatefulWidget {
  final String npub;
  final DataType dataType;

  const NoteListWidget({
    super.key,
    required this.npub,
    required this.dataType,
  });

  @override
  _NoteListWidgetState createState() => _NoteListWidgetState();
}

class _NoteListWidgetState extends State<NoteListWidget> {
  late SplayTreeSet<NoteModel> _itemsTree;
  late ValueNotifier<List<NoteModel>> _notesNotifier;
  late DataService _dataService;

  bool _isInitializing = true;
  final Map<String, int> _reactionCounts = {};
  final Map<String, int> _replyCounts = {};
  final Map<String, int> _repostCounts = {};

  @override
  void initState() {
    super.initState();
    _itemsTree = SplayTreeSet<NoteModel>(_compareNotes);
    _notesNotifier = ValueNotifier<List<NoteModel>>([]);
    _dataService = DataService(
      npub: widget.npub,
      dataType: widget.dataType,
      onNewNote: _handleNewNote,
      onReactionsUpdated: _handleReactionsUpdated,
      onRepliesUpdated: _handleRepliesUpdated,
      onReactionCountUpdated: _updateReactionCount,
      onReplyCountUpdated: _updateReplyCount,
      onRepostsUpdated: _handleRepostsUpdated,
      onRepostCountUpdated: _updateRepostCount,
    );
    _initialize();
  }

  int _compareNotes(NoteModel a, NoteModel b) {
    DateTime aTime =
        a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
    DateTime bTime =
        b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
    int result = bTime.compareTo(aTime);
    return result == 0 ? a.id.compareTo(b.id) : result;
  }

  Future<void> _initialize() async {
    try {
      await _dataService.initialize();
      await _dataService.loadNotesFromCache((cachedNotes) {
        _itemsTree
          ..clear()
          ..addAll(cachedNotes);
        for (var note in cachedNotes) {
          _reactionCounts[note.id] =
              _dataService.reactionsMap[note.id]?.length ?? 0;
          _replyCounts[note.id] = _dataService.repliesMap[note.id]?.length ?? 0;
          _repostCounts[note.id] =
              _dataService.repostsMap[note.id]?.length ?? 0;
        }
        _notesNotifier.value = _itemsTree.toList();
      });
      await _dataService.initializeConnections();
    } catch (e) {
      _showErrorSnackBar('Failed to initialize: $e');
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  void _handleNewNote(NoteModel newNote) {
    if (_itemsTree.add(newNote)) {
      _reactionCounts[newNote.id] = 0;
      _replyCounts[newNote.id] = 0;
      _repostCounts[newNote.id] = 0;
      _notesNotifier.value = _itemsTree.toList();
    }
  }

  void _handleReactionsUpdated(String noteId, List<ReactionModel> reactions) {
    if (mounted) {
      setState(() {
        _reactionCounts[noteId] = reactions.length;
      });
    }
  }

  void _handleRepliesUpdated(String noteId, List<ReplyModel> replies) {
    if (mounted) {
      setState(() {
        _replyCounts[noteId] = replies.length;
      });
    }
  }

  void _handleRepostsUpdated(String noteId, List<RepostModel> reposts) {
    if (mounted) {
      setState(() {
        _repostCounts[noteId] = reposts.length;
      });
    }
  }

  void _updateReactionCount(String noteId, int count) {
    if (mounted) {
      setState(() {
        _reactionCounts[noteId] = count;
      });
    }
  }

  void _updateReplyCount(String noteId, int count) {
    if (mounted) {
      setState(() {
        _replyCounts[noteId] = count;
      });
    }
  }

  void _updateRepostCount(String noteId, int count) {
    if (mounted) {
      setState(() {
        _repostCounts[noteId] = count;
      });
    }
  }

  void _showErrorSnackBar(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    });
  }

  @override
  void dispose() {
    _dataService.closeConnections();
    _notesNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const SliverToBoxAdapter(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return ValueListenableBuilder<List<NoteModel>>(
      valueListenable: _notesNotifier,
      builder: (context, notes, child) {
        if (notes.isEmpty) {
          return const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "No notes yet.",
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          );
        }
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final note = notes[index];
              return NoteWidget(
                key: ValueKey(note.id),
                note: note,
                reactionCount: _reactionCounts[note.id] ?? 0,
                replyCount: _replyCounts[note.id] ?? 0,
                repostCount: _repostCounts[note.id] ?? 0,
                dataService: _dataService,
                currentUserNpub: widget.npub,
              );
            },
            childCount: notes.length,
          ),
        );
      },
    );
  }
}
