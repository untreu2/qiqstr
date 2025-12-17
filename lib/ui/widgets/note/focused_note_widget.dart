import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/note_model.dart';
import '../../../models/user_model.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/time_service.dart';
import '../../theme/theme_manager.dart';
import '../../screens/profile/profile_page.dart';
import 'note_content_widget.dart';
import 'interaction_bar_widget.dart';

class FocusedNoteWidget extends StatefulWidget {
  final NoteModel note;
  final String currentUserNpub;
  final ValueNotifier<List<NoteModel>> notesNotifier;
  final Map<String, UserModel> profiles;
  final dynamic notesListProvider;
  final bool isSelectable;

  const FocusedNoteWidget({
    super.key,
    required this.note,
    required this.currentUserNpub,
    required this.notesNotifier,
    required this.profiles,
    this.notesListProvider,
    this.isSelectable = false,
  });

  @override
  State<FocusedNoteWidget> createState() => _FocusedNoteWidgetState();
}

class _FocusedNoteWidgetState extends State<FocusedNoteWidget> with AutomaticKeepAliveClientMixin {
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

  final ValueNotifier<_FocusedNoteState> _stateNotifier = ValueNotifier(_FocusedNoteState.initial());

  bool _isDisposed = false;
  bool _isInitialized = false;
  late final UserRepository _userRepository;

