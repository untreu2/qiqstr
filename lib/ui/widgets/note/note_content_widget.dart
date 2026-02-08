import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import '../../../data/services/rust_nostr_bridge.dart';
import '../../theme/theme_manager.dart';
import '../../../core/di/app_di.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/sync/sync_service.dart';
import '../../../presentation/blocs/note_content/note_content_bloc.dart';
import '../../../presentation/blocs/note_content/note_content_event.dart';
import '../../../presentation/blocs/note_content/note_content_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../screens/note/feed_page.dart';
import '../../screens/webview/webview_page.dart';
import '../media/link_preview_widget.dart';
import '../media/media_preview_widget.dart';
import '../media/mini_link_preview_widget.dart';
import 'quote_widget.dart';
import '../article/article_quote_widget.dart';
import '../common/snackbar_widget.dart';

enum NoteContentSize { small, big }

class NoteContentWidget extends StatefulWidget {
  final Map<String, dynamic> parsedContent;
  final String noteId;
  final void Function(String mentionId)? onNavigateToMentionProfile;
  final void Function(String noteId)? onShowMoreTap;
  final NoteContentSize size;
  final String? authorProfileImageUrl;
  final bool isSelectable;
  final bool shortMode;
  final Map<String, Map<String, dynamic>>? initialProfiles;

  const NoteContentWidget({
    super.key,
    required this.parsedContent,
    required this.noteId,
    this.onNavigateToMentionProfile,
    this.onShowMoreTap,
    this.size = NoteContentSize.small,
    this.authorProfileImageUrl,
    this.isSelectable = false,
    this.shortMode = false,
    this.initialProfiles,
  });

  @override
  State<NoteContentWidget> createState() => _NoteContentWidgetState();
}

class _NoteContentWidgetState extends State<NoteContentWidget> {
  late final List<dynamic> _textParts;
  late final List<String> _mediaUrls;
  late final List<String> _linkUrls;
  late final List<String> _quoteIds;
  late final List<String> _articleIds;

  final Map<String, bool> _mentionLoadingStates = {};
  final List<TapGestureRecognizer> _gestureRecognizers = [];

  List<InlineSpan>? _cachedSpans;
  int _cachedSpansHash = 0;

  @override
  void initState() {
    super.initState();
    _processParsedContent();
  }

  @override
  void dispose() {
    for (final recognizer in _gestureRecognizers) {
      recognizer.dispose();
    }
    _gestureRecognizers.clear();
    super.dispose();
  }

