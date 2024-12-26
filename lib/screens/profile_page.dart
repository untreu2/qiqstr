import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:qiqstr/models/reaction_model.dart';
import 'package:qiqstr/models/reply_model.dart';
import 'package:qiqstr/screens/login_page.dart';
import '../models/note_model.dart';
import '../services/qiqstr_service.dart';
import 'note_detail_page.dart';
import 'send_reply.dart';
import '../widgets/note_widget.dart';

class ProfilePage extends StatefulWidget {
  final String npub;

  const ProfilePage({super.key, required this.npub});

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final List<NoteModel> _profileNotes = [];
  final Set<String> _cachedNoteIds = {};
  final Set<String> _glowingNotes = {};
  final Set<String> _swipedNotes = {};
  bool _isLoadingOlderNotes = false;
  bool _isLoading = true;
  late DataService _dataService;

  Map<String, String> _userProfile = {
    'name': 'Loading...',
    'profileImage': '',
    'about': '',
    'nip05': '',
    'banner': '',
  };

  Color _backgroundColor = Colors.blueAccent.withOpacity(0.1);

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _initializeDataService();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _initializeDataService() async {
    try {
      _dataService = DataService(
        npub: widget.npub,
        dataType: DataType.Profile,
        onNewNote: _handleNewNote,
        onReactionsUpdated: _handleReactionsUpdated,
        onRepliesUpdated: _handleRepliesUpdated,
      );

      await _dataService.initialize();
      await _loadProfileFromCache();
      await _dataService.initializeConnections();
      await _updateUserProfile();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      print('Profile initialization error: $e');
    }
  }

  Future<void> _loadProfileFromCache() async {
    await _dataService.loadNotesFromCache((cachedNotes) {
      final newNotes = cachedNotes.where((note) => !_cachedNoteIds.contains(note.id)).toList();
      setState(() {
        _cachedNoteIds.addAll(newNotes.map((note) => note.id));
        _profileNotes.addAll(newNotes);
        _sortProfileNotes();
      });
    });
  }

  void _handleNewNote(NoteModel newNote) {
    if (!_cachedNoteIds.contains(newNote.id)) {
      setState(() {
        _cachedNoteIds.add(newNote.id);
        _profileNotes.insert(0, newNote);
        _sortProfileNotes();
      });
      _dataService.saveNotesToCache();
    }
  }

  void _handleReactionsUpdated(String noteId, List<ReactionModel> reactions) {}

  void _handleRepliesUpdated(String noteId, List<ReplyModel> replies) {}

  void _sortProfileNotes() {
    _profileNotes.sort((a, b) {
      final aTimestamp = a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
      final bTimestamp = b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
      return bTimestamp.compareTo(aTimestamp);
    });
  }

  void _onScroll() {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
          !_isLoadingOlderNotes &&
          !_isLoading) {
        _loadOlderNotes();
      }
    });
  }

  Future<void> _loadOlderNotes() async {
    if (_isLoadingOlderNotes) return;
    setState(() {
      _isLoadingOlderNotes = true;
    });

    try {
      await _dataService.fetchOlderNotes([widget.npub], _handleOlderNote);
    } catch (e) {
      print('Error loading older notes: $e');
    }

    if (mounted) {
      setState(() {
        _isLoadingOlderNotes = false;
      });
    }
  }

  void _handleOlderNote(NoteModel olderNote) {
    if (!_cachedNoteIds.contains(olderNote.id)) {
      setState(() {
        _cachedNoteIds.add(olderNote.id);
        _profileNotes.add(olderNote);
        _sortProfileNotes();
      });
    }
  }

  Future<void> _updateUserProfile() async {
    final profile = await _dataService.getCachedUserProfile(widget.npub);
    if (!mounted) return;
    setState(() {
      _userProfile = profile;
    });
    if (_userProfile['profileImage']!.isNotEmpty) {
      await _updateBackgroundColor(_userProfile['profileImage']!);
    }
  }

  Future<void> _updateBackgroundColor(String imageUrl) async {
    try {
      final PaletteGenerator paletteGenerator =
          await PaletteGenerator.fromImageProvider(CachedNetworkImageProvider(imageUrl));
      if (!mounted) return;
      setState(() {
        _backgroundColor = paletteGenerator.dominantColor?.color.withOpacity(0.1) ??
            Colors.blueAccent.withOpacity(0.1);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _backgroundColor = Colors.blueAccent.withOpacity(0.1);
      });
      print('Error generating palette: $e');
    }
  }

  Future<void> _sendReaction(String noteId) async {
    try {
      await _dataService.sendReaction(noteId, '💜');
      setState(() {
        _glowingNotes.add(noteId);
      });

      Timer(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() {
            _glowingNotes.remove(noteId);
          });
        }
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
        dataService: _dataService,
        noteId: noteId,
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: _backgroundColor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _userProfile['profileImage']!.isNotEmpty
              ? CircleAvatar(
                  radius: 30,
                  backgroundImage: CachedNetworkImageProvider(_userProfile['profileImage']!),
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
                  _userProfile['name']!,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_userProfile['about']!.isNotEmpty)
                  Text(
                    _userProfile['about']!,
                    style: const TextStyle(fontSize: 14),
                  ),
                const SizedBox(height: 8),
                if (_userProfile['nip05']!.isNotEmpty)
                  Text(
                    _userProfile['nip05']!,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBannerImage() {
    if (_userProfile['banner']!.isEmpty) return const SizedBox.shrink();
    return CachedNetworkImage(
      imageUrl: _userProfile['banner']!,
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
    );
  }

  Widget _buildFeedItem(NoteModel item) {
    return GestureDetector(
      onDoubleTap: () {
        _sendReaction(item.id);
      },
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 0) {
          _swipeNoteForReply(item.id);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          border: _glowingNotes.contains(item.id)
              ? Border.all(color: Colors.white, width: 4.0)
              : _swipedNotes.contains(item.id)
                  ? Border.all(color: Colors.white, width: 4.0)
                  : null,
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: NoteWidget(
          key: ValueKey(item.id),
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
  }

  Widget _buildNotesList() {
    if (_profileNotes.isEmpty) {
      return const SliverFillRemaining(
        child: Center(child: Text('No notes available.')),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == _profileNotes.length) {
            return _isLoadingOlderNotes
                ? const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : const SizedBox.shrink();
          }

          final item = _profileNotes[index];
          return _buildFeedItem(item);
        },
        childCount: _profileNotes.length + 1,
      ),
    );
  }

  Widget _buildSidebar() {
    return Drawer(
      child: ListView(
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(
              color: Colors.blue,
            ),
            child: Text(
              'Menu',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
              ),
            ),
          ),
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

      await _dataService.closeConnections();

      setState(() {
        _profileNotes.clear();
        _cachedNoteIds.clear();
        _glowingNotes.clear();
        _swipedNotes.clear();
        _isLoading = true;
      });

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (Route<dynamic> route) => false,
      );
    } catch (e) {
      print('Logout error: $e');
    }
  }

  void _swipeNoteForReply(String noteId) {
    setState(() {
      _swipedNotes.add(noteId);
    });
    _showReplyDialog(noteId);
    Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _swipedNotes.remove(noteId);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _profileNotes.isEmpty) {
      return Scaffold(
        key: _scaffoldKey,
        drawer: _buildSidebar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildSidebar(),
      body: SafeArea(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            if (_userProfile['banner']!.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildBannerImage(),
              ),
            SliverToBoxAdapter(
              child: _buildProfileHeader(),
            ),
            _buildNotesList(),
          ],
        ),
      ),
    );
  }
}
