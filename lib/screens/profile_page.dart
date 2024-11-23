import 'dart:async';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../services/profile_service.dart';
import '../screens/note_detail_page.dart';

class ProfilePage extends StatefulWidget {
  final String npub;

  const ProfilePage({Key? key, required this.npub}) : super(key: key);

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final List<NoteModel> profileNotes = [];
  final Map<String, List<ReactionModel>> reactionsMap = {};
  final Map<String, List<ReplyModel>> repliesMap = {};
  final Set<String> cachedNoteIds = {};
  bool isLoadingOlderNotes = false;

  ProfileService? _profileService;

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
    _initializeProfileService();
  }

  void _initializeProfileService() {
    _profileService?.closeConnections();

    profileNotes.clear();
    reactionsMap.clear();
    repliesMap.clear();
    cachedNoteIds.clear();
    userProfile = {
      'name': 'Loading...',
      'profileImage': '',
      'about': '',
      'nip05': '',
      'banner': '',
    };
    backgroundColor = Colors.blueAccent.withOpacity(0.1);

    _profileService = ProfileService(
      npub: widget.npub,
      onNewNote: (newNote) {
        if (!cachedNoteIds.contains(newNote.id)) {
          if (mounted) {
            setState(() {
              cachedNoteIds.add(newNote.id);
              profileNotes.insert(0, newNote);
              profileNotes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
            });
          }
        }
      },
      onReactionsUpdated: (noteId, reactions) {
        if (mounted) {
          setState(() {
            reactionsMap[noteId] = reactions;
          });
        }
      },
      onRepliesUpdated: (noteId, replies) {
        if (mounted) {
          setState(() {
            repliesMap[noteId] = replies;
          });
        }
      },
    );

    _loadProfileFromCache();
    _initializeRelayConnection();
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.npub != widget.npub) {
      _initializeProfileService();
    }
  }

  @override
  void dispose() {
    _profileService?.closeConnections();
    _profileService = null;
    super.dispose();
  }

  Future<void> _initializeRelayConnection() async {
    if (_profileService == null) return;
    await _profileService!.initializeConnections();

    final profile = await _profileService!.getCachedUserProfile(widget.npub);
    if (!mounted) return;
    setState(() {
      userProfile = profile;
    });

    if (userProfile['profileImage']!.isNotEmpty) {
      _updateBackgroundColor(userProfile['profileImage']!);
    }
  }

  Future<void> _loadProfileFromCache() async {
    if (_profileService == null) return;
    await _profileService!.loadNotesFromCache((cachedNote) {
      if (!cachedNoteIds.contains(cachedNote.id)) {
        if (mounted) {
          setState(() {
            cachedNoteIds.add(cachedNote.id);
            profileNotes.add(cachedNote);
          });
        }
      }
    });

    if (mounted) {
      setState(() {
        profileNotes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      });
    }
  }

  Future<void> _loadOlderNotes() async {
    if (_profileService == null) return;
    setState(() {
      isLoadingOlderNotes = true;
    });

    await _profileService!.fetchOlderNotes([widget.npub], (olderNote) {
      if (!cachedNoteIds.contains(olderNote.id)) {
        if (mounted) {
          setState(() {
            cachedNoteIds.add(olderNote.id);
            profileNotes.add(olderNote);
          });
        }
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
      final PaletteGenerator paletteGenerator =
          await PaletteGenerator.fromImageProvider(NetworkImage(imageUrl));
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
      ),
      body: CustomScrollView(
        slivers: [
          if (userProfile['banner']!.isNotEmpty)
            SliverToBoxAdapter(
              child: Container(
                width: double.infinity,
                child: AspectRatio(
                  aspectRatio: 18 / 9,
                  child: Image.network(
                    userProfile['banner']!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[300],
                        child: const Center(
                            child: Icon(Icons.broken_image, size: 50)),
                      );
                    },
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
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ProfilePage(npub: widget.npub),
                        ),
                      );
                    },
                    child: userProfile['profileImage']!.isNotEmpty
                        ? CircleAvatar(
                            radius: 30,
                            backgroundImage:
                                NetworkImage(userProfile['profileImage']!),
                          )
                        : const CircleAvatar(
                            radius: 30,
                            child: Icon(Icons.person, size: 30),
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ProfilePage(npub: widget.npub),
                              ),
                            );
                          },
                          child: Text(
                            userProfile['name']!,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
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
                            'NIP-05: ${userProfile['nip05']}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          profileNotes.isEmpty
              ? SliverFillRemaining(
                  child: const Center(child: CircularProgressIndicator()),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = profileNotes[index];
                      final reactions = reactionsMap[item.id] ?? [];
                      final replies = repliesMap[item.id] ?? [];
                      return ListTile(
                        title: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ProfilePage(npub: item.author),
                              ),
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
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  'Reactions: ${reactions.length}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  'Replies: ${replies.length}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ProfilePage(npub: item.author),
                              ),
                            );
                          },
                          child: item.authorProfileImage.isNotEmpty
                              ? CircleAvatar(
                                  backgroundImage:
                                      NetworkImage(item.authorProfileImage),
                                )
                              : const CircleAvatar(child: Icon(Icons.person)),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => NoteDetailPage(
                                note: item,
                                reactions: reactions,
                                replies: replies,
                                reactionsMap: reactionsMap,
                                repliesMap: repliesMap,
                              ),
                            ),
                          );
                        },
                      );
                    },
                    childCount: profileNotes.length,
                  ),
                ),
          if (isLoadingOlderNotes)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              ),
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
