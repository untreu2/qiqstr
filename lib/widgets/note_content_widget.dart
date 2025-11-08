import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import '../theme/theme_manager.dart';
import '../core/di/app_di.dart';
import '../data/repositories/user_repository.dart';
import '../data/repositories/auth_repository.dart';
import '../data/services/user_batch_fetcher.dart';
import '../models/user_model.dart';
import '../screens/feed_page.dart';
import 'link_preview_widget.dart';
import 'media_preview_widget.dart';
import 'mini_link_preview_widget.dart';
import 'quote_widget.dart';
import 'snackbar_widget.dart';

enum NoteContentSize { small, big }

class NoteContentWidget extends StatefulWidget {
  final Map<String, dynamic> parsedContent;
  final String noteId;
  final void Function(String mentionId)? onNavigateToMentionProfile;
  final void Function(String noteId)? onShowMoreTap;
  final NoteContentSize size;
  final String? authorProfileImageUrl;

  const NoteContentWidget({
    super.key,
    required this.parsedContent,
    required this.noteId,
    this.onNavigateToMentionProfile,
    this.onShowMoreTap,
    this.size = NoteContentSize.small,
    this.authorProfileImageUrl,
  });

  @override
  State<NoteContentWidget> createState() => _NoteContentWidgetState();
}

class _NoteContentWidgetState extends State<NoteContentWidget> {
  late final List<dynamic> _textParts;
  late final List<String> _mediaUrls;
  late final List<String> _linkUrls;
  late final List<String> _quoteIds;

  final Map<String, UserModel> _mentionUsers = {};
  final Map<String, bool> _mentionLoadingStates = {};
  final List<TapGestureRecognizer> _gestureRecognizers = [];
  late final UserRepository _userRepository;
  
  List<InlineSpan>? _cachedSpans;
  int _cachedSpansHash = 0;

