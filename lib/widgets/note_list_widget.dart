import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../theme/theme_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/services/data_service.dart';
import 'package:qiqstr/widgets/note_widget.dart';

enum NoteListFilterType {
  latest,
  media,
}

class NoteListWidget extends StatefulWidget {
  final String npub;
  final DataType dataType;
  final NoteListFilterType filterType;
  final DataService? sharedDataService;

  const NoteListWidget({
    super.key,
    required this.npub,
    required this.dataType,
    this.filterType = NoteListFilterType.latest,
    this.sharedDataService,
  });

  @override
  State<NoteListWidget> createState() => _NoteListWidgetState();
}

class _NoteListWidgetState extends State<NoteListWidget> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final ScrollController _scrollController = ScrollController();
  late DataService _dataService;

  String? _currentUserNpub;
  bool _isInitializing = true;
  bool _isLoadingMore = false;

  List<NoteModel> _filteredNotes = [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAsync();
    });
  }

  @override
  void didUpdateWidget(NoteListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterType != widget.filterType) {
      _updateFilteredNotes(_dataService.notesNotifier.value);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _dataService.notesNotifier.removeListener(_onNotesChanged);

    // Only close connections if we created our own DataService
    if (widget.sharedDataService == null) {
      _dataService.closeConnections();
    }
    super.dispose();
  }

  void _onNotesChanged() {
    if (mounted) {
      _updateFilteredNotes(_dataService.notesNotifier.value);
    }
  }

  Future<void> _initializeAsync() async {
    try {
      _currentUserNpub = await _secureStorage.read(key: 'npub');
      if (!mounted) return;

      // Use shared DataService if available, otherwise create our own
      if (widget.sharedDataService != null) {
        _dataService = widget.sharedDataService!;

        // For shared DataService, ensure it's configured for our npub and dataType
        if (_dataService.npub != widget.npub ||
            _dataService.dataType != widget.dataType) {
          // Create our own DataService if the shared one doesn't match our requirements
          _dataService = _createDataService();
          await _dataService.initializeLightweight();

          // Heavy operations in background
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              _dataService.initializeHeavyOperations().then((_) {
                if (mounted) {
                  _dataService.initializeConnections();
                }
              }).catchError((e) {
                print('[NoteListWidget] Heavy initialization error: $e');
              });
            }
          });
        } else {
          // Shared DataService matches, trigger initial load if needed
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted && _dataService.notesNotifier.value.isEmpty) {
              _dataService.initializeConnections();
            }
          });
        }
      } else {
        _dataService = _createDataService();

        // Lightweight initialization first
        await _dataService.initializeLightweight();

        // Heavy operations in background
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _dataService.initializeHeavyOperations().then((_) {
              if (mounted) {
                _dataService.initializeConnections();
              }
            }).catchError((e) {
              print('[NoteListWidget] Heavy initialization error: $e');
            });
          }
        });
      }

      _dataService.notesNotifier.addListener(_onNotesChanged);

      // Trigger initial update with existing notes
      _updateFilteredNotes(_dataService.notesNotifier.value);

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      print('[NoteListWidget] Initialization error: $e');
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  DataService _createDataService() {
    return DataService(
      npub: widget.npub,
      dataType: widget.dataType,
      onNewNote: (_) {},
      onReactionsUpdated: (_, __) {},
      onRepliesUpdated: (_, __) {},
      onRepostsUpdated: (_, __) {},
      onReactionCountUpdated: (_, __) {},
      onReplyCountUpdated: (_, __) {},
      onRepostCountUpdated: (_, __) {},
    );
  }

  void _onScroll() {
    if (!_isLoadingMore &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent * 0.9) {
      _loadMoreItemsFromNetwork();
    }
  }

  void _loadMoreItemsFromNetwork() {
    if (_isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    _dataService.loadMoreNotes().whenComplete(() {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    });
  }

  Future<void> _updateFilteredNotes(List<NoteModel> notes) async {
    List<NoteModel> filtered;
    switch (widget.filterType) {
      case NoteListFilterType.media:
        filtered = notes
            .where((n) => n.hasMedia && (!n.isReply || n.isRepost))
            .toList();
        break;
      case NoteListFilterType.latest:
        filtered = notes.where((n) => !n.isReply || n.isRepost).toList();
        break;
    }

    if (mounted) {
      setState(() {
        _filteredNotes = filtered;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing || _currentUserNpub == null) {
      return const SliverToBoxAdapter(
        child: Center(
            child: Padding(
                padding: EdgeInsets.all(40.0), child: Text("Loading..."))),
      );
    }

    if (_filteredNotes.isEmpty) {
      return const SliverToBoxAdapter(
        child: Center(
            child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text('No notes found.'))),
      );
    }

    final itemsToShow = _filteredNotes.length;

    return SliverList.separated(
      itemCount: itemsToShow + (_isLoadingMore ? 1 : 0),
      separatorBuilder: (context, index) => Divider(
        height: 12,
        thickness: 1,
        color: context.colors.border,
      ),
      itemBuilder: (context, index) {
        if (index >= itemsToShow) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        }

        final note = _filteredNotes[index];
        return NoteWidget(
          key: ValueKey(note.id),
          note: note,
          reactionCount: note.reactionCount,
          replyCount: note.replyCount,
          repostCount: note.repostCount,
          dataService: _dataService,
          currentUserNpub: _currentUserNpub!,
          notesNotifier: _dataService.notesNotifier,
          profiles: _dataService.profilesNotifier.value,
          isSmallView: true,
        );
      },
    );
  }
}
