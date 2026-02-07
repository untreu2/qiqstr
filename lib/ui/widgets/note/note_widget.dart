import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../../utils/string_optimizer.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../theme/theme_manager.dart';
import 'note_content_widget.dart';
import 'interaction_bar_widget.dart';

class NoteWidget extends StatefulWidget {
  final Map<String, dynamic> note;
  final String currentUserHex;
  final ValueNotifier<List<Map<String, dynamic>>> notesNotifier;
  final Map<String, Map<String, dynamic>> profiles;
  final Color? containerColor;
  final bool isSmallView;
  final ScrollController? scrollController;
  final dynamic notesListProvider;
  final bool isVisible;
  final bool isSelectable;
  final void Function(String noteId, String? rootId)? onNoteTap;

  const NoteWidget({
    super.key,
    required this.note,
    required this.currentUserHex,
    required this.notesNotifier,
    required this.profiles,
    this.containerColor,
    this.isSmallView = true,
    this.scrollController,
    this.notesListProvider,
    this.isVisible = true,
    this.isSelectable = false,
    this.onNoteTap,
  });

  @override
  State<NoteWidget> createState() => _NoteWidgetState();
}

class _NoteWidgetState extends State<NoteWidget> {
  late final String _noteId;
  late final String _authorId;
  late final String? _reposterId;
  late final String? _parentId;
  late final bool _isReply;
  late final bool _isRepost;
  late final DateTime _timestamp;
  late final String _widgetKey;

  late final String _formattedTimestamp;
  late final Map<String, dynamic> _parsedContent;
  late final bool _shouldTruncate;
  late final Map<String, dynamic>? _truncatedContent;

  final ValueNotifier<_NoteState> _stateNotifier =
      ValueNotifier(_NoteState.initial());
  final Map<String, Map<String, dynamic>> _locallyLoadedProfiles = {};

