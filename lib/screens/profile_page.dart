import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:qiqstr/screens/login_page.dart';
import 'package:qiqstr/screens/note_detail_page.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../services/qiqstr_service.dart';
import 'send_reply.dart';
import '../widgets/note_widget.dart';

class ThreeDotsLoading extends StatefulWidget {
  final double size;
  final Color color;
  final Duration duration;

  const ThreeDotsLoading({
    Key? key,
    this.size = 8.0,
    this.color = Colors.grey,
    this.duration = const Duration(milliseconds: 500),
  }) : super(key: key);

  @override
  _ThreeDotsLoadingState createState() => _ThreeDotsLoadingState();
}

class _ThreeDotsLoadingState extends State<ThreeDotsLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildDot(int index) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: widget.size,
        height: widget.size,
        margin: const EdgeInsets.symmetric(horizontal: 2.0),
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return DelayAnimation(
          delay: Duration(milliseconds: index * 200),
          child: _buildDot(index),
        );
      }),
    );
  }
}

class DelayAnimation extends StatelessWidget {
  final Widget child;
  final Duration delay;

  const DelayAnimation({Key? key, required this.child, required this.delay})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.delayed(delay),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return child;
        } else {
          return Opacity(opacity: 0.0, child: child);
        }
      },
    );
  }
}

class ReactionsSection extends StatelessWidget {
  final List<ReactionModel> reactions;
  final bool isLoading;

  const ReactionsSection({
    Key? key,
    required this.reactions,
    required this.isLoading,
  }) : super(key: key);

  Map<String, List<ReactionModel>> _groupReactions(
      List<ReactionModel> reactions) {
    Map<String, List<ReactionModel>> grouped = {};
    for (var reaction in reactions) {
      grouped.putIfAbsent(reaction.content, () => []).add(reaction);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            'REACTIONS:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        if (isLoading)
          const Padding(
            padding:
                EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
            child: ThreeDotsLoading(),
          )
        else if (reactions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'No reactions yet.',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _groupReactions(reactions).entries.map((entry) {
                final reactionContent = entry.key;
                final reactionList = entry.value;
                final reactionCount = reactionList.length;
                return GestureDetector(
                  onTap: () => _showReactionDetails(
                      context, reactionContent, reactionList),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          reactionContent,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$reactionCount',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  void _showReactionDetails(
      BuildContext context, String reactionContent, List<ReactionModel> reactionList) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return ReactionDetailsModal(
            reactionContent: reactionContent, reactions: reactionList);
      },
    );
  }
}

class RepliesSection extends StatelessWidget {
  final List<ReplyModel> replies;
  final bool isLoading;
  final Function(String) onSendReplyReaction;
  final Function(String) onShowReplyDialog;
  final Function(String) onNavigateToProfile;
  final Set<String> glowingReplies;
  final Set<String> swipedReplies;

  const RepliesSection({
    Key? key,
    required this.replies,
    required this.isLoading,
    required this.onSendReplyReaction,
    required this.onShowReplyDialog,
    required this.onNavigateToProfile,
    required this.glowingReplies,
    required this.swipedReplies,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            'REPLIES:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        if (isLoading)
          const Padding(
            padding:
                EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
            child: ThreeDotsLoading(),
          )
        else if (replies.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'No replies yet.',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: replies.length,
              itemBuilder: (context, index) {
                final reply = replies[index];
                return NoteWidget(
                  key: ValueKey(reply.id),
                  note: convertReplyToNote(reply),
                  reactionCount: 0,
                  replyCount: 0,
                  onSendReaction: onSendReplyReaction,
                  onShowReplyDialog: onShowReplyDialog,
                  onAuthorTap: () {
                    onNavigateToProfile(reply.author);
                  },
                  onRepostedByTap: null,
                  onNoteTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => NoteDetailPage(note: convertReplyToNote(reply)),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}

NoteModel convertReplyToNote(ReplyModel reply) {
  return NoteModel(
    id: reply.id,
    content: reply.content,
    author: reply.author,
    authorName: reply.authorName,
    authorProfileImage: reply.authorProfileImage,
    timestamp: reply.timestamp,
    isRepost: false,
    repostedBy: null,
    repostedByName: '',
  );
}

class ProfilePage extends StatefulWidget {
  final String npub;

  const ProfilePage({super.key, required this.npub});

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final List<NoteModel> _profileNotes = [];
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

  void _handleReactionsUpdated(String noteId, List<ReactionModel> reactions) {
    setState(() {
      _reactionCounts[noteId] = reactions.length;
    });
  }

  void _handleRepliesUpdated(String noteId, List<ReplyModel> replies) {
    setState(() {
      _replyCounts[noteId] = replies.length;
    });
  }

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
        _reactionCounts[noteId] = (_reactionCounts[noteId] ?? 0) + 1;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending reaction: $e')),
      );
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
    return NoteWidget(
      key: ValueKey(item.id),
      note: item,
      reactionCount: _reactionCounts[item.id] ?? 0,
      replyCount: _replyCounts[item.id] ?? 0,
      onSendReaction: _sendReaction,
      onShowReplyDialog: _showReplyDialog,
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

class ReactionDetailsModal extends StatelessWidget {
  final String reactionContent;
  final List<ReactionModel> reactions;

  const ReactionDetailsModal({
    Key? key,
    required this.reactionContent,
    required this.reactions,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 16),
          Text(
            'Reactions: $reactionContent',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: reactions.length,
              itemBuilder: (context, index) {
                final reaction = reactions[index];
                return ListTile(
                  leading: reaction.authorProfileImage.isNotEmpty
                      ? CircleAvatar(
                          backgroundImage:
                              CachedNetworkImageProvider(reaction.authorProfileImage),
                        )
                      : const CircleAvatar(
                          child: Icon(Icons.person),
                        ),
                  title: Text(reaction.authorName),
                  trailing: Text(
                      reaction.content.isNotEmpty ? reaction.content : '+'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProfilePage(npub: reaction.author),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
