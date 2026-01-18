import 'dart:async';
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip04/nip04.dart';
import '../../core/base/result.dart';
import 'auth_service.dart';
import 'event_cache_service.dart';
import '../../constants/relays.dart';

class DmService {
  final AuthService _authService;
  final EventCacheService _eventCacheService = EventCacheService.instance;
  Ndk? _ndk;
  String? _currentUserPubkeyHex;

  final Map<String, List<Map<String, dynamic>>> _messagesCache = {};
  final Map<String, StreamController<List<Map<String, dynamic>>>>
      _messageStreams = {};
  final Map<String, StreamSubscription<Nip01Event>> _liveMessageSubscriptions =
      {};
  final Map<String, String> _liveSubscriptionIds = {};
  StreamSubscription<Nip01Event>? _globalLiveSubscription;

  List<Map<String, dynamic>>? _cachedConversations;
  DateTime? _lastConversationsFetch;
  static const Duration _conversationsCacheDuration = Duration(minutes: 5);

  DmService({
    required AuthService authService,
  }) : _authService = authService;

  List<Map<String, dynamic>>? get cachedConversations => _cachedConversations;

  Future<String?> _getPrivateKey() async {
    final result = await _authService.getCurrentUserPrivateKey();
    if (result.isError || result.data == null) {
      return null;
    }
    return result.data;
  }

  Future<Result<void>> _ensureNdkInitialized() async {
    if (_ndk != null && _currentUserPubkeyHex != null) {
      return const Result.success(null);
    }

    try {
      final privateKey = await _getPrivateKey();
      if (privateKey == null) {
        return Result.error('Not authenticated');
      }

      final npubResult = await _authService.getCurrentUserNpub();
      if (npubResult.isError || npubResult.data == null) {
        return Result.error('Not authenticated');
      }

      final npub = npubResult.data!;
      _currentUserPubkeyHex = _authService.npubToHex(npub);

      if (_currentUserPubkeyHex == null) {
        return Result.error('Failed to convert npub to hex');
      }

      final relays = await getRelaySetMainSockets();

      _ndk = Ndk(
        NdkConfig(
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: relays,
        ),
      );

      _ndk!.accounts.loginPrivateKey(
        pubkey: _currentUserPubkeyHex!,
        privkey: privateKey,
      );

      await _startGlobalLiveSubscription();

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to initialize NDK: $e');
    }
  }

