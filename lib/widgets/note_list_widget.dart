import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/notes_list_provider.dart';
import '../services/data_service.dart';
import '../theme/theme_manager.dart';
import 'note_widget.dart';

class NoteListWidget extends StatefulWidget {
  const NoteListWidget({super.key});

  @override
  State<NoteListWidget> createState() => _NoteListWidgetState();
}

class _NoteListWidgetState extends State<NoteListWidget> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _setupScrollListener();

    // Trigger initial data fetch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<NotesListProvider>();
      provider.fetchInitialNotes();
    });
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      // Trigger load more when scrolled to 90% of the way down
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.9) {
        final provider = context.read<NotesListProvider>();
        provider.fetchMoreNotes();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NotesListProvider>(
      builder: (context, provider, child) {
        // Show initial loading state
        if (provider.isLoading && provider.notes.isEmpty) {
          return _buildInitialLoadingState();
        }

        // Show error state
        if (provider.hasError) {
          return _buildErrorState(provider.errorMessage ?? 'Unknown error');
        }

        // Show empty state
        if (provider.isEmpty) {
          return _buildEmptyState();
        }

        // Show notes list
        return _buildNotesList(provider);
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

  Widget _buildNotesList(NotesListProvider provider) {
    final notes = provider.notes;

    return SliverList.separated(
      itemCount: notes.length + (provider.isLoadingMore ? 1 : 0),
      separatorBuilder: (context, index) => Divider(
        height: 12,
        thickness: 1,
        color: context.colors.border,
      ),
      itemBuilder: (context, index) {
        // Show loading indicator for "load more"
        if (index >= notes.length) {
          return _buildLoadMoreIndicator();
        }

        final note = notes[index];
        return _buildNoteItem(note, provider);
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

  Widget _buildNoteItem(note, NotesListProvider provider) {
    return NoteWidget(
      key: ValueKey(note.id),
      note: note,
      reactionCount: note.reactionCount,
      replyCount: note.replyCount,
      repostCount: note.repostCount,
      dataService: provider.dataService,
      currentUserNpub: provider.npub,
      notesNotifier: provider.dataService.notesNotifier,
      profiles: {}, // Empty since we're using UserProvider globally
      isSmallView: true,
    );
  }
}

/// Factory method to create a NoteListWidget with proper provider setup
class NoteListWidgetFactory {
  static Widget create({
    required String npub,
    required DataType dataType,
    DataService? sharedDataService,
  }) {
    return ChangeNotifierProvider(
      create: (context) => NotesListProvider(
        npub: npub,
        dataType: dataType,
        sharedDataService: sharedDataService,
      ),
      child: const NoteListWidget(),
    );
  }
}
