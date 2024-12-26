import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
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
  static final List<NoteModel> feedItems = [];
  static final Set<String> cachedNoteIds = {};
  static final Set<String> glowingNotes = {};
  static final Set<String> swipedNotes = {};
  static bool isLoadingOlderNotes = false;
  static bool isInitializing = true;
  static DataService? _dataService;
  static final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  static final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (_dataService == null) {
      _dataService = DataService(
        npub: widget.npub,
        dataType: DataType.Feed,
        onNewNote: _handleNewNote,
      );
      _initializeFeed();
    } else {
      setState(() {
        isInitializing = false;
      });
    }
  }

  Future<void> _initializeFeed() async {
    try {
      await _dataService!.initialize();
      await _loadFeedFromCache();
      await _dataService!.initializeConnections();
      if (mounted) {
        setState(() {
          isInitializing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isInitializing = false;
        });
      }
    }
  }

  Future<void> _loadFeedFromCache() async {
    await _dataService!.loadNotesFromCache((cachedNotes) {
      final newNotes = cachedNotes.where((note) => !cachedNoteIds.contains(note.id)).toList();
      setState(() {
        cachedNoteIds.addAll(newNotes.map((note) => note.id));
        feedItems.addAll(newNotes);
feedItems.sort((a, b) {
  final aTimestamp = a.isRepost ? a.repostTimestamp ?? a.timestamp : a.timestamp;
  final bTimestamp = b.isRepost ? b.repostTimestamp ?? b.timestamp : b.timestamp;
  return bTimestamp.compareTo(aTimestamp);
});
      });
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

void _handleNewNote(NoteModel newNote) {
  if (!cachedNoteIds.contains(newNote.id)) {
    cachedNoteIds.add(newNote.id);
    feedItems.add(newNote);

    feedItems.sort((a, b) {
      final aTimestamp = a.isRepost ? a.repostTimestamp ?? a.timestamp : a.timestamp;
      final bTimestamp = b.isRepost ? b.repostTimestamp ?? b.timestamp : b.timestamp;
      return bTimestamp.compareTo(aTimestamp);
    });

    _dataService!.saveNotesToCache();
    if (mounted) {
      setState(() {});
    }
  }
}

Future<void> _loadOlderNotes() async {
  if (isLoadingOlderNotes) return;
  setState(() {
    isLoadingOlderNotes = true;
  });
  final followingList = await _dataService!.getFollowingList(widget.npub);
  await _dataService!.fetchOlderNotes(followingList, (olderNote) {
    if (!cachedNoteIds.contains(olderNote.id)) {
      cachedNoteIds.add(olderNote.id);
      feedItems.add(olderNote);

      feedItems.sort((a, b) {
        final aTimestamp = a.isRepost ? a.repostTimestamp ?? a.timestamp : a.timestamp;
        final bTimestamp = b.isRepost ? b.repostTimestamp ?? b.timestamp : b.timestamp;
        return bTimestamp.compareTo(aTimestamp);
      });

      if (mounted) {
        setState(() {});
      }
    }
  });
  if (mounted) {
    setState(() {
      isLoadingOlderNotes = false;
    });
  }
}

  Future<void> _sendReaction(String noteId) async {
    try {
      await _dataService!.sendReaction(noteId, '💜');
      setState(() {
        glowingNotes.add(noteId);
      });

      Timer(const Duration(seconds: 1), () {
        setState(() {
          glowingNotes.remove(noteId);
        });
      });
    } catch (e) {}
  }

  void _showReplyDialog(String noteId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) => SendReplyDialog(
        dataService: _dataService!,
        noteId: noteId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isInitializing && feedItems.isEmpty) {
      return Scaffold(
        key: _scaffoldKey,
        drawer: _buildSidebar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

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
                'FOLLOWING',
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
        body: feedItems.isEmpty
            ? const Center(child: Text('No feed items available.'))
            : NotificationListener<ScrollNotification>(
                onNotification: (scrollInfo) {
                  if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200 &&
                      !isLoadingOlderNotes) {
                    _loadOlderNotes();
                  }
                  return false;
                },
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: feedItems.length + (isLoadingOlderNotes ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == feedItems.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final item = feedItems[index];
                    return GestureDetector(
                      onDoubleTap: () {
                        _sendReaction(item.id);
                      },
                      onHorizontalDragEnd: (details) {
                        if (details.primaryVelocity! > 0) {
                          setState(() {
                            swipedNotes.add(item.id);
                          });
                          _showReplyDialog(item.id);
                          Timer(const Duration(milliseconds: 500), () {
                            setState(() {
                              swipedNotes.remove(item.id);
                            });
                          });
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          border: glowingNotes.contains(item.id)
                              ? Border.all(color: Colors.white, width: 4.0)
                              : swipedNotes.contains(item.id)
                                  ? Border.all(color: Colors.white, width: 4.0)
                                  : null,
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        child: NoteWidget(
                          note: item,
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
                        ),
                      ),
                    );
                  },
                ),
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
            builder: (context) => ShareNoteDialog(dataService: _dataService!),
          );
        },
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildSidebar() {
    return Drawer(
      child: ListView(
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
    );
  }

  Future<void> _logoutAndClearData() async {
    try {
      const secureStorage = FlutterSecureStorage();
      await secureStorage.deleteAll();

      await Hive.deleteFromDisk();

      await _dataService?.closeConnections();

      feedItems.clear();
      cachedNoteIds.clear();
      glowingNotes.clear();
      swipedNotes.clear();
      isInitializing = true;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (Route<dynamic> route) => false,
      );
    } catch (e) {
      print('Error during logout: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error during logout: $e')),
      );
    }
  }
}