  Future<Result<List<Map<String, dynamic>>>> getConversations(
      {bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedConversations != null &&
        _lastConversationsFetch != null) {
      final age = DateTime.now().difference(_lastConversationsFetch!);
      if (age < _conversationsCacheDuration) {
        return Result.success(_cachedConversations!);
      }
    }

    final initResult = await _ensureNdkInitialized();
    if (initResult.isError) {
      return Result.error(initResult.error!);
    }

    final privateKey = await _getPrivateKey();
    if (privateKey == null) {
      return Result.error('Not authenticated');
    }

    final Map<String, Map<String, dynamic>> conversationsMap = {};

    final cachedDMs = await _eventCacheService.getDMEvents(
      _currentUserPubkeyHex!,
      limit: 60,
    );

    for (final event in cachedDMs) {
      try {
        final eventData = event.toEventData();
        final eventPubkey = eventData['pubkey'] as String? ?? '';
        final eventContent = eventData['content'] as String? ?? '';
        final createdAt = eventData['created_at'] as int? ?? 0;
        final tags = eventData['tags'] as List<dynamic>? ?? [];

        String otherUserPubkeyHex;
        if (eventPubkey == _currentUserPubkeyHex) {
          String? pTag;
          for (final tag in tags) {
            if (tag is List &&
                tag.isNotEmpty &&
                tag[0] == 'p' &&
                tag.length > 1) {
              pTag = tag[1] as String?;
              break;
            }
          }
          if (pTag == null || pTag.isEmpty) continue;
          otherUserPubkeyHex = pTag;
        } else {
          otherUserPubkeyHex = eventPubkey;
        }

        if (otherUserPubkeyHex.isEmpty) continue;

        String decryptedContent;
        try {
          if (eventPubkey == _currentUserPubkeyHex) {
            decryptedContent = Nip04.decrypt(
                privateKey, otherUserPubkeyHex, eventContent);
          } else {
            decryptedContent = Nip04.decrypt(
                privateKey, eventPubkey, eventContent);
          }
        } catch (e) {
          continue;
        }

        final message = <String, dynamic>{
          'id': eventData['id'] as String? ?? '',
          'senderPubkeyHex': eventPubkey,
          'recipientPubkeyHex': otherUserPubkeyHex,
          'content': decryptedContent,
          'createdAt': DateTime.fromMillisecondsSinceEpoch(createdAt * 1000),
          'isFromCurrentUser': eventPubkey == _currentUserPubkeyHex,
        };

        final conversationKey = otherUserPubkeyHex;
        final messageTime = message['createdAt'] as DateTime?;

        if (!conversationsMap.containsKey(conversationKey)) {
          conversationsMap[conversationKey] = <String, dynamic>{
            'otherUserPubkeyHex': otherUserPubkeyHex,
            'lastMessage': message,
            'lastMessageTime': messageTime,
          };
        } else {
          final existing = conversationsMap[conversationKey]!;
          final existingLastTime = existing['lastMessageTime'] as DateTime?;
          if (existingLastTime == null ||
              (messageTime != null && messageTime.isAfter(existingLastTime))) {
            conversationsMap[conversationKey] = <String, dynamic>{
              'otherUserPubkeyHex': existing['otherUserPubkeyHex'] as String? ??
                  otherUserPubkeyHex,
              'lastMessage': message,
              'lastMessageTime': messageTime,
            };
          }
        }
      } catch (e) {
        continue;
      }
    }

    if (conversationsMap.isNotEmpty) {
      final conversations = conversationsMap.values.toList()
        ..sort((a, b) {
          final aTime = a['lastMessageTime'] as DateTime? ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = b['lastMessageTime'] as DateTime? ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });
      _cachedConversations = conversations;
      _lastConversationsFetch = DateTime.now();
      _refreshConversationsFromRelays();
      return Result.success(conversations);
    }

    try {
      final relays = await getRelaySetMainSockets();
      final response = _ndk!.requests.query(
        filters: [
          Filter(
            kinds: [4],
            authors: [_currentUserPubkeyHex!],
            limit: 30,
          ),
          Filter(
            kinds: [4],
            pTags: [_currentUserPubkeyHex!],
            limit: 30,
          ),
        ],
        explicitRelays: relays.toSet(),
        timeout: const Duration(seconds: 10),
      );

      final Map<String, Map<String, dynamic>> conversationsMap = {};
      final Set<String> processedEventIds = {};

      try {
        await for (final event in response.stream) {
          if (processedEventIds.contains(event.id)) continue;
          processedEventIds.add(event.id);

          String otherUserPubkeyHex;
          if (event.pubKey == _currentUserPubkeyHex) {
            final pTag = event.getFirstTag('p');
            if (pTag == null || pTag.isEmpty) continue;
            otherUserPubkeyHex = pTag;
          } else {
            otherUserPubkeyHex = event.pubKey;
          }

          if (otherUserPubkeyHex.isEmpty) continue;

          String decryptedContent;
          try {
            if (event.pubKey == _currentUserPubkeyHex) {
              decryptedContent = Nip04.decrypt(
                privateKey,
                otherUserPubkeyHex,
                event.content,
              );
            } else {
              decryptedContent = Nip04.decrypt(
                privateKey,
                event.pubKey,
                event.content,
              );
            }
          } catch (e) {
            continue;
          }

          final message = <String, dynamic>{
            'id': event.id,
            'senderPubkeyHex': event.pubKey,
            'recipientPubkeyHex': otherUserPubkeyHex,
            'content': decryptedContent,
            'createdAt':
                DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
            'isFromCurrentUser': event.pubKey == _currentUserPubkeyHex,
          };

          final conversationKey = otherUserPubkeyHex;

          if (!_messagesCache.containsKey(conversationKey)) {
            _messagesCache[conversationKey] = [];
          }

          final existingMessages = _messagesCache[conversationKey]!;
          final messageId = message['id'] as String? ?? '';
          if (messageId.isNotEmpty &&
              !existingMessages
                  .any((m) => (m['id'] as String? ?? '') == messageId)) {
            existingMessages.add(message);
            if (existingMessages.length > 50) {
              existingMessages.sort((a, b) {
                final aTime = a['createdAt'] as DateTime? ?? DateTime(2000);
                final bTime = b['createdAt'] as DateTime? ?? DateTime(2000);
                return bTime.compareTo(aTime);
              });
              _messagesCache[conversationKey] =
                  existingMessages.take(50).toList();
              _messagesCache[conversationKey]!.sort((a, b) {
                final aTime = a['createdAt'] as DateTime? ?? DateTime(2000);
                final bTime = b['createdAt'] as DateTime? ?? DateTime(2000);
                return aTime.compareTo(bTime);
              });
            } else {
              existingMessages.sort((a, b) {
                final aTime = a['createdAt'] as DateTime? ?? DateTime(2000);
                final bTime = b['createdAt'] as DateTime? ?? DateTime(2000);
                return aTime.compareTo(bTime);
              });
            }
            _notifyMessageStream(conversationKey);
          }

          if (!conversationsMap.containsKey(conversationKey)) {
            conversationsMap[conversationKey] = <String, dynamic>{
              'otherUserPubkeyHex': otherUserPubkeyHex,
              'lastMessage': message,
              'lastMessageTime': message['createdAt'] as DateTime?,
            };
          } else {
            final existing = conversationsMap[conversationKey]!;
            final existingLastTime = existing['lastMessageTime'] as DateTime?;
            final messageTime = message['createdAt'] as DateTime?;
            if (existingLastTime == null ||
                (messageTime != null &&
                    messageTime.isAfter(existingLastTime))) {
              conversationsMap[conversationKey] = <String, dynamic>{
                'otherUserPubkeyHex':
                    existing['otherUserPubkeyHex'] as String? ??
                        otherUserPubkeyHex,
                'otherUserName': existing['otherUserName'] as String?,
                'otherUserProfileImage':
                    existing['otherUserProfileImage'] as String?,
                'lastMessage': message,
                'unreadCount': existing['unreadCount'] as int? ?? 0,
                'lastMessageTime': messageTime,
              };
            }
          }
        }
      } catch (e) {
        return Result.error('Failed to get conversations: $e');
      }

      final conversations = conversationsMap.values.toList()
        ..sort((a, b) {
          final aTime = a['lastMessageTime'] as DateTime? ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = b['lastMessageTime'] as DateTime? ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });

      _cachedConversations = conversations;
      _lastConversationsFetch = DateTime.now();

      return Result.success(conversations);
    } catch (e) {
      return Result.error('Failed to get conversations: $e');
    }
  }

