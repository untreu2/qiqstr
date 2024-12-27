import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:qiqstr/models/reaction_model.dart';
import 'package:qiqstr/models/reply_model.dart';
import 'package:qiqstr/screens/share_note.dart';
import '../models/note_model.dart';
import '../services/qiqstr_service.dart';
import 'note_detail_page.dart';
import 'profile_page.dart';
import 'login_page.dart';
import 'send_reply.dart';
import '../widgets/note_widget.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class FeedPage extends StatefulWidget {
  final String npub;

  const FeedPage({Key? key, required this.npub}) : super(key: key);

  @override
  _FeedPageState createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final List<NoteModel> _feedItems = [];
  final Set<String> _cachedNoteIds = {};
  final Set<String> _glowingNotes = {};
  final Set<String> _swipedNotes = {};
  bool _isLoadingOlderNotes = false;
  bool _isLoadingNewNotes = false;
  bool _isInitializing = true;
  late DataService _dataService;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _dataService = DataService(
      npub: widget.npub,
      dataType: DataType.Feed,
      onNewNote: _handleNewNote,
      onReactionsUpdated: _handleReactionsUpdated,
      onRepliesUpdated: _handleRepliesUpdated,
    );
    _initializeFeed();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _initializeFeed() async {
    try {
      await _dataService.initialize();
      await _loadFeedFromCache();
      await _dataService.initializeConnections();

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
      print('Error initializing feed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading feed: $e')),
      );
    }
  }

  Future<void> _loadFeedFromCache() async {
    await _dataService.loadNotesFromCache((cachedNotes) {
      final newNotes = cachedNotes.where((note) => !_cachedNoteIds.contains(note.id)).toList();
      setState(() {
        _cachedNoteIds.addAll(newNotes.map((note) => note.id));
        _feedItems.addAll(newNotes);
        _sortFeedItems();
        _isLoadingNewNotes = false;
      });
    });
  }

  void _handleNewNote(NoteModel newNote) {
    if (!_cachedNoteIds.contains(newNote.id)) {
      setState(() {
        _cachedNoteIds.add(newNote.id);
        _feedItems.insert(0, newNote);
        _sortFeedItems();
      });
      _dataService.saveNotesToCache();
    }

    if (_isLoadingNewNotes) {
      setState(() {
        _isLoadingNewNotes = false;
      });
    }
  }

  void _handleReactionsUpdated(String noteId, List<ReactionModel> reactions) {
    setState(() {
      final index = _feedItems.indexWhere((note) => note.id == noteId);
      if (index != -1) {
      }
    });
  }

  void _handleRepliesUpdated(String noteId, List<ReplyModel> replies) {
    setState(() {
      final index = _feedItems.indexWhere((note) => note.id == noteId);
      if (index != -1) {
      }
    });
  }

  void _sortFeedItems() {
    _feedItems.sort((a, b) {
      final aTimestamp = a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
      final bTimestamp = b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
      return bTimestamp.compareTo(aTimestamp);
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingOlderNotes &&
        !_isInitializing) {
      _loadOlderNotes();
    }
  }

  Future<void> _loadOlderNotes() async {
    if (_isLoadingOlderNotes) return;
    setState(() {
      _isLoadingOlderNotes = true;
    });
    try {
      final followingList = await _dataService.getFollowingList(widget.npub);
      await _dataService.fetchOlderNotes(followingList, _handleOlderNote);
    } catch (e) {
      print('Error loading older notes: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading older notes: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingOlderNotes = false;
        });
      }
    }
  }

  void _handleOlderNote(NoteModel olderNote) {
    if (!_cachedNoteIds.contains(olderNote.id)) {
      setState(() {
        _cachedNoteIds.add(olderNote.id);
        _feedItems.add(olderNote);
        _sortFeedItems();
      });
    }
  }

  Future<void> _sendReaction(String noteId) async {
    try {
      await _dataService.sendReaction(noteId, '💜');
      setState(() {
        _glowingNotes.add(noteId);
      });

      Timer(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() {
            _glowingNotes.remove(noteId);
          });
        }
      });
    } catch (e) {
      print('Error sending reaction: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending reaction: $e')),
      );
    }
  }

  void _showReplyDialog(String noteId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) => SendReplyDialog(
        dataService: _dataService,
        noteId: noteId,
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _dataService.closeConnections();
    Hive.close();
    super.dispose();
  }

  Widget _buildSidebar() {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('PROFILE'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ProfilePage(npub: widget.npub)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('LOGOUT'),
              onTap: _logoutAndClearData,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logoutAndClearData() async {
    try {
      const secureStorage = FlutterSecureStorage();
      await secureStorage.deleteAll();

      await Hive.deleteFromDisk();

      await _dataService.closeConnections();

      setState(() {
        _feedItems.clear();
        _cachedNoteIds.clear();
        _glowingNotes.clear();
        _swipedNotes.clear();
        _isInitializing = true;
      });

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (Route<dynamic> route) => false,
      );
    } catch (e) {
      print('Logout error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logout error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildSidebar(),
      body: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
          return [
            SliverAppBar(
              leading: IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () {
                  _scaffoldKey.currentState?.openDrawer();
                },
              ),
              title: const Text(
                'qiqstr',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 24.0,
                ),
              ),
              floating: true,
              pinned: false,
              elevation: 4.0,
              flexibleSpace: const FlexibleSpaceBar(),
            ),
          ];
        },
        body: RefreshIndicator(
          onRefresh: () async {
            await _dataService.fetchNotes(await _dataService.getFollowingList(widget.npub), initialLoad: true);
          },
          child: _isInitializing
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : (_feedItems.isEmpty
                  ? ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        SizedBox(height: 100),
                        Center(
                          child: Text(
                            'No notes to display yet. They will appear here when new notes are loaded.',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: _feedItems.length + (_isLoadingOlderNotes ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _feedItems.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final item = _feedItems[index];
                        return NoteWidget(
                          key: ValueKey(item.id),
                          note: item,
                          onSendReaction: _sendReaction,
                          onShowReplyDialog: _showReplyDialog,
                          onAuthorTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ProfilePage(npub: item.author),
                              ),
                            );
                          },
                          onRepostedByTap: item.isRepost
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ProfilePage(npub: item.repostedBy!),
                                    ),
                                  );
                                }
                              : null,
                          onNoteTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => NoteDetailPage(
                                  note: item,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    )),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
            ),
            builder: (context) => ShareNoteDialog(dataService: _dataService),
          );
        },
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
