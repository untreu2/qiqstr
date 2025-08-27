import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import '../theme/theme_manager.dart';
import '../models/note_model.dart';
import '../models/user_model.dart';
import '../screens/thread_page.dart';
import '../services/data_service.dart';
import '../providers/user_provider.dart';
import 'note_content_widget.dart';

class QuoteWidget extends StatefulWidget {
  final String bech32;
  final DataService dataService;

  const QuoteWidget({
    super.key,
    required this.bech32,
    required this.dataService,
  });

  @override
  State<QuoteWidget> createState() => _QuoteWidgetState();
}

class _QuoteWidgetState extends State<QuoteWidget> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final Future<NoteModel?> _noteFuture;
  UserModel? _cachedUser;
  String? _cachedUserNpub;

  @override
  void initState() {
    super.initState();
    _noteFuture = _fetchNote();
  }

  @override
  void dispose() {
    if (_cachedUserNpub != null) {
      UserProvider.instance.removeListener(_onUserDataChange);
    }
    super.dispose();
  }

  void _onUserDataChange() {
    if (!mounted || _cachedUserNpub == null) return;

    final newUser = UserProvider.instance.getUserOrDefault(_cachedUserNpub!);
    if (_cachedUser?.profileImage != newUser.profileImage || _cachedUser?.name != newUser.name) {
      setState(() {
        _cachedUser = newUser;
      });
    }
  }

  String _formatTimestamp(DateTime ts) {
    final d = DateTime.now().difference(ts);
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    return '${(d.inDays / 7).floor()}w';
  }

  void _navigateToMentionProfile(BuildContext context, String id) => widget.dataService.openUserProfile(context, id);

  Map<String, dynamic> _createTruncatedParsedContentWithShowMore(Map<String, dynamic> originalParsed, int characterLimit, NoteModel note) {
    final textParts = (originalParsed['textParts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    final truncatedParts = <Map<String, dynamic>>[];
    int currentLength = 0;

    for (var part in textParts) {
      if (part['type'] == 'text') {
        final text = part['text'] as String;
        if (currentLength + text.length <= characterLimit) {
          truncatedParts.add(part);
          currentLength += text.length;
        } else {
          final remainingChars = characterLimit - currentLength;
          if (remainingChars > 0) {
            truncatedParts.add({
              'type': 'text',
              'text': text.substring(0, remainingChars) + '... ',
            });
          }
          break;
        }
      } else if (part['type'] == 'mention') {
        if (currentLength + 8 <= characterLimit) {
          truncatedParts.add(part);
          currentLength += 8;
        }
      } else {
        break;
      }
    }

    truncatedParts.add({
      'type': 'show_more',
      'text': 'Show more...',
      'noteId': note.id,
    });

    return {
      'textParts': truncatedParts,
      'mediaUrls': originalParsed['mediaUrls'] ?? [],
      'linkUrls': originalParsed['linkUrls'] ?? [],
      'quoteIds': originalParsed['quoteIds'] ?? [],
    };
  }

  Widget _buildNoteContent(BuildContext context, Map<String, dynamic> parsed, NoteModel note) {
    final textParts = (parsed['textParts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    String fullText = '';

    for (var part in textParts) {
      if (part['type'] == 'text') {
        fullText += part['text'] as String;
      } else if (part['type'] == 'mention') {
        fullText += '@mention ';
      }
    }

    const int characterLimit = 140;
    final shouldTruncate = fullText.length > characterLimit;

    return NoteContentWidget(
      parsedContent: shouldTruncate ? _createTruncatedParsedContentWithShowMore(parsed, characterLimit, note) : parsed,
      dataService: widget.dataService,
      onNavigateToMentionProfile: (id) => _navigateToMentionProfile(context, id),
      onShowMoreTap: shouldTruncate
          ? (noteId) => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ThreadPage(
                    rootNoteId: noteId,
                    dataService: widget.dataService,
                  ),
                ),
              )
          : null,
    );
  }

  Future<NoteModel?> _fetchNote() async {
    String? hex;
    if (widget.bech32.startsWith('note1')) {
      hex = decodeBasicBech32(widget.bech32, 'note');
    } else if (widget.bech32.startsWith('nevent1')) {
      hex = decodeTlvBech32Full(widget.bech32, 'nevent')['type_0_main'];
    }
    if (hex == null) return null;
    return await widget.dataService.getCachedNote(hex);
  }

  Widget _authorInfo(BuildContext context, String npub) {
    if (_cachedUserNpub != npub) {
      if (_cachedUserNpub != null) {
        UserProvider.instance.removeListener(_onUserDataChange);
      }
      _cachedUserNpub = npub;
      _cachedUser = UserProvider.instance.getUserOrDefault(npub);
      UserProvider.instance.addListener(_onUserDataChange);

      if (UserProvider.instance.getUser(npub) == null) {
        UserProvider.instance.loadUser(npub);
      }
    }

    final user = _cachedUser ?? UserProvider.instance.getUserOrDefault(npub);

    return GestureDetector(
      onTap: () => widget.dataService.openUserProfile(context, npub),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: user.profileImage.isNotEmpty ? context.colors.surfaceTransparent : context.colors.secondary,
            backgroundImage: user.profileImage.isNotEmpty ? CachedNetworkImageProvider(user.profileImage) : null,
            child: user.profileImage.isEmpty
                ? Icon(
                    Icons.person,
                    size: 14,
                    color: context.colors.textPrimary,
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Text(
            user.name.length > 25 ? user.name.substring(0, 25) : user.name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return GestureDetector(
        onTap: () async {
          final note = await _noteFuture;
          if (note != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ThreadPage(
                  rootNoteId: note.id,
                  dataService: widget.dataService,
                ),
              ),
            );
          }
        },
        child: FutureBuilder<NoteModel?>(
          future: _noteFuture,
          builder: (_, snap) {
            if (!snap.hasData || snap.data == null) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.background,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.colors.border, width: 0.8),
                ),
                child: Center(
                  child: Text(
                    'Event not found',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            }

            final n = snap.data!;

            final parsed = n.parsedContentLazy;
            final hasText = (parsed['textParts'] as List).any((p) => p['type'] == 'text' && (p['text'] as String).trim().isNotEmpty);
            final hasMedia = (parsed['mediaUrls'] as List?)?.isNotEmpty ?? false;

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.colors.border, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _authorInfo(context, n.author),
                      const Spacer(),
                      Text(
                        _formatTimestamp(n.timestamp),
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.textSecondary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  if (hasText || hasMedia)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _buildNoteContent(context, parsed, n),
                    ),
                ],
              ),
            );
          },
        ));
  }
}