  void _notifyMessageStream(String otherUserPubkeyHex) {
    final messages = _messagesCache[otherUserPubkeyHex] ?? [];
    final controller = _messageStreams[otherUserPubkeyHex];
    if (controller != null && !controller.isClosed) {
      controller.add(List.from(messages));
    }
  }

  Future<void> _refreshConversationsFromRelays() async {
    try {
      final relays = await getRelaySetMainSockets();
      final response = _ndk!.requests.query(
        filters: [
          Filter(
            kinds: [4],
            authors: [_currentUserPubkeyHex!],
            limit: 30,
          ),
          Filter(
            kinds: [4],
            pTags: [_currentUserPubkeyHex!],
            limit: 30,
          ),
        ],
        explicitRelays: relays.toSet(),
        timeout: const Duration(seconds: 10),
      );

      await for (final event in response.stream) {
        final eventData = <String, dynamic>{
          'id': event.id,
          'pubkey': event.pubKey,
          'kind': 4,
          'created_at': event.createdAt,
          'content': event.content,
          'tags': event.tags,
          'sig': event.sig,
        };
        await _eventCacheService.saveEvent(eventData);
      }
    } catch (e) {}
  }

  Future<Result<List<Map<String, dynamic>>>> getMessages(
      String otherUserPubkeyHex) async {
    final initResult = await _ensureNdkInitialized();
    if (initResult.isError) {
      return Result.error(initResult.error!);
    }

    if (_messagesCache.containsKey(otherUserPubkeyHex) &&
        _messagesCache[otherUserPubkeyHex]!.isNotEmpty) {
      _fetchMessagesInBackground(otherUserPubkeyHex);
      return Result.success(_messagesCache[otherUserPubkeyHex]!);
    }

    final privateKey = await _getPrivateKey();
    if (privateKey == null) {
      return Result.error('Not authenticated');
    }

    try {
      final relays = await getRelaySetMainSockets();
      final response = _ndk!.requests.query(
        filters: [
          Filter(
            kinds: [4],
            authors: [_currentUserPubkeyHex!],
            pTags: [otherUserPubkeyHex],
            limit: 40,
          ),
          Filter(
            kinds: [4],
            authors: [otherUserPubkeyHex],
            pTags: [_currentUserPubkeyHex!],
            limit: 40,
          ),
        ],
        explicitRelays: relays.toSet(),
        timeout: const Duration(seconds: 8),
      );

      final Map<String, Map<String, dynamic>> messagesMap = {};
      final Set<String> processedEventIds = {};

      try {
        await for (final event in response.stream) {
          if (processedEventIds.contains(event.id)) continue;
          processedEventIds.add(event.id);

          String decryptedContent;
          try {
            if (event.pubKey == _currentUserPubkeyHex) {
              decryptedContent = Nip04.decrypt(
                privateKey,
                otherUserPubkeyHex,
                event.content,
              );
            } else {
              decryptedContent = Nip04.decrypt(
                privateKey,
                event.pubKey,
                event.content,
              );
            }
          } catch (e) {
            continue;
          }

          messagesMap[event.id] = <String, dynamic>{
            'id': event.id,
            'senderPubkeyHex': event.pubKey,
            'recipientPubkeyHex': event.pubKey == _currentUserPubkeyHex
                ? otherUserPubkeyHex
                : _currentUserPubkeyHex!,
            'content': decryptedContent,
            'createdAt':
                DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
            'isFromCurrentUser': event.pubKey == _currentUserPubkeyHex,
          };
        }
      } catch (e) {
        return Result.error('Failed to get messages: $e');
      }

      final merged =
          _mergeAndCapMessages(otherUserPubkeyHex, messagesMap.values);
      return Result.success(merged);
    } catch (e) {
      return Result.error('Failed to get messages: $e');
    }
  }

