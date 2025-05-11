import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/services/data_service.dart';
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

class _NoteListWidgetState extends State<NoteListWidget> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final ScrollController _scrollController = ScrollController();

  String? _currentUserNpub;
  bool _isInitializing = true;
  bool _preloadDone = false;

  late DataService _dataService;
  final List<NoteModel> _pendingNotes = [];

  int _selectedTabIndex = 1;

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

    final prefs = await SharedPreferences.getInstance();
    final preloadKey =
        'note_preload_done_${widget.npub}_${widget.dataType.name}';
    final preloadAlreadyDone = prefs.getBool(preloadKey) ?? false;

    _dataService = _createDataService();

    await _dataService.initialize();
    await _dataService.initializeConnections();

    if (!preloadAlreadyDone) {
      await Future.delayed(const Duration(seconds: 0));
      await _dataService.closeConnections();

      _dataService = _createDataService();
      await _dataService.initialize();
      await _dataService.initializeConnections();

      _applyPendingNotes();
      await prefs.setBool(preloadKey, true);
    }

    if (mounted) {
      setState(() {
        _isInitializing = false;
        _preloadDone = true;
      });
    }
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

  Widget buildButton(int index, String label) {
    final isSelected = _selectedTabIndex == index;

    return Expanded(
      child: TextButton(
        onPressed: () {
          setState(() {
            _selectedTabIndex = index;
          });
        },
        style: TextButton.styleFrom(
          backgroundColor:
              isSelected ? Colors.white.withOpacity(0.12) : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isSelected ? const Color(0xFFECB200) : Colors.white10,
              width: 1.4,
            ),
          ),
          foregroundColor: isSelected ? Colors.white : Colors.white70,
          padding: const EdgeInsets.symmetric(vertical: 12),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
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
        if (notes.isEmpty) {
          return const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No notes found.',
                    style: TextStyle(color: Colors.white70)),
              ),
            ),
          );
        }

        List<NoteModel> filteredNotes = switch (_selectedTabIndex) {
          0 => notes
              .where((n) =>
                  n.timestamp.isAfter(
                      DateTime.now().subtract(const Duration(hours: 24))) &&
                  (!n.isReply || n.isRepost))
              .toList()
            ..sort((a, b) =>
                (b.reactionCount + b.replyCount + b.repostCount + b.zapAmount)
                    .compareTo(a.reactionCount +
                        a.replyCount +
                        a.repostCount +
                        a.zapAmount)),
          2 => notes
              .where((n) => n.hasMedia && (!n.isReply || n.isRepost))
              .toList(),
          _ => notes.where((n) => !n.isReply || n.isRepost).toList(),
        };

        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (index == 0) {
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      buildButton(1, "Latest"),
                      const SizedBox(width: 6),
                      buildButton(0, "Popular (24h)"),
                      const SizedBox(width: 6),
                      buildButton(2, "Media"),
                    ],
                  ),
                );
              }

              final note = filteredNotes[index - 1];
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
                  ),
                  if (index < filteredNotes.length)
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      height: 1,
                      width: double.infinity,
                      color: Colors.white24,
                    ),
                ],
              );
            },
            childCount: filteredNotes.length + 1,
          ),
        );
      },
    );
  }
}
