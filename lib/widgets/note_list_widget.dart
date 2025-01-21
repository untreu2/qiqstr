import 'package:flutter/material.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/models/reaction_model.dart';
import 'package:qiqstr/models/reply_model.dart';
import 'package:qiqstr/services/qiqstr_service.dart';
import 'package:qiqstr/widgets/note_widget.dart';

class NoteListWidget extends StatefulWidget {
  final String npub;
  final DataType dataType;

  const NoteListWidget({
    Key? key,
    required this.npub,
    required this.dataType,
  }) : super(key: key);

  @override
  _NoteListWidgetState createState() => _NoteListWidgetState();
}

class _NoteListWidgetState extends State<NoteListWidget> {
  final List<NoteModel> _items = [];
  late DataService _dataService;
  final ScrollController _scrollController = ScrollController();
  bool _isInitializing = true;
  bool _isLoadingOlderNotes = false;
  Map<String, int> _reactionCounts = {};
  Map<String, int> _replyCounts = {};

  @override
  void initState() {
    super.initState();
    _dataService = DataService(
      npub: widget.npub,
      dataType: widget.dataType,
      onNewNote: _handleNewNote,
      onReactionsUpdated: _handleReactionsUpdated,
      onRepliesUpdated: _handleRepliesUpdated,
      onReactionCountUpdated: _updateReactionCount,
      onReplyCountUpdated: _updateReplyCount,
    );
    _initialize();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _initialize() async {
    try {
      await _dataService.initialize();
      await _dataService.loadNotesFromCache((cachedNotes) {
        setState(() {
          _items.clear();
          _items.addAll(cachedNotes);
          _sortNotes();

          for (var note in _items) {
            _reactionCounts[note.id] = _dataService.reactionsMap[note.id]?.length ?? 0;
            _replyCounts[note.id] = _dataService.repliesMap[note.id]?.length ?? 0;
          }
        });
      });
      await _dataService.initializeConnections();
    } catch (e) {
      _showErrorSnackBar('Failed to initialize: $e');
    } finally {
      setState(() => _isInitializing = false);
    }
  }

  void _handleNewNote(NoteModel newNote) {
    setState(() {
      _items.insert(0, newNote);
      _sortNotes();
      _reactionCounts[newNote.id] = 0;
      _replyCounts[newNote.id] = 0;
    });
  }

  void _sortNotes() {
    _items.sort((a, b) {
      DateTime aTimestamp =
          a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
      DateTime bTimestamp =
          b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
      return bTimestamp.compareTo(aTimestamp);
    });

    debugPrint('Notes sorted:');
    for (var note in _items) {
      debugPrint(
          'ID: ${note.id}, Timestamp: ${note.timestamp}, Repost: ${note.repostTimestamp}');
    }
  }

  void _handleReactionsUpdated(String noteId, List<ReactionModel> reactions) {
    setState(() {
      _reactionCounts[noteId] = reactions.length;
    });
  }

  void _handleRepliesUpdated(String noteId, List<ReplyModel> replies) {
    setState(() {
      _replyCounts[noteId] = replies.length;
    });
  }

  void _updateReactionCount(String noteId, int count) {
    setState(() {
      _reactionCounts[noteId] = count;
    });
  }

  void _updateReplyCount(String noteId, int count) {
    setState(() {
      _replyCounts[noteId] = count;
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingOlderNotes) {
      _loadOlderNotes();
    }
  }

  Future<void> _loadOlderNotes() async {
    setState(() => _isLoadingOlderNotes = true);
    try {
      await _dataService.fetchOlderNotes(widget.dataType == DataType.Feed
          ? await _dataService.getFollowingList(widget.npub)
          : [widget.npub], (olderNote) {
        setState(() {
          _items.add(olderNote);
          _sortNotes();
          _reactionCounts[olderNote.id] = 0;
          _replyCounts[olderNote.id] = 0;
        });
      });
    } catch (e) {
      _showErrorSnackBar('Error loading older notes: $e');
    } finally {
      setState(() => _isLoadingOlderNotes = false);
    }
  }

  void _showErrorSnackBar(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _dataService.closeConnections();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _initialize,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _items.length + (_isLoadingOlderNotes ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _items.length && _isLoadingOlderNotes) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final item = _items[index];
          return NoteWidget(
            key: ValueKey(item.id),
            note: item,
            reactionCount: _reactionCounts[item.id] ?? 0,
            replyCount: _replyCounts[item.id] ?? 0,
            dataService: _dataService,
          );
        },
      ),
    );
  }
}
