import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import '../theme/theme_manager.dart';
import '../models/note_model.dart';
import '../models/user_model.dart';
import '../screens/thread_page.dart';
import '../screens/profile_page.dart';
import '../core/di/app_di.dart';
import '../data/repositories/user_repository.dart';
import '../data/services/nostr_data_service.dart';
import 'note_content_widget.dart';

class QuoteWidget extends StatefulWidget {
  final String bech32;

  const QuoteWidget({
    super.key,
    required this.bech32,
  });

  @override
  State<QuoteWidget> createState() => _QuoteWidgetState();
}

class _QuoteWidgetState extends State<QuoteWidget> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  NoteModel? _note;
  UserModel? _user;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isDisposed = false;
  int _retryCount = 0;
  static const int _maxRetries = 2;
  DateTime? _lastFetchTime;
  DateTime? _lastRetryTime;

  late final NostrDataService _nostrDataService;
  late final UserRepository _userRepository;
  late final String? _eventId;

  String? _formattedTime;
  Map<String, dynamic>? _parsedContent;
  bool _shouldTruncate = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadQuoteData();
  }

  void _initializeServices() {
    try {
      _nostrDataService = AppDI.get<NostrDataService>();
      _userRepository = AppDI.get<UserRepository>();
      _eventId = _extractEventId(widget.bech32);
    } catch (e) {
      debugPrint('[QuoteWidget] Service init error: $e');
      _setError();
    }
  }

  String? _extractEventId(String bech32) {
    try {
      debugPrint('[QuoteWidget] Extracting eventId from: $bech32');

      if (bech32.startsWith('note1')) {
        final decoded = decodeBasicBech32(bech32, 'note');
        debugPrint('[QuoteWidget] note1 decoded to: $decoded');
        return decoded;
      } else if (bech32.startsWith('nevent1')) {
        debugPrint('[QuoteWidget] Decoding nevent1...');
        final result = decodeTlvBech32Full(bech32, 'nevent');
        debugPrint('[QuoteWidget] nevent1 full result: $result');

        final eventId = result['type_0_main'];
        debugPrint('[QuoteWidget] nevent1 extracted eventId: $eventId');
        return eventId;
      }

      debugPrint('[QuoteWidget] Unknown bech32 format: $bech32');
    } catch (e) {
      debugPrint('[QuoteWidget] Bech32 decode error: $e');
      debugPrint('[QuoteWidget] Error type: ${e.runtimeType}');
    }
    return null;
  }

  void _loadQuoteData() {
    if (_eventId == null) {
      _setError();
      return;
    }

    final cachedNote = _nostrDataService.cachedNotes.where((note) => note.id == _eventId).firstOrNull;

    if (cachedNote != null) {
      _setNote(cachedNote);
      return;
    }

    _startBackgroundFetch();
  }

  void _startBackgroundFetch() {
    final fetchTime = DateTime.now();
    _lastFetchTime = fetchTime;
    
    Future.delayed(const Duration(seconds: 8), () {
      if (_isDisposed || !mounted || _note != null || _lastFetchTime != fetchTime) return;
      _setError();
    });

    Future.microtask(() async {
      if (_isDisposed || !mounted) return;

      try {
        debugPrint('[QuoteWidget] Starting background fetch for event: $_eventId');
        final success = await _nostrDataService.fetchSpecificNote(_eventId!);

        if (_isDisposed || !mounted) return;

        if (success) {
          final fetchedNote = _nostrDataService.cachedNotes.where((note) => note.id == _eventId).firstOrNull;
          if (fetchedNote != null) {
            debugPrint('[QuoteWidget] Successfully fetched note: $_eventId');
            _setNote(fetchedNote);
            return;
          }
        }

        debugPrint('[QuoteWidget] Note not found via fetchSpecificNote, checking all cached notes...');
        final allCachedNotes = _nostrDataService.cachedNotes;
        final foundNote = allCachedNotes.where((note) => note.id == _eventId).firstOrNull;

        if (foundNote != null) {
          debugPrint('[QuoteWidget] Found note in cached data: $_eventId');
          _setNote(foundNote);
        } else {
          debugPrint('[QuoteWidget] Note not found in any cached data: $_eventId');
          _retryOrSetError();
        }
      } catch (e) {
        debugPrint('[QuoteWidget] Background fetch error: $e');
        _retryOrSetError();
      }
    });
  }

  void _setNote(NoteModel note) {
    if (_isDisposed || !mounted) return;

    setState(() {
      _note = note;
      _isLoading = false;
      _hasError = false;
    });

    _precomputeData(note);
    _loadUser(note.author);
  }

  void _setError() {
    if (_isDisposed || !mounted) return;

    setState(() {
      _isLoading = false;
      _hasError = true;
    });
  }

  void _retryOrSetError() {
    if (_retryCount < _maxRetries) {
      _retryCount++;
      debugPrint('[QuoteWidget] Retrying fetch (attempt $_retryCount/$_maxRetries)');

      final retryTime = DateTime.now();
      _lastRetryTime = retryTime;
      
      Future.delayed(Duration(seconds: _retryCount * 2), () {
        if (!_isDisposed && mounted && _lastRetryTime == retryTime) {
          _startBackgroundFetch();
        }
      });
    } else {
      debugPrint('[QuoteWidget] Max retries reached, setting error');
      _setError();
    }
  }

  void _precomputeData(NoteModel note) {
    try {
      _formattedTime = _formatTime(note.timestamp);
      _parsedContent = note.parsedContentLazy;
      _shouldTruncate = _checkTruncation(_parsedContent);
    } catch (e) {
      debugPrint('[QuoteWidget] Precompute error: $e');
      _parsedContent = {
        'textParts': [
          {'type': 'text', 'text': note.content}
        ],
        'mediaUrls': <String>[],
        'linkUrls': <String>[],
        'quoteIds': <String>[],
      };
    }
  }

  void _loadUser(String npub) {
    _userRepository.getUserProfile(npub).then((result) {
      if (_isDisposed || !mounted) return;

      result.fold(
        (user) {
          if (mounted) {
            setState(() => _user = user);
          }
        },
        (error) {
          if (mounted) {
            setState(() => _user = _createFallbackUser(npub));
          }
        },
      );
    });
  }

  UserModel _createFallbackUser(String npub) {
    final shortName = npub.length > 8 ? npub.substring(0, 8) : npub;
    return UserModel(
      pubkeyHex: npub,
      name: shortName,
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

  String _formatTime(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}w';
  }

  bool _checkTruncation(Map<String, dynamic>? parsed) {
    if (parsed == null) return false;

    try {
      final textParts = (parsed['textParts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      String fullText = '';

      for (var part in textParts) {
        if (part['type'] == 'text') {
          fullText += part['text'] as String? ?? '';
        }
      }

      return fullText.length > 140;
    } catch (e) {
      return false;
    }
  }

  void _navigateToThread() {
    if (_note != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ThreadPage(rootNoteId: _note!.id),
        ),
      );
    }
  }

  void _navigateToProfile() {
    if (_user != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProfilePage(user: _user!),
        ),
      );
    }
  }

  void _navigateToMentionProfile(String npub) {
    if (mounted) {
      _userRepository.getUserProfile(npub).then((result) {
        result.fold(
          (user) => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProfilePage(user: user),
            ),
          ),
          (error) => debugPrint('[QuoteWidget] Mention navigation error: $error'),
        );
      });
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isDisposed || !mounted) {
      return const SizedBox.shrink();
    }

    if (_isLoading) {
      return _buildLoading();
    }

    if (_hasError || _note == null) {
      return _buildError();
    }

    return _buildContent();
  }

  Widget _buildLoading() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.border, width: 1),
      ),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border, width: 0.8),
      ),
      child: Column(
        children: [
          Icon(
            Icons.error_outline,
            color: context.colors.textSecondary,
            size: 20,
          ),
          const SizedBox(height: 8),
          Text(
            'Event not found',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_retryCount > 0)
            Text(
              'Tried $_retryCount times',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final note = _note!;
    final user = _user ?? _createFallbackUser(note.author);
    final parsedContent = _parsedContent!;

    return GestureDetector(
      onTap: _navigateToThread,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(user),
            if (_hasContent(parsedContent))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _buildNoteContent(parsedContent),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(UserModel user) {
    return Row(
      children: [
        GestureDetector(
          onTap: _navigateToProfile,
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
                user.name.length > 25 ? '${user.name.substring(0, 25)}...' : user.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const Spacer(),
        if (_formattedTime != null)
          Text(
            _formattedTime!,
            style: TextStyle(
              fontSize: 12,
              color: context.colors.textSecondary,
              fontWeight: FontWeight.w400,
            ),
          ),
      ],
    );
  }

  bool _hasContent(Map<String, dynamic> parsedContent) {
    final textParts = parsedContent['textParts'] as List?;
    final hasText = textParts?.any((p) => p['type'] == 'text' && (p['text'] as String? ?? '').trim().isNotEmpty) ?? false;
    final hasMedia = (parsedContent['mediaUrls'] as List?)?.isNotEmpty ?? false;
    return hasText || hasMedia;
  }

  Widget _buildNoteContent(Map<String, dynamic> parsedContent) {
    Map<String, dynamic> contentToShow = parsedContent;

    if (_shouldTruncate) {
      contentToShow = _createTruncatedContent(parsedContent);
    }

    return NoteContentWidget(
      noteId: _note!.id,
      parsedContent: contentToShow,
      onNavigateToMentionProfile: _navigateToMentionProfile,
      onShowMoreTap: _shouldTruncate ? (String noteId) => _navigateToThread() : null,
    );
  }

  Map<String, dynamic> _createTruncatedContent(Map<String, dynamic> original) {
    try {
      const int limit = 140;
      final textParts = (original['textParts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final truncatedParts = <Map<String, dynamic>>[];
      int currentLength = 0;

      for (var part in textParts) {
        if (part['type'] == 'text') {
          final text = part['text'] as String? ?? '';
          if (currentLength + text.length <= limit) {
            truncatedParts.add(part);
            currentLength += text.length;
          } else {
            final remainingChars = limit - currentLength;
            if (remainingChars > 0) {
              truncatedParts.add({
                'type': 'text',
                'text': '${text.substring(0, remainingChars)}... ',
              });
            }
            break;
          }
        } else if (part['type'] == 'mention') {
          if (currentLength + 8 <= limit) {
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
        'noteId': _note!.id,
      });

      return {
        'textParts': truncatedParts,
        'mediaUrls': original['mediaUrls'] ?? [],
        'linkUrls': original['linkUrls'] ?? [],
        'quoteIds': original['quoteIds'] ?? [],
      };
    } catch (e) {
      return original;
    }
  }
}
