import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import '../theme/theme_manager.dart';
import '../core/di/app_di.dart';
import '../data/repositories/user_repository.dart';
import '../models/user_model.dart';
import 'link_preview_widget.dart';
import 'media_preview_widget.dart';
import 'mini_link_preview_widget.dart';
import 'quote_widget.dart';

enum NoteContentSize { small, big }

class NoteContentWidget extends StatefulWidget {
  final Map<String, dynamic> parsedContent;
  final String noteId;
  final void Function(String mentionId)? onNavigateToMentionProfile;
  final void Function(String noteId)? onShowMoreTap;
  final NoteContentSize size;

  const NoteContentWidget({
    super.key,
    required this.parsedContent,
    required this.noteId,
    this.onNavigateToMentionProfile,
    this.onShowMoreTap,
    this.size = NoteContentSize.small,
  });

  @override
  State<NoteContentWidget> createState() => _NoteContentWidgetState();
}

class _NoteContentWidgetState extends State<NoteContentWidget> {
  late final List<dynamic> _textParts;
  late final List<String> _mediaUrls;
  late final List<String> _linkUrls;
  late final List<String> _quoteIds;

  // User cache for mentions
  final Map<String, UserModel> _mentionUsers = {};
  final Map<String, bool> _mentionLoadingStates = {};
  late final UserRepository _userRepository;

  @override
  void initState() {
    super.initState();
    _userRepository = AppDI.get<UserRepository>();
    _processParsedContent();
    _preloadMentionUsers();
  }

  void _processParsedContent() {
    _textParts = (widget.parsedContent['textParts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    _mediaUrls = (widget.parsedContent['mediaUrls'] as List<dynamic>?)?.cast<String>() ?? [];
    _linkUrls = (widget.parsedContent['linkUrls'] as List<dynamic>?)?.cast<String>() ?? [];
    _quoteIds = (widget.parsedContent['quoteIds'] as List<dynamic>?)?.cast<String>() ?? [];
  }

  /// Extract pubkey from bech32 mention (npub1 or nprofile1)
  String? _extractPubkey(String bech32) {
    try {
      debugPrint('[NoteContentWidget] Extracting pubkey from: $bech32');

      if (bech32.startsWith('npub1')) {
        // npub1 için: decodeBasicBech32 ile hex alıyoruz
        final decoded = decodeBasicBech32(bech32, 'npub');
        debugPrint('[NoteContentWidget] npub1 decoded to: $decoded');
        return decoded;
      } else if (bech32.startsWith('nprofile1')) {
        // nprofile1 için: decodeTlvBech32Full ile decode edip 0. indeksteki type_0_main alıyoruz
        debugPrint('[NoteContentWidget] Decoding nprofile1...');
        final result = decodeTlvBech32Full(bech32, 'nprofile');
        debugPrint('[NoteContentWidget] nprofile1 full result: $result');

        final pubkey = result['type_0_main'];
        debugPrint('[NoteContentWidget] nprofile1 extracted pubkey: $pubkey');
        return pubkey;
      }

      debugPrint('[NoteContentWidget] Unknown bech32 format: $bech32');
    } catch (e) {
      debugPrint('[NoteContentWidget] Bech32 decode error: $e');
      debugPrint('[NoteContentWidget] Error type: ${e.runtimeType}');
    }
    return null;
  }

  /// Preload user profiles for all mentions
  void _preloadMentionUsers() {
    final mentionIds = _textParts.where((part) => part['type'] == 'mention').map((part) => part['id'] as String).toSet();

    for (final mentionId in mentionIds) {
      // Extract actual pubkey from bech32 if needed
      final actualPubkey = _extractPubkey(mentionId) ?? mentionId;
      debugPrint('[NoteContentWidget] Preloading mention - original: $mentionId, extracted: $actualPubkey');
      _loadMentionUser(actualPubkey);
    }
  }

  /// Load user profile for mention
  Future<void> _loadMentionUser(String pubkeyHex) async {
    debugPrint('[NoteContentWidget] Loading user for pubkey: $pubkeyHex');

    if (_mentionLoadingStates[pubkeyHex] == true || _mentionUsers.containsKey(pubkeyHex)) {
      debugPrint('[NoteContentWidget] User already loading or loaded for: $pubkeyHex');
      return; // Already loading or loaded
    }

    _mentionLoadingStates[pubkeyHex] = true;

    try {
      // UserRepository npub formatında bekliyor, hex'i npub'a encode edelim
      final npubEncoded = encodeBasicBech32(pubkeyHex, 'npub');
      debugPrint('[NoteContentWidget] Encoded hex $pubkeyHex to npub: $npubEncoded');

      final userResult = await _userRepository.getUserProfile(npubEncoded);
      debugPrint('[NoteContentWidget] User repository result for $npubEncoded: ${userResult.isSuccess}');

      if (mounted) {
        userResult.fold(
          (user) {
            debugPrint('[NoteContentWidget] Successfully loaded user: ${user.name} for pubkey: $pubkeyHex');
            setState(() {
              _mentionUsers[pubkeyHex] = user;
              _mentionLoadingStates[pubkeyHex] = false;
            });
          },
          (error) {
            debugPrint('[NoteContentWidget] Failed to load user, creating fallback for: $pubkeyHex, error: $error');
            // Create fallback user
            setState(() {
              _mentionUsers[pubkeyHex] = UserModel(
                pubkeyHex: pubkeyHex,
                name: pubkeyHex.length > 8 ? pubkeyHex.substring(0, 8) : pubkeyHex,
                about: '',
                profileImage: '',
                banner: '',
                website: '',
                nip05: '',
                lud16: '',
                updatedAt: DateTime.now(),
                nip05Verified: false,
              );
              _mentionLoadingStates[pubkeyHex] = false;
            });
          },
        );
      }
    } catch (e) {
      debugPrint('[NoteContentWidget] Exception loading user for $pubkeyHex: $e');
      if (mounted) {
        setState(() {
          _mentionLoadingStates[pubkeyHex] = false;
        });
      }
    }
  }

  double get _fontSize => widget.size == NoteContentSize.big ? 18.0 : 16.0;

  Future<void> _onOpenLink(LinkableElement link) async {
    try {
      final url = Uri.parse(link.url);
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not launch ${link.url}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening link: $e')),
        );
      }
    }
  }

