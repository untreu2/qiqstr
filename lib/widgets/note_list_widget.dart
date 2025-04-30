import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  State<NoteListWidget> createState() => _NoteListWidgetState();
}

class _NoteListWidgetState extends State<NoteListWidget>
    with SingleTickerProviderStateMixin {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final ScrollController _scrollController = ScrollController();

  String? _currentUserNpub;
  bool _isInitializing = true;
  bool _isFakeLoadingDone = false;

  late DataService _dataService;
  late Future<void> _renderReadyFuture;

  final List<NoteModel> _pendingNotes = [];
  List<Future<void>> _noteLoadFutures = [];
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runFakeScrollAndLoading().then((_) => _setupInitialService());
    });
  }

  Future<void> _runFakeScrollAndLoading() async {
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      await _scrollController.animateTo(
        150.0,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
      );
      await Future.delayed(const Duration(milliseconds: 200));

      await _scrollController.animateTo(
        300.0,
        duration: const Duration(milliseconds: 1000),
        curve: Curves.easeInOut,
      );
      await Future.delayed(const Duration(milliseconds: 300));

      await _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 1000),
        curve: Curves.easeInOut,
      );
      await Future.delayed(const Duration(milliseconds: 400));
    } catch (_) {}

    await WidgetsBinding.instance.endOfFrame;
    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      setState(() {
        _isFakeLoadingDone = true;
      });
    }
  }

  Future<void> _setupInitialService() async {
    _currentUserNpub = await _secureStorage.read(key: 'npub');
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final preloadKey =
        'note_preload_done_${widget.npub}_${widget.dataType.name}';
    final preloadAlreadyDone = prefs.getBool(preloadKey) ?? false;

    _dataService = DataService(
      npub: widget.npub,
      dataType: widget.dataType,
      onNewNote: _handleNewNote,
      onReactionsUpdated: (_, __) {},
      onRepliesUpdated: (_, __) {},
      onRepostsUpdated: (_, __) {},
      onReactionCountUpdated: (_, __) {},
      onReplyCountUpdated: (_, __) {},
      onRepostCountUpdated: (_, __) {},
    );

    await _dataService.initialize();
    await _dataService.initializeConnections();

    if (!preloadAlreadyDone) {
      await Future.delayed(const Duration(seconds: 3));
      await _dataService.closeConnections();

      _dataService = DataService(
        npub: widget.npub,
        dataType: widget.dataType,
        onNewNote: _handleNewNote,
        onReactionsUpdated: (_, __) {},
        onRepliesUpdated: (_, __) {},
        onRepostsUpdated: (_, __) {},
        onReactionCountUpdated: (_, __) {},
        onReplyCountUpdated: (_, __) {},
        onRepostCountUpdated: (_, __) {},
      );

      await _dataService.initialize();
      await _dataService.initializeConnections();
      _applyPendingNotes();
      await prefs.setBool(preloadKey, true);
    }

    if (mounted) {
      setState(() {
        _isInitializing = false;
      });

      final notes = _dataService.notesNotifier.value;
      _noteLoadFutures = List.generate(
        notes.length,
        (i) => Future.delayed(Duration(milliseconds: min(i * 50, 2500))),
      );
      _renderReadyFuture = Future.wait(_noteLoadFutures);
    }
  }

  void _handleNewNote(NoteModel note) {
    _dataService.addPendingNote(note);
    _dataService.applyPendingNotes();
  }

  void _applyPendingNotes() {
    _pendingNotes.forEach(_dataService.addPendingNote);
    _dataService.applyPendingNotes();
    _pendingNotes.clear();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _dataService.closeConnections();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isFakeLoadingDone ||
        _isInitializing ||
        _currentUserNpub == null ||
        _noteLoadFutures.isEmpty) {
      return const SliverToBoxAdapter(
        child: SizedBox(
          height: 300,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return FutureBuilder(
      future: _renderReadyFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SliverToBoxAdapter(
            child: SizedBox(
              height: 300,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        return ValueListenableBuilder<List<NoteModel>>(
          valueListenable: _dataService.notesNotifier,
          builder: (context, notes, child) {
            final filteredNotes = _selectedTabIndex == 0
                ? notes
                : notes.where((n) => n.hasMedia).toList();

            return SliverList(
              delegate: SliverChildListDelegate([
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () =>
                              setState(() => _selectedTabIndex = 0),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _selectedTabIndex == 0
                                ? Colors.amber.withOpacity(0.2)
                                : Colors.grey.withOpacity(0.1),
                            foregroundColor: _selectedTabIndex == 0
                                ? Colors.amber[800]
                                : Colors.grey,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text("All Notes"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () =>
                              setState(() => _selectedTabIndex = 1),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _selectedTabIndex == 1
                                ? Colors.amber.withOpacity(0.2)
                                : Colors.grey.withOpacity(0.1),
                            foregroundColor: _selectedTabIndex == 1
                                ? Colors.amber[800]
                                : Colors.grey,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text("Media"),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ...List.generate(filteredNotes.length, (index) {
                  final note = filteredNotes[index];
                  return RepaintBoundary(
                    key: ValueKey(note.id),
                    child: NoteWidget(
                      note: note,
                      reactionCount: note.reactionCount,
                      replyCount: note.replyCount,
                      repostCount: note.repostCount,
                      dataService: _dataService,
                      currentUserNpub: _currentUserNpub!,
                      notesNotifier: _dataService.notesNotifier,
                    ),
                  );
                }),
              ]),
            );
          },
        );
      },
    );
  }
}
