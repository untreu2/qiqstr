import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hive/hive.dart';
import '../models/note_model.dart';
import '../services/qiqstr_service.dart';
import 'note_detail_page.dart';
import 'profile_page.dart';
import 'login_page.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class FeedPage extends StatefulWidget {
  final String npub;

  const FeedPage({Key? key, required this.npub}) : super(key: key);

  @override
  _FeedPageState createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final List<NoteModel> feedItems = [];
  final Set<String> cachedNoteIds = {};
  bool isLoadingOlderNotes = false;
  bool isInitializing = true;
  late DataService _dataService;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _dataService = DataService(
      npub: widget.npub,
      dataType: DataType.Feed,
      onNewNote: _handleNewNote,
    );
    _initializeFeed();
  }

  Future<void> _initializeFeed() async {
    try {
      await _dataService.initialize();
      await _loadFeedFromCache();
      await _dataService.initializeConnections();
      if (mounted) {
        setState(() {
          isInitializing = false;
        });
      }
    } catch (e) {
      print('Error initializing feed: $e');
      if (mounted) {
        setState(() {
          isInitializing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _dataService.closeConnections();
    super.dispose();
  }

  void _handleNewNote(NoteModel newNote) {
    if (!cachedNoteIds.contains(newNote.id)) {
      cachedNoteIds.add(newNote.id);
      int insertIndex =
          feedItems.indexWhere((note) => note.timestamp.isBefore(newNote.timestamp));
      if (insertIndex == -1) {
        feedItems.add(newNote);
      } else {
        feedItems.insert(insertIndex, newNote);
      }
      _dataService.saveNotesToCache();
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _loadFeedFromCache() async {
    await _dataService.loadNotesFromCache((cachedNotes) {
      setState(() {
        for (var cachedNote in cachedNotes) {
          if (!cachedNoteIds.contains(cachedNote.id)) {
            cachedNoteIds.add(cachedNote.id);
            feedItems.add(cachedNote);
          }
        }
        feedItems.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      });
    });
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadOlderNotes() async {
    if (isLoadingOlderNotes) return;
    setState(() {
      isLoadingOlderNotes = true;
    });
    final followingList = await _dataService.getFollowingList(widget.npub);
    await _dataService.fetchOlderNotes(followingList, (olderNote) {
      if (!cachedNoteIds.contains(olderNote.id)) {
        cachedNoteIds.add(olderNote.id);
        feedItems.add(olderNote);
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

  Future<void> _logoutAndClearData() async {
    try {
      const secureStorage = FlutterSecureStorage();
      await secureStorage.deleteAll();
      await Hive.deleteFromDisk();
      await _dataService.closeConnections();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (Route<dynamic> route) => false,
      );
    } catch (e) {
      print('Error during logout: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isInitializing && feedItems.isEmpty) {
      return Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: const Text('Following'),
          leading: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () {
              _scaffoldKey.currentState?.openDrawer();
            },
          ),
        ),
        drawer: _buildSidebar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Following'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
      ),
      drawer: _buildSidebar(),
      body: feedItems.isEmpty
          ? const Center(child: Text('No feed items available.'))
          : NotificationListener<ScrollNotification>(
              onNotification: (scrollInfo) {
                if (scrollInfo.metrics.pixels >=
                        scrollInfo.metrics.maxScrollExtent - 200 &&
                    !isLoadingOlderNotes) {
                  _loadOlderNotes();
                }
                return false;
              },
              child: ListView.builder(
                itemCount: feedItems.length + (isLoadingOlderNotes ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == feedItems.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final item = feedItems[index];
                  return ListTile(
                    title: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => ProfilePage(npub: item.author)),
                        );
                      },
                      child: Text(item.authorName),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.content),
                        const SizedBox(height: 4),
                        Text(
                          _formatTimestamp(item.timestamp),
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    trailing: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => ProfilePage(npub: item.author)),
                        );
                      },
                      child: item.authorProfileImage.isNotEmpty
                          ? CircleAvatar(
                              backgroundImage:
                                  CachedNetworkImageProvider(item.authorProfileImage),
                            )
                          : const CircleAvatar(child: Icon(Icons.person)),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => NoteDetailPage(
                                  note: item,
                                  reactions: [],
                                  replies: [],
                                  reactionsMap: {},
                                  repliesMap: {},
                                )),
                      );
                    },
                  );
                },
              ),
            ),
    );
  }

Widget _buildSidebar() {
  return Drawer(
    child: ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.person),
          title: const Text('Profile'),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => ProfilePage(npub: widget.npub)),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Logout'),
          onTap: _logoutAndClearData,
        ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    return "${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} "
        "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}";
  }
}