  @override
  void initState() {
    super.initState();
    try {
      _userRepository = AppDI.get<UserRepository>();
      _precomputeImmutableData();
      _initializeAsync();
    } catch (e) {
      debugPrint('[FocusedNoteWidget] InitState error: $e');
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
    _widgetKey = '${_noteId}_${_authorId}_focused';

    _formattedTimestamp = _calculateTimestamp(_timestamp);

    try {
      _parsedContent = widget.note.parsedContentLazy;
    } catch (e) {
      debugPrint('[FocusedNoteWidget] ParseContent error: $e');
      _parsedContent = {
        'textParts': [
          {'type': 'text', 'text': _content}
        ],
        'mediaUrls': <String>[],
        'linkUrls': <String>[],
        'quoteIds': <String>[],
      };
    }

    _isInitialized = true;
  }

  void _initializeAsync() {
    Future.microtask(() {
      if (_isDisposed || !mounted) return;

      try {
        _setupUserListener();
        _loadInitialUserData();
        _loadUsersAsync();
      } catch (e) {
        debugPrint('[FocusedNoteWidget] Async init error: $e');
      }
    });
  }

  void _setupUserListener() {
    try {
      widget.notesNotifier.addListener(_onNotesChange);
    } catch (e) {
      debugPrint('[FocusedNoteWidget] Setup listener error: $e');
    }
  }

  void _onNotesChange() {
    if (!mounted || _isDisposed) return;

    try {
      _updateUserData();
    } catch (e) {
      debugPrint('[FocusedNoteWidget] Notes change error: $e');
    }
  }

  void _loadInitialUserData() {
    try {
      _updateUserData();
    } catch (e) {
      debugPrint('[FocusedNoteWidget] Load initial user data error: $e');
    }
  }

  void _updateUserData() {
    if (_isDisposed || !mounted) return;

    try {
      final currentState = _stateNotifier.value;

      UserModel? authorUser = widget.profiles[_authorId];
      UserModel? reposterUser = _reposterId != null ? widget.profiles[_reposterId] : null;

      authorUser ??= UserModel.create(
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
        reposterUser = UserModel.create(
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

      final newState = _FocusedNoteState(
        authorUser: authorUser,
        reposterUser: reposterUser,
        replyText: replyText,
      );

      if (currentState != newState) {
        _stateNotifier.value = newState;
      }
    } catch (e) {
      debugPrint('[FocusedNoteWidget] Update user data error: $e');
    }
  }

  Future<void> _loadUsersAsync() async {
    if (_isDisposed || !mounted) return;

    try {
      if (widget.notesListProvider != null) {
        final authorPreloaded = widget.notesListProvider.getPreloadedUser(_authorId);
        final reposterPreloaded = _reposterId != null ? widget.notesListProvider.getPreloadedUser(_reposterId) : null;

        if (authorPreloaded != null &&
            authorPreloaded.name != 'Anonymous' &&
            (_reposterId == null || (reposterPreloaded != null && reposterPreloaded.name != 'Anonymous'))) {
          return;
        }
      }

      final authorResult = await _userRepository.getUserProfile(_authorId);
      authorResult.fold(
        (user) {
          if (mounted && !_isDisposed) {
            widget.profiles[_authorId] = user;
            _updateUserData();
          }
        },
        (error) => debugPrint('[FocusedNoteWidget] Failed to load author: $error'),
      );

      if (_reposterId != null) {
        final reposterId = _reposterId;
        final reposterResult = await _userRepository.getUserProfile(reposterId);
        reposterResult.fold(
          (user) {
            if (mounted && !_isDisposed) {
              widget.profiles[reposterId] = user;
              _updateUserData();
            }
          },
          (error) => debugPrint('[FocusedNoteWidget] Failed to load reposter: $error'),
        );
      }
    } catch (e) {
      debugPrint('[FocusedNoteWidget] Load users async error: $e');
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
      debugPrint('[FocusedNoteWidget] Calculate timestamp error: $e');
      return 'unknown';
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    try {
      widget.notesNotifier.removeListener(_onNotesChange);
      _stateNotifier.dispose();
    } catch (e) {
      debugPrint('[FocusedNoteWidget] Dispose error: $e');
    }
    super.dispose();
  }

  void _navigateToProfile(String npub) {
    try {
      if (mounted && !_isDisposed) {
        debugPrint('[FocusedNoteWidget] Attempting to navigate to profile: $npub');

        final user = widget.profiles[npub] ??
            UserModel.create(
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

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfilePage(user: user),
          ),
        );
      }
    } catch (e) {
      debugPrint('[FocusedNoteWidget] Navigate to profile error: $e');
    }
  }

  void _navigateToMentionProfile(String id) {
    try {
      if (mounted && !_isDisposed) {
        _navigateToProfile(id);
      }
    } catch (e) {
      debugPrint('[FocusedNoteWidget] Navigate to mention profile error: $e');
    }
  }

  String _getInteractionNoteId() {
    if (_isRepost && widget.note.rootId != null && widget.note.rootId!.isNotEmpty) {
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

      return RepaintBoundary(
        key: ValueKey(_widgetKey),
        child: Card(
          margin: EdgeInsets.zero,
          color: colors.background,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.only(top: 16.0, bottom: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FocusedProfileSection(
                  stateNotifier: _stateNotifier,
                  isRepost: _isRepost,
                  onAuthorTap: () => _navigateToProfile(_authorId),
                  onReposterTap: _reposterId != null ? () => _navigateToProfile(_reposterId) : null,
                  colors: colors,
                  widgetKey: _widgetKey,
                  formattedTimestamp: _formattedTimestamp,
                ),
                const SizedBox(height: 8),
                _FocusedUserInfoSection(
                  stateNotifier: _stateNotifier,
                  formattedTimestamp: _formattedTimestamp,
                  colors: colors,
                ),
                RepaintBoundary(
                  child: _FocusedContentSection(
                    parsedContent: _parsedContent,
                    onMentionTap: _navigateToMentionProfile,
                    notesListProvider: widget.notesListProvider,
                    noteId: _noteId,
                    authorProfileImageUrl: _stateNotifier.value.authorUser?.profileImage,
                    authorId: _authorId,
                    isSelectable: widget.isSelectable,
                  ),
                ),
                const SizedBox(height: 8),
                RepaintBoundary(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5.0),
                    child: widget.currentUserNpub.isNotEmpty
                        ? InteractionBar(
                            noteId: _getInteractionNoteId(),
                            currentUserNpub: widget.currentUserNpub,
                            note: widget.note,
                            isBigSize: true,
                          )
                        : const SizedBox(height: 36),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('[FocusedNoteWidget] Build error: $e');
      return const SizedBox.shrink();
    }
  }
}

class _FocusedNoteState {
  final UserModel? authorUser;
  final UserModel? reposterUser;
  final String? replyText;

  const _FocusedNoteState({
    this.authorUser,
    this.reposterUser,
    this.replyText,
  });

  factory _FocusedNoteState.initial() {
    return const _FocusedNoteState(
      authorUser: null,
      reposterUser: null,
      replyText: null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _FocusedNoteState &&
          runtimeType == other.runtimeType &&
          authorUser?.hashCode == other.authorUser?.hashCode &&
          reposterUser?.hashCode == other.reposterUser?.hashCode &&
          replyText == other.replyText;

  @override
  int get hashCode => (authorUser?.hashCode ?? 0) ^ (reposterUser?.hashCode ?? 0) ^ (replyText?.hashCode ?? 0);
}

class _FocusedProfileSection extends StatelessWidget {
  final ValueNotifier<_FocusedNoteState> stateNotifier;
  final bool isRepost;
  final VoidCallback onAuthorTap;
  final VoidCallback? onReposterTap;
  final dynamic colors;
  final String widgetKey;
  final String formattedTimestamp;

  static final Map<String, Widget> _avatarCache = <String, Widget>{};

  const _FocusedProfileSection({
    required this.stateNotifier,
    required this.isRepost,
    required this.onAuthorTap,
    required this.onReposterTap,
    required this.colors,
    required this.widgetKey,
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
              size: radius * 0.8,
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
                size: radius * 0.8,
                color: colors.textSecondary,
              ),
              errorWidget: (context, url, error) => Icon(
                Icons.person,
                size: radius * 0.8,
                color: colors.textSecondary,
              ),
            ),
          ),
        );
      } catch (e) {
        debugPrint('[FocusedProfileSection] Avatar cache error: $e');
        return CircleAvatar(
          radius: radius,
          backgroundColor: colors.surfaceTransparent,
          child: Icon(
            Icons.person,
            size: radius * 0.8,
            color: colors.textSecondary,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_FocusedNoteState>(
      valueListenable: stateNotifier,
      builder: (context, state, _) {
        try {
          return GestureDetector(
            onTap: onAuthorTap,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: onAuthorTap,
                  child: _getCachedAvatar(
                    state.authorUser?.profileImage ?? '',
                    21,
                    '${widgetKey}_author_${state.authorUser?.profileImage.hashCode ?? 0}',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          state.authorUser?.name.isNotEmpty == true
                              ? state.authorUser!.name
                              : (state.authorUser?.npub.substring(0, 8) ?? 'Anonymous'),
                          style: TextStyle(
                            fontSize: 16,
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
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
        } catch (e) {
          debugPrint('[FocusedProfileSection] Build error: $e');
          return const SizedBox(width: 56, height: 56);
        }
      },
    );
  }
}

class _FocusedUserInfoSection extends StatelessWidget {
  final ValueNotifier<_FocusedNoteState> stateNotifier;
  final String formattedTimestamp;
  final dynamic colors;

  const _FocusedUserInfoSection({
    required this.stateNotifier,
    required this.formattedTimestamp,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_FocusedNoteState>(
      valueListenable: stateNotifier,
      builder: (context, state, _) {
        try {
          return const SizedBox.shrink();
        } catch (e) {
          debugPrint('[FocusedUserInfoSection] Build error: $e');
          return const SizedBox.shrink();
        }
      },
    );
  }
}

class _FocusedContentSection extends StatelessWidget {
  final Map<String, dynamic> parsedContent;
  final Function(String) onMentionTap;
  final dynamic notesListProvider;
  final String noteId;
  final String? authorProfileImageUrl;
  final String authorId;
  final bool isSelectable;

  const _FocusedContentSection({
    required this.parsedContent,
    required this.onMentionTap,
    this.notesListProvider,
    required this.noteId,
    this.authorProfileImageUrl,
    required this.authorId,
    this.isSelectable = false,
  });

  @override
  Widget build(BuildContext context) {
    try {
      return NoteContentWidget(
        parsedContent: parsedContent,
        noteId: noteId,
        onNavigateToMentionProfile: onMentionTap,
        size: NoteContentSize.big,
        authorProfileImageUrl: authorProfileImageUrl,
        isSelectable: isSelectable,
      );
    } catch (e) {
      debugPrint('[FocusedContentSection] Build error: $e');
      return const SizedBox.shrink();
    }
  }
}
