import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; 
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:video_player/video_player.dart';
import '../providers/profile_service_provider.dart';
import '../models/note_model.dart';
import '../services/qiqstr_service.dart';
import 'note_detail_page.dart';

class ProfilePage extends ConsumerStatefulWidget {
  final String npub;

  const ProfilePage({Key? key, required this.npub}) : super(key: key);

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final List<NoteModel> profileNotes = [];
  final Set<String> cachedNoteIds = {};

  bool isLoadingOlderNotes = false;
  bool isLoadingProfile = true;
  Color backgroundColor = Colors.blueAccent.withOpacity(0.1);

  Map<String, String> userProfile = {
    'name': 'Loading...',
    'profileImage': '',
    'about': '',
    'nip05': '',
    'banner': '',
  };

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dataServiceAsync = ref.watch(profileServiceProvider(widget.npub));

    return dataServiceAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        body: Center(child: Text('Error: $error')),
      ),
      data: (dataService) {
        for (var note in dataService.notes) {
          if (!cachedNoteIds.contains(note.id)) {
            cachedNoteIds.add(note.id);
            profileNotes.add(note);
          }
        }
        profileNotes.sort((a, b) => b.timestamp.compareTo(a.timestamp));

        _updateUserProfile(dataService);

        return Scaffold(
          body: SafeArea(
            child: NotificationListener<ScrollNotification>(
              onNotification: (scrollInfo) {
                if (scrollInfo.metrics.pixels >=
                        scrollInfo.metrics.maxScrollExtent - 200 &&
                    !isLoadingOlderNotes) {
                  _loadOlderNotes(dataService);
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
                          child: const Center(
                            child: Icon(Icons.broken_image, size: 50),
                          ),
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
                                  backgroundImage: CachedNetworkImageProvider(
                                    userProfile['profileImage']!,
                                  ),
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
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
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
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (profileNotes.isEmpty)
                    const SliverFillRemaining(
                      child: Center(child: Text('No notes available.')),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (index == profileNotes.length) {
                            return isLoadingOlderNotes
                                ? const Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                : const SizedBox.shrink();
                          }

                          final item = profileNotes[index];
                          final parsedContent = _parseContent(item.content);

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (item.isRepost)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 16.0,
                                    top: 8.0,
                                  ),
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
                                      builder: (context) => ProfilePage(
                                        npub: item.author,
                                      ),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8.0,
                                    horizontal: 16.0,
                                  ),
                                  child: Row(
                                    children: [
                                      item.authorProfileImage.isNotEmpty
                                          ? CircleAvatar(
                                              radius: 18,
                                              backgroundImage:
                                                  CachedNetworkImageProvider(
                                                item.authorProfileImage,
                                              ),
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
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16.0,
                                        ),
                                        child: Text(parsedContent['text']),
                                      ),
                                    if (parsedContent['text'] != null &&
                                        parsedContent['text'] != '' &&
                                        parsedContent['mediaUrls'] != null &&
                                        parsedContent['mediaUrls'].isNotEmpty)
                                      const SizedBox(height: 16.0),
                                    if (parsedContent['mediaUrls'] != null &&
                                        parsedContent['mediaUrls'].isNotEmpty)
                                      _buildMediaPreviews(parsedContent['mediaUrls']),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0,
                                        vertical: 8.0,
                                      ),
                                      child: Text(
                                        _formatTimestamp(item.timestamp),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
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
          ),
        );
      },
    );
  }

  Future<void> _updateUserProfile(DataService dataService) async {
    if (!isLoadingProfile && userProfile['name'] != 'Loading...') {
      return;
    }
    try {
      final profile = await dataService.getCachedUserProfile(widget.npub);
      if (!mounted) return;
      setState(() {
        userProfile = profile;
        isLoadingProfile = false;
      });
      if (userProfile['profileImage']!.isNotEmpty) {
        await _updateBackgroundColor(userProfile['profileImage']!);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoadingProfile = false;
        });
      }
    }
  }

  Future<void> _loadOlderNotes(DataService dataService) async {
    if (isLoadingOlderNotes) return;
    setState(() {
      isLoadingOlderNotes = true;
    });

    await dataService.fetchOlderNotes([widget.npub], (olderNote) {
      if (!cachedNoteIds.contains(olderNote.id)) {
        cachedNoteIds.add(olderNote.id);
        profileNotes.add(olderNote);
      }
    });

    if (mounted) {
      setState(() {
        profileNotes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        isLoadingOlderNotes = false;
      });
    }
  }

  Future<void> _updateBackgroundColor(String imageUrl) async {
    try {
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(imageUrl),
      );
      if (!mounted) return;
      setState(() {
        backgroundColor = paletteGenerator.dominantColor?.color.withOpacity(0.1)
            ?? Colors.blueAccent.withOpacity(0.1);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        backgroundColor = Colors.blueAccent.withOpacity(0.1);
      });
    }
  }

  Map<String, dynamic> _parseContent(String content) {
    final mediaRegExp = RegExp(
      r'(https?:\/\/\S+\.(?:jpg|jpeg|png|webp|gif|mp4))',
      caseSensitive: false,
    );
    final matches = mediaRegExp.allMatches(content);

    final mediaUrls = matches.map((m) => m.group(0)!).toList();
    final text = content.replaceAll(mediaRegExp, '').trim();

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
            placeholder: (context, _) => const Center(
              child: CircularProgressIndicator(),
            ),
            errorWidget: (context, _, __) => const Icon(Icons.error),
            fit: BoxFit.cover,
            width: double.infinity,
          );
        }
      }).toList(),
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
        if (mounted) setState(() => _isInitialized = true);
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
