import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import '../theme/theme_manager.dart';
import '../models/note_model.dart';
import '../models/user_model.dart';
import '../screens/thread_page.dart';
import '../services/data_service.dart';
import '../services/nostr_service.dart';
import '../constants/relays.dart';
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

  // Immutable cached data
  late final String _bech32;
  late final DataService _dataService;
  late final String? _eventId;
  late final String _widgetHash;

  // Async state management
  final ValueNotifier<NoteModel?> _noteNotifier = ValueNotifier(null);
  final ValueNotifier<UserModel?> _userNotifier = ValueNotifier(null);
  final ValueNotifier<bool> _isLoadingNotifier = ValueNotifier(true);
  final ValueNotifier<bool> _hasErrorNotifier = ValueNotifier(false);

  // Computed data cache - with null safety
  String? _cachedFormattedTime;
  Map<String, dynamic>? _cachedParsedContent;
  Map<String, dynamic>? _cachedTruncatedContent;
  bool? _cachedShouldTruncate;

  bool _isDisposed = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    try {
      _precomputeData();
      _initializeAsync();
    } catch (e) {
      debugPrint('[QuoteWidget] InitState error: $e');
      _hasErrorNotifier.value = true;
      _isLoadingNotifier.value = false;
    }
  }

  void _precomputeData() {
    try {
      // Cache immutable data
      _bech32 = widget.bech32;
      _dataService = widget.dataService;
      _widgetHash = _bech32.hashCode.toString();

      // Extract event ID once with error handling
      _eventId = _extractEventId(_bech32);

      _isInitialized = true;
    } catch (e) {
      debugPrint('[QuoteWidget] PrecomputeData error: $e');
      _isInitialized = false;
      rethrow;
    }
  }

  String? _extractEventId(String bech32) {
    try {
      if (bech32.startsWith('note1')) {
        return decodeBasicBech32(bech32, 'note');
      } else if (bech32.startsWith('nevent1')) {
        final result = decodeTlvBech32Full(bech32, 'nevent');
        return result['type_0_main'];
      }
    } catch (e) {
      debugPrint('[QuoteWidget] Error extracting event ID: $e');
    }
    return null;
  }

  void _initializeAsync() {
    if (_eventId == null) {
      _hasErrorNotifier.value = true;
      _isLoadingNotifier.value = false;
      return;
    }

    Future.microtask(() async {
      if (_isDisposed || !mounted) return;

      try {
        // Try cache first
        var note = await _dataService.getCachedNote(_eventId);

        // Fetch from network if needed
        if (note == null) {
          note = await _fetchNoteFromNetwork(_eventId);
        }

        if (!_isDisposed && mounted) {
          if (note != null) {
            _noteNotifier.value = note;
            _precomputeNoteData(note);
            _loadUserAsync(note.author);
          } else {
            _hasErrorNotifier.value = true;
          }
          _isLoadingNotifier.value = false;
        }
      } catch (e) {
        debugPrint('[QuoteWidget] Error fetching note: $e');
        if (!_isDisposed && mounted) {
          _hasErrorNotifier.value = true;
          _isLoadingNotifier.value = false;
        }
      }
    });
  }

  void _precomputeNoteData(NoteModel note) {
    try {
      // Pre-compute formatted time
      _cachedFormattedTime = _formatTimestamp(note.timestamp);

      // Pre-compute parsed content with error handling
      try {
        _cachedParsedContent = note.parsedContentLazy;
      } catch (e) {
        debugPrint('[QuoteWidget] Error parsing content: $e');
        _cachedParsedContent = {
          'textParts': [
            {'type': 'text', 'text': note.content}
          ],
          'mediaUrls': <String>[],
          'linkUrls': <String>[],
          'quoteIds': <String>[],
        };
      }

      // Pre-compute truncation
      if (_cachedParsedContent != null) {
        _cachedShouldTruncate = _shouldTruncateContent(_cachedParsedContent!);

        if (_cachedShouldTruncate == true) {
          _cachedTruncatedContent = _createTruncatedContent(_cachedParsedContent!, note);
        }
      }
    } catch (e) {
      debugPrint('[QuoteWidget] Error precomputing note data: $e');
    }
  }

  void _loadUserAsync(String npub) {
    Future.microtask(() async {
      if (_isDisposed || !mounted) return;

      try {
        final provider = UserProvider.instance;

        // Try to get from cache/provider first
        var user = provider.getUserIfExists(npub);

        if (user == null || user.name == 'Anonymous') {
          // Load from network
          user = await provider.loadUser(npub);
        }

        if (!_isDisposed && mounted && user.name != 'Anonymous') {
          _userNotifier.value = user;
          _setupUserListener(npub);
        }
      } catch (e) {
        debugPrint('[QuoteWidget] Error loading user: $e');
        // User loading failed, widget will remain hidden
      }
    });
  }

  void _setupUserListener(String npub) {
    try {
      UserProvider.instance.addListener(() => _onUserDataChange(npub));
    } catch (e) {
      debugPrint('[QuoteWidget] Error setting up user listener: $e');
    }
  }

  void _onUserDataChange(String npub) {
    if (!mounted || _isDisposed) return;

    try {
      final provider = UserProvider.instance;

      final newUser = provider.getUserOrDefault(npub);
      final currentUser = _userNotifier.value;

      if (currentUser?.profileImage != newUser.profileImage || currentUser?.name != newUser.name) {
        _userNotifier.value = newUser;
      }
    } catch (e) {
      debugPrint('[QuoteWidget] Error in user data change: $e');
    }
  }

  String _formatTimestamp(DateTime ts) {
    try {
      final d = DateTime.now().difference(ts);
      if (d.inMinutes < 60) return '${d.inMinutes}m';
      if (d.inHours < 24) return '${d.inHours}h';
      if (d.inDays < 7) return '${d.inDays}d';
      return '${(d.inDays / 7).floor()}w';
    } catch (e) {
      debugPrint('[QuoteWidget] Error formatting timestamp: $e');
      return 'unknown';
    }
  }

  bool _shouldTruncateContent(Map<String, dynamic> parsed) {
    try {
      final textParts = (parsed['textParts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      String fullText = '';

      for (var part in textParts) {
        if (part['type'] == 'text') {
          fullText += part['text'] as String? ?? '';
        } else if (part['type'] == 'mention') {
          fullText += '@mention ';
        }
      }

      return fullText.length > 140;
    } catch (e) {
      debugPrint('[QuoteWidget] Error checking truncation: $e');
      return false;
    }
  }

  Map<String, dynamic> _createTruncatedContent(Map<String, dynamic> originalParsed, NoteModel note) {
    try {
      const int characterLimit = 140;
      final textParts = (originalParsed['textParts'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
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
    } catch (e) {
      debugPrint('[QuoteWidget] Error creating truncated content: $e');
      return originalParsed;
    }
  }

  Future<NoteModel?> _fetchNoteFromNetwork(String eventId) async {
    try {
      final relayUrls = relaySetMainSockets.take(3).toList();

      for (final relayUrl in relayUrls) {
        try {
          final note = await _fetchNoteFromRelay(relayUrl, eventId);
          if (note != null) return note;
        } catch (e) {
          debugPrint('[QuoteWidget] Error fetching from relay $relayUrl: $e');
          continue;
        }
      }

      return null;
    } catch (e) {
      debugPrint('[QuoteWidget] Error in network fetch: $e');
      return null;
    }
  }

  Future<NoteModel?> _fetchNoteFromRelay(String relayUrl, String eventId) async {
    WebSocket? ws;
    try {
      ws = await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 5));

      final filter = NostrService.createEventByIdFilter(eventIds: [eventId]);
      final request = NostrService.createRequest(filter);
      final serializedRequest = NostrService.serializeRequest(request);

      final completer = Completer<Map<String, dynamic>?>();

      late StreamSubscription sub;
      sub = ws.listen((event) {
        try {
          if (completer.isCompleted) return;
          final decoded = jsonDecode(event);
          if (decoded is List && decoded.length >= 3) {
            if (decoded[0] == 'EVENT') {
              final eventData = decoded[2] as Map<String, dynamic>?;
              if (eventData != null && eventData['id'] == eventId) {
                completer.complete(eventData);
              }
            } else if (decoded[0] == 'EOSE') {
              if (!completer.isCompleted) {
                completer.complete(null);
              }
            }
          }
        } catch (e) {
          if (!completer.isCompleted) completer.complete(null);
        }
      }, onError: (error) {
        if (!completer.isCompleted) completer.complete(null);
      }, onDone: () {
        if (!completer.isCompleted) completer.complete(null);
      });

      if (ws.readyState == WebSocket.open) {
        ws.add(serializedRequest);
      }

      final eventData = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );

      await sub.cancel();
      await ws.close();

      if (eventData != null) {
        return NoteModel(
          id: eventData['id'] as String? ?? '',
          content: eventData['content'] as String? ?? '',
          author: eventData['pubkey'] as String? ?? '',
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            ((eventData['created_at'] as int?) ?? 0) * 1000,
          ),
          isReply: false,
          isRepost: false,
          rawWs: jsonEncode(eventData),
        );
      }

      return null;
    } catch (e) {
      try {
        await ws?.close();
      } catch (_) {}
      debugPrint('[QuoteWidget] Error fetching from relay: $e');
      return null;
    }
  }

  void _navigateToThread(String noteId) {
    try {
      if (mounted && !_isDisposed) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ThreadPage(
              rootNoteId: noteId,
              dataService: _dataService,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[QuoteWidget] Error navigating to thread: $e');
    }
  }

  void _navigateToMentionProfile(String id) {
    try {
      if (mounted && !_isDisposed) {
        _dataService.openUserProfile(context, id);
      }
    } catch (e) {
      debugPrint('[QuoteWidget] Error navigating to mention profile: $e');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    try {
      UserProvider.instance.removeListener(() => _onUserDataChange);
      _noteNotifier.dispose();
      _userNotifier.dispose();
      _isLoadingNotifier.dispose();
      _hasErrorNotifier.dispose();
    } catch (e) {
      debugPrint('[QuoteWidget] Error in dispose: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (!_isInitialized || _isDisposed || !mounted) {
      return const SizedBox.shrink();
    }

    try {
      return _SafeQuoteManager(
        noteNotifier: _noteNotifier,
        userNotifier: _userNotifier,
        isLoadingNotifier: _isLoadingNotifier,
        hasErrorNotifier: _hasErrorNotifier,
        cachedFormattedTime: _cachedFormattedTime,
        cachedParsedContent: _cachedParsedContent,
        cachedTruncatedContent: _cachedTruncatedContent,
        cachedShouldTruncate: _cachedShouldTruncate,
        dataService: _dataService,
        widgetHash: _widgetHash,
        onNavigateToThread: _navigateToThread,
        onNavigateToMentionProfile: _navigateToMentionProfile,
      );
    } catch (e) {
      debugPrint('[QuoteWidget] Error in build: $e');
      return const SizedBox.shrink();
    }
  }
}

// Safe state manager with null checks
class _SafeQuoteManager extends StatelessWidget {
  final ValueNotifier<NoteModel?> noteNotifier;
  final ValueNotifier<UserModel?> userNotifier;
  final ValueNotifier<bool> isLoadingNotifier;
  final ValueNotifier<bool> hasErrorNotifier;
  final String? cachedFormattedTime;
  final Map<String, dynamic>? cachedParsedContent;
  final Map<String, dynamic>? cachedTruncatedContent;
  final bool? cachedShouldTruncate;
  final DataService dataService;
  final String widgetHash;
  final Function(String) onNavigateToThread;
  final Function(String) onNavigateToMentionProfile;

  const _SafeQuoteManager({
    required this.noteNotifier,
    required this.userNotifier,
    required this.isLoadingNotifier,
    required this.hasErrorNotifier,
    required this.cachedFormattedTime,
    required this.cachedParsedContent,
    required this.cachedTruncatedContent,
    required this.cachedShouldTruncate,
    required this.dataService,
    required this.widgetHash,
    required this.onNavigateToThread,
    required this.onNavigateToMentionProfile,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isLoadingNotifier,
      builder: (context, isLoading, _) {
        if (isLoading) {
          return const _LoadingQuote();
        }

        return ValueListenableBuilder<bool>(
          valueListenable: hasErrorNotifier,
          builder: (context, hasError, _) {
            if (hasError) {
              return const _ErrorQuote();
            }

            return ValueListenableBuilder<NoteModel?>(
              valueListenable: noteNotifier,
              builder: (context, note, _) {
                if (note == null) {
                  return const _ErrorQuote();
                }

                return ValueListenableBuilder<UserModel?>(
                  valueListenable: userNotifier,
                  builder: (context, user, _) {
                    // Hide quote if user couldn't be loaded
                    if (user == null || user.name == 'Anonymous') {
                      return const SizedBox.shrink();
                    }

                    // Null safety checks
                    if (cachedFormattedTime == null || cachedParsedContent == null) {
                      return const _ErrorQuote();
                    }

                    return _SafeQuoteContent(
                      note: note,
                      user: user,
                      cachedFormattedTime: cachedFormattedTime!,
                      cachedParsedContent: cachedParsedContent!,
                      cachedTruncatedContent: cachedTruncatedContent,
                      cachedShouldTruncate: cachedShouldTruncate ?? false,
                      dataService: dataService,
                      widgetHash: widgetHash,
                      onNavigateToThread: onNavigateToThread,
                      onNavigateToMentionProfile: onNavigateToMentionProfile,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

// Safe quote content with error handling
class _SafeQuoteContent extends StatelessWidget {
  final NoteModel note;
  final UserModel user;
  final String cachedFormattedTime;
  final Map<String, dynamic> cachedParsedContent;
  final Map<String, dynamic>? cachedTruncatedContent;
  final bool cachedShouldTruncate;
  final DataService dataService;
  final String widgetHash;
  final Function(String) onNavigateToThread;
  final Function(String) onNavigateToMentionProfile;

  const _SafeQuoteContent({
    required this.note,
    required this.user,
    required this.cachedFormattedTime,
    required this.cachedParsedContent,
    required this.cachedTruncatedContent,
    required this.cachedShouldTruncate,
    required this.dataService,
    required this.widgetHash,
    required this.onNavigateToThread,
    required this.onNavigateToMentionProfile,
  });

  @override
  Widget build(BuildContext context) {
    try {
      final textParts = cachedParsedContent['textParts'] as List?;
      final hasText = textParts?.any((p) => p['type'] == 'text' && (p['text'] as String? ?? '').trim().isNotEmpty) ?? false;
      final hasMedia = (cachedParsedContent['mediaUrls'] as List?)?.isNotEmpty ?? false;

      return GestureDetector(
        onTap: () => onNavigateToThread(note.id),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.colors.border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SafeQuoteHeader(
                user: user,
                formattedTime: cachedFormattedTime,
                dataService: dataService,
                widgetHash: widgetHash,
              ),
              if (hasText || hasMedia)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _SafeQuoteContentSection(
                    parsedContent: cachedShouldTruncate && cachedTruncatedContent != null ? cachedTruncatedContent! : cachedParsedContent,
                    dataService: dataService,
                    widgetHash: widgetHash,
                    onNavigateToMentionProfile: onNavigateToMentionProfile,
                    onShowMoreTap: cachedShouldTruncate ? onNavigateToThread : null,
                  ),
                ),
            ],
          ),
        ),
      );
    } catch (e) {
      debugPrint('[QuoteContent] Build error: $e');
      return const _ErrorQuote();
    }
  }
}

// Safe quote header
class _SafeQuoteHeader extends StatelessWidget {
  final UserModel user;
  final String formattedTime;
  final DataService dataService;
  final String widgetHash;

  const _SafeQuoteHeader({
    required this.user,
    required this.formattedTime,
    required this.dataService,
    required this.widgetHash,
  });

  @override
  Widget build(BuildContext context) {
    try {
      return Row(
        children: [
          GestureDetector(
            onTap: () => dataService.openUserProfile(context, user.npub),
            child: Row(
              children: [
                _SafeUserAvatar(user: user, widgetHash: widgetHash),
                const SizedBox(width: 8),
                _SafeUserName(user: user),
              ],
            ),
          ),
          const Spacer(),
          _SafeTimeStamp(formattedTime: formattedTime),
        ],
      );
    } catch (e) {
      debugPrint('[QuoteHeader] Build error: $e');
      return const SizedBox(height: 20);
    }
  }
}

// Safe user avatar
class _SafeUserAvatar extends StatelessWidget {
  final UserModel user;
  final String widgetHash;

  const _SafeUserAvatar({
    required this.user,
    required this.widgetHash,
  });

  @override
  Widget build(BuildContext context) {
    try {
      return CircleAvatar(
        key: ValueKey('avatar_${widgetHash}_${user.profileImage.hashCode}'),
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
      );
    } catch (e) {
      debugPrint('[UserAvatar] Build error: $e');
      return CircleAvatar(
        radius: 14,
        backgroundColor: context.colors.secondary,
        child: Icon(
          Icons.person,
          size: 14,
          color: context.colors.textPrimary,
        ),
      );
    }
  }
}

// Safe user name
class _SafeUserName extends StatelessWidget {
  final UserModel user;

  const _SafeUserName({required this.user});

  @override
  Widget build(BuildContext context) {
    try {
      final userName = user.name;
      final displayName = userName.length > 25 ? '${userName.substring(0, 25)}...' : userName;

      return Text(
        displayName,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: context.colors.textPrimary,
        ),
        overflow: TextOverflow.ellipsis,
      );
    } catch (e) {
      debugPrint('[UserName] Build error: $e');
      return Text(
        'Unknown User',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: context.colors.textPrimary,
        ),
      );
    }
  }
}

// Safe timestamp
class _SafeTimeStamp extends StatelessWidget {
  final String formattedTime;

  const _SafeTimeStamp({required this.formattedTime});

  @override
  Widget build(BuildContext context) {
    try {
      return Text(
        formattedTime,
        style: TextStyle(
          fontSize: 12,
          color: context.colors.textSecondary,
          fontWeight: FontWeight.w400,
        ),
      );
    } catch (e) {
      debugPrint('[TimeStamp] Build error: $e');
      return const SizedBox.shrink();
    }
  }
}

// Safe content section
class _SafeQuoteContentSection extends StatelessWidget {
  final Map<String, dynamic> parsedContent;
  final DataService dataService;
  final String widgetHash;
  final Function(String) onNavigateToMentionProfile;
  final Function(String)? onShowMoreTap;

  const _SafeQuoteContentSection({
    required this.parsedContent,
    required this.dataService,
    required this.widgetHash,
    required this.onNavigateToMentionProfile,
    required this.onShowMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    try {
      return NoteContentWidget(
        key: ValueKey('content_$widgetHash'),
        parsedContent: parsedContent,
        dataService: dataService,
        onNavigateToMentionProfile: onNavigateToMentionProfile,
        onShowMoreTap: onShowMoreTap,
      );
    } catch (e) {
      debugPrint('[QuoteContentSection] Build error: $e');
      return const SizedBox.shrink();
    }
  }
}

// Safe loading state
class _LoadingQuote extends StatelessWidget {
  const _LoadingQuote();

  @override
  Widget build(BuildContext context) {
    try {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
    } catch (e) {
      debugPrint('[LoadingQuote] Build error: $e');
      return const SizedBox.shrink();
    }
  }
}

// Safe error state
class _ErrorQuote extends StatelessWidget {
  const _ErrorQuote();

  @override
  Widget build(BuildContext context) {
    try {
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
    } catch (e) {
      debugPrint('[ErrorQuote] Build error: $e');
      return const SizedBox.shrink();
    }
  }
}
