import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../ui/widgets/common/app_image.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../../data/services/rust_database_service.dart';
import '../../../data/sync/sync_service.dart';
import '../../../core/di/app_di.dart';
import '../../../utils/thread_chain.dart';
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
  late final bool _isQuote;
  late final bool _isRepost;
  late final String _widgetKey;
  late final String _formattedTimestamp;
  late final Map<String, dynamic> _parsedContent;
  late final bool _shouldTruncate;
  late final Map<String, dynamic>? _truncatedContent;

  _ProfileData _authorProfile = const _ProfileData('', '');
  _ProfileData _reposterProfile = const _ProfileData('', '');

  StreamSubscription<Map<String, dynamic>?>? _authorSub;
  StreamSubscription<Map<String, dynamic>?>? _reposterSub;

  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _extractImmutableFields();
    _isInitialized = true;
    _initProfiles();
    _subscribeStreams();
  }

  void _extractImmutableFields() {
    _noteId = widget.note['id'] as String? ?? '';
    _authorId = widget.note['pubkey'] as String? ??
        widget.note['author'] as String? ??
        '';
    _reposterId = widget.note['repostedBy'] as String?;

    final rootId = widget.note['rootId'] as String?;
    final parentId = widget.note['parentId'] as String?;
    _parentId = parentId ?? rootId;

    final explicitIsReply = widget.note['isReply'] as bool?;
    final localParentId = _parentId;
    _isReply =
        explicitIsReply ?? (localParentId != null && localParentId.isNotEmpty);
    _isQuote = widget.note['isQuote'] as bool? ?? false;
    _isRepost = widget.note['isRepost'] as bool? ?? false;
    _widgetKey = '${_noteId}_$_authorId';

    _formattedTimestamp =
        widget.note['formattedTimestamp'] as String? ?? _fallbackTimestamp();

    final rawParsed = widget.note['parsedContent'];
    if (rawParsed is Map<String, dynamic>) {
      _parsedContent = rawParsed;
    } else {
      _parsedContent = {
        'textParts': [
          {'type': 'text', 'text': widget.note['content'] as String? ?? ''}
        ],
        'mediaUrls': <String>[],
        'linkUrls': <String>[],
        'quoteIds': <String>[],
        'articleIds': <String>[],
        'shouldTruncate': false,
        'truncatedParts': <dynamic>[],
      };
    }

    _shouldTruncate = _parsedContent['shouldTruncate'] as bool? ?? false;
    if (_shouldTruncate) {
      final truncParts = _parsedContent['truncatedParts'];
      _truncatedContent = {
        'textParts': truncParts ?? [],
        'mediaUrls': _parsedContent['mediaUrls'] ?? [],
        'linkUrls': _parsedContent['linkUrls'] ?? [],
        'quoteIds': _parsedContent['quoteIds'] ?? [],
        'articleIds': _parsedContent['articleIds'] ?? [],
      };
    } else {
      _truncatedContent = null;
    }
  }

  void _initProfiles() {
    final authorName = (widget.note['authorName'] as String? ?? '').isNotEmpty
        ? widget.note['authorName'] as String
        : (_authorId.length > 8 ? _authorId.substring(0, 8) : _authorId);
    final authorImage = widget.note['authorImage'] as String? ?? '';
    _authorProfile = _ProfileData(authorName, authorImage);

    final localReposterId = _reposterId;
    if (localReposterId != null) {
      final reposterName =
          (widget.note['reposterName'] as String? ?? '').isNotEmpty
              ? widget.note['reposterName'] as String
              : (localReposterId.length > 8
                  ? localReposterId.substring(0, 8)
                  : localReposterId);
      final reposterImage = widget.note['reposterImage'] as String? ?? '';
      _reposterProfile = _ProfileData(reposterName, reposterImage);
    }
  }

  void _subscribeStreams() {
    final db = RustDatabaseService.instance;

    if (_authorId.isNotEmpty) {
      _authorSub = db.watchProfile(_authorId).listen(_onAuthorProfile);
      _triggerSyncIfMissing(_authorId,
          _authorProfile.image.isEmpty || _authorProfile.name.length == 8);
    }

    final localReposter = _reposterId;
    if (localReposter != null && localReposter.isNotEmpty) {
      _reposterSub = db.watchProfile(localReposter).listen(_onReposterProfile);
      _triggerSyncIfMissing(localReposter,
          _reposterProfile.image.isEmpty || _reposterProfile.name.length == 8);
    }
  }

  void _triggerSyncIfMissing(String pubkey, bool missing) {
    if (!missing) return;
    Future.microtask(() async {
      if (!mounted) return;
      try {
        await AppDI.get<SyncService>().syncProfile(pubkey);
      } catch (_) {}
    });
  }

  void _onAuthorProfile(Map<String, dynamic>? data) {
    if (!mounted || data == null) return;
    final name = _resolveProfileName(data, _authorId);
    final image =
        data['picture'] as String? ?? data['profileImage'] as String? ?? '';
    final next = _ProfileData(name, image);
    if (next != _authorProfile) {
      setState(() => _authorProfile = next);
    }
  }

  void _onReposterProfile(Map<String, dynamic>? data) {
    final localReposterId = _reposterId;
    if (!mounted || data == null || localReposterId == null) return;
    final name = _resolveProfileName(data, localReposterId);
    final image =
        data['picture'] as String? ?? data['profileImage'] as String? ?? '';
    final next = _ProfileData(name, image);
    if (next != _reposterProfile) {
      setState(() => _reposterProfile = next);
    }
  }

  String _resolveProfileName(Map<String, dynamic> data, String pubkey) {
    final name =
        data['name'] as String? ?? data['display_name'] as String? ?? '';
    if (name.isNotEmpty) return name;
    return pubkey.length > 8 ? pubkey.substring(0, 8) : pubkey;
  }

  @override
  void dispose() {
    _authorSub?.cancel();
    _reposterSub?.cancel();
    super.dispose();
  }

  String _fallbackTimestamp() {
    final createdAt = widget.note['created_at'];
    if (createdAt is int) {
      final ts = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
      final d = DateTime.now().difference(ts);
      if (d.inSeconds < 5) return 'now';
      if (d.inSeconds < 60) return '${d.inSeconds}s';
      if (d.inMinutes < 60) return '${d.inMinutes}m';
      if (d.inHours < 24) return '${d.inHours}h';
      if (d.inDays < 7) return '${d.inDays}d';
      if (d.inDays < 30) return '${(d.inDays / 7).floor()}w';
      if (d.inDays < 365) return '${(d.inDays / 30).floor()}mo';
      return '${(d.inDays / 365).floor()}y';
    }
    return '';
  }

  void _navigateToProfile(String pubkey) {
    if (!mounted || !_isInitialized) return;
    final loc = GoRouterState.of(context).matchedLocation;
    final encoded = Uri.encodeComponent(pubkey);
    if (loc.startsWith('/home/feed')) {
      context.push('/home/feed/profile?npub=$encoded&pubkeyHex=$encoded');
    } else if (loc.startsWith('/home/notifications')) {
      context
          .push('/home/notifications/profile?npub=$encoded&pubkeyHex=$encoded');
    } else {
      context.push('/profile?npub=$encoded&pubkeyHex=$encoded');
    }
  }

  void _navigateToThreadPage() {
    if (!mounted || !_isInitialized) return;

    var noteRootId = widget.note['rootId'] as String?;
    if ((noteRootId == null || noteRootId.isEmpty) && _isReply) {
      noteRootId = _resolveRootFromTags(widget.note);
    }

    if (widget.onNoteTap != null) {
      widget.onNoteTap!(_noteId, noteRootId);
      return;
    }

    final chain = <String>[];
    final hasRoot = noteRootId != null && noteRootId.isNotEmpty;
    if (hasRoot) {
      chain.add(noteRootId);
      final parentId = widget.note['parentId'] as String?;
      if (parentId != null &&
          parentId.isNotEmpty &&
          parentId != noteRootId &&
          parentId != _noteId) {
        chain.add(parentId);
      }
      if (_noteId != noteRootId) chain.add(_noteId);
    } else {
      chain.add(_noteId);
    }

    final chainStr = ThreadChain.build(chain);
    final noteData = Map<String, dynamic>.from(widget.note);
    final loc = GoRouterState.of(context).matchedLocation;
    if (loc.startsWith('/home/feed')) {
      context.push('/home/feed/thread/$chainStr', extra: noteData);
    } else if (loc.startsWith('/home/notifications')) {
      context.push('/home/notifications/thread/$chainStr', extra: noteData);
    } else {
      context.push('/thread/$chainStr', extra: noteData);
    }
  }

  String? _resolveRootFromTags(Map<String, dynamic> note) {
    final tags = note['tags'] as List<dynamic>? ?? [];
    String? firstE;
    for (final tag in tags) {
      if (tag is List && tag.length > 1 && tag[0] == 'e') {
        final marker = tag.length >= 4 ? tag[3] as String? : null;
        if (marker == 'root') return tag[1] as String;
        firstE ??= tag[1] as String;
      }
    }
    return firstE;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) return const SizedBox.shrink();
    final colors = context.colors;
    final isExpanded = context.themeState?.isExpandedNoteMode ?? false;
    return isExpanded
        ? _buildExpandedLayout(colors)
        : _buildNormalLayout(colors);
  }

  Widget _buildNormalLayout(dynamic colors) {
    final reposterId = _reposterId;
    return RepaintBoundary(
      key: ValueKey(_widgetKey),
      child: GestureDetector(
        onTap: _navigateToThreadPage,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: widget.containerColor ?? colors.background,
          padding: const EdgeInsets.only(bottom: 2),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isRepost && reposterId != null)
                  _RepostBanner(
                    name: _reposterProfile.name,
                    imageUrl: _reposterProfile.image,
                    onTap: () => _navigateToProfile(reposterId),
                    colors: colors,
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: GestureDetector(
                        onTap: () => _navigateToProfile(_authorId),
                        child: _ProfileAvatar(
                          imageUrl: _authorProfile.image,
                          radius: 20,
                          colors: colors,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _UserInfoRow(
                            authorName: _authorProfile.name,
                            formattedTimestamp: _formattedTimestamp,
                            isReply: _isReply,
                            isQuote: _isQuote,
                            colors: colors,
                          ),
                          Transform.translate(
                            offset: const Offset(0, -4),
                            child: RepaintBoundary(
                              child: NoteContentWidget(
                                parsedContent: _shouldTruncate
                                    ? _truncatedContent!
                                    : _parsedContent,
                                noteId: _noteId,
                                onNavigateToMentionProfile: _navigateToProfile,
                                onShowMoreTap: _shouldTruncate
                                    ? (_) => _navigateToThreadPage()
                                    : null,
                                authorProfileImageUrl: _authorProfile.image,
                                isSelectable: widget.isSelectable,
                                initialProfiles: widget.profiles,
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
                                      noteId: _noteId,
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
        ),
      ),
    );
  }

  Widget _buildExpandedLayout(dynamic colors) {
    final reposterId = _reposterId;
    return RepaintBoundary(
      key: ValueKey(_widgetKey),
      child: GestureDetector(
        onTap: _navigateToThreadPage,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: widget.containerColor ?? colors.background,
          padding: const EdgeInsets.only(bottom: 2),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isRepost && reposterId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _RepostBanner(
                      name: _reposterProfile.name,
                      imageUrl: _reposterProfile.image,
                      onTap: () => _navigateToProfile(reposterId),
                      colors: colors,
                    ),
                  ),
                if (_isReply && !_isQuote && _parentId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: Row(
                      children: [
                        Icon(Icons.reply,
                            size: 14, color: colors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          'Reply to...',
                          style: TextStyle(
                              fontSize: 12, color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.only(
                      top: (_isRepost || _isReply || _isQuote) ? 8 : 4),
                  child: GestureDetector(
                    onTap: () => _navigateToProfile(_authorId),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _ProfileAvatar(
                          imageUrl: _authorProfile.image,
                          radius: 16,
                          colors: colors,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  _authorProfile.name,
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
                                child: Text(
                                  '• $_formattedTimestamp',
                                  style: TextStyle(
                                      fontSize: 12.5, color: colors.secondary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Transform.translate(
                  offset: const Offset(0, -4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: RepaintBoundary(
                      child: NoteContentWidget(
                        parsedContent: _shouldTruncate
                            ? _truncatedContent!
                            : _parsedContent,
                        noteId: _noteId,
                        onNavigateToMentionProfile: _navigateToProfile,
                        onShowMoreTap: _shouldTruncate
                            ? (_) => _navigateToThreadPage()
                            : null,
                        authorProfileImageUrl: _authorProfile.image,
                        isSelectable: widget.isSelectable,
                        initialProfiles: widget.profiles,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: RepaintBoundary(
                    child: widget.currentUserHex.isNotEmpty && widget.isVisible
                        ? InteractionBar(
                            noteId: _noteId,
                            currentUserHex: widget.currentUserHex,
                            note: widget.note,
                          )
                        : const SizedBox(height: 32),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileData {
  final String name;
  final String image;

  const _ProfileData(this.name, this.image);

  @override
  bool operator ==(Object other) =>
      other is _ProfileData && name == other.name && image == other.image;

  @override
  int get hashCode => Object.hash(name, image);
}

class _RepostBanner extends StatelessWidget {
  final String name;
  final String imageUrl;
  final VoidCallback onTap;
  final dynamic colors;

  const _RepostBanner({
    required this.name,
    required this.imageUrl,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Icon(CarbonIcons.renew, size: 16, color: colors.textSecondary),
            const SizedBox(width: 6),
            _ProfileAvatar(imageUrl: imageUrl, radius: 10, colors: colors),
            const SizedBox(width: 6),
            Text(
              'Reposted by ',
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
            Flexible(
              child: Text(
                name,
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserInfoRow extends StatelessWidget {
  final String authorName;
  final String formattedTimestamp;
  final bool isReply;
  final bool isQuote;
  final dynamic colors;

  const _UserInfoRow({
    required this.authorName,
    required this.formattedTimestamp,
    required this.isReply,
    required this.isQuote,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                authorName.length > 25
                    ? '${authorName.substring(0, 25)}...'
                    : authorName,
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
        if (isReply && !isQuote)
          Transform.translate(
            offset: const Offset(0, -4),
            child: Text(
              'Reply to...',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ),
      ],
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
          child: Icon(Icons.person, size: radius, color: colors.textSecondary),
        ),
      );
    }

    return RepaintBoundary(
      child: ClipOval(
        clipBehavior: Clip.antiAlias,
        child: AppImage(
          key: ValueKey('avatar_${imageUrl.hashCode}_$radius'),
          url: imageUrl,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          memCacheWidth: (radius * 5).toInt(),
          placeholder: (_) => Container(
            width: radius * 2,
            height: radius * 2,
            color: colors.surfaceTransparent,
            child:
                Icon(Icons.person, size: radius, color: colors.textSecondary),
          ),
          errorWidget: (_) => Container(
            width: radius * 2,
            height: radius * 2,
            color: colors.surfaceTransparent,
            child:
                Icon(Icons.person, size: radius, color: colors.textSecondary),
          ),
        ),
      ),
    );
  }
}