  void _onHashtagTap(String hashtag) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Hashtag: $hashtag')),
    );
  }

  List<InlineSpan> _buildSpans() {
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
                fontSize: _fontSize,
                color: colors.textPrimary,
              ),
            ));
          }

          final urlMatch = m.group(1);
          final hashtagMatch = m.group(2);

          if (urlMatch != null) {
            spans.add(TextSpan(
              text: urlMatch,
              style: TextStyle(
                fontSize: _fontSize,
                color: colors.accent,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()..onTap = () => _onOpenLink(LinkableElement(urlMatch, urlMatch)),
            ));
          } else if (hashtagMatch != null) {
            spans.add(TextSpan(
              text: hashtagMatch,
              style: TextStyle(
                fontSize: _fontSize,
                color: colors.accent,
                fontWeight: FontWeight.w500,
              ),
              recognizer: TapGestureRecognizer()..onTap = () => _onHashtagTap(hashtagMatch),
            ));
          }
          last = m.end;
        }

        if (last < text.length) {
          spans.add(TextSpan(
            text: text.substring(last),
            style: TextStyle(
              fontSize: _fontSize,
              color: colors.textPrimary,
            ),
          ));
        }
      } else if (p['type'] == 'mention') {
        final id = p['id'] as String;
        // Extract actual pubkey from bech32 if needed
        final actualPubkey = _extractPubkey(id) ?? id;
        final user = _mentionUsers[actualPubkey];
        final isLoading = _mentionLoadingStates[actualPubkey] == true;

        String displayText;
        if (isLoading) {
          displayText = '@loading...';
        } else if (user != null) {
          // Use real user name, truncate if too long
          final userName = user.name.isNotEmpty ? user.name : (id.length > 8 ? id.substring(0, 8) : id);
          displayText = userName.length > 15 ? '@${userName.substring(0, 15)}...' : '@$userName';
        } else {
          // Fallback to ID
          displayText = '@${id.length > 8 ? id.substring(0, 8) : id}...';
        }

        spans.add(TextSpan(
          text: displayText,
          style: TextStyle(
            fontSize: _fontSize,
            color: colors.accent,
            fontWeight: FontWeight.w500,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              // Navigation için de npub formatında gönder
              final npubForNavigation = encodeBasicBech32(actualPubkey, 'npub');
              debugPrint('[NoteContentWidget] Navigating to profile with npub: $npubForNavigation');
              widget.onNavigateToMentionProfile?.call(npubForNavigation);
            },
        ));
      } else if (p['type'] == 'show_more') {
        spans.add(TextSpan(
          text: p['text'] as String,
          style: TextStyle(
            fontSize: _fontSize,
            color: colors.accent,
            fontWeight: FontWeight.w500,
          ),
          recognizer: TapGestureRecognizer()..onTap = () => widget.onShowMoreTap?.call(widget.noteId),
        ));
      }
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Text content
        if (_textParts.isNotEmpty)
          RichText(
            text: TextSpan(children: _buildSpans()),
            textHeightBehavior: const TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
            ),
          ),

        // Media content
        if (_mediaUrls.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: MediaPreviewWidget(mediaUrls: _mediaUrls),
          ),

        // Link previews (only if no media)
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

        // Quote content
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
    );
  }
}