  Future<void> _fetchMessagesInBackground(String otherUserPubkeyHex) async {
    try {
      final privateKey = await _getPrivateKey();
      if (privateKey == null) return;

      final relays = await getRelaySetMainSockets();
      final response = _ndk!.requests.query(
        filters: [
          Filter(
            kinds: [4],
            authors: [_currentUserPubkeyHex!],
            pTags: [otherUserPubkeyHex],
            limit: 40,
          ),
          Filter(
            kinds: [4],
            authors: [otherUserPubkeyHex],
            pTags: [_currentUserPubkeyHex!],
            limit: 40,
          ),
        ],
        explicitRelays: relays.toSet(),
        timeout: const Duration(seconds: 5),
      );

      final Map<String, Map<String, dynamic>> messagesMap = {};
      final Set<String> processedEventIds = {};

      await for (final event in response.stream) {
        if (processedEventIds.contains(event.id)) continue;
        processedEventIds.add(event.id);

        String decryptedContent;
        try {
          if (event.pubKey == _currentUserPubkeyHex) {
            decryptedContent = Nip04.decrypt(
              privateKey,
              otherUserPubkeyHex,
              event.content,
            );
          } else {
            decryptedContent = Nip04.decrypt(
              privateKey,
              event.pubKey,
              event.content,
            );
          }
        } catch (e) {
          continue;
        }

        messagesMap[event.id] = <String, dynamic>{
          'id': event.id,
          'senderPubkeyHex': event.pubKey,
          'recipientPubkeyHex': event.pubKey == _currentUserPubkeyHex
              ? otherUserPubkeyHex
              : _currentUserPubkeyHex!,
          'content': decryptedContent,
          'createdAt':
              DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
          'isFromCurrentUser': event.pubKey == _currentUserPubkeyHex,
        };
      }

      if (messagesMap.isNotEmpty) {
        _mergeAndCapMessages(otherUserPubkeyHex, messagesMap.values,
            notify: true);
      }
    } catch (e) {}
  }

