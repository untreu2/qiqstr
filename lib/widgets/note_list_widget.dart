import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/widgets/note_widget.dart';

enum NoteListFilterType {
  latest,
  popular,
  media,
}

class NoteListWidget extends StatefulWidget {
  final String npub;
  final DataType dataType;
  final NoteListFilterType filterType;

  const NoteListWidget({
    super.key,
    required this.npub,
    required this.dataType,
    this.filterType = NoteListFilterType.latest,
  });

  @override
  State<NoteListWidget> createState() => _NoteListWidgetState();
}


class _NoteListWidgetState extends State<NoteListWidget> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final ScrollController _scrollController = ScrollController();

  String? _currentUserNpub;
  bool _isInitializing = true;
  bool _preloadDone = false;

  late DataService _dataService;
  final List<NoteModel> _pendingNotes = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupInitialService();
    });
  }

  Future<void> _setupInitialService() async {
    _currentUserNpub = await _secureStorage.read(key: 'npub');
    if (!mounted || _currentUserNpub == null) return;

    _dataService = _createDataService();

    await _dataService.initialize();
    _dataService.initializeConnections();

    setState(() {
      _isInitializing = false;
      _preloadDone = true;
    });
  }

  DataService _createDataService() {
    return DataService(
      npub: widget.npub,
      dataType: widget.dataType,
      onNewNote: _handleNewNote,
      onReactionsUpdated: (_, __) => _updateSafely(),
      onRepliesUpdated: (_, __) => _updateSafely(),
      onRepostsUpdated: (_, __) => _updateSafely(),
      onReactionCountUpdated: (_, __) => _updateSafely(),
      onReplyCountUpdated: (_, __) => _updateSafely(),
      onRepostCountUpdated: (_, __) => _updateSafely(),
    );
  }

  void _handleNewNote(NoteModel note) {
    _pendingNotes.add(note);
    if (_preloadDone) {
      _applyPendingNotes();
    }
  }

  void _applyPendingNotes() {
    for (final note in _pendingNotes) {
      _dataService.addPendingNote(note);
    }
    _dataService.applyPendingNotes();
    _pendingNotes.clear();
    _updateSafely();
  }

  void _updateSafely() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _dataService.closeConnections();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing || _currentUserNpub == null) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text(
              'Loading...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    return ValueListenableBuilder<List<NoteModel>>(
      valueListenable: _dataService.notesNotifier,
      builder: (context, notes, child) {
        if (notes.isEmpty && _preloadDone) {
          return const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No notes available yet.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }

        List<NoteModel> filteredNotes;
        switch (widget.filterType) {
          case NoteListFilterType.popular:
            filteredNotes = notes
                .where((n) =>
                    n.timestamp.isAfter(DateTime.now().subtract(const Duration(hours: 24))) &&
                    (!n.isReply || n.isRepost))
                .toList()
              ..sort((a, b) => (b.reactionCount + b.replyCount + b.repostCount + b.zapAmount)
                  .compareTo(a.reactionCount + a.replyCount + a.repostCount + a.zapAmount));
            break;
          case NoteListFilterType.media:
            filteredNotes = notes.where((n) => n.hasMedia && (!n.isReply || n.isRepost)).toList();
            break;
          case NoteListFilterType.latest:
            filteredNotes = notes.where((n) => !n.isReply || n.isRepost).toList();
            break;
        }

        if (filteredNotes.isEmpty && _preloadDone) {
          return const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No notes match the current filter.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }

        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final note = filteredNotes[index];

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  NoteWidget(
                    key: ValueKey(note.id),
                    note: note,
                    reactionCount: note.reactionCount,
                    replyCount: note.replyCount,
                    repostCount: note.repostCount,
                    dataService: _dataService,
                    currentUserNpub: _currentUserNpub!,
                    notesNotifier: _dataService.notesNotifier,
                    profiles: _dataService.profilesNotifier.value,
                  ),
                  if (index < filteredNotes.length - 1)
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      height: 1,
                      width: double.infinity,
                      color: Colors.white24,
                    ),
                ],
              );
            },
            childCount: filteredNotes.length,
          ),
        );
      },
    );
  }
}
