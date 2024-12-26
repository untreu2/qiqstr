import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import '../models/note_model.dart';
import '../services/qiqstr_service.dart';
import 'note_detail_page.dart';
import 'send_reply.dart';
import '../widgets/note_widget.dart';

class ProfilePage extends StatefulWidget {
  final String npub;

  const ProfilePage({Key? key, required this.npub}) : super(key: key);

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final List<NoteModel> profileNotes = [];
  final Set<String> cachedNoteIds = {};
  final Set<String> glowingNotes = {};
  final Set<String> swipedNotes = {};
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
    profileNotes.add(newNote);

    profileNotes.sort((a, b) {
      final aTimestamp = a.isRepost ? a.repostTimestamp ?? a.timestamp : a.timestamp;
      final bTimestamp = b.isRepost ? b.repostTimestamp ?? b.timestamp : b.timestamp;
      return bTimestamp.compareTo(aTimestamp);
    });

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
  profileNotes.sort((a, b) {
    final aTimestamp = a.isRepost ? a.repostTimestamp ?? a.timestamp : a.timestamp;
    final bTimestamp = b.isRepost ? b.repostTimestamp ?? b.timestamp : b.timestamp;
    return bTimestamp.compareTo(aTimestamp);
  });

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

  Future<void> _sendReaction(String noteId) async {
    try {
      await _dataService.sendReaction(noteId, '💜');
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
        dataService: _dataService,
        noteId: noteId,
      ),
    );
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

      profileNotes.sort((a, b) {
        final aTimestamp = a.isRepost ? a.repostTimestamp ?? a.timestamp : a.timestamp;
        final bTimestamp = b.isRepost ? b.repostTimestamp ?? b.timestamp : b.timestamp;
        return bTimestamp.compareTo(aTimestamp);
      });

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

  @override
  Widget build(BuildContext context) {
    if (isLoading && profileNotes.isEmpty) {
      return Scaffold(
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: SafeArea(
        top: true,
        bottom: false,
        left: true,
        right: true,
        child: NotificationListener<ScrollNotification>(
          onNotification: (scrollInfo) {
            if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200 &&
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
                              backgroundImage: CachedNetworkImageProvider(userProfile['profileImage']!),
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
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
                        childCount: profileNotes.length + 1,
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}