  void _processParsedContent() {
    _textParts = (widget.parsedContent['textParts'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    _mediaUrls =
        (widget.parsedContent['mediaUrls'] as List<dynamic>?)?.cast<String>() ??
            [];
    _linkUrls =
        (widget.parsedContent['linkUrls'] as List<dynamic>?)?.cast<String>() ??
            [];
    _quoteIds =
        (widget.parsedContent['quoteIds'] as List<dynamic>?)?.cast<String>() ??
            [];
    _articleIds = (widget.parsedContent['articleIds'] as List<dynamic>?)
            ?.cast<String>() ??
        [];
  }

  double _fontSize(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final baseSize = widget.size == NoteContentSize.big ? 18.0 : 16.0;
    return textScaler.scale(baseSize);
  }

  Future<void> _onOpenLink(LinkableElement link) async {
    try {
      final url = Uri.parse(link.url);
      if (mounted) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          enableDrag: false,
          isDismissible: true,
          useRootNavigator: true,
          builder: (context) => WebViewPage(url: url.toString()),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Error opening link: $e');
      }
    }
  }

  Future<void> _onHashtagTap(String hashtag, NoteContentBloc bloc) async {
    try {
      final cleanHashtag =
          hashtag.startsWith('#') ? hashtag.substring(1) : hashtag;

      final userHex = await bloc.getCurrentUserHex();

      if (userHex == null) {
        if (mounted) {
          AppSnackbar.error(context, 'Could not load hashtag feed');
        }
        return;
      }

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => FeedPage(
              userHex: userHex,
              hashtag: cleanHashtag,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Error opening hashtag');
      }
    }
  }

  List<InlineSpan> _buildSpans(
      BuildContext context, Map<String, Map<String, dynamic>> mentionUsers) {
    final mentionUsersHash = mentionUsers.entries
        .map((e) => Object.hash(e.key, e.value['name'] as String? ?? '',
            e.value['profileImage'] as String? ?? ''))
        .fold(0, (prev, hash) => Object.hash(prev, hash));

    final currentHash = Object.hash(
      mentionUsersHash,
      _mentionLoadingStates.length,
      _textParts.length,
      context.colors.textPrimary.hashCode,
      context.colors.accent.hashCode,
    );

    if (_cachedSpans != null && _cachedSpansHash == currentHash) {
      return _cachedSpans!;
    }

    for (final recognizer in _gestureRecognizers) {
      recognizer.dispose();
    }
    _gestureRecognizers.clear();

    final parts = _textParts;
    final spans = <InlineSpan>[];
    final colors = context.colors;

    for (var p in parts) {
      if (p['type'] == 'text') {
        final text = p['text'] as String;
        final regex = RegExp(r'(https?:\/\/[^\s]+)|(#\w+)');
        final matches = regex.allMatches(text);
        var last = 0;

        for (final m in matches) {
          if (m.start > last) {
            spans.add(TextSpan(
              text: text.substring(last, m.start),
              style: TextStyle(
                fontSize: _fontSize(context),
                color: colors.textPrimary,
              ),
            ));
          }

          final urlMatch = m.group(1);
          final hashtagMatch = m.group(2);

          if (urlMatch != null) {
            final recognizer = TapGestureRecognizer()
              ..onTap = () => _onOpenLink(LinkableElement(urlMatch, urlMatch));
            _gestureRecognizers.add(recognizer);
            spans.add(TextSpan(
              text: urlMatch,
              style: TextStyle(
                fontSize: _fontSize(context),
                color: colors.accent,
                decoration: TextDecoration.underline,
              ),
              recognizer: recognizer,
            ));
          } else if (hashtagMatch != null) {
            final bloc = context.read<NoteContentBloc>();
            final recognizer = TapGestureRecognizer()
              ..onTap = () => _onHashtagTap(hashtagMatch, bloc);
            _gestureRecognizers.add(recognizer);
            spans.add(TextSpan(
              text: hashtagMatch,
              style: TextStyle(
                fontSize: _fontSize(context),
                color: colors.accent,
                fontWeight: FontWeight.w500,
              ),
              recognizer: recognizer,
            ));

            final cleanHashtag = hashtagMatch.toLowerCase().replaceAll('#', '');
            if (cleanHashtag == 'bitcoin') {
              final fontSize = _fontSize(context);
              final iconSize = fontSize * 1.4;
              spans.add(WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: SizedBox(
                  width: iconSize,
                  height: iconSize,
                  child: Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Image.asset(
                      'assets/bitcoin.png',
                      width: iconSize,
                      height: iconSize,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ));
            }
          }
          last = m.end;
        }

        if (last < text.length) {
          spans.add(TextSpan(
            text: text.substring(last),
            style: TextStyle(
              fontSize: _fontSize(context),
              color: colors.textPrimary,
            ),
          ));
        }
      } else if (p['type'] == 'mention') {
        final id = p['id'] as String;
        String? actualPubkey;
        try {
          if (id.startsWith('npub1')) {
            actualPubkey = decodeBasicBech32(id, 'npub');
          } else if (id.startsWith('nprofile1')) {
            final result = decodeTlvBech32Full(id);
            actualPubkey = result['pubkey'] as String?;
          }
        } catch (e) {
          continue;
        }
        if (actualPubkey == null) continue;

        final pubkey = actualPubkey;
        final user = mentionUsers[pubkey];
        final isLoading = _mentionLoadingStates[pubkey] == true;

        String displayText;
        if (isLoading) {
          displayText = '@loading...';
        } else if (user != null) {
          final userName = () {
            final name = user['name'] as String? ?? '';
            if (name.isNotEmpty) {
              return name;
            }
            final pubkeyHex = user['pubkeyHex'] as String? ?? '';
            return pubkeyHex.length > 8 ? pubkeyHex.substring(0, 8) : pubkeyHex;
          }();
          displayText = userName.length > 25
              ? '@${userName.substring(0, 25)}...'
              : '@$userName';
        } else {
          final fallbackName =
              pubkey.length > 8 ? pubkey.substring(0, 8) : pubkey;
          displayText = '@$fallbackName';
        }

        final recognizer = TapGestureRecognizer()
          ..onTap = () {
            try {
              final npubForNavigation = pubkey.startsWith('npub1')
                  ? pubkey
                  : encodeBasicBech32(pubkey, 'npub');
              widget.onNavigateToMentionProfile?.call(npubForNavigation);
            } catch (_) {}
          };
        _gestureRecognizers.add(recognizer);

        final fontSize = _fontSize(context);

        spans.add(TextSpan(
          text: displayText,
          style: TextStyle(
            fontSize: fontSize,
            color: colors.accent,
            fontWeight: FontWeight.w500,
          ),
          recognizer: recognizer,
        ));
      } else if (p['type'] == 'show_more') {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => widget.onShowMoreTap?.call(widget.noteId);
        _gestureRecognizers.add(recognizer);
        spans.add(TextSpan(
          text: p['text'] as String,
          style: TextStyle(
            fontSize: _fontSize(context),
            color: colors.accent,
            fontWeight: FontWeight.w500,
          ),
          recognizer: recognizer,
        ));
      }
    }

    _cachedSpans = spans;
    _cachedSpansHash = currentHash;
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<NoteContentBloc>(
      create: (context) {
        final bloc = NoteContentBloc(
          profileRepository: AppDI.get<ProfileRepository>(),
          authService: AppDI.get<AuthService>(),
          syncService: AppDI.get<SyncService>(),
        );
        bloc.add(NoteContentInitialized(
          textParts: _textParts.cast<Map<String, dynamic>>(),
          initialProfiles: widget.initialProfiles,
        ));
        return bloc;
      },
      child: BlocBuilder<NoteContentBloc, NoteContentState>(
        builder: (context, state) {
          final mentionUsers = state is NoteContentLoaded
              ? state.mentionUsers
              : <String, Map<String, dynamic>>{};

          return RepaintBoundary(
            key: ValueKey('content_${widget.noteId}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_textParts.isNotEmpty)
                  RepaintBoundary(
                    child: widget.isSelectable
                        ? SelectableText.rich(
                            TextSpan(
                                children: _buildSpans(context, mentionUsers)),
                            style: TextStyle(
                              fontSize: _fontSize(context),
                              height: 1.2,
                            ),
                            textHeightBehavior: const TextHeightBehavior(
                              applyHeightToFirstAscent: false,
                              applyHeightToLastDescent: false,
                            ),
                          )
                        : RichText(
                            text: TextSpan(
                                children: _buildSpans(context, mentionUsers)),
                            textHeightBehavior: const TextHeightBehavior(
                              applyHeightToFirstAscent: false,
                              applyHeightToLastDescent: false,
                            ),
                          ),
                  ),
                if (_mediaUrls.isNotEmpty && !widget.shortMode)
                  RepaintBoundary(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: MediaPreviewWidget(
                        key: ValueKey(
                            'media_${widget.noteId}_${_mediaUrls.length}'),
                        mediaUrls: _mediaUrls,
                        authorProfileImageUrl: widget.authorProfileImageUrl,
                      ),
                    ),
                  ),
                if (_linkUrls.isNotEmpty &&
                    _mediaUrls.isEmpty &&
                    !widget.shortMode)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: _linkUrls.length > 1
                          ? _linkUrls
                              .map((url) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: MiniLinkPreviewWidget(url: url),
                                  ))
                              .toList()
                          : _linkUrls
                              .map((url) => LinkPreviewWidget(url: url))
                              .toList(),
                    ),
                  ),
                if (_quoteIds.isNotEmpty && !widget.shortMode)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: _quoteIds
                        .map((quoteId) => Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 2),
                              child: QuoteWidget(bech32: quoteId),
                            ))
                        .toList(),
                  ),
                if (_articleIds.isNotEmpty && !widget.shortMode)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: _articleIds
                        .map((articleId) => Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 2),
                              child: ArticleQuoteWidget(naddr: articleId),
                            ))
                        .toList(),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