  @override
  void initState() {
    super.initState();
    _userRepository = AppDI.get<UserRepository>();
    _processParsedContent();
    _loadMentionUsersSync();
    _preloadMentionUsers();
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
    _textParts = (widget.parsedContent['textParts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    _mediaUrls = (widget.parsedContent['mediaUrls'] as List<dynamic>?)?.cast<String>() ?? [];
    _linkUrls = (widget.parsedContent['linkUrls'] as List<dynamic>?)?.cast<String>() ?? [];
    _quoteIds = (widget.parsedContent['quoteIds'] as List<dynamic>?)?.cast<String>() ?? [];
  }

  String? _extractPubkey(String bech32) {
    try {
      if (bech32.startsWith('npub1')) {
        return decodeBasicBech32(bech32, 'npub');
      } else if (bech32.startsWith('nprofile1')) {
        final result = decodeTlvBech32Full(bech32, 'nprofile');
        return result['type_0_main'];
      }
    } catch (e) {
      debugPrint('[NoteContentWidget] Bech32 decode error: $e');
    }
    return null;
  }

  static UserModel _createPlaceholderUser(String pubkey) {
    return UserModel(
      pubkeyHex: pubkey,
      name: pubkey.length > 8 ? pubkey.substring(0, 8) : pubkey,
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

  void _loadMentionUsersSync() {
    final mentionIds = _textParts.where((part) => part['type'] == 'mention').map((part) => part['id'] as String).toSet();

    for (final mentionId in mentionIds) {
      final actualPubkey = _extractPubkey(mentionId) ?? mentionId;
      
      final npubEncoded = encodeBasicBech32(actualPubkey, 'npub');
      final cachedUser = _userRepository.getCachedUserSync(npubEncoded);
      
      if (cachedUser != null) {
        _mentionUsers[actualPubkey] = cachedUser;
      } else {
        _mentionUsers[actualPubkey] = _createPlaceholderUser(actualPubkey);
      }
    }
  }

  void _preloadMentionUsers() {
    final mentionIds = _textParts.where((part) => part['type'] == 'mention').map((part) => part['id'] as String).toSet();
    
    if (mentionIds.isEmpty) return;

    final pubkeyHexToNpubMap = <String, String>{};
    final npubsToFetch = <String>[];
    
    for (final mentionId in mentionIds) {
      final actualPubkey = _extractPubkey(mentionId) ?? mentionId;
      
      if (!_mentionUsers.containsKey(actualPubkey) || _mentionUsers[actualPubkey]!.name == actualPubkey.substring(0, 8)) {
        final npubEncoded = encodeBasicBech32(actualPubkey, 'npub');
        pubkeyHexToNpubMap[actualPubkey] = npubEncoded;
        npubsToFetch.add(npubEncoded);
      }
    }
    
    if (npubsToFetch.isEmpty) return;

    _loadMentionUsersBatch(npubsToFetch, pubkeyHexToNpubMap);
  }

  Future<void> _loadMentionUsersBatch(List<String> npubs, Map<String, String> pubkeyMap) async {
    if (npubs.isEmpty) return;

    try {
      final results = await _userRepository.getUserProfiles(npubs, priority: FetchPriority.normal);
      
      if (!mounted) return;

      bool hasUpdates = false;
      for (final entry in results.entries) {
        final npub = entry.key;
        final result = entry.value;
        
        final pubkeyHex = pubkeyMap.entries
            .firstWhere((e) => e.value == npub, orElse: () => MapEntry('', ''))
            .key;
        
        if (pubkeyHex.isEmpty) continue;
        
        result.fold(
          (user) {
            if (_mentionUsers[pubkeyHex]?.name != user.name) {
              _mentionUsers[pubkeyHex] = user;
              hasUpdates = true;
            }
          },
          (_) {
            if (_mentionUsers[pubkeyHex] == null) {
              _mentionUsers[pubkeyHex] = _createPlaceholderUser(pubkeyHex);
              hasUpdates = true;
            }
          },
        );
      }
      
      if (mounted && hasUpdates) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('[NoteContentWidget] Batch load error: $e');
    }
  }

  double _fontSize(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final baseSize = widget.size == NoteContentSize.big ? 18.0 : 16.0;
    return textScaler.scale(baseSize);
  }

  Future<void> _onOpenLink(LinkableElement link) async {
    try {
      final url = Uri.parse(link.url);
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        if (mounted) {
          AppSnackbar.error(context, 'Could not launch ${link.url}');
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Error opening link: $e');
      }
    }
  }

  Future<void> _onHashtagTap(String hashtag) async {
    try {
      final cleanHashtag = hashtag.startsWith('#') ? hashtag.substring(1) : hashtag;

      final authRepository = AppDI.get<AuthRepository>();
      final npubResult = await authRepository.getCurrentUserNpub();

      if (npubResult.isError || npubResult.data == null) {
        if (mounted) {
          AppSnackbar.error(context, 'Could not load hashtag feed');
        }
        return;
      }

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => FeedPage(
              npub: npubResult.data!,
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

  List<InlineSpan> _buildSpans() {
    final currentHash = Object.hash(
      _mentionUsers.length,
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
            final recognizer = TapGestureRecognizer()..onTap = () => _onOpenLink(LinkableElement(urlMatch, urlMatch));
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
            final recognizer = TapGestureRecognizer()..onTap = () => _onHashtagTap(hashtagMatch);
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
        final actualPubkey = _extractPubkey(id) ?? id;
        final user = _mentionUsers[actualPubkey];
        final isLoading = _mentionLoadingStates[actualPubkey] == true;

        String displayText;
        if (isLoading) {
          displayText = '@loading...';
        } else if (user != null) {
          final userName = user.name.isNotEmpty ? user.name : (id.length > 8 ? id.substring(0, 8) : id);
          displayText = userName.length > 15 ? '@${userName.substring(0, 15)}...' : '@$userName';
        } else {
          displayText = '@${id.length > 8 ? id.substring(0, 8) : id}...';
        }

        final recognizer = TapGestureRecognizer()
          ..onTap = () {
            final npubForNavigation = encodeBasicBech32(actualPubkey, 'npub');
            widget.onNavigateToMentionProfile?.call(npubForNavigation);
          };
        _gestureRecognizers.add(recognizer);
        spans.add(TextSpan(
          text: displayText,
          style: TextStyle(
            fontSize: _fontSize(context),
            color: colors.accent,
            fontWeight: FontWeight.w500,
          ),
          recognizer: recognizer,
        ));
      } else if (p['type'] == 'show_more') {
        final recognizer = TapGestureRecognizer()..onTap = () => widget.onShowMoreTap?.call(widget.noteId);
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
    return RepaintBoundary(
      key: ValueKey('content_${widget.noteId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_textParts.isNotEmpty)
            RepaintBoundary(
              child: RichText(
                text: TextSpan(children: _buildSpans()),
                textHeightBehavior: const TextHeightBehavior(
                  applyHeightToFirstAscent: false,
                  applyHeightToLastDescent: false,
                ),
              ),
            ),
          if (_mediaUrls.isNotEmpty)
            RepaintBoundary(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: MediaPreviewWidget(
                  key: ValueKey('media_${widget.noteId}_${_mediaUrls.length}'),
                  mediaUrls: _mediaUrls,
                  authorProfileImageUrl: widget.authorProfileImageUrl,
                ),
              ),
            ),
          if (_linkUrls.isNotEmpty && _mediaUrls.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _linkUrls.length > 1
                    ? _linkUrls
                        .map((url) => Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: MiniLinkPreviewWidget(url: url),
                            ))
                        .toList()
                    : _linkUrls.map((url) => LinkPreviewWidget(url: url)).toList(),
              ),
            ),
          if (_quoteIds.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _quoteIds
                  .map((quoteId) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: QuoteWidget(bech32: quoteId),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }
}
