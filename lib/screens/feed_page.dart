import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:video_player/video_player.dart';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/data_service_provider.dart';
import '../models/note_model.dart';
import '../services/qiqstr_service.dart';
import 'share_note.dart';
import 'profile_page.dart';
import 'login_page.dart';
import '../widgets/note_widget.dart';

class FeedPage extends ConsumerStatefulWidget {
  final String npub;

  const FeedPage({Key? key, required this.npub}) : super(key: key);

  @override
  _FeedPageState createState() => _FeedPageState();
}

class _FeedPageState extends ConsumerState<FeedPage> {
  final List<NoteModel> feedItems = [];
  final Set<String> cachedNoteIds = {};

  bool isLoadingOlderNotes = false;
  bool isInitializing = true;

  late DataService _dataService;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    _dataService = ref.read(dataServiceProvider(widget.npub));

    _dataService.onNewNote = _handleNewNote;

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
      if (mounted) {
        setState(() {
          isInitializing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
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
    }
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
              snap: false,
              pinned: false,
              backgroundColor: Colors.transparent,
              elevation: 0,
              flexibleSpace: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    color: Colors.black.withOpacity(0.3),
                  ),
                ),
              ),
            ),
          ];
        },
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
                    return NoteWidget(
                      key: ValueKey(item.id),
                      note: item,
                      onTapAuthor: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProfilePage(npub: item.author),
                          ),
                        );
                      },
                      onTapRepost: () {
                        if (item.repostedBy != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ProfilePage(npub: item.repostedBy!),
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
              ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: SizedBox(
          width: double.infinity,
          height: 48.0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20.0,
                  spreadRadius: 2.0,
                ),
              ],
            ),
            child: FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ShareNotePage(dataService: _dataService),
                  ),
                );
              },
              label: const Text(
                'COMPOSE A NOTE',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
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
                MaterialPageRoute(
                  builder: (context) => ProfilePage(npub: widget.npub),
                ),
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
}

class _VideoPreview extends StatefulWidget {
  final String url;

  const _VideoPreview({Key? key, required this.url}) : super(key: key);

  @override
  __VideoPreviewState createState() => __VideoPreviewState();
}

class __VideoPreviewState extends State<_VideoPreview> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.url)
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: double.infinity,
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
          ),
          if (!_controller.value.isPlaying)
            const Icon(
              Icons.play_circle_outline,
              size: 64.0,
              color: Colors.white70,
            ),
        ],
      ),
    );
  }
}
