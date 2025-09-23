import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/note_model.dart';
import '../models/user_model.dart';
import '../services/data_service.dart';
import '../theme/theme_manager.dart';
import '../screens/thread_page.dart';
import '../providers/user_provider.dart';
import 'note_content_widget.dart';
import 'interaction_bar_widget.dart';

class NoteWidget extends StatefulWidget {
  final NoteModel note;
  final DataService dataService;
  final String currentUserNpub;
  final ValueNotifier<List<NoteModel>> notesNotifier;
  final Map<String, UserModel> profiles;
  final Color? containerColor;
  final bool isSmallView;
  final ScrollController? scrollController;
  final dynamic notesListProvider; // Add notes list provider for pre-loaded data

  const NoteWidget({
    super.key,
    required this.note,
    required this.dataService,
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

  // Immutable cached values
  late final String _noteId;
  late final String _authorId;
  late final String? _reposterId;
  late final String? _parentId;
  late final bool _isReply;
  late final bool _isRepost;
  late final DateTime _timestamp;
  late final String _content;
  late final String _widgetKey;

  // Pre-computed immutable data
  late final String _formattedTimestamp;
  late final Map<String, dynamic> _parsedContent;
  late final bool _shouldTruncate;
  late final Map<String, dynamic>? _truncatedContent;

  // Single consolidated state for all user data
  final ValueNotifier<_NoteState> _stateNotifier = ValueNotifier(_NoteState.initial());

  bool _isDisposed = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    try {
      _precomputeImmutableData();
      _initializeAsync();
    } catch (e) {
      debugPrint('[NoteWidget] InitState error: $e');
      _isInitialized = false;
    }
  }

  void _precomputeImmutableData() {
    // Cache all immutable values with null safety
    _noteId = widget.note.id;
    _authorId = widget.note.author;
    _reposterId = widget.note.repostedBy;
    _parentId = widget.note.parentId;
    _isReply = widget.note.isReply;
    _isRepost = widget.note.isRepost;
    _timestamp = widget.note.timestamp;
    _content = widget.note.content;
    _widgetKey = '${_noteId}_${_authorId}';

    // Pre-compute all derived data safely
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
      } catch (e) {
        debugPrint('[NoteWidget] Async init error: $e');
      }
    });
  }

  void _setupUserListener() {
    try {
      UserProvider.instance.addListener(_onUserProviderChange);
    } catch (e) {
      debugPrint('[NoteWidget] Setup listener error: $e');
    }
  }

  void _onUserProviderChange() {
    if (!mounted || _isDisposed) return;

    try {
      _updateUserData();
    } catch (e) {
      debugPrint('[NoteWidget] User provider change error: $e');
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

      // Try to get pre-loaded user data first
      UserModel? authorUser;
      UserModel? reposterUser;

      if (widget.notesListProvider != null) {
        authorUser = widget.notesListProvider.getPreloadedUser(_authorId);
        if (_reposterId != null) {
          reposterUser = widget.notesListProvider.getPreloadedUser(_reposterId);
        }
      }

      // Fallback to UserProvider if not pre-loaded
      authorUser ??= UserProvider.instance.getUserOrDefault(_authorId);
      if (_reposterId != null) {
        reposterUser ??= UserProvider.instance.getUserOrDefault(_reposterId);
      }

      final replyText = _isReply && _parentId != null ? 'Reply to...' : null;

      final newState = _NoteState(
        authorUser: authorUser,
        reposterUser: reposterUser,
        replyText: replyText,
      );

      // Only notify if something actually changed
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
      // If we have a notes list provider with pre-loaded data, skip async loading
      if (widget.notesListProvider != null) {
        final authorPreloaded = widget.notesListProvider.getPreloadedUser(_authorId);
        final reposterPreloaded = _reposterId != null ? widget.notesListProvider.getPreloadedUser(_reposterId) : null;

        if (authorPreloaded != null &&
            authorPreloaded.name != 'Anonymous' &&
            (_reposterId == null || (reposterPreloaded != null && reposterPreloaded.name != 'Anonymous'))) {
          // All users are pre-loaded, no need for async loading
          return;
        }
      }

      // Fallback to async loading if not pre-loaded
      final usersToLoad = <String>[_authorId];
      if (_reposterId != null) usersToLoad.add(_reposterId);
      if (_isReply && _parentId != null) usersToLoad.add(_parentId);

      UserProvider.instance.loadUsers(usersToLoad);
    } catch (e) {
      debugPrint('[NoteWidget] Load users async error: $e');
    }
  }

  String _calculateTimestamp(DateTime timestamp) {
    try {
      final d = DateTime.now().difference(timestamp);
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
      UserProvider.instance.removeListener(_onUserProviderChange);
      _stateNotifier.dispose();
    } catch (e) {
      debugPrint('[NoteWidget] Dispose error: $e');
    }
    super.dispose();
  }

  void _navigateToProfile(String npub) {
    try {
      if (mounted && !_isDisposed) {
        widget.dataService.openUserProfile(context, npub);
      }
    } catch (e) {
      debugPrint('[NoteWidget] Navigate to profile error: $e');
    }
  }

  void _navigateToMentionProfile(String id) {
    try {
      if (mounted && !_isDisposed) {
        widget.dataService.openUserProfile(context, id);
      }
    } catch (e) {
      debugPrint('[NoteWidget] Navigate to mention profile error: $e');
    }
  }

  void _navigateToThreadPage() {
    try {
      if (!mounted || _isDisposed) return;

      final rootId = (_isReply && widget.note.rootId != null && widget.note.rootId!.isNotEmpty) ? widget.note.rootId! : _noteId;
      final focusedId = (_isReply && rootId != _noteId) ? _noteId : null;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ThreadPage(
            rootNoteId: rootId,
            dataService: widget.dataService,
            focusedNoteId: focusedId,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[NoteWidget] Navigate to thread error: $e');
    }
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
                        onAuthorTap: () => _navigateToProfile(_authorId),
                        onReposterTap: _reposterId != null ? () => _navigateToProfile(_reposterId) : null,
                        colors: colors,
                        widgetKey: _widgetKey,
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
                                dataService: widget.dataService,
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
                                child: InteractionBar(
                                  noteId: _noteId,
                                  currentUserNpub: widget.currentUserNpub,
                                  dataService: widget.dataService,
                                  note: widget.note,
                                ),
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
    } catch (e) {
      debugPrint('[NoteWidget] Build error: $e');
      return const SizedBox.shrink();
    }
  }
}

