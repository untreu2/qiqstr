import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/services/note_preloader_service.dart';
import 'package:qiqstr/widgets/lazy_note_widget.dart';

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
  late NotePreloaderService _preloaderService;
  final List<NoteModel> _pendingNotes = [];

  List<NoteModel> _cachedFilteredNotes = [];
  NoteListFilterType? _lastFilterType;
  int _lastNotesHash = 0;

  static const int _itemsPerPage = 20;
  int _currentPage = 0;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupInitialService();
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMoreItems();
    }
  }

  void _loadMoreItems() {
    if (_isLoadingMore || _cachedFilteredNotes.isEmpty) return;

    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    });
  }

  Future<void> _setupInitialService() async {
    _currentUserNpub = await _secureStorage.read(key: 'npub');
    if (!mounted || _currentUserNpub == null) return;

    _dataService = _createDataService();
    _preloaderService = NotePreloaderService(_dataService);

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
    _invalidateCache();
    _updateSafely();
  }

  void _invalidateCache() {
    _cachedFilteredNotes.clear();
    _lastFilterType = null;
    _lastNotesHash = 0;
    _currentPage = 0;
  }

  void _updateSafely() {
    if (mounted) setState(() {});
  }

  List<NoteModel> _getFilteredNotes(List<NoteModel> notes) {
    final currentHash = notes.length.hashCode ^ widget.filterType.hashCode;
    if (_lastFilterType == widget.filterType && _lastNotesHash == currentHash && _cachedFilteredNotes.isNotEmpty) {
      return _cachedFilteredNotes;
    }

    List<NoteModel> filtered;
    switch (widget.filterType) {
      case NoteListFilterType.popular:
        final cutoffTime = DateTime.now().subtract(const Duration(hours: 24));
        filtered = notes.where((n) => n.timestamp.isAfter(cutoffTime) && (!n.isReply || n.isRepost)).toList();

        filtered.sort((a, b) {
          final aScore = _calculateEngagementScore(a);
          final bScore = _calculateEngagementScore(b);
          return bScore.compareTo(aScore);
        });
        break;

      case NoteListFilterType.media:
        filtered = notes.where((n) => n.hasMedia && (!n.isReply || n.isRepost)).toList();
        break;

      case NoteListFilterType.latest:
        filtered = notes.where((n) => !n.isReply || n.isRepost).toList();
        break;
    }

    _cachedFilteredNotes = filtered;
    _lastFilterType = widget.filterType;
    _lastNotesHash = currentHash;

    return filtered;
  }

  int _calculateEngagementScore(NoteModel note) {
    return note.reactionCount + note.replyCount + note.repostCount + (note.zapAmount ~/ 1000);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _preloaderService.dispose();
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

        final filteredNotes = _getFilteredNotes(notes);

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

    
        if (filteredNotes.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _preloaderService.preloadNotes(filteredNotes.take(30).toList());
          });
        }

    
        final totalItems = filteredNotes.length;
        final visibleItems = (_currentPage + 1) * _itemsPerPage;
        final itemsToShow = visibleItems > totalItems ? totalItems : visibleItems;
        final displayNotes = filteredNotes.take(itemsToShow).toList();

        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
          
              if (index == displayNotes.length) {
                if (_isLoadingMore && itemsToShow < totalItems) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white38),
                        ),
                      ),
                    ),
                  );
                }
                return null;
              }

              final note = displayNotes[index];
              final isReady = _preloaderService.isNoteReady(note.id);

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isReady)
                    LazyNoteWidget(
                      key: ValueKey(note.id),
                      note: note,
                      dataService: _dataService,
                      currentUserNpub: _currentUserNpub!,
                      notesNotifier: _dataService.notesNotifier,
                      profiles: _dataService.profilesNotifier.value,
                      isSmallView: true,
                    )
                  else
                    _buildLoadingPlaceholder(note),
                  if (index < displayNotes.length - 1)
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      height: 1,
                      width: double.infinity,
                      color: Colors.white24,
                    ),
                ],
              );
            },
            childCount: displayNotes.length + (_isLoadingMore && itemsToShow < totalItems ? 1 : 0),
          ),
        );
      },
    );
  }

  Widget _buildLoadingPlaceholder(NoteModel note) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900]?.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white12,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white38),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 14,
                      width: 120,
                      decoration: BoxDecoration(
                        color: Colors.grey[700],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 12,
                      width: 80,
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          Container(
            height: 16,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[700],
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 16,
            width: MediaQuery.of(context).size.width * 0.7,
            decoration: BoxDecoration(
              color: Colors.grey[700],
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 16,
            width: MediaQuery.of(context).size.width * 0.5,
            decoration: BoxDecoration(
              color: Colors.grey[700],
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          
        ],
      ),
    );
  }
}
