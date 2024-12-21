import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hive/hive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:video_player/video_player.dart';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/data_service_provider.dart';
import '../models/note_model.dart';
import '../services/qiqstr_service.dart';
import 'share_note.dart';
import 'note_detail_page.dart';
import 'profile_page.dart';
import 'login_page.dart';

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
                    final parsedContent = _parseContent(item.content);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item.isRepost)
                          Padding(
                            padding: const EdgeInsets.only(left: 16.0, top: 8.0),
                            child: GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        ProfilePage(npub: item.repostedBy!),
                                  ),
                                );
                              },
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.repeat,
                                    size: 16.0,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 4.0),
                                  Text(
                                    'Reposted by ${item.repostedByName}',
                                    style: const TextStyle(
                                      fontSize: 12.0,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    ProfilePage(npub: item.author),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 8.0, horizontal: 16.0),
                            child: Row(
                              children: [
                                item.authorProfileImage.isNotEmpty
                                    ? CircleAvatar(
                                        radius: 18,
                                        backgroundImage:
                                            CachedNetworkImageProvider(
                                                item.authorProfileImage),
                                      )
                                    : const CircleAvatar(
                                        radius: 12,
                                        child: Icon(Icons.person, size: 16),
                                      ),
                                const SizedBox(width: 12),
                                Text(
                                  item.authorName,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        GestureDetector(
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
                                ),
                              ),
                            );
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (parsedContent['text'] != null &&
                                  parsedContent['text'] != '')
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 16.0),
                                  child: Text(parsedContent['text']),
                                ),
                              if (parsedContent['text'] != null &&
                                  parsedContent['text'] != '' &&
                                  parsedContent['mediaUrls'] != null &&
                                  parsedContent['mediaUrls'].isNotEmpty)
                                const SizedBox(height: 16.0),
                              if (parsedContent['mediaUrls'] != null &&
                                  parsedContent['mediaUrls'].isNotEmpty)
                                _buildMediaPreviews(
                                    parsedContent['mediaUrls']),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0, vertical: 8.0),
                                child: Text(
                                  _formatTimestamp(item.timestamp),
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  Map<String, dynamic> _parseContent(String content) {
    final RegExp mediaRegExp = RegExp(
      r'(https?:\/\/\S+\.(?:jpg|jpeg|png|webp|gif|mp4))',
      caseSensitive: false,
    );
    final Iterable<RegExpMatch> matches = mediaRegExp.allMatches(content);

    final List<String> mediaUrls = matches.map((m) => m.group(0)!).toList();
    final String text = content.replaceAll(mediaRegExp, '').trim();

    return {
      'text': text,
      'mediaUrls': mediaUrls,
    };
  }

  Widget _buildMediaPreviews(List<String> mediaUrls) {
    return Column(
      children: mediaUrls.map((url) {
        if (url.toLowerCase().endsWith('.mp4')) {
          return _VideoPreview(url: url);
        } else {
          return CachedNetworkImage(
            imageUrl: url,
            placeholder: (context, url) =>
                const Center(child: CircularProgressIndicator()),
            errorWidget: (context, url, error) => const Icon(Icons.error),
            fit: BoxFit.cover,
            width: double.infinity,
          );
        }
      }).toList(),
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

  String _formatTimestamp(DateTime timestamp) {
    return "${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}"
        "-${timestamp.day.toString().padLeft(2, '0')} "
        "${timestamp.hour.toString().padLeft(2, '0')}:"
        "${timestamp.minute.toString().padLeft(2, '0')}:"
        "${timestamp.second.toString().padLeft(2, '0')}";
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