  bool _isDisposed = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    try {
      _precomputeImmutableData();
      _setupUserListener();
      _loadInitialUserDataSync();
      _initializeAsync();
    } catch (e) {
      debugPrint('[NoteWidget] InitState error: $e');
      _isInitialized = false;
    }
  }

  void _precomputeImmutableData() {
    _noteId = widget.note['id'] as String? ?? '';
    _authorId = widget.note['pubkey'] as String? ??
        widget.note['author'] as String? ??
        '';
    _reposterId = widget.note['repostedBy'] as String?;

    final rootId = widget.note['rootId'] as String?;
    final parentId = widget.note['parentId'] as String?;
    _parentId = parentId ?? rootId;

    final explicitIsReply = widget.note['isReply'] as bool?;
    _isReply = explicitIsReply ?? (_parentId != null && _parentId.isNotEmpty);

    _isRepost = widget.note['isRepost'] as bool? ?? false;
    final createdAt = widget.note['created_at'];
    if (createdAt is int) {
      _timestamp = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
    } else {
      _timestamp = widget.note['timestamp'] as DateTime? ?? DateTime.now();
    }
    _widgetKey = '${_noteId}_$_authorId';

    _formattedTimestamp = _calculateTimestamp(_timestamp);

    final noteContent = widget.note['content'] as String? ?? '';
    _parsedContent = stringOptimizer.parseContentOptimized(noteContent);
    _shouldTruncate = _calculateTruncation(_parsedContent);
    _truncatedContent = _shouldTruncate ? _createTruncatedContent() : null;

    _isInitialized = true;
  }

  void _loadInitialUserDataSync() {
    try {
      final currentState = _stateNotifier.value;

      Map<String, dynamic>? authorUser =
          widget.profiles[_authorId] ?? _locallyLoadedProfiles[_authorId];
      Map<String, dynamic>? reposterUser = _reposterId != null
          ? (widget.profiles[_reposterId] ??
              _locallyLoadedProfiles[_reposterId])
          : null;

      authorUser ??= {
        'pubkeyHex': _authorId,
        'name': _authorId.length > 8 ? _authorId.substring(0, 8) : _authorId,
        'about': '',
        'profileImage': '',
        'banner': '',
        'website': '',
        'nip05': '',
        'lud16': '',
        'updatedAt': DateTime.now(),
        'nip05Verified': false,
      };

      if (_reposterId != null && reposterUser == null) {
        final reposterId = _reposterId;
        reposterUser = {
          'pubkeyHex': reposterId,
          'name':
              reposterId.length > 8 ? reposterId.substring(0, 8) : reposterId,
          'about': '',
          'profileImage': '',
          'banner': '',
          'website': '',
          'nip05': '',
          'lud16': '',
          'updatedAt': DateTime.now(),
          'nip05Verified': false,
        };
      }

      final replyText = _isReply && _parentId != null ? 'Reply to...' : null;

      final newState = _NoteState(
        authorUser: authorUser,
        reposterUser: reposterUser,
        replyText: replyText,
      );

      if (currentState != newState) {
        _stateNotifier.value = newState;
      }
    } catch (e) {
      debugPrint('[NoteWidget] Load initial user data sync error: $e');
    }
  }

  void _initializeAsync() {
    Future.microtask(() {
      if (_isDisposed || !mounted) return;

      try {
        _loadUsersAsync();
      } catch (e) {
        debugPrint('[NoteWidget] Async init error: $e');
      }
    });
  }

  Future<void> _loadUsersAsync() async {
    if (_isDisposed || !mounted) return;

    try {
      final profileRepo = AppDI.get<ProfileRepository>();
      final syncService = AppDI.get<SyncService>();

      final currentAuthor =
          widget.profiles[_authorId] ?? _locallyLoadedProfiles[_authorId];
      final currentReposter = _reposterId != null
          ? (widget.profiles[_reposterId] ??
              _locallyLoadedProfiles[_reposterId])
          : null;

      final shouldLoadAuthor = currentAuthor == null ||
          (currentAuthor['profileImage'] as String? ?? '').isEmpty ||
          (currentAuthor['name'] as String? ?? '').isEmpty ||
          (currentAuthor['name'] as String? ?? '') ==
              _authorId.substring(
                  0, _authorId.length > 8 ? 8 : _authorId.length);

      if (shouldLoadAuthor) {
        final profile = await profileRepo.getProfile(_authorId);
        if (profile != null && mounted && !_isDisposed) {
          _locallyLoadedProfiles[_authorId] = {
            'pubkeyHex': profile.pubkey,
            'name': profile.name ?? '',
            'about': profile.about ?? '',
            'profileImage': profile.picture ?? '',
            'banner': profile.banner ?? '',
            'website': profile.website ?? '',
            'nip05': profile.nip05 ?? '',
            'lud16': profile.lud16 ?? '',
            'updatedAt': DateTime.now(),
            'nip05Verified': false,
          };
          _updateUserData();
        } else if (profile == null) {
          _syncProfileInBackground(syncService, _authorId);
        }
      }

      if (_reposterId != null) {
        final reposterId = _reposterId;
        final shouldLoadReposter = currentReposter == null ||
            (currentReposter['profileImage'] as String? ?? '').isEmpty ||
            (currentReposter['name'] as String? ?? '').isEmpty ||
            (currentReposter['name'] as String? ?? '') ==
                reposterId.substring(
                    0, reposterId.length > 8 ? 8 : reposterId.length);

        if (shouldLoadReposter) {
          final profile = await profileRepo.getProfile(reposterId);
          if (profile != null && mounted && !_isDisposed) {
            _locallyLoadedProfiles[reposterId] = {
              'pubkeyHex': profile.pubkey,
              'name': profile.name ?? '',
              'about': profile.about ?? '',
              'profileImage': profile.picture ?? '',
              'banner': profile.banner ?? '',
              'website': profile.website ?? '',
              'nip05': profile.nip05 ?? '',
              'lud16': profile.lud16 ?? '',
              'updatedAt': DateTime.now(),
              'nip05Verified': false,
            };
            _updateUserData();
          } else if (profile == null) {
            _syncProfileInBackground(syncService, reposterId);
          }
        }
      }
    } catch (e) {
      debugPrint('[NoteWidget] Load users async error: $e');
    }
  }

  void _syncProfileInBackground(SyncService syncService, String pubkey) {
    Future.microtask(() async {
      if (_isDisposed || !mounted) return;
      try {
        await syncService.syncProfile(pubkey);
        if (_isDisposed || !mounted) return;

        final profileRepo = AppDI.get<ProfileRepository>();
        final profile = await profileRepo.getProfile(pubkey);
        if (profile != null && mounted && !_isDisposed) {
          _locallyLoadedProfiles[pubkey] = {
            'pubkeyHex': profile.pubkey,
            'name': profile.name ?? '',
            'about': profile.about ?? '',
            'profileImage': profile.picture ?? '',
            'banner': profile.banner ?? '',
            'website': profile.website ?? '',
            'nip05': profile.nip05 ?? '',
            'lud16': profile.lud16 ?? '',
            'updatedAt': DateTime.now(),
            'nip05Verified': false,
          };
          _updateUserData();
        }
      } catch (_) {}
    });
  }

  @override
  void didUpdateWidget(NoteWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.profiles != widget.profiles) {
      _updateUserData();
    } else {
      final oldAuthor =
          oldWidget.profiles[_authorId] ?? _locallyLoadedProfiles[_authorId];
      final newAuthor =
          widget.profiles[_authorId] ?? _locallyLoadedProfiles[_authorId];
      final oldReposter = _reposterId != null
          ? (oldWidget.profiles[_reposterId] ??
              _locallyLoadedProfiles[_reposterId])
          : null;
      final newReposter = _reposterId != null
          ? (widget.profiles[_reposterId] ??
              _locallyLoadedProfiles[_reposterId])
          : null;

      if (oldAuthor != newAuthor || oldReposter != newReposter) {
        _updateUserData();
      }
    }
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
      final notes = widget.notesNotifier.value;
      if (notes.isEmpty) return;

      bool hasRelevantChange = notes.any((note) {
        final noteId = note['id'] as String? ?? '';
        final rootId = widget.note['rootId'] as String?;
        return noteId == _noteId ||
            (_isRepost && noteId == rootId) ||
            (_isReply && noteId == _parentId);
      });

      if (hasRelevantChange) {
        _updateUserData();
      }
    } catch (e) {}
  }

  void _updateUserData() {
    if (_isDisposed || !mounted) return;

    try {
      final currentState = _stateNotifier.value;

      Map<String, dynamic>? authorUser =
          widget.profiles[_authorId] ?? _locallyLoadedProfiles[_authorId];
      Map<String, dynamic>? reposterUser = _reposterId != null
          ? (widget.profiles[_reposterId] ??
              _locallyLoadedProfiles[_reposterId])
          : null;

      authorUser ??= {
        'pubkeyHex': _authorId,
        'name': _authorId.length > 8 ? _authorId.substring(0, 8) : _authorId,
        'about': '',
        'profileImage': '',
        'banner': '',
        'website': '',
        'nip05': '',
        'lud16': '',
        'updatedAt': DateTime.now(),
        'nip05Verified': false,
      };

      if (_reposterId != null && reposterUser == null) {
        final reposterId = _reposterId;
        reposterUser = {
          'pubkeyHex': reposterId,
          'name':
              reposterId.length > 8 ? reposterId.substring(0, 8) : reposterId,
          'about': '',
          'profileImage': '',
          'banner': '',
          'website': '',
          'nip05': '',
          'lud16': '',
          'updatedAt': DateTime.now(),
          'nip05Verified': false,
        };
      }

      final replyText = _isReply && _parentId != null ? 'Reply to...' : null;

      final newState = _NoteState(
        authorUser: authorUser,
        reposterUser: reposterUser,
        replyText: replyText,
      );

      if (currentState != newState) {
        if (mounted && !_isDisposed) {
          _stateNotifier.value = newState;
        }
      }
    } catch (e) {}
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
      final textParts = (parsed['textParts'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [];

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
      final textParts = (_parsedContent['textParts'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [];
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
        'articleIds': _parsedContent['articleIds'] ?? [],
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
      if (!mounted || _isDisposed || !_isInitialized) return;

      final user = widget.profiles[npub] ??
          _locallyLoadedProfiles[npub] ??
          {
            'pubkeyHex': npub,
            'name': npub.length > 8 ? npub.substring(0, 8) : npub,
            'about': '',
            'profileImage': '',
            'banner': '',
            'website': '',
            'nip05': '',
            'lud16': '',
            'updatedAt': DateTime.now(),
            'nip05Verified': false,
          };

      final userNpub = user['npub'] as String? ?? npub;
      final userPubkeyHex = user['pubkeyHex'] as String? ?? npub;
      final currentLocation = GoRouterState.of(context).matchedLocation;
      if (currentLocation.startsWith('/home/feed')) {
        context.push(
            '/home/feed/profile?npub=${Uri.encodeComponent(userNpub)}&pubkeyHex=${Uri.encodeComponent(userPubkeyHex)}');
      } else if (currentLocation.startsWith('/home/notifications')) {
        context.push(
            '/home/notifications/profile?npub=${Uri.encodeComponent(userNpub)}&pubkeyHex=${Uri.encodeComponent(userPubkeyHex)}');
      } else {
        context.push(
            '/profile?npub=${Uri.encodeComponent(userNpub)}&pubkeyHex=${Uri.encodeComponent(userPubkeyHex)}');
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
    } catch (e) {}
  }

  void _navigateToThreadPage() {
    try {
      if (!mounted || _isDisposed || !_isInitialized) return;

      String rootId;
      String focusedId;

      final noteRootId = widget.note['rootId'] as String?;
      if (_isRepost && noteRootId != null && noteRootId.isNotEmpty) {
        // For reposts, navigate to the original note's thread and focus on it
        rootId = noteRootId;
        focusedId = noteRootId;
      } else if (_isReply && noteRootId != null && noteRootId.isNotEmpty) {
        // For replies, use the root as thread root but focus on this reply
        rootId = noteRootId;
        focusedId = _noteId;
      } else {
        // For root notes, use note as both root and focused
        rootId = _noteId;
        focusedId = _noteId;
      }

      if (widget.onNoteTap != null) {
        widget.onNoteTap!(_noteId, rootId);
      } else {
        final currentLocation = GoRouterState.of(context).matchedLocation;
        if (currentLocation.startsWith('/home/feed')) {
          context.push(
              '/home/feed/thread?rootNoteId=${Uri.encodeComponent(rootId)}&focusedNoteId=${Uri.encodeComponent(focusedId)}');
        } else if (currentLocation.startsWith('/home/notifications')) {
          context.push(
              '/home/notifications/thread?rootNoteId=${Uri.encodeComponent(rootId)}&focusedNoteId=${Uri.encodeComponent(focusedId)}');
        } else {
          context.push(
              '/thread?rootNoteId=${Uri.encodeComponent(rootId)}&focusedNoteId=${Uri.encodeComponent(focusedId)}');
        }
      }
    } catch (e) {
      debugPrint('[NoteWidget] Navigate to thread error: $e');
    }
  }

  String _getInteractionNoteId() {
    return _noteId;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _isDisposed || !mounted) {
      return const SizedBox.shrink();
    }

    try {
      final colors = context.colors;
      final themeState = context.themeState;
      final isExpanded = themeState?.isExpandedNoteMode ?? false;

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
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: widget.containerColor ?? colors.background,
          padding: const EdgeInsets.only(bottom: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isRepost && _reposterId != null)
                      ValueListenableBuilder<_NoteState>(
                        valueListenable: _stateNotifier,
                        builder: (context, state, _) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 0),
                            child: GestureDetector(
                              onTap: () {
                                final reposterId = _reposterId;
                                _navigateToProfile(reposterId);
                              },
                              child: Row(
                                children: [
                                  Icon(
                                    CarbonIcons.renew,
                                    size: 16,
                                    color: colors.textSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  _ProfileAvatar(
                                    imageUrl:
                                        state.reposterUser?['profileImage']
                                                as String? ??
                                            '',
                                    radius: 12,
                                    colors: colors,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Reposted by ',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                  Text(
                                    () {
                                      final name = state.reposterUser?['name']
                                              as String? ??
                                          '';
                                      if (name.isNotEmpty) {
                                        return name;
                                      }
                                      final pubkeyHex =
                                          state.reposterUser?['pubkeyHex']
                                                  as String? ??
                                              '';
                                      return pubkeyHex.length > 8
                                          ? pubkeyHex.substring(0, 8)
                                          : (pubkeyHex.isEmpty
                                              ? 'Anonymous'
                                              : pubkeyHex);
                                    }(),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SafeProfileSection(
                          stateNotifier: _stateNotifier,
                          isRepost: _isRepost,
                          onAuthorTap: () => _navigateToProfile(_authorId),
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
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _SafeUserInfoSection(
                                stateNotifier: _stateNotifier,
                                formattedTimestamp: _formattedTimestamp,
                                colors: colors,
                              ),
                              Transform.translate(
                                offset: const Offset(0, -4),
                                child: RepaintBoundary(
                                  child: _SafeContentSection(
                                    parsedContent: _shouldTruncate
                                        ? _truncatedContent!
                                        : _parsedContent,
                                    onMentionTap: _navigateToMentionProfile,
                                    onShowMoreTap: _shouldTruncate
                                        ? (_) => _navigateToThreadPage()
                                        : null,
                                    notesListProvider: widget.notesListProvider,
                                    noteId: _noteId,
                                    authorProfileImageUrl: _stateNotifier.value
                                        .authorUser?['profileImage'] as String?,
                                    authorId: _authorId,
                                    isSelectable: widget.isSelectable,
                                    profiles: widget.profiles,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              RepaintBoundary(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  child: widget.currentUserHex.isNotEmpty &&
                                          widget.isVisible
                                      ? InteractionBar(
                                          noteId: _getInteractionNoteId(),
                                          currentUserHex: widget.currentUserHex,
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
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: widget.containerColor ?? colors.background,
          padding: const EdgeInsets.only(bottom: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueListenableBuilder<_NoteState>(
                      valueListenable: _stateNotifier,
                      builder: (context, state, _) {
                        final hasRepost = _isRepost && _reposterId != null;
                        final hasReply = state.replyText != null;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hasRepost)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: 4,
                                  bottom: hasReply ? 0 : 0,
                                ),
                                child: GestureDetector(
                                  onTap: () {
                                    final reposterId = _reposterId;
                                    _navigateToProfile(reposterId);
                                  },
                                  child: Row(
                                    children: [
                                      Icon(
                                        CarbonIcons.renew,
                                        size: 16,
                                        color: colors.textSecondary,
                                      ),
                                      const SizedBox(width: 6),
                                      _ProfileAvatar(
                                        imageUrl:
                                            state.reposterUser?['profileImage']
                                                    as String? ??
                                                '',
                                        radius: 10,
                                        colors: colors,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Reposted by ',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                      Text(
                                        () {
                                          final name =
                                              state.reposterUser?['name']
                                                      as String? ??
                                                  '';
                                          if (name.isNotEmpty) {
                                            return name;
                                          }
                                          final pubkeyHex =
                                              state.reposterUser?['pubkeyHex']
                                                      as String? ??
                                                  '';
                                          return pubkeyHex.length > 8
                                              ? pubkeyHex.substring(0, 8)
                                              : (pubkeyHex.isEmpty
                                                  ? 'Anonymous'
                                                  : pubkeyHex);
                                        }(),
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
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
                      padding:
                          EdgeInsets.only(top: (_isRepost || _isReply) ? 8 : 4),
                      child: _SafeProfileSection(
                        stateNotifier: _stateNotifier,
                        isRepost: _isRepost,
                        onAuthorTap: () => _navigateToProfile(_authorId),
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
                    const SizedBox(height: 12),
                    Transform.translate(
                      offset: const Offset(0, -4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: RepaintBoundary(
                          child: _SafeContentSection(
                            parsedContent: _shouldTruncate
                                ? _truncatedContent!
                                : _parsedContent,
                            onMentionTap: _navigateToMentionProfile,
                            onShowMoreTap: _shouldTruncate
                                ? (_) => _navigateToThreadPage()
                                : null,
                            notesListProvider: widget.notesListProvider,
                            noteId: _noteId,
                            authorProfileImageUrl: _stateNotifier
                                .value.authorUser?['profileImage'] as String?,
                            authorId: _authorId,
                            isSelectable: widget.isSelectable,
                            profiles: widget.profiles,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: RepaintBoundary(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: widget.currentUserHex.isNotEmpty &&
                                  widget.isVisible
                              ? InteractionBar(
                                  noteId: _getInteractionNoteId(),
                                  currentUserHex: widget.currentUserHex,
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
  final Map<String, dynamic>? authorUser;
  final Map<String, dynamic>? reposterUser;
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
          (authorUser?['pubkeyHex'] as String? ?? '') ==
              (other.authorUser?['pubkeyHex'] as String? ?? '') &&
          (authorUser?['name'] as String? ?? '') ==
              (other.authorUser?['name'] as String? ?? '') &&
          (authorUser?['profileImage'] as String? ?? '') ==
              (other.authorUser?['profileImage'] as String? ?? '') &&
          (reposterUser?['pubkeyHex'] as String? ?? '') ==
              (other.reposterUser?['pubkeyHex'] as String? ?? '') &&
          (reposterUser?['name'] as String? ?? '') ==
              (other.reposterUser?['name'] as String? ?? '') &&
          (reposterUser?['profileImage'] as String? ?? '') ==
              (other.reposterUser?['profileImage'] as String? ?? '') &&
          replyText == other.replyText;

  @override
  int get hashCode => Object.hash(
        authorUser?['pubkeyHex'] as String?,
        authorUser?['name'] as String?,
        authorUser?['profileImage'] as String?,
        reposterUser?['pubkeyHex'] as String?,
        reposterUser?['name'] as String?,
        reposterUser?['profileImage'] as String?,
        replyText,
      );
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
          return const SizedBox(width: 40, height: 40);
        }
      },
    );
  }

  Widget _buildNormalProfile(_NoteState state) {
    final authorImageUrl = state.authorUser?['profileImage'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: onAuthorTap,
        child: _ProfileAvatar(
          imageUrl: authorImageUrl,
          radius: 20,
          colors: colors,
        ),
      ),
    );
  }

  Widget _buildExpandedProfile(_NoteState state) {
    final authorImageUrl = state.authorUser?['profileImage'] as String? ?? '';

    return GestureDetector(
      onTap: onAuthorTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: onAuthorTap,
            child: _ProfileAvatar(
              imageUrl: authorImageUrl,
              radius: 16,
              colors: colors,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    () {
                      final name = state.authorUser?['name'] as String? ?? '';
                      if (name.isNotEmpty) {
                        return name;
                      }
                      final pubkeyHex =
                          state.authorUser?['pubkeyHex'] as String? ?? '';
                      return pubkeyHex.length > 8
                          ? pubkeyHex.substring(0, 8)
                          : (pubkeyHex.isEmpty ? 'Anonymous' : pubkeyHex);
                    }(),
                    style: TextStyle(
                      fontSize: 15,
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text('• $formattedTimestamp',
                      style:
                          TextStyle(fontSize: 12.5, color: colors.secondary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final String imageUrl;
  final double radius;
  final dynamic colors;

  const _ProfileAvatar({
    required this.imageUrl,
    required this.radius,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return RepaintBoundary(
        child: CircleAvatar(
          radius: radius,
          backgroundColor: colors.surfaceTransparent,
          child: Icon(
            Icons.person,
            size: radius,
            color: colors.textSecondary,
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: ClipOval(
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: radius * 2,
          height: radius * 2,
          color: Colors.transparent,
          child: CachedNetworkImage(
            key: ValueKey('avatar_${imageUrl.hashCode}_$radius'),
            imageUrl: imageUrl,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            memCacheWidth: (radius * 5).toInt(),
            maxWidthDiskCache: (radius * 5).toInt(),
            maxHeightDiskCache: (radius * 5).toInt(),
            placeholder: (context, url) => Container(
              color: colors.surfaceTransparent,
              child: Icon(
                Icons.person,
                size: radius,
                color: colors.textSecondary,
              ),
            ),
            errorWidget: (context, url, error) => Container(
              color: colors.surfaceTransparent,
              child: Icon(
                Icons.person,
                size: radius,
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
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
                    child: Text(
                      () {
                        final name = user['name'] as String? ?? '';
                        return name.length > 25
                            ? '${name.substring(0, 25)}...'
                            : name;
                      }(),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
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
  final String? authorProfileImageUrl;
  final String authorId;
  final bool isSelectable;
  final Map<String, Map<String, dynamic>>? profiles;

  const _SafeContentSection({
    required this.parsedContent,
    required this.onMentionTap,
    required this.onShowMoreTap,
    this.notesListProvider,
    required this.noteId,
    this.authorProfileImageUrl,
    required this.authorId,
    this.isSelectable = false,
    this.profiles,
  });

  @override
  Widget build(BuildContext context) {
    try {
      return NoteContentWidget(
        parsedContent: parsedContent,
        noteId: noteId,
        onNavigateToMentionProfile: onMentionTap,
        onShowMoreTap: onShowMoreTap,
        authorProfileImageUrl: authorProfileImageUrl,
        isSelectable: isSelectable,
        initialProfiles: profiles,
      );
    } catch (e) {
      debugPrint('[ContentSection] Build error: $e');
      return const SizedBox.shrink();
    }
  }
}