// Safe consolidated state class
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

// Safe profile section with null-safe cached avatars
class _SafeProfileSection extends StatelessWidget {
  final ValueNotifier<_NoteState> stateNotifier;
  final bool isRepost;
  final VoidCallback onAuthorTap;
  final VoidCallback? onReposterTap;
  final dynamic colors;
  final String widgetKey;

  // Static cache for profile images
  static final Map<String, Widget> _avatarCache = <String, Widget>{};

  const _SafeProfileSection({
    required this.stateNotifier,
    required this.isRepost,
    required this.onAuthorTap,
    required this.onReposterTap,
    required this.colors,
    required this.widgetKey,
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
        } catch (e) {
          debugPrint('[ProfileSection] Build error: $e');
          return const SizedBox(width: 44, height: 44);
        }
      },
    );
  }
}

// Safe user info section
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

// Safe content section
class _SafeContentSection extends StatelessWidget {
  final Map<String, dynamic> parsedContent;
  final DataService dataService;
  final Function(String) onMentionTap;
  final Function(String)? onShowMoreTap;
  final dynamic notesListProvider;
  final String noteId;

  const _SafeContentSection({
    required this.parsedContent,
    required this.dataService,
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
        dataService: dataService,
        onNavigateToMentionProfile: onMentionTap,
        onShowMoreTap: onShowMoreTap,
        notesListProvider: notesListProvider,
        noteId: noteId,
      );
    } catch (e) {
      debugPrint('[ContentSection] Build error: $e');
      return const SizedBox.shrink();
    }
  }
}
