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
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _setupScrollListener();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<NotesListProvider>();
      provider.fetchInitialNotes();
    });
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
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
        if (provider.isLoading && provider.notes.isEmpty) {
          return _buildLoadingState();
        }

        if (provider.hasError) {
          return _buildErrorState(provider.errorMessage ?? 'Unknown error');
        }

        if (provider.isEmpty) {
          return _buildEmptyState();
        }

        return _buildNotesList(provider.notes, provider.isLoadingMore);
      },
    );
  }

  Widget _buildLoadingState() {
    return const SliverToBoxAdapter(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
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
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error loading notes', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(error, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.read<NotesListProvider>().fetchInitialNotes(),
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
              Icon(Icons.note_alt_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('No notes found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
              SizedBox(height: 8),
              Text('Check back later for new content', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotesList(List<dynamic> notes, bool isLoadingMore) {
    return SliverList.builder(
      itemCount: notes.length + (isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= notes.length) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final note = notes[index];
        final provider = context.read<NotesListProvider>();

        return Column(
          children: [
            NoteWidget(
              key: ValueKey('note_${note.id}'),
              note: note,
              reactionCount: note.reactionCount,
              replyCount: note.replyCount,
              repostCount: note.repostCount,
              dataService: provider.dataService,
              currentUserNpub: provider.npub,
              notesNotifier: provider.dataService.notesNotifier,
              profiles: {},
              isSmallView: true,
            ),
            if (index < notes.length - 1) Divider(height: 12, thickness: 1, color: context.colors.border),
          ],
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
      child: const NoteListWidget(),
    );
  }
}
