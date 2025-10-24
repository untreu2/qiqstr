import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/note_model.dart';
import '../models/user_model.dart';
import '../core/di/app_di.dart';
import '../data/repositories/user_repository.dart';
import '../data/repositories/note_repository.dart';
import '../services/time_service.dart';
import '../theme/theme_manager.dart';
import '../screens/thread_page.dart';
import '../screens/profile_page.dart';
import 'note_content_widget.dart';
import 'interaction_bar_widget.dart';

class NoteWidget extends StatefulWidget {
  final NoteModel note;
  final String currentUserNpub;
  final ValueNotifier<List<NoteModel>> notesNotifier;
  final Map<String, UserModel> profiles;
  final Color? containerColor;
  final bool isSmallView;
  final ScrollController? scrollController;
  final dynamic notesListProvider;

  const NoteWidget({
    super.key,
    required this.note,
    required this.currentUserNpub,
    required this.notesNotifier,
    required this.profiles,
    this.containerColor,
    this.isSmallView = true,
    this.scrollController,
    this.notesListProvider,
  });

  @override
  State<NoteWidget> createState() => _NoteWidgetState();
}

class _NoteWidgetState extends State<NoteWidget> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final String _noteId;
  late final String _authorId;
  late final String? _reposterId;
  late final String? _parentId;
  late final bool _isReply;
  late final bool _isRepost;
  late final DateTime _timestamp;
  late final String _content;
  late final String _widgetKey;

  late final String _formattedTimestamp;
  late final Map<String, dynamic> _parsedContent;
  late final bool _shouldTruncate;
  late final Map<String, dynamic>? _truncatedContent;

  final ValueNotifier<_NoteState> _stateNotifier = ValueNotifier(_NoteState.initial());

  bool _isDisposed = false;
  bool _isInitialized = false;
  late final UserRepository _userRepository;
  late final NoteRepository _noteRepository;

  @override
  void initState() {
    super.initState();
    try {
      _userRepository = AppDI.get<UserRepository>();
      _noteRepository = AppDI.get<NoteRepository>();
      _precomputeImmutableData();
      _initializeAsync();
    } catch (e) {
      debugPrint('[NoteWidget] InitState error: $e');
      _isInitialized = false;
    }
  }

  void _precomputeImmutableData() {
    _noteId = widget.note.id;
    _authorId = widget.note.author;
    _reposterId = widget.note.repostedBy;
    _parentId = widget.note.parentId;
    _isReply = widget.note.isReply;
    _isRepost = widget.note.isRepost;
    _timestamp = widget.note.timestamp;
    _content = widget.note.content;
    _widgetKey = '${_noteId}_$_authorId';

    debugPrint(' [NoteWidget] Note ${_noteId.substring(0, 8)}: isReply=$_isReply, isRepost=$_isRepost, parentId=$_parentId');
    if (_isRepost) {
      debugPrint(' [NoteWidget] Repost by: $_reposterId, rootId: ${widget.note.rootId}');
    }

    _formattedTimestamp = _calculateTimestamp(_timestamp);

    try {
      _parsedContent = widget.note.parsedContentLazy;
    } catch (e) {
      debugPrint('[NoteWidget] ParseContent error: $e');
      _parsedContent = {
        'textParts': [
          {'type': 'text', 'text': _content}
        ],
        'mediaUrls': <String>[],
        'linkUrls': <String>[],
        'quoteIds': <String>[],
      };
    }

    _shouldTruncate = _calculateTruncation(_parsedContent);
    _truncatedContent = _shouldTruncate ? _createTruncatedContent() : null;

    _isInitialized = true;
  }

  void _initializeAsync() {
    Future.microtask(() {
      if (_isDisposed || !mounted) return;

      try {
        _setupUserListener();
        _loadInitialUserData();
        _loadUsersAsync();
        _loadInteractionsAsync();
      } catch (e) {
        debugPrint('[NoteWidget] Async init error: $e');
      }
    });
  }

  void _setupUserListener() {
    try {
      widget.notesNotifier.addListener(_onNotesChange);
    } catch (e) {
      debugPrint('[NoteWidget] Setup listener error: $e');
    }
  }

  void _onNotesChange() {
    if (!mounted || _isDisposed) return;

    try {
      _updateUserData();
    } catch (e) {
      debugPrint('[NoteWidget] Notes change error: $e');
    }
  }

  void _loadInitialUserData() {
    try {
      _updateUserData();
    } catch (e) {
      debugPrint('[NoteWidget] Load initial user data error: $e');
    }
  }

  void _updateUserData() {
    if (_isDisposed || !mounted) return;

    try {
      final currentState = _stateNotifier.value;

      UserModel? authorUser = widget.profiles[_authorId];
      UserModel? reposterUser = _reposterId != null ? widget.profiles[_reposterId] : null;

      authorUser ??= UserModel(
        pubkeyHex: _authorId,
        name: _authorId.length > 8 ? _authorId.substring(0, 8) : _authorId,
        about: '',
        profileImage: '',
        banner: '',
        website: '',
        nip05: '',
        lud16: '',
        updatedAt: DateTime.now(),
        nip05Verified: false,
      );

      if (_reposterId != null && reposterUser == null) {
        final reposterId = _reposterId;
        reposterUser = UserModel(
          pubkeyHex: reposterId,
          name: reposterId.length > 8 ? reposterId.substring(0, 8) : reposterId,
          about: '',
          profileImage: '',
          banner: '',
          website: '',
          nip05: '',
          lud16: '',
          updatedAt: DateTime.now(),
          nip05Verified: false,
        );
      }

      final replyText = _isReply && _parentId != null ? 'Reply to...' : null;

      if (_isReply) {
        debugPrint(' [NoteWidget] Reply detected: parentId=$_parentId, replyText="$replyText"');
      }

      final newState = _NoteState(
        authorUser: authorUser,
        reposterUser: reposterUser,
        replyText: replyText,
      );

      if (currentState != newState) {
        _stateNotifier.value = newState;
      }
    } catch (e) {
      debugPrint('[NoteWidget] Update user data error: $e');
    }
  }

  Future<void> _loadUsersAsync() async {
    if (_isDisposed || !mounted) return;

    try {
      final authorUser = widget.profiles[_authorId];
      final reposterUser = _reposterId != null ? widget.profiles[_reposterId] : null;

      bool isProfileComplete(UserModel? user, String userId) {
        if (user == null) return false;
        if (user.name == 'Anonymous') return false;
        if (user.name == userId.substring(0, 8)) return false;
        if (user.profileImage.isEmpty) return false;
        return true;
      }

      final reposterId = _reposterId;
      if (isProfileComplete(authorUser, _authorId) && (reposterId == null || isProfileComplete(reposterUser, reposterId))) {
        debugPrint('[NoteWidget] ✓ Using cached profiles with images for ${_noteId.substring(0, 8)}');
        return;
      }

      debugPrint('[NoteWidget] ️ Loading missing/incomplete profiles for ${_noteId.substring(0, 8)}');
      if (authorUser != null && authorUser.profileImage.isEmpty) {
        debugPrint('[NoteWidget]   → Author ${authorUser.name} missing profile image');
      }
      if (reposterUser != null && reposterUser.profileImage.isEmpty) {
        debugPrint('[NoteWidget]   → Reposter ${reposterUser.name} missing profile image');
      }

      if (widget.notesListProvider != null) {
        final authorPreloaded = widget.notesListProvider.getPreloadedUser(_authorId);
        final reposterPreloaded = reposterId != null ? widget.notesListProvider.getPreloadedUser(reposterId) : null;

        if (isProfileComplete(authorPreloaded, _authorId) && (reposterId == null || isProfileComplete(reposterPreloaded, reposterId))) {
          return;
        }
      }

      if (!isProfileComplete(authorUser, _authorId)) {
        debugPrint('[NoteWidget] Loading author profile: ${_authorId.substring(0, 8)}...');
        final authorResult = await _userRepository.getUserProfile(_authorId);
        authorResult.fold(
          (user) {
            if (mounted && !_isDisposed) {
              widget.profiles[_authorId] = user;
              debugPrint('[NoteWidget]  Author profile loaded: ${user.name} (image: ${user.profileImage.isNotEmpty ? "✓" : "✗"})');
              _updateUserData();
            }
          },
          (error) => debugPrint('[NoteWidget]  Failed to load author: $error'),
        );
      }

      if (_reposterId != null) {
        final reposterId = _reposterId;
        final currentReposterUser = widget.profiles[reposterId];

        if (!isProfileComplete(currentReposterUser, reposterId)) {
          debugPrint('[NoteWidget] Loading reposter profile: ${reposterId.substring(0, 8)}...');
          final reposterResult = await _userRepository.getUserProfile(reposterId);
          reposterResult.fold(
            (user) {
              if (mounted && !_isDisposed) {
                widget.profiles[reposterId] = user;
                debugPrint('[NoteWidget]  Reposter profile loaded: ${user.name} (image: ${user.profileImage.isNotEmpty ? "✓" : "✗"})');
                _updateUserData();
              }
            },
            (error) => debugPrint('[NoteWidget]  Failed to load reposter: $error'),
          );
        }
      }
    } catch (e) {
      debugPrint('[NoteWidget] Load users async error: $e');
    }
  }

  Future<void> _loadInteractionsAsync() async {
    if (_isDisposed || !mounted) return;

    try {
      Future.microtask(() {
        if (!_isDisposed && mounted) {
          final interactionNoteId = _getInteractionNoteId();
          _noteRepository.fetchInteractionsForNote(interactionNoteId);
        }
      });
    } catch (e) {
      debugPrint('[NoteWidget] Load interactions async error: $e');
    }
  }

  String _calculateTimestamp(DateTime timestamp) {
    try {
      final d = timeService.difference(timestamp);
      if (d.inSeconds < 5) return 'now';
      if (d.inSeconds < 60) return '${d.inSeconds}s';
      if (d.inMinutes < 60) return '${d.inMinutes}m';
      if (d.inHours < 24) return '${d.inHours}h';
      if (d.inDays < 7) return '${d.inDays}d';
      if (d.inDays < 30) return '${(d.inDays / 7).floor()}w';
      if (d.inDays < 365) return '${(d.inDays / 30).floor()}mo';
      return '${(d.inDays / 365).floor()}y';
    } catch (e) {
      debugPrint('[NoteWidget] Calculate timestamp error: $e');
      return 'unknown';
    }
  }

  bool _calculateTruncation(Map<String, dynamic> parsed) {
    try {
      const int characterLimit = 280;
      final textParts = (parsed['textParts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

      int estimatedLength = 0;
      for (var part in textParts) {
        if (part['type'] == 'text') {
          estimatedLength += (part['text'] as String? ?? '').length;
        } else if (part['type'] == 'mention') {
          estimatedLength += 8;
        }
        if (estimatedLength > characterLimit) return true;
      }
      return false;
    } catch (e) {
      debugPrint('[NoteWidget] Calculate truncation error: $e');
      return false;
    }
  }

  Map<String, dynamic> _createTruncatedContent() {
    try {
      const int characterLimit = 280;
      final textParts = (_parsedContent['textParts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      final truncatedParts = <Map<String, dynamic>>[];
      int currentLength = 0;

      for (var part in textParts) {
        if (part['type'] == 'text') {
          final text = part['text'] as String? ?? '';
          if (currentLength + text.length <= characterLimit) {
            truncatedParts.add(part);
            currentLength += text.length;
          } else {
            final remainingChars = characterLimit - currentLength;
            if (remainingChars > 0) {
              truncatedParts.add({
                'type': 'text',
                'text': '${text.substring(0, remainingChars)}... ',
              });
            }
            break;
          }
        } else if (part['type'] == 'mention') {
          if (currentLength + 8 <= characterLimit) {
            truncatedParts.add(part);
            currentLength += 8;
          } else {
            break;
          }
        }
      }

      truncatedParts.add({
        'type': 'show_more',
        'text': 'Show more...',
        'noteId': _noteId,
      });

      return {
        'textParts': truncatedParts,
        'mediaUrls': _parsedContent['mediaUrls'] ?? [],
        'linkUrls': _parsedContent['linkUrls'] ?? [],
        'quoteIds': _parsedContent['quoteIds'] ?? [],
      };
    } catch (e) {
      debugPrint('[NoteWidget] Create truncated content error: $e');
      return _parsedContent;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    try {
      widget.notesNotifier.removeListener(_onNotesChange);
      _stateNotifier.dispose();
    } catch (e) {
      debugPrint('[NoteWidget] Dispose error: $e');
    }
    super.dispose();
  }

  void _navigateToProfile(String npub) {
    try {
      if (mounted && !_isDisposed) {
        debugPrint('[NoteWidget] Attempting to navigate to profile: $npub');

        final user = widget.profiles[npub] ??
            UserModel(
              pubkeyHex: npub,
              name: npub.length > 8 ? npub.substring(0, 8) : npub,
              about: '',
              profileImage: '',
              banner: '',
              website: '',
              nip05: '',
              lud16: '',
              updatedAt: DateTime.now(),
              nip05Verified: false,
            );

        debugPrint('[NoteWidget] Created user for navigation: ${user.name}');

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfilePage(user: user),
          ),
        ).then((_) {
          debugPrint('[NoteWidget] Navigation completed');
        }).catchError((error) {
          debugPrint('[NoteWidget] Navigation error: $error');
        });
      }
    } catch (e) {
      debugPrint('[NoteWidget] Navigate to profile error: $e');
    }
  }

  void _navigateToMentionProfile(String id) {
    try {
      if (mounted && !_isDisposed) {
        _navigateToProfile(id);
      }
    } catch (e) {
      debugPrint('[NoteWidget] Navigate to mention profile error: $e');
    }
  }

  void _navigateToThreadPage() {
    try {
      if (!mounted || _isDisposed) return;

      String rootId;
      String? focusedId;

      if (_isRepost && widget.note.rootId != null && widget.note.rootId!.isNotEmpty) {
        rootId = widget.note.rootId!;
        focusedId = null;
        debugPrint('[NoteWidget] Navigating to repost thread - original note: $rootId');
      } else if (_isReply && widget.note.rootId != null && widget.note.rootId!.isNotEmpty) {
        rootId = widget.note.rootId!;
        focusedId = _noteId;
        debugPrint('[NoteWidget] Navigating to reply thread - root: $rootId, focused: $focusedId');
      } else {
        rootId = _noteId;
        focusedId = null;
        debugPrint('[NoteWidget] Navigating to regular note thread: $rootId');
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ThreadPage(
            rootNoteId: rootId,
            focusedNoteId: focusedId,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[NoteWidget] Navigate to thread error: $e');
    }
  }

  String _getInteractionNoteId() {
    if (_isRepost && widget.note.rootId != null && widget.note.rootId!.isNotEmpty) {
      debugPrint('[NoteWidget] Using original note ID for repost interactions: ${widget.note.rootId}');
      return widget.note.rootId!;
    }

    return _noteId;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (!_isInitialized || _isDisposed || !mounted) {
      return const SizedBox.shrink();
    }

    try {
      final colors = context.colors;
      final themeManager = context.themeManager;
      final isExpanded = themeManager?.isExpandedNoteMode ?? false;

      if (isExpanded) {
        return _buildExpandedLayout(colors);
      } else {
        return _buildNormalLayout(colors);
      }
    } catch (e) {
      debugPrint('[NoteWidget] Build error: $e');
      return const SizedBox.shrink();
    }
  }

  Widget _buildNormalLayout(dynamic colors) {
    return RepaintBoundary(
      key: ValueKey(_widgetKey),
      child: GestureDetector(
        onTap: _navigateToThreadPage,
        child: Container(
          color: widget.containerColor ?? colors.background,
          padding: const EdgeInsets.only(bottom: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SafeProfileSection(
                      stateNotifier: _stateNotifier,
                      isRepost: _isRepost,
                      onAuthorTap: () {
                        debugPrint('[NoteWidget] Author avatar tapped for: $_authorId');
                        _navigateToProfile(_authorId);
                      },
                      onReposterTap: _reposterId != null
                          ? () {
                              final reposterId = _reposterId;
                              _navigateToProfile(reposterId);
                            }
                          : null,
                      colors: colors,
                      widgetKey: _widgetKey,
                      isExpanded: false,
                      formattedTimestamp: _formattedTimestamp,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SafeUserInfoSection(
                            stateNotifier: _stateNotifier,
                            formattedTimestamp: _formattedTimestamp,
                            colors: colors,
                          ),
                          RepaintBoundary(
                            child: _SafeContentSection(
                              parsedContent: _shouldTruncate ? _truncatedContent! : _parsedContent,
                              onMentionTap: _navigateToMentionProfile,
                              onShowMoreTap: _shouldTruncate ? (_) => _navigateToThreadPage() : null,
                              notesListProvider: widget.notesListProvider,
                              noteId: _noteId,
                            ),
                          ),
                          const SizedBox(height: 8),
                          RepaintBoundary(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: widget.currentUserNpub.isNotEmpty
                                  ? InteractionBar(
                                      noteId: _getInteractionNoteId(),
                                      currentUserNpub: widget.currentUserNpub,
                                      note: widget.note,
                                    )
                                  : const SizedBox(height: 32),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedLayout(dynamic colors) {
    return RepaintBoundary(
      key: ValueKey(_widgetKey),
      child: GestureDetector(
        onTap: _navigateToThreadPage,
        child: Container(
          color: widget.containerColor ?? colors.background,
          padding: const EdgeInsets.only(bottom: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValueListenableBuilder<_NoteState>(
                      valueListenable: _stateNotifier,
                      builder: (context, state, _) {
                        final hasRepost = _isRepost && _reposterId != null;
                        final hasReply = state.replyText != null;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (hasRepost)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: 4,
                                  bottom: hasReply ? 2 : 4,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.repeat,
                                      size: 14,
                                      color: colors.textSecondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Reposted by ${state.reposterUser?.name ?? 'Anonymous'}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (hasReply)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: hasRepost ? 0 : 4,
                                  bottom: 4,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.reply,
                                      size: 14,
                                      color: colors.textSecondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      state.replyText!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    Padding(
                      padding: EdgeInsets.only(top: (_isRepost || _isReply) ? 0 : 4),
                      child: _SafeProfileSection(
                        stateNotifier: _stateNotifier,
                        isRepost: _isRepost,
                        onAuthorTap: () {
                          debugPrint('[NoteWidget] Author avatar tapped for: $_authorId');
                          _navigateToProfile(_authorId);
                        },
                        onReposterTap: _reposterId != null
                            ? () {
                                final reposterId = _reposterId;
                                _navigateToProfile(reposterId);
                              }
                            : null,
                        colors: colors,
                        widgetKey: _widgetKey,
                        isExpanded: true,
                        formattedTimestamp: _formattedTimestamp,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: RepaintBoundary(
                        child: _SafeContentSection(
                          parsedContent: _shouldTruncate ? _truncatedContent! : _parsedContent,
                          onMentionTap: _navigateToMentionProfile,
                          onShowMoreTap: _shouldTruncate ? (_) => _navigateToThreadPage() : null,
                          notesListProvider: widget.notesListProvider,
                          noteId: _noteId,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: RepaintBoundary(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: widget.currentUserNpub.isNotEmpty
                              ? InteractionBar(
                                  noteId: _getInteractionNoteId(),
                                  currentUserNpub: widget.currentUserNpub,
                                  note: widget.note,
                                )
                              : const SizedBox(height: 32),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteState {
  final UserModel? authorUser;
  final UserModel? reposterUser;
  final String? replyText;

  const _NoteState({
    this.authorUser,
    this.reposterUser,
    this.replyText,
  });

  factory _NoteState.initial() {
    return const _NoteState(
      authorUser: null,
      reposterUser: null,
      replyText: null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _NoteState &&
          runtimeType == other.runtimeType &&
          authorUser?.hashCode == other.authorUser?.hashCode &&
          reposterUser?.hashCode == other.reposterUser?.hashCode &&
          replyText == other.replyText;

  @override
  int get hashCode => (authorUser?.hashCode ?? 0) ^ (reposterUser?.hashCode ?? 0) ^ (replyText?.hashCode ?? 0);
}

class _SafeProfileSection extends StatelessWidget {
  final ValueNotifier<_NoteState> stateNotifier;
  final bool isRepost;
  final VoidCallback onAuthorTap;
  final VoidCallback? onReposterTap;
  final dynamic colors;
  final String widgetKey;
  final bool isExpanded;
  final String formattedTimestamp;

  static final Map<String, Widget> _avatarCache = <String, Widget>{};

  const _SafeProfileSection({
    required this.stateNotifier,
    required this.isRepost,
    required this.onAuthorTap,
    required this.onReposterTap,
    required this.colors,
    required this.widgetKey,
    required this.isExpanded,
    required this.formattedTimestamp,
  });

  Widget _getCachedAvatar(String imageUrl, double radius, String cacheKey) {
    return _avatarCache.putIfAbsent(cacheKey, () {
      try {
        if (imageUrl.isEmpty) {
          return CircleAvatar(
            radius: radius,
            backgroundColor: colors.surfaceTransparent,
            child: Icon(
              Icons.person,
              size: radius,
              color: colors.textSecondary,
            ),
          );
        }

        return CircleAvatar(
          radius: radius,
          backgroundColor: colors.surfaceTransparent,
          child: ClipOval(
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              width: radius * 2,
              height: radius * 2,
              fit: BoxFit.cover,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholder: (context, url) => Icon(
                Icons.person,
                size: radius,
                color: colors.textSecondary,
              ),
              errorWidget: (context, url, error) => Icon(
                Icons.person,
                size: radius,
                color: colors.textSecondary,
              ),
            ),
          ),
        );
      } catch (e) {
        debugPrint('[ProfileSection] Avatar cache error: $e');
        return CircleAvatar(
          radius: radius,
          backgroundColor: colors.surfaceTransparent,
          child: Icon(
            Icons.person,
            size: radius,
            color: colors.textSecondary,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_NoteState>(
      valueListenable: stateNotifier,
      builder: (context, state, _) {
        try {
          if (isExpanded) {
            return _buildExpandedProfile(state);
          } else {
            return _buildNormalProfile(state);
          }
        } catch (e) {
          debugPrint('[ProfileSection] Build error: $e');
          return const SizedBox(width: 44, height: 44);
        }
      },
    );
  }

  Widget _buildNormalProfile(_NoteState state) {
    return Stack(
      children: [
        Padding(
          padding: isRepost ? const EdgeInsets.only(top: 8, left: 10) : const EdgeInsets.only(top: 8),
          child: GestureDetector(
            onTap: onAuthorTap,
            child: _getCachedAvatar(
              state.authorUser?.profileImage ?? '',
              22,
              '${widgetKey}_author_${state.authorUser?.profileImage.hashCode ?? 0}',
            ),
          ),
        ),
        if (isRepost && state.reposterUser != null)
          Positioned(
            top: 0,
            left: 0,
            child: GestureDetector(
              onTap: onReposterTap,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.surface,
                ),
                child: _getCachedAvatar(
                  state.reposterUser?.profileImage ?? '',
                  12,
                  '${widgetKey}_reposter_${state.reposterUser?.profileImage.hashCode ?? 0}',
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildExpandedProfile(_NoteState state) {
    return GestureDetector(
      onTap: onAuthorTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: onAuthorTap,
            child: _getCachedAvatar(
              state.authorUser?.profileImage ?? '',
              22,
              '${widgetKey}_author_${state.authorUser?.profileImage.hashCode ?? 0}',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          state.authorUser?.name.isNotEmpty == true
                              ? state.authorUser!.name
                              : (state.authorUser?.pubkeyHex.substring(0, 8) ?? 'Anonymous'),
                          style: TextStyle(
                            fontSize: 15,
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (state.authorUser?.nip05.isNotEmpty == true && state.authorUser?.nip05Verified == true) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.verified,
                          size: 16,
                          color: colors.accent,
                        ),
                      ],
                    ],
                  ),
                ),
                if (state.authorUser?.nip05.isNotEmpty == true)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        '• ${state.authorUser!.nip05}',
                        style: TextStyle(fontSize: 12.5, color: colors.secondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text('• $formattedTimestamp', style: TextStyle(fontSize: 12.5, color: colors.secondary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SafeUserInfoSection extends StatelessWidget {
  final ValueNotifier<_NoteState> stateNotifier;
  final String formattedTimestamp;
  final dynamic colors;

  const _SafeUserInfoSection({
    required this.stateNotifier,
    required this.formattedTimestamp,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_NoteState>(
      valueListenable: stateNotifier,
      builder: (context, state, _) {
        try {
          final user = state.authorUser;
          if (user == null) return const SizedBox(height: 20);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            user.name.length > 25 ? '${user.name.substring(0, 25)}...' : user.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (user.nip05.isNotEmpty && user.nip05Verified) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.verified,
                            size: 16,
                            color: colors.accent,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (user.nip05.isNotEmpty) ...[
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          '• ${user.nip05}',
                          style: TextStyle(fontSize: 12.5, color: colors.secondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      '• $formattedTimestamp',
                      style: TextStyle(fontSize: 12.5, color: colors.secondary),
                    ),
                  ),
                ],
              ),
              if (state.replyText != null)
                Transform.translate(
                  offset: const Offset(0, -4),
                  child: Text(
                    state.replyText!,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
            ],
          );
        } catch (e) {
          debugPrint('[UserInfoSection] Build error: $e');
          return const SizedBox(height: 20);
        }
      },
    );
  }
}

class _SafeContentSection extends StatelessWidget {
  final Map<String, dynamic> parsedContent;
  final Function(String) onMentionTap;
  final Function(String)? onShowMoreTap;
  final dynamic notesListProvider;
  final String noteId;

  const _SafeContentSection({
    required this.parsedContent,
    required this.onMentionTap,
    required this.onShowMoreTap,
    this.notesListProvider,
    required this.noteId,
  });

  @override
  Widget build(BuildContext context) {
    try {
      return NoteContentWidget(
        parsedContent: parsedContent,
        noteId: noteId,
        onNavigateToMentionProfile: onMentionTap,
        onShowMoreTap: onShowMoreTap,
      );
    } catch (e) {
      debugPrint('[ContentSection] Build error: $e');
      return const SizedBox.shrink();
    }
  }
}
