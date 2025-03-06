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
      onInteractionUpdated: (noteId, kind, interactions) => setState(() {}),
      onInteractionCountUpdated: (noteId, kind, count) => setState(() {}),
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

  bool _shouldDisplay(NoteModel note, List<String> following) {
    if (widget.dataType == DataType.Feed) {
      if (note.isRepost) {
        final rb = note.repostedBy;
        if (rb == null) return false;
        return following.contains(rb);
      } else {
        return following.contains(note.author);
      }
    } else if (widget.dataType == DataType.Profile) {
      if (note.isRepost) {
        return note.repostedBy == widget.npub;
      } else {
        return note.author == widget.npub;
      }
    } else {
      return true;
    }
  }

  Future<void> _initialize() async {
    try {
      await _dataService.initialize();

      List<String> following = [];
      if (widget.dataType == DataType.Feed) {
        following = await _dataService.getFollowingList(widget.npub);
      }

      await _dataService.loadNotesFromCache((cachedNotes) {
        final filtered = cachedNotes
            .where((note) => _shouldDisplay(note, following))
            .toList();

        _itemsTree
          ..clear()
          ..addAll(filtered);

        _notesNotifier.value = _itemsTree.toList();
      });

      await _dataService.initializeConnections();
    } catch (e) {
      _showErrorSnackBar('Failed to initialize: $e');
    } finally {
      setState(() => _isInitializing = false);
    }
  }

  void _handleNewNote(NoteModel newNote) async {
    List<String> following = [];
    if (widget.dataType == DataType.Feed) {
      following = await _dataService.getFollowingList(widget.npub);
    }

    if (!_shouldDisplay(newNote, following)) {
      return;
    }

    if (_itemsTree.add(newNote)) {
      _notesNotifier.value = _itemsTree.toList();
    }
  }

  Future<void> _loadOlderNotes() async {
    if (_isLoadingOlderNotes) return;
    setState(() => _isLoadingOlderNotes = true);
    try {
      final npubsToFetch = widget.dataType == DataType.Feed
          ? await _dataService.getFollowingList(widget.npub)
          : [widget.npub];

      await _dataService.fetchOlderNotes(npubsToFetch, (olderNote) {
        if (_shouldDisplay(olderNote, npubsToFetch)) {
          if (_itemsTree.add(olderNote)) {
            _notesNotifier.value = _itemsTree.toList();
          }
        }
      });
    } catch (e) {
      _showErrorSnackBar('Error loading older notes: $e');
    } finally {
      setState(() => _isLoadingOlderNotes = false);
    }
  }

  void _showErrorSnackBar(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
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
