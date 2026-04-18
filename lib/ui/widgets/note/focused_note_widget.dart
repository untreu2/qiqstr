import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../utils/string_optimizer.dart';
import '../../theme/theme_manager.dart';
import '../../../l10n/app_localizations.dart';
import 'note_content_widget.dart';
import 'interaction_bar_widget.dart';

class FocusedNoteWidget extends StatefulWidget {
  final Map<String, dynamic> note;
  final String currentUserHex;
  final ValueNotifier<List<Map<String, dynamic>>> notesNotifier;
  final Map<String, Map<String, dynamic>> profiles;
  final dynamic notesListProvider;
  final bool isSelectable;
  final int quoteCount;
  final VoidCallback? onQuotesTap;

  const FocusedNoteWidget({
    super.key,
    required this.note,
    required this.currentUserHex,
    required this.notesNotifier,
    required this.profiles,
    this.notesListProvider,
    this.isSelectable = false,
    this.quoteCount = 0,
    this.onQuotesTap,
  });

  @override
  State<FocusedNoteWidget> createState() => _FocusedNoteWidgetState();
}

class _FocusedNoteWidgetState extends State<FocusedNoteWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final String _noteId;
  late final String _authorId;
  late final String? _reposterId;
  late final String? _parentId;
  late final bool _isReply;
  late final bool _isRepost;
  late final DateTime _timestamp;
  late final String _widgetKey;
  late final Map<String, dynamic> _parsedContent;

  final ValueNotifier<_AuthorState> _stateNotifier =
      ValueNotifier(_AuthorState.empty());

  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    try {
      _precompute();
      _resolveAuthors();
    } catch (e) {
      debugPrint('[FocusedNoteWidget] initState error: $e');
    }
  }

  @override
  void didUpdateWidget(FocusedNoteWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profiles != widget.profiles) _resolveAuthors();
  }

  @override
  void dispose() {
    _stateNotifier.dispose();
    super.dispose();
  }

  // ── data ──────────────────────────────────────────────────────────────────

  void _precompute() {
    _noteId = widget.note['id'] as String? ?? '';
    _authorId = widget.note['pubkey'] as String? ?? '';
    _reposterId = widget.note['repostedBy'] as String?;
    _parentId = widget.note['parentId'] as String? ??
        widget.note['rootId'] as String?;
    _isReply = widget.note['isReply'] as bool? ??
        (_parentId != null && _parentId.isNotEmpty);
    _isRepost = widget.note['isRepost'] as bool? ?? false;

    final createdAt = widget.note['created_at'];
    _timestamp = createdAt is int
        ? DateTime.fromMillisecondsSinceEpoch(createdAt * 1000)
        : (widget.note['timestamp'] as DateTime? ?? DateTime.now());

    _widgetKey = '${_noteId}_${_authorId}_focused';

    final content = widget.note['content'] as String? ?? '';
    _parsedContent = stringOptimizer.parseContentOptimized(content);
    final tags = widget.note['tags'] as List<dynamic>? ?? [];
    final dims = _extractDimensions(tags);
    if (dims.isNotEmpty) _parsedContent['mediaDimensions'] = dims;

    _isInitialized = true;
  }

  void _resolveAuthors() {
    Map<String, dynamic>? author = widget.profiles[_authorId];
    Map<String, dynamic>? reposter =
        _reposterId != null ? widget.profiles[_reposterId] : null;

    author ??= {
      'pubkey': _authorId,
      'name': _authorId.length > 8 ? _authorId.substring(0, 8) : _authorId,
      'picture': '',
    };

    if (_reposterId != null && reposter == null) {
      final rid = _reposterId;
      reposter = {
        'pubkey': rid,
        'name': rid.length > 8 ? rid.substring(0, 8) : rid,
        'picture': '',
      };
    }

    final next = _AuthorState(author: author, reposter: reposter);
    if (_stateNotifier.value != next) _stateNotifier.value = next;
  }

  static Map<String, String> _extractDimensions(List<dynamic> tags) {
    final out = <String, String>{};
    for (final tag in tags) {
      if (tag is! List || tag.isEmpty || tag[0].toString() != 'imeta') continue;
      String? url, dim;
      for (int i = 1; i < tag.length; i++) {
        final e = tag[i].toString();
        if (e.startsWith('url ')) url = e.substring(4);
        if (e.startsWith('dim ')) dim = e.substring(4);
      }
      if (url != null && dim != null) out[url] = dim;
    }
    return out;
  }

  // ── timestamp helpers ─────────────────────────────────────────────────────

  String _absoluteTimestamp() {
    final h = _timestamp.hour.toString().padLeft(2, '0');
    final min = _timestamp.minute.toString().padLeft(2, '0');
    final y = _timestamp.year;
    final mo = _timestamp.month.toString().padLeft(2, '0');
    final d = _timestamp.day.toString().padLeft(2, '0');
    return '$h:$min  ·  $y-$mo-$d';
  }

  // ── navigation ────────────────────────────────────────────────────────────

  void _navigateToProfile(String pubkey) {
    if (!mounted) return;
    final user = widget.profiles[pubkey] ?? {'pubkey': pubkey};
    final npub = user['npub'] as String? ?? pubkey;
    final hex = user['pubkey'] as String? ?? pubkey;
    final loc = GoRouterState.of(context).matchedLocation;
    final path = loc.startsWith('/home/feed')
        ? '/home/feed/profile'
        : loc.startsWith('/home/notifications')
            ? '/home/notifications/profile'
            : '/profile';
    context.push(
        '$path?npub=${Uri.encodeComponent(npub)}&pubkey=${Uri.encodeComponent(hex)}');
  }

  String _getInteractionNoteId() {
    final rootId = widget.note['rootId'] as String?;
    if (_isRepost && rootId != null && rootId.isNotEmpty) return rootId;
    return _noteId;
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_isInitialized) return const SizedBox.shrink();

    final colors = context.colors;
    final l10n = AppLocalizations.of(context)!;

    return RepaintBoundary(
      key: ValueKey(_widgetKey),
      child: Card(
        margin: EdgeInsets.zero,
        color: colors.background,
        elevation: 0,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Author row
              ValueListenableBuilder<_AuthorState>(
                valueListenable: _stateNotifier,
                builder: (context, state, _) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: GestureDetector(
                    onTap: () => _navigateToProfile(_authorId),
                    child: Row(
                      children: [
                        _Avatar(
                          imageUrl:
                              state.author?['picture'] as String? ?? '',
                          radius: 21,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                () {
                                  final name =
                                      state.author?['name'] as String? ??
                                          '';
                                  return name.isNotEmpty
                                      ? name
                                      : (_authorId.length > 8
                                          ? _authorId.substring(0, 8)
                                          : _authorId);
                                }(),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (_isReply && _parentId != null)
                                Text(
                                  l10n.replyTo,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Content
              RepaintBoundary(
                child: _FocusedContentSection(
                  parsedContent: _parsedContent,
                  onMentionTap: (id) => _navigateToProfile(id),
                  notesListProvider: widget.notesListProvider,
                  noteId: _noteId,
                  authorProfileImageUrl: widget.profiles[_authorId]
                      ?['picture'] as String?,
                  authorId: _authorId,
                  isSelectable: widget.isSelectable,
                  embeddedNotes:
                      widget.note['embeddedNotes'] as Map<String, dynamic>?,
                  embeddedArticles: widget.note['embeddedArticles']
                      as Map<String, dynamic>?,
                ),
              ),

              const SizedBox(height: 10),

              // Timestamp — absolute only
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Text(
                  _absoluteTimestamp(),
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.textSecondary,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Interaction bar
              RepaintBoundary(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: widget.currentUserHex.isNotEmpty
                      ? InteractionBar(
                          noteId: _getInteractionNoteId(),
                          currentUserHex: widget.currentUserHex,
                          note: widget.note,
                          isBigSize: true,
                        )
                      : const SizedBox(height: 36),
                ),
              ),

              if (widget.quoteCount > 0 && widget.onQuotesTap != null)
                Padding(
                  padding: const EdgeInsets.only(left: 5, top: 4),
                  child: GestureDetector(
                    onTap: widget.onQuotesTap,
                    child: Text(
                      widget.quoteCount == 1
                          ? '1 ${l10n.quote}'
                          : '${widget.quoteCount} ${l10n.quotePlural}',
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.accent,
                        decoration: TextDecoration.underline,
                        decorationColor: colors.accent,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── author state ─────────────────────────────────────────────────────────────

class _AuthorState {
  final Map<String, dynamic>? author;
  final Map<String, dynamic>? reposter;

  const _AuthorState({this.author, this.reposter});

  factory _AuthorState.empty() => const _AuthorState();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _AuthorState &&
          (author?['pubkey'] == other.author?['pubkey']) &&
          (author?['name'] == other.author?['name']) &&
          (author?['picture'] == other.author?['picture']) &&
          (reposter?['pubkey'] == other.reposter?['pubkey']);

  @override
  int get hashCode => Object.hash(
        author?['pubkey'],
        author?['name'],
        author?['picture'],
        reposter?['pubkey'],
      );
}

// ── avatar ───────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String imageUrl;
  final double radius;

  const _Avatar({required this.imageUrl, required this.radius});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (imageUrl.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: colors.surfaceTransparent,
        child: Icon(Icons.person, size: radius, color: colors.textSecondary),
      );
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheDim = (radius * 2 * dpr).ceil();
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
          memCacheWidth: cacheDim,
          maxWidthDiskCache: cacheDim,
          maxHeightDiskCache: cacheDim,
          placeholder: (_, __) => Icon(
            Icons.person,
            size: radius,
            color: colors.textSecondary,
          ),
          errorWidget: (_, __, ___) => Icon(
            Icons.person,
            size: radius,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── content ───────────────────────────────────────────────────────────────────

class _FocusedContentSection extends StatelessWidget {
  final Map<String, dynamic> parsedContent;
  final Function(String) onMentionTap;
  final dynamic notesListProvider;
  final String noteId;
  final String? authorProfileImageUrl;
  final String authorId;
  final bool isSelectable;
  final Map<String, dynamic>? embeddedNotes;
  final Map<String, dynamic>? embeddedArticles;

  const _FocusedContentSection({
    required this.parsedContent,
    required this.onMentionTap,
    this.notesListProvider,
    required this.noteId,
    this.authorProfileImageUrl,
    required this.authorId,
    this.isSelectable = false,
    this.embeddedNotes,
    this.embeddedArticles,
  });

  @override
  Widget build(BuildContext context) {
    return NoteContentWidget(
      parsedContent: parsedContent,
      noteId: noteId,
      onNavigateToMentionProfile: onMentionTap,
      size: NoteContentSize.big,
      authorProfileImageUrl: authorProfileImageUrl,
      isSelectable: isSelectable,
      embeddedNotes: embeddedNotes,
      embeddedArticles: embeddedArticles,
    );
  }
}
