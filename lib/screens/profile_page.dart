import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hive/hive.dart';
import 'package:palette_generator/palette_generator.dart';
import '../models/note_model.dart';
import '../services/qiqstr_service.dart';
import 'note_detail_page.dart';
import 'login_page.dart';
import 'package:video_player/video_player.dart';

class ProfilePage extends StatefulWidget {
  final String npub;

  const ProfilePage({Key? key, required this.npub}) : super(key: key);

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final List<NoteModel> profileNotes = [];
  final Set<String> cachedNoteIds = {};
  bool isLoadingOlderNotes = false;
  bool isLoading = true;
  late DataService _dataService;

  Map<String, String> userProfile = {
    'name': 'Loading...',
    'profileImage': '',
    'about': '',
    'nip05': '',
    'banner': '',
  };

  Color backgroundColor = Colors.blueAccent.withOpacity(0.1);

  @override
  void initState() {
    super.initState();
    _initializeDataService();
  }

  Future<void> _initializeDataService() async {
    try {
      _dataService = DataService(
        npub: widget.npub,
        dataType: DataType.Profile,
        onNewNote: _handleNewNote,
      );

      await _dataService.initialize();

      await _loadProfileFromCache();

      await _dataService.initializeConnections();

      await _updateUserProfile();

      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error initializing profile: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
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
          profileNotes.indexWhere((note) => note.timestamp.isBefore(newNote.timestamp));
      if (insertIndex == -1) {
        profileNotes.add(newNote);
      } else {
        profileNotes.insert(insertIndex, newNote);
      }
      _dataService.saveNotesToCache();
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _loadProfileFromCache() async {
    await _dataService.loadNotesFromCache((cachedNotes) {
      for (var cachedNote in cachedNotes) {
        if (!cachedNoteIds.contains(cachedNote.id)) {
          cachedNoteIds.add(cachedNote.id);
          profileNotes.add(cachedNote);
        }
      }
    });
    profileNotes.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _updateUserProfile() async {
    final profile = await _dataService.getCachedUserProfile(widget.npub);
    if (!mounted) return;
    setState(() {
      userProfile = profile;
    });
    if (userProfile['profileImage']!.isNotEmpty) {
      await _updateBackgroundColor(userProfile['profileImage']!);
    }
  }

  Future<void> _loadOlderNotes() async {
    if (isLoadingOlderNotes) return;
    setState(() {
      isLoadingOlderNotes = true;
    });

    await _dataService.fetchOlderNotes([widget.npub], (olderNote) {
      if (!cachedNoteIds.contains(olderNote.id)) {
        cachedNoteIds.add(olderNote.id);
        profileNotes.add(olderNote);
        if (mounted) {
          setState(() {});
        }
      }
    });

    setState(() {
      isLoadingOlderNotes = false;
    });
  }

  Future<void> _updateBackgroundColor(String imageUrl) async {
    try {
      final PaletteGenerator paletteGenerator =
          await PaletteGenerator.fromImageProvider(CachedNetworkImageProvider(imageUrl));
      if (!mounted) return;
      setState(() {
        backgroundColor = paletteGenerator.dominantColor?.color.withOpacity(0.1) ??
            Colors.blueAccent.withOpacity(0.1);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        backgroundColor = Colors.blueAccent.withOpacity(0.1);
      });
    }
  }

  Future<void> _logoutAndClearData() async {
    try {
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
    if (isLoading && profileNotes.isEmpty) {
      return Scaffold(
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: (scrollInfo) {
          if (scrollInfo.metrics.pixels >=
                  scrollInfo.metrics.maxScrollExtent - 200 &&
              !isLoadingOlderNotes) {
            _loadOlderNotes();
          }
          return false;
        },
        child: CustomScrollView(
          slivers: [
            if (userProfile['banner']!.isNotEmpty)
              SliverToBoxAdapter(
                child: CachedNetworkImage(
                  imageUrl: userProfile['banner']!,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: Colors.grey[300],
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey[300],
                    child: const Center(child: Icon(Icons.broken_image, size: 50)),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(16),
                color: backgroundColor,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    userProfile['profileImage']!.isNotEmpty
                        ? CircleAvatar(
                            radius: 30,
                            backgroundImage:
                                CachedNetworkImageProvider(userProfile['profileImage']!),
                          )
                        : const CircleAvatar(
                            radius: 30,
                            child: Icon(Icons.person, size: 30),
                          ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userProfile['name']!,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          if (userProfile['about']!.isNotEmpty)
                            Text(
                              userProfile['about']!,
                              style: const TextStyle(fontSize: 14),
                            ),
                          const SizedBox(height: 8),
                          if (userProfile['nip05']!.isNotEmpty)
                            Text(
                              userProfile['nip05']!,
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            profileNotes.isEmpty
                ? const SliverFillRemaining(
                    child: Center(child: Text('No notes available.')),
                  )
                : SliverList(
  delegate: SliverChildBuilderDelegate(
    (context, index) {
      if (index == profileNotes.length) {
        return isLoadingOlderNotes
            ? const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              )
            : const SizedBox.shrink();
      }

      final item = profileNotes[index];
      final parsedContent = _parseContent(item.content);

      return Column(
        children: [
          ListTile(
            title: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ProfilePage(npub: item.author)),
                );
              },
              child: Row(
                children: [
                  item.authorProfileImage.isNotEmpty
                      ? CircleAvatar(
                          radius: 18, 
                          backgroundImage:
                              CachedNetworkImageProvider(item.authorProfileImage),
                        )
                      : const CircleAvatar(
                          radius: 12,
                          child: Icon(Icons.person, size: 16),
                        ),
                  const SizedBox(width: 8), 
                  Text(item.authorName),
                ],
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Text(parsedContent['text'] ?? ''),
                const SizedBox(height: 4),
                if (parsedContent['mediaUrls'] != null &&
                    parsedContent['mediaUrls']!.isNotEmpty)
                  _buildMediaPreviews(parsedContent['mediaUrls']!),
                const SizedBox(height: 4),
                Text(
                  _formatTimestamp(item.timestamp),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
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
                  ),
                ),
              );
            },
          ),
        ],
      );
    },
    childCount: profileNotes.length + 1,
                    ),
                  ),
          ],
        ),
      ),
    );
  }


  Map<String, dynamic> _parseContent(String content) {
    final RegExp mediaRegExp = RegExp(
        r'(https?:\/\/\S+\.(?:jpg|jpeg|png|webp|gif|mp4))',
        caseSensitive: false);
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
          return Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: CachedNetworkImage(
              imageUrl: url,
              placeholder: (context, url) =>
                  const Center(child: CircularProgressIndicator()),
              errorWidget: (context, url, error) => const Icon(Icons.error),
            ),
          );
        }
      }).toList(),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    return "${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} "
        "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}";
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
        setState(() {
          _isInitialized = true;
        });
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
          AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
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
