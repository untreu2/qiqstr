import 'package:flutter/material.dart';
import 'dart:collection';
import 'package:qiqstr/models/note_model.dart';
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
  bool _isLoadingOlderNotes = false;

  @override
  void initState() {
    super.initState();
    _itemsTree = SplayTreeSet<NoteModel>(_compareNotes);
    _notesNotifier = ValueNotifier<List<NoteModel>>([]);
    _dataService = DataService(
      npub: widget.npub,
      dataType: widget.dataType,
      onNewNote: _handleNewNote,
      onReactionsUpdated: (noteId, reactions) => setState(() {}),
      onRepliesUpdated: (noteId, replies) => setState(() {}),
      onReactionCountUpdated: (noteId, count) => setState(() {}),
      onReplyCountUpdated: (noteId, count) => setState(() {}),
      onRepostsUpdated: (noteId, reposts) => setState(() {}),
      onRepostCountUpdated: (noteId, count) => setState(() {}),
    );
    _initialize();
  }

  int _compareNotes(NoteModel a, NoteModel b) {
    DateTime aTime =
        a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
    DateTime bTime =
        b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
    int result = bTime.compareTo(aTime);
    if (result == 0) {
      return a.id.compareTo(b.id);
    }
    return result;
  }

  Future<void> _initialize() async {
    try {
      await _dataService.initialize();
      await _dataService.loadNotesFromCache((cachedNotes) {
        _itemsTree
          ..clear()
          ..addAll(cachedNotes);
        _notesNotifier.value = _itemsTree.toList();
      });
      await _dataService.initializeConnections();
    } catch (e) {
      _showErrorSnackBar('Failed to initialize: $e');
    } finally {
      setState(() => _isInitializing = false);
    }
  }

  void _handleNewNote(NoteModel newNote) {
    if (_itemsTree.add(newNote)) {
      _notesNotifier.value = _itemsTree.toList();
    }
  }

  Future<void> _loadOlderNotes() async {
    if (_isLoadingOlderNotes) return;
    setState(() => _isLoadingOlderNotes = true);
    try {
      await _dataService.fetchOlderNotes(
        widget.dataType == DataType.Feed
            ? await _dataService.getFollowingList(widget.npub)
            : [widget.npub],
        (olderNote) {
          if (_itemsTree.add(olderNote)) {
            _notesNotifier.value = _itemsTree.toList();
          }
        },
      );
    } catch (e) {
      _showErrorSnackBar('Error loading older notes: $e');
    } finally {
      setState(() => _isLoadingOlderNotes = false);
    }
  }

  void _showErrorSnackBar(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
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
      return const Center(child: CircularProgressIndicator());
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (scrollInfo) {
        if (!_isLoadingOlderNotes &&
            scrollInfo.metrics.pixels >=
                scrollInfo.metrics.maxScrollExtent - 200) {
          _loadOlderNotes();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: _initialize,
        child: ValueListenableBuilder<List<NoteModel>>(
          valueListenable: _notesNotifier,
          builder: (context, notes, child) {
            return ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: notes.length + (_isLoadingOlderNotes ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == notes.length && _isLoadingOlderNotes) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final note = notes[index];
                return NoteWidget(
                  key: ValueKey(note.id),
                  note: note,
                  dataService: _dataService,
                );
              },
            );
          },
        ),
      ),
    );
  }
}
