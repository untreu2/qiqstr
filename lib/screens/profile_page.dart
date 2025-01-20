import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hive/hive.dart';
import 'package:qiqstr/models/note_model.dart';
import 'package:qiqstr/models/user_model.dart';
import 'package:qiqstr/services/qiqstr_service.dart';
import '../widgets/note_widget.dart';

class ProfilePage extends StatefulWidget {
  final String npub;

  const ProfilePage({Key? key, required this.npub}) : super(key: key);

  @override
  ProfilePageState createState() => ProfilePageState();
}

class ProfilePageState extends State<ProfilePage> {
  final List<NoteModel> _profileItems = [];
  bool _isLoadingOlderNotes = false;
  bool _isInitializing = true;
  late DataService _dataService;
  UserModel? _currentUserProfile;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  Map<String, int> _reactionCounts = {};
  Map<String, int> _replyCounts = {};
  Map<String, int> _repostCounts = {};

  @override
  void initState() {
    super.initState();
    _initializeProfile();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _initializeProfile() async {
    try {
      _dataService = DataService(
        npub: widget.npub,
        dataType: DataType.Profile,
        onNewNote: _handleNewNote,
        onReactionsUpdated: _handleReactionsUpdated,
        onRepliesUpdated: _handleRepliesUpdated,
        onReactionCountUpdated: _updateReactionCount,
        onReplyCountUpdated: _updateReplyCount,
        onRepostCountUpdated: _updateRepostCount,
      );

      await _dataService.initialize();
      await _dataService.loadNotesFromCache((cachedNotes) {
        setState(() {
          _profileItems.addAll(cachedNotes);
          _sortProfileItems();
          for (var note in _profileItems) {
            _reactionCounts[note.id] = _dataService.reactionsMap[note.id]?.length ?? 0;
            _replyCounts[note.id] = _dataService.repliesMap[note.id]?.length ?? 0;
            _repostCounts[note.id] = _dataService.repostsMap[note.id]?.length ?? 0;
          }
        });
      });

      await _dataService.initializeConnections();
      await _loadUserProfile();
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
      print('Error initializing profile: $e');
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final usersBox = Hive.box<UserModel>('users');
      final user = usersBox.get(widget.npub);
      setState(() {
        _currentUserProfile = user;
      });
    } catch (e) {
      print('Error loading profile data: $e');
    }
  }

  void _handleNewNote(NoteModel newNote) {
    setState(() {
      _profileItems.insert(0, newNote);
      _sortProfileItems();
      _reactionCounts[newNote.id] = _dataService.reactionsMap[newNote.id]?.length ?? 0;
      _replyCounts[newNote.id] = _dataService.repliesMap[newNote.id]?.length ?? 0;
      _repostCounts[newNote.id] = _dataService.repostsMap[newNote.id]?.length ?? 0;
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

  void _updateRepostCount(String noteId, int count) {
    setState(() {
      _repostCounts[noteId] = count;
    });
  }

  void _sortProfileItems() {
    _profileItems.sort((a, b) {
      final aTimestamp = a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
      final bTimestamp = b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
      return bTimestamp.compareTo(aTimestamp);
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
      _profileItems.add(olderNote);
      _sortProfileItems();
      _reactionCounts[olderNote.id] = _dataService.reactionsMap[olderNote.id]?.length ?? 0;
      _replyCounts[olderNote.id] = _dataService.repliesMap[olderNote.id]?.length ?? 0;
      _repostCounts[olderNote.id] = _dataService.repostsMap[olderNote.id]?.length ?? 0;
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingOlderNotes &&
        !_isInitializing) {
      _loadOlderNotes();
    }
  }

  Widget _buildProfileHeader() {
    if (_currentUserProfile == null) return const SizedBox.shrink();
    return Column(
      children: [
        if (_currentUserProfile!.banner.isNotEmpty)
          CachedNetworkImage(
            imageUrl: _currentUserProfile!.banner,
            width: double.infinity,
            height: 200,
            fit: BoxFit.cover,
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundImage: CachedNetworkImageProvider(_currentUserProfile!.profileImage),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_currentUserProfile!.name,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    if (_currentUserProfile!.nip05.isNotEmpty)
                      Text(_currentUserProfile!.nip05,
                          style: const TextStyle(fontSize: 14, color: Colors.grey)),
                    if (_currentUserProfile!.about.isNotEmpty)
                      Text(_currentUserProfile!.about),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(child: _buildProfileHeader()),
          _isInitializing
              ? const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = _profileItems[index];
                      return NoteWidget(
                        note: item,
                        reactionCount: _reactionCounts[item.id] ?? 0,
                        replyCount: _replyCounts[item.id] ?? 0,
                        repostCount: _repostCounts[item.id] ?? 0,
                        dataService: _dataService,
                      );
                    },
                    childCount: _profileItems.length,
                  ),
                ),
        ],
      ),
    );
  }
}
