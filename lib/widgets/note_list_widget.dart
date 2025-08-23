import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../providers/notes_list_provider.dart';
import '../services/data_service.dart';
import '../theme/theme_manager.dart';
import 'note_widget.dart';

class NoteListWidget extends StatefulWidget {
  final String? scrollRestorationId;

  const NoteListWidget({
    super.key,
    this.scrollRestorationId,
  });

  @override
  State<NoteListWidget> createState() => _NoteListWidgetState();
}

class _NoteListWidgetState extends State<NoteListWidget> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  late final ScrollController _scrollController;

  final Set<String> _interactionsLoaded = <String>{};

  DateTime _lastScrollUpdate = DateTime.now();

  static final Map<String, double> _savedScrollPositions = {};
  String get _scrollKey => widget.scrollRestorationId ?? 'default_scroll';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    final savedPosition = _savedScrollPositions[_scrollKey] ?? 0.0;
    _scrollController = ScrollController(initialScrollOffset: savedPosition);

    _setupScrollListener();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<NotesListProvider>();
      provider.fetchInitialNotes();

      if (savedPosition > 0) {
        _restoreScrollPosition();
      }
    });
  }

  void _restoreScrollPosition() {
    final savedPosition = _savedScrollPositions[_scrollKey] ?? 0.0;
    if (savedPosition > 0 && _scrollController.hasClients) {
      _scrollController.animateTo(
        savedPosition,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused) {
      _saveScrollPosition();
    }
  }

  void _saveScrollPosition() {
    if (_scrollController.hasClients) {
      _savedScrollPositions[_scrollKey] = _scrollController.offset;
    }
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      final now = DateTime.now();
      if (now.difference(_lastScrollUpdate).inMilliseconds < 1000) return;
      _lastScrollUpdate = now;

      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.9) {
        final provider = context.read<NotesListProvider>();
        provider.fetchMoreNotes();
      }
    });
  }

  @override
  void dispose() {
    _saveScrollPosition();

    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _interactionsLoaded.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Selector<NotesListProvider,
        ({List<dynamic> notes, bool isLoading, bool hasError, String? errorMessage, bool isLoadingMore, bool isEmpty})>(
      selector: (context, provider) => (
        notes: provider.notes,
        isLoading: provider.isLoading,
        hasError: provider.hasError,
        errorMessage: provider.errorMessage,
        isLoadingMore: provider.isLoadingMore,
        isEmpty: provider.isEmpty,
      ),
      builder: (context, data, child) {
        if (data.isLoading && data.notes.isEmpty) {
          return _buildInitialLoadingState();
        }

        if (data.hasError) {
          return _buildErrorState(data.errorMessage ?? 'Unknown error');
        }

        if (data.isEmpty) {
          return _buildEmptyState();
        }

        return _buildNotesList(data.notes, data.isLoadingMore);
      },
    );
  }

  Widget _buildInitialLoadingState() {
    return const SliverToBoxAdapter(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading notes...'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return SliverToBoxAdapter(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                'Error loading notes',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                error,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  final provider = context.read<NotesListProvider>();
                  provider.fetchInitialNotes();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const SliverToBoxAdapter(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.note_alt_outlined,
                size: 64,
                color: Colors.grey,
              ),
              SizedBox(height: 16),
              Text(
                'No notes found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Check back later for new content',
                style: TextStyle(
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotesList(List<dynamic> notes, bool isLoadingMore) {
    return SliverList.builder(
      addAutomaticKeepAlives: true,
      addRepaintBoundaries: true,
      itemCount: notes.length + (isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= notes.length) {
          return _buildLoadMoreIndicator();
        }

        final note = notes[index];

        return Container(
          key: ValueKey('note_container_${note.id}'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RepaintBoundary(
                child: _buildNoteItem(note),
              ),
              if (index < notes.length - 1)
                Divider(
                  height: 12,
                  thickness: 1,
                  color: context.colors.border,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoadMoreIndicator() {
    return const Padding(
      padding: EdgeInsets.all(16.0),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildNoteItem(note) {
    return Builder(
      builder: (context) {
        final provider = context.read<NotesListProvider>();
        return NoteWidget(
          key: ValueKey('note_widget_${note.id}'),
          note: note,
          reactionCount: note.reactionCount,
          replyCount: note.replyCount,
          repostCount: note.repostCount,
          dataService: provider.dataService,
          currentUserNpub: provider.npub,
          notesNotifier: provider.dataService.notesNotifier,
          profiles: {},
          isSmallView: true,
        );
      },
    );
  }
}

class NoteListWidgetFactory {
  static Widget create({
    required String npub,
    required DataType dataType,
    DataService? sharedDataService,
    String? scrollRestorationId,
  }) {
    return ChangeNotifierProvider(
      create: (context) => NotesListProvider(
        npub: npub,
        dataType: dataType,
        sharedDataService: sharedDataService,
      ),
      child: NoteListWidget(
        scrollRestorationId: scrollRestorationId ?? '${npub}_${dataType.name}',
      ),
    );
  }
}
