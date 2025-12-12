import 'dart:async';
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip04/nip04.dart';
import '../../core/base/result.dart';
import '../../models/dm_message_model.dart';
import 'auth_service.dart';
import '../../constants/relays.dart';

class DmService {
  final AuthService _authService;
  Ndk? _ndk;
  String? _currentUserPubkeyHex;
  String? _currentUserPrivateKey;

  final Map<String, List<DmMessageModel>> _messagesCache = {};
  final Map<String, StreamController<List<DmMessageModel>>> _messageStreams = {};
  final Map<String, StreamSubscription<Nip01Event>> _liveMessageSubscriptions = {};
  final Map<String, String> _liveSubscriptionIds = {};
  StreamSubscription<Nip01Event>? _globalLiveSubscription;

  List<DmConversationModel>? _cachedConversations;
  DateTime? _lastConversationsFetch;
  static const Duration _conversationsCacheDuration = Duration(minutes: 5);

  DmService({
    required AuthService authService,
  }) : _authService = authService;

  List<DmConversationModel>? get cachedConversations => _cachedConversations;

  Future<Result<void>> _ensureNdkInitialized() async {
    if (_ndk != null && _currentUserPubkeyHex != null && _currentUserPrivateKey != null) {
      return const Result.success(null);
    }

    try {
      final privateKeyResult = await _authService.getCurrentUserPrivateKey();
      if (privateKeyResult.isError || privateKeyResult.data == null) {
        return Result.error('Not authenticated');
      }

      final npubResult = await _authService.getCurrentUserNpub();
      if (npubResult.isError || npubResult.data == null) {
        return Result.error('Not authenticated');
      }

      _currentUserPrivateKey = privateKeyResult.data;
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
        privkey: _currentUserPrivateKey!,
      );

      await _startGlobalLiveSubscription();

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to initialize NDK: $e');
    }
  }

  Future<Result<List<DmConversationModel>>> getConversations({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedConversations != null && _lastConversationsFetch != null) {
      final age = DateTime.now().difference(_lastConversationsFetch!);
      if (age < _conversationsCacheDuration) {
        return Result.success(_cachedConversations!);
      }
    }

    final initResult = await _ensureNdkInitialized();
    if (initResult.isError) {
      return Result.error(initResult.error!);
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

      final Map<String, DmConversationModel> conversationsMap = {};
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
                _currentUserPrivateKey!,
                otherUserPubkeyHex,
                event.content,
              );
            } else {
              decryptedContent = Nip04.decrypt(
                _currentUserPrivateKey!,
                event.pubKey,
                event.content,
              );
            }
          } catch (e) {
            continue;
          }

          final message = DmMessageModel(
            id: event.id,
            senderPubkeyHex: event.pubKey,
            recipientPubkeyHex: otherUserPubkeyHex,
            content: decryptedContent,
            createdAt: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
            isFromCurrentUser: event.pubKey == _currentUserPubkeyHex,
          );

          final conversationKey = otherUserPubkeyHex;

          if (!_messagesCache.containsKey(conversationKey)) {
            _messagesCache[conversationKey] = [];
          }

          final existingMessages = _messagesCache[conversationKey]!;
          if (!existingMessages.any((m) => m.id == message.id)) {
            existingMessages.add(message);
            if (existingMessages.length > 50) {
              existingMessages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
              _messagesCache[conversationKey] = existingMessages.take(50).toList();
              _messagesCache[conversationKey]!.sort((a, b) => a.createdAt.compareTo(b.createdAt));
            } else {
              existingMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
            }
            _notifyMessageStream(conversationKey);
          }

          if (!conversationsMap.containsKey(conversationKey)) {
            conversationsMap[conversationKey] = DmConversationModel(
              otherUserPubkeyHex: otherUserPubkeyHex,
              lastMessage: message,
              lastMessageTime: message.createdAt,
            );
          } else {
            final existing = conversationsMap[conversationKey]!;
            if (existing.lastMessageTime == null || message.createdAt.isAfter(existing.lastMessageTime!)) {
              conversationsMap[conversationKey] = existing.copyWith(
                lastMessage: message,
                lastMessageTime: message.createdAt,
              );
            }
          }
        }
      } catch (e) {
        return Result.error('Failed to get conversations: $e');
      }

      final conversations = conversationsMap.values.toList()
        ..sort((a, b) {
          final aTime = a.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = b.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0);
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

  Future<Result<List<DmMessageModel>>> getMessages(String otherUserPubkeyHex) async {
    final initResult = await _ensureNdkInitialized();
    if (initResult.isError) {
      return Result.error(initResult.error!);
    }

    if (_messagesCache.containsKey(otherUserPubkeyHex) && _messagesCache[otherUserPubkeyHex]!.isNotEmpty) {
      _fetchMessagesInBackground(otherUserPubkeyHex);
      return Result.success(_messagesCache[otherUserPubkeyHex]!);
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

      final Map<String, DmMessageModel> messagesMap = {};
      final Set<String> processedEventIds = {};

      try {
        await for (final event in response.stream) {
          if (processedEventIds.contains(event.id)) continue;
          processedEventIds.add(event.id);

          String decryptedContent;
          try {
            if (event.pubKey == _currentUserPubkeyHex) {
              decryptedContent = Nip04.decrypt(
                _currentUserPrivateKey!,
                otherUserPubkeyHex,
                event.content,
              );
            } else {
              decryptedContent = Nip04.decrypt(
                _currentUserPrivateKey!,
                event.pubKey,
                event.content,
              );
            }
          } catch (e) {
            continue;
          }

          messagesMap[event.id] = DmMessageModel(
            id: event.id,
            senderPubkeyHex: event.pubKey,
            recipientPubkeyHex: event.pubKey == _currentUserPubkeyHex ? otherUserPubkeyHex : _currentUserPubkeyHex!,
            content: decryptedContent,
            createdAt: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
            isFromCurrentUser: event.pubKey == _currentUserPubkeyHex,
          );
        }
      } catch (e) {
        return Result.error('Failed to get messages: $e');
      }

      final merged = _mergeAndCapMessages(otherUserPubkeyHex, messagesMap.values);
      return Result.success(merged);
    } catch (e) {
      return Result.error('Failed to get messages: $e');
    }
  }

  Future<void> _fetchMessagesInBackground(String otherUserPubkeyHex) async {
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
        timeout: const Duration(seconds: 5),
      );

      final Map<String, DmMessageModel> messagesMap = {};
      final Set<String> processedEventIds = {};

      await for (final event in response.stream) {
        if (processedEventIds.contains(event.id)) continue;
        processedEventIds.add(event.id);

        String decryptedContent;
        try {
          if (event.pubKey == _currentUserPubkeyHex) {
            decryptedContent = Nip04.decrypt(
              _currentUserPrivateKey!,
              otherUserPubkeyHex,
              event.content,
            );
          } else {
            decryptedContent = Nip04.decrypt(
              _currentUserPrivateKey!,
              event.pubKey,
              event.content,
            );
          }
        } catch (e) {
          continue;
        }

        messagesMap[event.id] = DmMessageModel(
          id: event.id,
          senderPubkeyHex: event.pubKey,
          recipientPubkeyHex: event.pubKey == _currentUserPubkeyHex ? otherUserPubkeyHex : _currentUserPubkeyHex!,
          content: decryptedContent,
          createdAt: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
          isFromCurrentUser: event.pubKey == _currentUserPubkeyHex,
        );
      }

      if (messagesMap.isNotEmpty) {
        _mergeAndCapMessages(otherUserPubkeyHex, messagesMap.values, notify: true);
      }
    } catch (e) {}
  }

  List<DmMessageModel> _mergeAndCapMessages(
    String otherUserPubkeyHex,
    Iterable<DmMessageModel> incoming, {
    bool notify = false,
  }) {
    final existing = _messagesCache[otherUserPubkeyHex] ?? [];
    final mergedMap = <String, DmMessageModel>{};
    for (final m in existing) {
      mergedMap[m.id] = m;
    }
    for (final m in incoming) {
      mergedMap[m.id] = m;
    }

    final merged = mergedMap.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final capped = merged.length > 50 ? merged.sublist(merged.length - 50) : merged;

    _messagesCache[otherUserPubkeyHex] = capped;
    if (notify) {
      _notifyMessageStream(otherUserPubkeyHex);
    }
    return capped;
  }

  Future<Result<void>> sendMessage(String recipientPubkeyHex, String content) async {
    final initResult = await _ensureNdkInitialized();
    if (initResult.isError) {
      return Result.error(initResult.error!);
    }

    try {
      final encryptedContent = Nip04.encrypt(
        _currentUserPrivateKey!,
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
      final optimisticMessage = DmMessageModel(
        id: event.id,
        senderPubkeyHex: _currentUserPubkeyHex!,
        recipientPubkeyHex: recipientPubkeyHex,
        content: content,
        createdAt: DateTime.now(),
        isFromCurrentUser: true,
      );

      if (!_messagesCache.containsKey(recipientPubkeyHex)) {
        _messagesCache[recipientPubkeyHex] = [];
      }
      final msgs = _messagesCache[recipientPubkeyHex]!;
      msgs.add(optimisticMessage);
      if (msgs.length > 50) {
        msgs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _messagesCache[recipientPubkeyHex] = msgs.take(50).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      } else {
        msgs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      }
      _notifyMessageStream(recipientPubkeyHex);

      // Update conversation cache
      _updateConversationCache(recipientPubkeyHex, optimisticMessage);

      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to send message: $e');
    }
  }

  void _updateConversationCache(String otherUserPubkeyHex, DmMessageModel message) {
    if (_cachedConversations == null) return;
    final idx = _cachedConversations!.indexWhere((c) => c.otherUserPubkeyHex == otherUserPubkeyHex);
    if (idx >= 0) {
      final updated = _cachedConversations![idx].copyWith(
        lastMessage: message,
        lastMessageTime: message.createdAt,
      );
      _cachedConversations![idx] = updated;
    } else {
      _cachedConversations!.add(DmConversationModel(
        otherUserPubkeyHex: otherUserPubkeyHex,
        lastMessage: message,
        lastMessageTime: message.createdAt,
      ));
    }
    _cachedConversations!.sort((a, b) {
      final aTime = a.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
  }

  Stream<List<DmMessageModel>> subscribeToMessages(String otherUserPubkeyHex) {
    StreamController<List<DmMessageModel>> controller;

    if (!_messageStreams.containsKey(otherUserPubkeyHex)) {
      controller = StreamController<List<DmMessageModel>>.broadcast();
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

      final sub = response.stream.listen((event) {
        if (event.pubKey != _currentUserPubkeyHex && event.pubKey != otherUserPubkeyHex) {
          return;
        }

        if (!_messagesCache.containsKey(otherUserPubkeyHex)) {
          _messagesCache[otherUserPubkeyHex] = [];
        }

        final existingMessages = _messagesCache[otherUserPubkeyHex]!;
        if (existingMessages.any((m) => m.id == event.id)) return;

        String decryptedContent;
        try {
          if (event.pubKey == _currentUserPubkeyHex) {
            decryptedContent = Nip04.decrypt(
              _currentUserPrivateKey!,
              otherUserPubkeyHex,
              event.content,
            );
          } else {
            decryptedContent = Nip04.decrypt(
              _currentUserPrivateKey!,
              event.pubKey,
              event.content,
            );
          }
        } catch (e) {
          return;
        }

        final message = DmMessageModel(
          id: event.id,
          senderPubkeyHex: event.pubKey,
          recipientPubkeyHex: event.pubKey == _currentUserPubkeyHex ? otherUserPubkeyHex : _currentUserPubkeyHex!,
          content: decryptedContent,
          createdAt: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
          isFromCurrentUser: event.pubKey == _currentUserPubkeyHex,
        );

        existingMessages.add(message);
        if (existingMessages.length > 50) {
          existingMessages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          _messagesCache[otherUserPubkeyHex] = existingMessages.take(50).toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        } else {
          existingMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        }

        _notifyMessageStream(otherUserPubkeyHex);
      });

      _liveMessageSubscriptions[otherUserPubkeyHex] = sub;
      _liveSubscriptionIds[otherUserPubkeyHex] = response.requestId;
    } catch (_) {}
  }

  Future<void> _startGlobalLiveSubscription() async {
    if (_globalLiveSubscription != null) return;
    final initResult = await _ensureNdkInitialized();
    if (initResult.isError) return;

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

      _globalLiveSubscription = response.stream.listen((event) {
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
        if (existingMessages.any((m) => m.id == event.id)) return;

        String decryptedContent;
        try {
          if (event.pubKey == _currentUserPubkeyHex) {
            decryptedContent = Nip04.decrypt(
              _currentUserPrivateKey!,
              otherUserPubkeyHex,
              event.content,
            );
          } else {
            decryptedContent = Nip04.decrypt(
              _currentUserPrivateKey!,
              event.pubKey,
              event.content,
            );
          }
        } catch (_) {
          return;
        }

        final message = DmMessageModel(
          id: event.id,
          senderPubkeyHex: event.pubKey,
          recipientPubkeyHex: event.pubKey == _currentUserPubkeyHex ? otherUserPubkeyHex : _currentUserPubkeyHex!,
          content: decryptedContent,
          createdAt: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
          isFromCurrentUser: event.pubKey == _currentUserPubkeyHex,
        );

        existingMessages.add(message);
        if (existingMessages.length > 50) {
          existingMessages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          _messagesCache[otherUserPubkeyHex] = existingMessages.take(50).toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        } else {
          existingMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        }

        _notifyMessageStream(otherUserPubkeyHex);
      });
    } catch (_) {}
  }
}

extension DmConversationModelExtension on DmConversationModel {
  DmConversationModel copyWith({
    String? otherUserPubkeyHex,
    String? otherUserName,
    String? otherUserProfileImage,
    DmMessageModel? lastMessage,
    int? unreadCount,
    DateTime? lastMessageTime,
  }) {
    return DmConversationModel(
      otherUserPubkeyHex: otherUserPubkeyHex ?? this.otherUserPubkeyHex,
      otherUserName: otherUserName ?? this.otherUserName,
      otherUserProfileImage: otherUserProfileImage ?? this.otherUserProfileImage,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
    );
  }
}