  List<Map<String, dynamic>> _mergeAndCapMessages(
    String otherUserPubkeyHex,
    Iterable<Map<String, dynamic>> incoming, {
    bool notify = false,
  }) {
    final existing = _messagesCache[otherUserPubkeyHex] ?? [];
    final mergedMap = <String, Map<String, dynamic>>{};
    for (final m in existing) {
      final mId = m['id'] as String? ?? '';
      if (mId.isNotEmpty) {
        mergedMap[mId] = m;
      }
    }
    for (final m in incoming) {
      final mId = m['id'] as String? ?? '';
      if (mId.isNotEmpty) {
        mergedMap[mId] = m;
      }
    }

    final merged = mergedMap.values.toList()
      ..sort((a, b) {
        final aTime = a['createdAt'] as DateTime? ?? DateTime(2000);
        final bTime = b['createdAt'] as DateTime? ?? DateTime(2000);
        return aTime.compareTo(bTime);
      });
    final capped =
        merged.length > 50 ? merged.sublist(merged.length - 50) : merged;

    _messagesCache[otherUserPubkeyHex] = capped;
    if (notify) {
      _notifyMessageStream(otherUserPubkeyHex);
    }
    return capped;
  }

  Future<Result<void>> sendMessage(
      String recipientPubkeyHex, String content) async {
    final initResult = await _ensureNdkInitialized();
    if (initResult.isError) {
      return Result.error(initResult.error!);
    }

    final privateKey = await _getPrivateKey();
    if (privateKey == null) {
      return Result.error('Not authenticated');
    }

    try {
      final encryptedContent = Nip04.encrypt(
        privateKey,
        recipientPubkeyHex,
        content,
      );

      final event = Nip01Event(
        pubKey: _currentUserPubkeyHex!,
        kind: 4,
        content: encryptedContent,
        tags: [
          ['p', recipientPubkeyHex],
        ],
      );

      await _ndk!.accounts.sign(event);

      final relays = await getRelaySetMainSockets();
      await _ndk!.broadcast.broadcast(
        nostrEvent: event,
        specificRelays: relays.toSet(),
      );

      // Optimistic local append for instant UI update
      final optimisticMessage = <String, dynamic>{
        'id': event.id,
        'senderPubkeyHex': _currentUserPubkeyHex!,
        'recipientPubkeyHex': recipientPubkeyHex,
        'content': content,
        'createdAt': DateTime.now(),
        'isFromCurrentUser': true,
      };

      if (!_messagesCache.containsKey(recipientPubkeyHex)) {
        _messagesCache[recipientPubkeyHex] = [];
      }
      final msgs = _messagesCache[recipientPubkeyHex]!;
      msgs.add(optimisticMessage);
      if (msgs.length > 50) {
        msgs.sort((a, b) {
          final aTime = a['createdAt'] as DateTime? ?? DateTime(2000);
          final bTime = b['createdAt'] as DateTime? ?? DateTime(2000);
          return bTime.compareTo(aTime);
        });
        _messagesCache[recipientPubkeyHex] = msgs.take(50).toList()
          ..sort((a, b) {
            final aTime = a['createdAt'] as DateTime? ?? DateTime(2000);
            final bTime = b['createdAt'] as DateTime? ?? DateTime(2000);
            return aTime.compareTo(bTime);
          });
      } else {
        msgs.sort((a, b) {
          final aTime = a['createdAt'] as DateTime? ?? DateTime(2000);
          final bTime = b['createdAt'] as DateTime? ?? DateTime(2000);
          return aTime.compareTo(bTime);
        });
      }
      _notifyMessageStream(recipientPubkeyHex);

      // Update conversation cache
      _updateConversationCache(recipientPubkeyHex, optimisticMessage);

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to send message: $e');
    }
  }

