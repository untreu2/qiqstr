import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/services/qiqstr_service.dart';
import '../screens/login_page.dart';
import '../widgets/note_widget.dart';

class ProfilePage extends StatefulWidget {
  final String npub;

  const ProfilePage({super.key, required this.npub});

  @override
  ProfilePageState createState() => ProfilePageState();
}

class ProfilePageState extends State<ProfilePage> {
  final List<NoteModel> _profileNotes = [];
  final Set<String> _glowingNotes = {};
  final Set<String> _swipedNotes = {};
  bool _isLoadingOlderNotes = false;
  bool _isLoading = true;
  late DataService _dataService;
  UserModel? _currentUserProfile;
  Color _backgroundColor = Colors.blueAccent.withOpacity(0.1);
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  final Map<String, int> _reactionCounts = {};
  final Map<String, int> _replyCounts = {};

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
        onReactionCountUpdated: _updateReactionCount,
        onReplyCountUpdated: _updateReplyCount,
      );
      await _dataService.initialize();
      await _dataService.loadNotesFromCache((cachedNotes) {
        setState(() {
          _profileNotes.addAll(cachedNotes);
          _sortProfileNotes();
          for (var note in _profileNotes) {
            _reactionCounts[note.id] = _dataService.reactionsMap[note.id]?.length ?? 0;
            _replyCounts[note.id] = _dataService.repliesMap[note.id]?.length ?? 0;
          }
        });
      });
      await _dataService.initializeConnections();
      await _fetchCountsForNotes();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Profile initialization error: $e')),
      );
    }
  }

  Future<void> _fetchCountsForNotes() async {
    try {
      for (var note in _profileNotes) {
        final reactionCount = _dataService.reactionsMap[note.id]?.length ?? 0;
        final replyCount = _dataService.repliesMap[note.id]?.length ?? 0;
        setState(() {
          _reactionCounts[note.id] = reactionCount;
          _replyCounts[note.id] = replyCount;
        });
      }
    } catch (e) {
      print('Error fetching counts: $e');
      setState(() {
        for (var note in _profileNotes) {
          _reactionCounts[note.id] = _reactionCounts[note.id] ?? 0;
          _replyCounts[note.id] = _replyCounts[note.id] ?? 0;
        }
      });
    }
  }

  void _handleNewNote(NoteModel newNote) {
    setState(() {
      _profileNotes.insert(0, newNote);
      _sortProfileNotes();
      _reactionCounts[newNote.id] = _dataService.reactionsMap[newNote.id]?.length ?? 0;
      _replyCounts[newNote.id] = _dataService.repliesMap[newNote.id]?.length ?? 0;
    });
    _dataService.saveNotesToCache();
  }

  void _handleReactionsUpdated(String noteId, List<dynamic> reactions) {
    setState(() {
      _reactionCounts[noteId] = reactions.length;
    });
  }

  void _handleRepliesUpdated(String noteId, List<dynamic> replies) {
    setState(() {
      _replyCounts[noteId] = replies.length;
    });
  }

  void _updateReactionCount(String noteId, int count) {
    setState(() {
      _reactionCounts[noteId] = count;
    });
  }

  void _updateReplyCount(String noteId, int count) {
    setState(() {
      _replyCounts[noteId] = count;
    });
  }

  void _sortProfileNotes() {
    _profileNotes.sort((a, b) {
      final aTimestamp = a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
      final bTimestamp = b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
      return bTimestamp.compareTo(aTimestamp);
    });
  }

  Future<void> _updateUserProfile() async {
    try {
      final usersBox = Hive.box<UserModel>('users');
      final userModel = usersBox.get(widget.npub);
      setState(() {
        _currentUserProfile = userModel;
      });
      if (_currentUserProfile != null && _currentUserProfile!.profileImage.isNotEmpty) {
        await _updateBackgroundColor(_currentUserProfile!.profileImage);
      }
    } catch (e) {
      print('Error updating user profile: $e');
    }
  }

  Future<void> _updateBackgroundColor(String imageUrl) async {
    try {
      final paletteGenerator =
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

  Widget _buildBannerImage() {
    if (_currentUserProfile == null) return const SizedBox.shrink();
    final bannerUrl = _currentUserProfile!.banner;
    if (bannerUrl.isEmpty) return const SizedBox.shrink();
    return CachedNetworkImage(
      imageUrl: bannerUrl,
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

  Widget _buildProfileHeader() {
    if (_currentUserProfile == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        color: _backgroundColor,
        child: const Text('Loading profile...'),
      );
    }
    final profileImage = _currentUserProfile!.profileImage;
    final name = _currentUserProfile!.name;
    final about = _currentUserProfile!.about;
    final nip05 = _currentUserProfile!.nip05;
    return Container(
      padding: const EdgeInsets.all(16),
      color: _backgroundColor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          profileImage.isNotEmpty
              ? CircleAvatar(
                  radius: 30,
                  backgroundImage: CachedNetworkImageProvider(profileImage),
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
                  name,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (about.isNotEmpty)
                  Text(
                    about,
                    style: const TextStyle(fontSize: 14),
                  ),
                const SizedBox(height: 8),
                if (nip05.isNotEmpty)
                  Text(
                    nip05,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedItem(NoteModel item) {
    return NoteWidget(
      key: ValueKey(item.id),
      note: item,
      reactionCount: _reactionCounts[item.id] ?? 0,
      replyCount: _replyCounts[item.id] ?? 0,
      dataService: _dataService,
    );
  }

  Widget _buildNotesList() {
    if (_profileNotes.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Text(
            'No notes available.',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
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

  void _onScroll() {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
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
      await _fetchCountsForNotes();
    } catch (e) {
      print('Error loading older notes: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading older notes: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingOlderNotes = false;
        });
      }
    }
  }

  void _handleOlderNote(NoteModel olderNote) {
    setState(() {
      _profileNotes.add(olderNote);
      _sortProfileNotes();
      _reactionCounts[olderNote.id] = _dataService.reactionsMap[olderNote.id]?.length ?? 0;
      _replyCounts[olderNote.id] = _dataService.repliesMap[olderNote.id]?.length ?? 0;
    });
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
              Navigator.pop(context);
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
        _glowingNotes.clear();
        _swipedNotes.clear();
        _reactionCounts.clear();
        _replyCounts.clear();
        _isLoading = true;
      });
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (Route<dynamic> route) => false,
      );
    } catch (e) {
      print('Logout error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logout error: $e')),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _dataService.closeConnections();
    Hive.close();
    super.dispose();
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
        top: true,
        bottom: false,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            if (_currentUserProfile != null && _currentUserProfile!.banner.isNotEmpty)
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
