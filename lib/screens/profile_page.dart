import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/note_model.dart';
import '../services/qiqstr_service.dart';
import '../widgets/note_widget.dart';
import 'note_detail_page.dart';
import 'share_note.dart';
import 'send_reply.dart';
import 'login_page.dart';

class ProfilePage extends StatefulWidget {
  final String npub;

  const ProfilePage({Key? key, required this.npub}) : super(key: key);

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final List<NoteModel> profileItems = [];
  final Set<String> cachedNoteIds = {};
  final Set<String> glowingNotes = {};
  final Set<String> swipedNotes = {};
  bool isLoadingOlderNotes = false;
  bool isInitializing = true;
  DataService? _dataService;
  final ScrollController _scrollController = ScrollController();

  String bio = "";
  String nip05 = "";
  String name = "";
  String profileImageUrl = "";
  String bannerImageUrl = "";

  @override
  void initState() {
    super.initState();
    _initializeProfile();
  }

  Future<void> _initializeProfile() async {
    try {
      _dataService = DataService(
        npub: widget.npub,
        dataType: DataType.Profile,
        onNewNote: _handleNewNote,
      );

      await _dataService!.initialize();
      await _dataService!.initializeConnections();
      await _loadProfileFromCache();
      await _loadUserInfo();

      setState(() {
        isInitializing = false;
      });
    } catch (e) {
      print('Profile initialization error: $e');
      setState(() {
        isInitializing = false;
      });
    }
  }

  Future<void> _loadProfileFromCache() async {
    await _dataService!.loadNotesFromCache((cachedNotes) {
      final newNotes = cachedNotes.where((note) => !cachedNoteIds.contains(note.id)).toList();
      setState(() {
        cachedNoteIds.addAll(newNotes.map((note) => note.id));
        profileItems.addAll(newNotes);
        profileItems.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      });
    });
  }

  Future<void> _loadUserInfo() async {
    try {
      final userInfo = await _dataService!.getCachedUserProfile(widget.npub);
      setState(() {
        bio = userInfo['about'] ?? '';
        nip05 = userInfo['nip05'] ?? '';
        name = userInfo['name'] ?? 'Anonymous';
        profileImageUrl = userInfo['profileImage'] ?? '';
        bannerImageUrl = userInfo['banner'] ?? '';
      });
    } catch (e) {
      print('Error loading user info: $e');
    }
  }

  @override
  void dispose() {
    _dataService?.closeConnections();
    super.dispose();
  }

  void _handleNewNote(NoteModel newNote) {
    if (!cachedNoteIds.contains(newNote.id)) {
      cachedNoteIds.add(newNote.id);
      int insertIndex = profileItems.indexWhere((note) => note.timestamp.isBefore(newNote.timestamp));
      if (insertIndex == -1) {
        profileItems.add(newNote);
      } else {
        profileItems.insert(insertIndex, newNote);
      }
      _dataService!.saveNotesToCache();
      setState(() {});
    }
  }

  Future<void> _loadOlderNotes() async {
    if (isLoadingOlderNotes) return;
    setState(() {
      isLoadingOlderNotes = true;
    });
    await _dataService!.fetchOlderNotes(widget.npub as List<String>, (olderNote) {
      if (!cachedNoteIds.contains(olderNote.id)) {
        cachedNoteIds.add(olderNote.id);
        profileItems.add(olderNote);
        setState(() {});
      }
    });
    setState(() {
      isLoadingOlderNotes = false;
    });
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
    } catch (e) {
      print('Error sending reaction: $e');
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
        dataService: _dataService!,
        noteId: noteId,
      ),
    );
  }

  Future<void> _logoutAndClearData() async {
    try {
      const secureStorage = FlutterSecureStorage();
      await secureStorage.deleteAll();

      await Hive.deleteFromDisk();

      await _dataService?.closeConnections();

      profileItems.clear();
      cachedNoteIds.clear();
      glowingNotes.clear();
      swipedNotes.clear();
      setState(() {
        isInitializing = true;
      });

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: isInitializing && profileItems.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : NotificationListener<ScrollNotification>(
                onNotification: (scrollInfo) {
                  if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200 &&
                      !isLoadingOlderNotes) {
                    _loadOlderNotes();
                  }
                  return false;
                },
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          bannerImageUrl.isNotEmpty
                              ? Image.network(
                                  bannerImageUrl,
                                  width: double.infinity,
                                  height: 150,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  width: double.infinity,
                                  height: 150,
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.scanner, size: 50, color: Colors.white),
                                ),
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 40,
                                  backgroundImage: profileImageUrl.isNotEmpty
                                      ? NetworkImage(profileImageUrl)
                                      : null,
                                  child: profileImageUrl.isEmpty
                                      ? const Icon(Icons.person, size: 40)
                                      : null,
                                ),
                                const SizedBox(width: 16.0),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name.isNotEmpty ? name : 'Username',
                                        style: const TextStyle(
                                          fontSize: 20.0,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4.0),
                                      Text(
                                        bio.isNotEmpty ? bio : 'No bio available.',
                                        style: const TextStyle(fontSize: 14.0),
                                      ),
                                      const SizedBox(height: 4.0),
                                      Text(
                                        nip05.isNotEmpty ? 'NIP-05: $nip05' : 'No NIP-05 information.',
                                        style: const TextStyle(fontSize: 12.0, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.logout),
                                  onPressed: _logoutAndClearData,
                                ),
                              ],
                            ),
                          ),
                          const Divider(),
                        ],
                      ),
                    ),
                    profileItems.isEmpty
                        ? const SliverFillRemaining(
                            child: Center(child: Text('You have not shared anything yet.')),
                          )
                        : SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                if (index == profileItems.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Center(child: CircularProgressIndicator()),
                                  );
                                }
                                final item = profileItems[index];
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
                                            builder: (context) => NoteDetailPage(note: item),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                );
                              },
                              childCount: profileItems.length + (isLoadingOlderNotes ? 1 : 0),
                            ),
                          ),
                  ],
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
}