  void _updateConversationCache(
      String otherUserPubkeyHex, Map<String, dynamic> message) {
    if (_cachedConversations == null) return;
    final idx = _cachedConversations!.indexWhere((c) =>
        (c['otherUserPubkeyHex'] as String? ?? '') == otherUserPubkeyHex);
    if (idx >= 0) {
      final existing = _cachedConversations![idx];
      final messageTime = message['createdAt'] as DateTime?;
      _cachedConversations![idx] = <String, dynamic>{
        'otherUserPubkeyHex':
            existing['otherUserPubkeyHex'] as String? ?? otherUserPubkeyHex,
        'otherUserName': existing['otherUserName'] as String?,
        'otherUserProfileImage': existing['otherUserProfileImage'] as String?,
        'lastMessage': message,
        'unreadCount': existing['unreadCount'] as int? ?? 0,
        'lastMessageTime': messageTime,
      };
    } else {
      final messageTime = message['createdAt'] as DateTime?;
      _cachedConversations!.add(<String, dynamic>{
        'otherUserPubkeyHex': otherUserPubkeyHex,
        'otherUserName': null,
        'otherUserProfileImage': null,
        'lastMessage': message,
        'unreadCount': 0,
        'lastMessageTime': messageTime,
      });
    }
    _cachedConversations!.sort((a, b) {
      final aTime = a['lastMessageTime'] as DateTime? ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b['lastMessageTime'] as DateTime? ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
  }

  Stream<List<Map<String, dynamic>>> subscribeToMessages(
      String otherUserPubkeyHex) {
    StreamController<List<Map<String, dynamic>>> controller;

    if (!_messageStreams.containsKey(otherUserPubkeyHex)) {
      controller = StreamController<List<Map<String, dynamic>>>.broadcast();
      _messageStreams[otherUserPubkeyHex] = controller;

      controller.onCancel = () {
        _messageStreams.remove(otherUserPubkeyHex);
        _liveMessageSubscriptions[otherUserPubkeyHex]?.cancel();
        _liveMessageSubscriptions.remove(otherUserPubkeyHex);
        final subscriptionId = _liveSubscriptionIds.remove(otherUserPubkeyHex);
        if (subscriptionId != null) {
          _ndk?.requests.closeSubscription(subscriptionId);
        }
        if (!controller.isClosed) {
          controller.close();
        }
      };
    } else {
      controller = _messageStreams[otherUserPubkeyHex]!;
    }

    final cachedMessages = _messagesCache[otherUserPubkeyHex] ?? [];

    return Stream.multi((sink) {
      sink.add(List.from(cachedMessages));

      _ensureLiveSubscription(otherUserPubkeyHex);

      final subscription = controller.stream.listen(
        (messages) {
          sink.add(messages);
        },
        onError: (error) {
          sink.addError(error);
        },
        onDone: () {
          sink.close();
        },
      );

      sink.onCancel = () {
        subscription.cancel();
      };
    });
  }

  Future<void> _ensureLiveSubscription(String otherUserPubkeyHex) async {
    if (_liveMessageSubscriptions.containsKey(otherUserPubkeyHex)) return;

    final initResult = await _ensureNdkInitialized();
    if (initResult.isError) {
      return;
    }

    try {
      final relays = await getRelaySetMainSockets();
      final response = _ndk!.requests.subscription(
        name: 'dm-live-$otherUserPubkeyHex',
        filters: [
          Filter(
            kinds: [4],
            authors: [_currentUserPubkeyHex!],
            pTags: [otherUserPubkeyHex],
          ),
          Filter(
            kinds: [4],
            authors: [otherUserPubkeyHex],
            pTags: [_currentUserPubkeyHex!],
          ),
        ],
        explicitRelays: relays.toSet(),
      );

      final sub = response.stream.listen((event) async {
        if (event.pubKey != _currentUserPubkeyHex &&
            event.pubKey != otherUserPubkeyHex) {
          return;
        }

        if (!_messagesCache.containsKey(otherUserPubkeyHex)) {
          _messagesCache[otherUserPubkeyHex] = [];
        }

        final existingMessages = _messagesCache[otherUserPubkeyHex]!;
        final eventId = event.id;
        if (existingMessages.any((m) => (m['id'] as String? ?? '') == eventId))
          return;

        final privateKey = await _getPrivateKey();
        if (privateKey == null) return;

        String decryptedContent;
        try {
          if (event.pubKey == _currentUserPubkeyHex) {
            decryptedContent = Nip04.decrypt(
              privateKey,
              otherUserPubkeyHex,
              event.content,
            );
          } else {
            decryptedContent = Nip04.decrypt(
              privateKey,
              event.pubKey,
              event.content,
            );
          }
        } catch (e) {
          return;
        }

        final message = <String, dynamic>{
          'id': event.id,
          'senderPubkeyHex': event.pubKey,
          'recipientPubkeyHex': event.pubKey == _currentUserPubkeyHex
              ? otherUserPubkeyHex
              : _currentUserPubkeyHex!,
          'content': decryptedContent,
          'createdAt':
              DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
          'isFromCurrentUser': event.pubKey == _currentUserPubkeyHex,
        };

        existingMessages.add(message);
        if (existingMessages.length > 50) {
          existingMessages.sort((a, b) {
            final aTime = a['createdAt'] as DateTime? ?? DateTime(2000);
            final bTime = b['createdAt'] as DateTime? ?? DateTime(2000);
            return bTime.compareTo(aTime);
          });
          _messagesCache[otherUserPubkeyHex] =
              existingMessages.take(50).toList()
                ..sort((a, b) {
                  final aTime = a['createdAt'] as DateTime? ?? DateTime(2000);
                  final bTime = b['createdAt'] as DateTime? ?? DateTime(2000);
                  return aTime.compareTo(bTime);
                });
        } else {
          existingMessages.sort((a, b) {
            final aTime = a['createdAt'] as DateTime? ?? DateTime(2000);
            final bTime = b['createdAt'] as DateTime? ?? DateTime(2000);
            return aTime.compareTo(bTime);
          });
        }

        _notifyMessageStream(otherUserPubkeyHex);
      });

      _liveMessageSubscriptions[otherUserPubkeyHex] = sub;
      _liveSubscriptionIds[otherUserPubkeyHex] = response.requestId;
    } catch (_) {}
  }

  Future<void> _startGlobalLiveSubscription() async {
    if (_globalLiveSubscription != null) return;
    if (_ndk == null || _currentUserPubkeyHex == null) return;

    try {
      final relays = await getRelaySetMainSockets();
      final response = _ndk!.requests.subscription(
        name: 'dm-live-all',
        filters: [
          Filter(
            kinds: [4],
            authors: [_currentUserPubkeyHex!],
          ),
          Filter(
            kinds: [4],
            pTags: [_currentUserPubkeyHex!],
          ),
        ],
        explicitRelays: relays.toSet(),
      );

      _globalLiveSubscription = response.stream.listen((event) async {
        String otherUserPubkeyHex;
        if (event.pubKey == _currentUserPubkeyHex) {
          final pTag = event.getFirstTag('p');
          if (pTag == null || pTag.isEmpty) return;
          otherUserPubkeyHex = pTag;
        } else {
          otherUserPubkeyHex = event.pubKey;
        }

        if (otherUserPubkeyHex.isEmpty) return;

        if (!_messagesCache.containsKey(otherUserPubkeyHex)) {
          _messagesCache[otherUserPubkeyHex] = [];
        }

        final existingMessages = _messagesCache[otherUserPubkeyHex]!;
        final eventId = event.id;
        if (existingMessages.any((m) => (m['id'] as String? ?? '') == eventId))
          return;

        final privateKey = await _getPrivateKey();
        if (privateKey == null) return;

        String decryptedContent;
        try {
          if (event.pubKey == _currentUserPubkeyHex) {
            decryptedContent = Nip04.decrypt(
              privateKey,
              otherUserPubkeyHex,
              event.content,
            );
          } else {
            decryptedContent = Nip04.decrypt(
              privateKey,
              event.pubKey,
              event.content,
            );
          }
        } catch (_) {
          return;
        }

        final message = <String, dynamic>{
          'id': event.id,
          'senderPubkeyHex': event.pubKey,
          'recipientPubkeyHex': event.pubKey == _currentUserPubkeyHex
              ? otherUserPubkeyHex
              : _currentUserPubkeyHex!,
          'content': decryptedContent,
          'createdAt':
              DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
          'isFromCurrentUser': event.pubKey == _currentUserPubkeyHex,
        };

        existingMessages.add(message);
        if (existingMessages.length > 50) {
          existingMessages.sort((a, b) {
            final aTime = a['createdAt'] as DateTime? ?? DateTime(2000);
            final bTime = b['createdAt'] as DateTime? ?? DateTime(2000);
            return bTime.compareTo(aTime);
          });
          _messagesCache[otherUserPubkeyHex] =
              existingMessages.take(50).toList()
                ..sort((a, b) {
                  final aTime = a['createdAt'] as DateTime? ?? DateTime(2000);
                  final bTime = b['createdAt'] as DateTime? ?? DateTime(2000);
                  return aTime.compareTo(bTime);
                });
        } else {
          existingMessages.sort((a, b) {
            final aTime = a['createdAt'] as DateTime? ?? DateTime(2000);
            final bTime = b['createdAt'] as DateTime? ?? DateTime(2000);
            return aTime.compareTo(bTime);
          });
        }

        _notifyMessageStream(otherUserPubkeyHex);
      });
    } catch (_) {}
  }
}
