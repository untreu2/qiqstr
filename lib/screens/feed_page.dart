import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/screens/share_note.dart';
import 'package:qiqstr/services/qiqstr_service.dart';
import 'package:qiqstr/widgets/note_widget.dart';
import 'package:qiqstr/widgets/sidebar_widget.dart';

class FeedPage extends StatefulWidget {
  final String npub;
  const FeedPage({super.key, required this.npub});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final ScrollController _scrollController = ScrollController();

  late final DataService _dataService;
  final SplayTreeSet<NoteModel> _notes = SplayTreeSet(_compareNotes);

  bool _isLoading = true;
  bool _isLoadingOlder = false;
  bool _showFab = true;
  double _lastOffset = 0;
  UserModel? _user;

  static int _compareNotes(NoteModel a, NoteModel b) {
    final aTime = a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
    final bTime = b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
    final res = bTime.compareTo(aTime);
    return res == 0 ? a.id.compareTo(b.id) : res;
  }

  @override
  void initState() {
    super.initState();
    _dataService = DataService(
      npub: widget.npub,
      dataType: DataType.Feed,
      onNewNote: _onNewNote,
    );
    _scrollController.addListener(_onScroll);
    _initialize();
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    if (offset > _lastOffset + 20 && _showFab) {
      setState(() => _showFab = false);
    } else if (offset < _lastOffset - 20 && !_showFab) {
      setState(() => _showFab = true);
    }
    _lastOffset = offset;

    if (!_isLoadingOlder &&
        offset >= _scrollController.position.maxScrollExtent - 200) {
      _loadOlderNotes();
    }
  }

  Future<void> _initialize() async {
    await _dataService.initialize();
    final profile = await _dataService.getCachedUserProfile(widget.npub);
    _user = UserModel.fromCachedProfile(widget.npub, profile);

    await _dataService.loadNotesFromCache((cached) {
      _notes.addAll(cached);
    });

    await _dataService.initializeConnections();
    setState(() => _isLoading = false);
  }

  Future<void> _loadOlderNotes() async {
    setState(() => _isLoadingOlder = true);
    await _dataService.fetchOlderNotes(
      await _dataService.getFollowingList(widget.npub),
      (note) => _notes.add(note),
    );
    setState(() => _isLoadingOlder = false);
  }

  void _onNewNote(NoteModel note) {
    if (_notes.add(note)) setState(() {});
  }

  void _goToShareNote() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ShareNotePage(dataService: _dataService)),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _dataService.closeConnections();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: SidebarWidget(user: _user),
      floatingActionButton: AnimatedSlide(
        offset: _showFab ? Offset.zero : const Offset(0, 2),
        duration: const Duration(milliseconds: 300),
        child: AnimatedOpacity(
          opacity: _showFab ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: FloatingActionButton.extended(
            onPressed: _goToShareNote,
            backgroundColor: Colors.white,
            icon: SvgPicture.asset(
              'assets/new_post_button.svg',
              color: Colors.black,
              width: 20,
              height: 20,
            ),
            label: const Text('New', style: TextStyle(color: Colors.black)),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverAppBar(
                  backgroundColor: Colors.black,
                  floating: true,
                  snap: true,
                  pinned: false,
                  title: Image.asset('assets/main_icon.png', height: 35),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index == _notes.length && _isLoadingOlder) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final note = _notes.elementAt(index);
                      return NoteWidget(
                        note: note,
                        dataService: _dataService,
                        reactionCount: 0,
                        replyCount: 0,
                        repostCount: 0,
                      );
                    },
                    childCount: _notes.length + (_isLoadingOlder ? 1 : 0),
                  ),
                ),
              ],
            ),
    );
  }
}
