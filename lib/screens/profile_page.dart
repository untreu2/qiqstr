import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../services/qiqstr_service.dart';
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
  DataService? _dataService;

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

  void _initializeDataService() {
    _dataService?.closeConnections();

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

    _dataService = DataService(
      npub: widget.npub,
      dataType: DataType.Profile,
      onNewNote: _handleNewNote,
      onReactionsUpdated: _handleReactionsUpdated,
      onRepliesUpdated: _handleRepliesUpdated,
    );

    _loadProfileFromCache();
    _initializeRelayConnection();
  }

  void _handleNewNote(NoteModel newNote) {
    if (!cachedNoteIds.contains(newNote.id)) {
      cachedNoteIds.add(newNote.id);
      int insertIndex = profileNotes.indexWhere((note) => note.timestamp.isBefore(newNote.timestamp));
      if (insertIndex == -1) {
        profileNotes.add(newNote);
      } else {
        profileNotes.insert(insertIndex, newNote);
      }
      _dataService!.fetchReactionsForNotes([newNote.id]);
      _dataService!.fetchRepliesForNotes([newNote.id]);
      setState(() {});
    }
  }

  void _handleReactionsUpdated(String noteId, List<ReactionModel> reactions) {
    reactionsMap[noteId] = reactions;
    _dataService!.saveReactionsToCache();
    setState(() {});
  }

  void _handleRepliesUpdated(String noteId, List<ReplyModel> replies) {
    repliesMap[noteId] = replies;
    _dataService!.saveRepliesToCache();
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.npub != widget.npub) {
      _initializeDataService();
    }
  }

  @override
  void dispose() {
    _dataService?.closeConnections();
    _dataService = null;
    super.dispose();
  }

  Future<void> _initializeRelayConnection() async {
    if (_dataService == null) return;
    await _dataService!.initializeConnections();

    _dataService!.getCachedUserProfile(widget.npub).then((profile) {
      if (!mounted) return;
      setState(() {
        userProfile = profile;
      });
      if (userProfile['profileImage']!.isNotEmpty) {
        _updateBackgroundColor(userProfile['profileImage']!);
      }
    });
  }

  Future<void> _loadProfileFromCache() async {
    if (_dataService == null) return;
    await _dataService!.loadNotesFromCache((cachedNote) {
      if (!cachedNoteIds.contains(cachedNote.id)) {
        cachedNoteIds.add(cachedNote.id);
        profileNotes.add(cachedNote);
      }
    });
    profileNotes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    setState(() {});
    _loadReactionsAndReplies();
  }

  void _loadReactionsAndReplies() {
    _dataService!.loadReactionsFromCache().then((_) {
      reactionsMap.addAll(_dataService!.reactionsMap);
      setState(() {});
    });
    _dataService!.loadRepliesFromCache().then((_) {
      repliesMap.addAll(_dataService!.repliesMap);
      setState(() {});
    });
  }

  Future<void> _loadOlderNotes() async {
    if (_dataService == null || isLoadingOlderNotes) return;
    setState(() {
      isLoadingOlderNotes = true;
    });

    await _dataService!.fetchOlderNotes([widget.npub], (olderNote) {
      if (!cachedNoteIds.contains(olderNote.id)) {
        cachedNoteIds.add(olderNote.id);
        profileNotes.add(olderNote);
        _dataService!.fetchReactionsForNotes([olderNote.id]);
        _dataService!.fetchRepliesForNotes([olderNote.id]);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: CustomScrollView(
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
                  GestureDetector(
                    onTap: () {},
                    child: userProfile['profileImage']!.isNotEmpty
                        ? CircleAvatar(
                            radius: 30,
                            backgroundImage:
                                CachedNetworkImageProvider(userProfile['profileImage']!),
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
                            '${userProfile['nip05']}',
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
                  child: Center(child: CircularProgressIndicator()),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index == profileNotes.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final item = profileNotes[index];
                      final reactions = reactionsMap[item.id] ?? [];
                      final replies = repliesMap[item.id] ?? [];
                      return ListTile(
                        title: GestureDetector(
                          onTap: () {},
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
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  'Reactions: ${reactions.length}',
                                  style:
                                      const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  'Replies: ${replies.length}',
                                  style:
                                      const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: GestureDetector(
                          onTap: () {},
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
                                      reactions: reactions,
                                      replies: replies,
                                      reactionsMap: reactionsMap,
                                      repliesMap: repliesMap,
                                    )),
                          );
                        },
                      );
                    },
                    childCount: profileNotes.length + (isLoadingOlderNotes ? 1 : 0),
                  ),
                ),
          if (isLoadingOlderNotes)
            SliverToBoxAdapter(
              child: const Padding(
                padding: EdgeInsets.all(16.0),
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
