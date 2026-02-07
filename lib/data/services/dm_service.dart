import 'dart:async';
import 'dart:convert';
import 'package:isar/isar.dart';
import '../../core/base/result.dart';
import '../../models/event_model.dart';
import 'auth_service.dart';
import 'isar_database_service.dart';
import 'nostr_service.dart';
import 'relay_service.dart';
import '../../constants/relays.dart';
import '../../src/rust/api/nip17.dart' as rust_nip17;

class DmService {
  final AuthService _authService;
  final IsarDatabaseService _isarService = IsarDatabaseService.instance;
  String? _currentUserPubkeyHex;
  bool _initialized = false;

  final Map<String, List<Map<String, dynamic>>> _messagesCache = {};
  final Map<String, StreamController<List<Map<String, dynamic>>>>
      _messageStreams = {};
  final Set<String> _failedUnwrapIds = {};

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

  Future<Result<void>> _ensureInitialized() async {
    if (_initialized && _currentUserPubkeyHex != null) {
      return const Result.success(null);
    }

    try {
      final npubResult = await _authService.getCurrentUserNpub();
      if (npubResult.isError || npubResult.data == null) {
        return Result.error('Not authenticated');
      }

      final npub = npubResult.data!;
      _currentUserPubkeyHex = _authService.npubToHex(npub);

      if (_currentUserPubkeyHex == null) {
        return Result.error('Failed to convert npub to hex');
      }

      _initialized = true;
      return const Result.success(null);
    } catch (e) {
      return Result.error('Failed to initialize: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _queryDmRelays({
    required List<Map<String, dynamic>> filters,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final wsManager = WebSocketManager.instance;
    final events = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    for (final filter in filters) {
      final request = NostrService.createRequest(filter);
      final requestJson = jsonDecode(request) as List<dynamic>;
      final subscriptionId = requestJson[1] as String;

      final relays = wsManager.healthyRelays.isNotEmpty
          ? wsManager.healthyRelays
          : wsManager.relayUrls;
      if (relays.isEmpty) continue;

      final completers = relays.take(5).map((relayUrl) {
        return wsManager.sendQuery(
          relayUrl,
          request,
          subscriptionId,
          onEvent: (eventMap, url) {
            final id = eventMap['id'] as String?;
            if (id != null && seenIds.add(id)) {
              events.add(eventMap);
            }
          },
          timeout: timeout,
        ).then((c) => c.future);
      }).toList();

      await Future.wait(completers)
          .timeout(timeout + const Duration(seconds: 5), onTimeout: () => []);
    }

    return events;
  }

  Map<String, dynamic>? _unwrapGiftWrap(
    Map<String, dynamic> eventData,
    String privateKey,
  ) {
    final kind = eventData['kind'] as int? ?? 0;
    if (kind != 1059) return null;

    final eventId = eventData['id'] as String? ?? '';
    if (eventId.isNotEmpty && _failedUnwrapIds.contains(eventId)) return null;

    try {
      final giftWrapJson = jsonEncode(eventData);
      final unwrappedJson = rust_nip17.unwrapGiftWrap(
        receiverPrivateKeyHex: privateKey,
        giftWrapJson: giftWrapJson,
      );
      final unwrapped = jsonDecode(unwrappedJson) as Map<String, dynamic>;
      final sender = unwrapped['sender'] as String? ?? '';
      final rumor = unwrapped['rumor'] as Map<String, dynamic>? ?? {};
      final rumorKind = rumor['kind'] as int? ?? 0;

      if (rumorKind != 14) return null;

      final content = rumor['content'] as String? ?? '';
      final rumorCreatedAt = rumor['created_at'] as int? ?? 0;
      final rumorId = rumor['id'] as String? ?? eventId;
      final tags = rumor['tags'] as List<dynamic>? ?? [];

      String? recipientPubkey;
      for (final tag in tags) {
        if (tag is List && tag.isNotEmpty && tag[0] == 'p' && tag.length > 1) {
          recipientPubkey = tag[1] as String?;
          break;
        }
      }

      final isFromCurrentUser = sender == _currentUserPubkeyHex;
      final otherUserPubkeyHex =
          isFromCurrentUser ? (recipientPubkey ?? '') : sender;

      if (otherUserPubkeyHex.isEmpty) return null;

      return <String, dynamic>{
        'id': rumorId,
        'senderPubkeyHex': sender,
        'recipientPubkeyHex': otherUserPubkeyHex,
        'content': content,
        'createdAt': DateTime.fromMillisecondsSinceEpoch(rumorCreatedAt * 1000),
        'isFromCurrentUser': isFromCurrentUser,
      };
    } catch (_) {
      if (eventId.isNotEmpty) _failedUnwrapIds.add(eventId);
      return null;
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

    final initResult = await _ensureInitialized();
    if (initResult.isError) {
      return Result.error(initResult.error!);
    }

    final privateKey = await _getPrivateKey();
    if (privateKey == null) {
      return Result.error('Not authenticated');
    }

    final Map<String, Map<String, dynamic>> conversationsMap = {};

    final cachedDMs = await _getDMEvents(_currentUserPubkeyHex!, limit: 60);

    for (final event in cachedDMs) {
      try {
        final eventData = event.toEventData();
        final message = _unwrapGiftWrap(eventData, privateKey);
        if (message == null) continue;

        final otherUserPubkeyHex = message['isFromCurrentUser'] == true
            ? message['recipientPubkeyHex'] as String
            : message['senderPubkeyHex'] as String;

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
      final relayEvents = await _queryDmRelays(
        filters: [
          {
            'kinds': [1059],
            '#p': [_currentUserPubkeyHex!],
            'limit': 40
          },
        ],
      );

      final Set<String> processedEventIds = {};

      for (final eventData in relayEvents) {
        final eventId = eventData['id'] as String? ?? '';
        if (processedEventIds.contains(eventId)) continue;
        processedEventIds.add(eventId);

        final message = _unwrapGiftWrap(eventData, privateKey);
        if (message == null) continue;

        final otherUserPubkeyHex = message['isFromCurrentUser'] == true
            ? message['recipientPubkeyHex'] as String
            : message['senderPubkeyHex'] as String;

        final conversationKey = otherUserPubkeyHex;

        if (!_messagesCache.containsKey(conversationKey)) {
          _messagesCache[conversationKey] = [];
        }

        final existingMessages = _messagesCache[conversationKey]!;
        final msgId = message['id'] as String? ?? '';
        if (msgId.isNotEmpty &&
            !existingMessages.any((m) => (m['id'] as String? ?? '') == msgId)) {
          existingMessages.add(message);
          _sortAndCapMessages(conversationKey);
          _notifyMessageStream(conversationKey);
        }

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

        await _saveEvent(eventData);
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

  void _sortAndCapMessages(String key) {
    final msgs = _messagesCache[key];
    if (msgs == null) return;
    msgs.sort((a, b) {
      final aTime = a['createdAt'] as DateTime? ?? DateTime(2000);
      final bTime = b['createdAt'] as DateTime? ?? DateTime(2000);
      return aTime.compareTo(bTime);
    });
    if (msgs.length > 50) {
      _messagesCache[key] = msgs.sublist(msgs.length - 50);
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
      final relayEvents = await _queryDmRelays(
        filters: [
          {
            'kinds': [1059],
            '#p': [_currentUserPubkeyHex!],
            'limit': 40
          },
        ],
      );

      for (final eventData in relayEvents) {
        await _saveEvent(eventData);
      }
    } catch (e) {}
  }

  Future<Result<List<Map<String, dynamic>>>> getMessages(
      String otherUserPubkeyHex) async {
    final initResult = await _ensureInitialized();
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
      final relayEvents = await _queryDmRelays(
        filters: [
          {
            'kinds': [1059],
            '#p': [_currentUserPubkeyHex!],
            'limit': 80
          },
        ],
        timeout: const Duration(seconds: 8),
      );

      final Map<String, Map<String, dynamic>> messagesMap = {};

      for (final eventData in relayEvents) {
        final eventId = eventData['id'] as String? ?? '';
        if (messagesMap.containsKey(eventId)) continue;

        final message = _unwrapGiftWrap(eventData, privateKey);
        if (message == null) continue;

        final msgOther = message['isFromCurrentUser'] == true
            ? message['recipientPubkeyHex'] as String
            : message['senderPubkeyHex'] as String;
        if (msgOther != otherUserPubkeyHex) continue;

        messagesMap[message['id'] as String? ?? eventId] = message;
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

      final relayEvents = await _queryDmRelays(
        filters: [
          {
            'kinds': [1059],
            '#p': [_currentUserPubkeyHex!],
            'limit': 80
          },
        ],
        timeout: const Duration(seconds: 5),
      );

      final Map<String, Map<String, dynamic>> messagesMap = {};

      for (final eventData in relayEvents) {
        final eventId = eventData['id'] as String? ?? '';
        if (messagesMap.containsKey(eventId)) continue;

        final message = _unwrapGiftWrap(eventData, privateKey);
        if (message == null) continue;

        final msgOther = message['isFromCurrentUser'] == true
            ? message['recipientPubkeyHex'] as String
            : message['senderPubkeyHex'] as String;
        if (msgOther != otherUserPubkeyHex) continue;

        messagesMap[message['id'] as String? ?? eventId] = message;
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
      if (mId.isNotEmpty) mergedMap[mId] = m;
    }
    for (final m in incoming) {
      final mId = m['id'] as String? ?? '';
      if (mId.isNotEmpty) mergedMap[mId] = m;
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
    if (notify) _notifyMessageStream(otherUserPubkeyHex);
    return capped;
  }

  Future<Result<void>> sendMessage(
      String recipientPubkeyHex, String content) async {
    final initResult = await _ensureInitialized();
    if (initResult.isError) {
      return Result.error(initResult.error!);
    }

    final privateKey = await _getPrivateKey();
    if (privateKey == null) {
      return Result.error('Not authenticated');
    }

    try {
      final recipientWrapJson = rust_nip17.createGiftWrapDm(
        senderPrivateKeyHex: privateKey,
        receiverPubkeyHex: recipientPubkeyHex,
        message: content,
      );

      final senderWrapJson = rust_nip17.createGiftWrapDmForSender(
        senderPrivateKeyHex: privateKey,
        receiverPubkeyHex: recipientPubkeyHex,
        message: content,
      );

      final recipientWrap =
          jsonDecode(recipientWrapJson) as Map<String, dynamic>;
      final senderWrap = jsonDecode(senderWrapJson) as Map<String, dynamic>;

      final wsManager = WebSocketManager.instance;
      final recipientSerialized = NostrService.serializeEvent(recipientWrap);
      await wsManager.priorityBroadcastToAll(recipientSerialized);

      final senderSerialized = NostrService.serializeEvent(senderWrap);
      await wsManager.priorityBroadcastToAll(senderSerialized);

      final optimisticMessage = <String, dynamic>{
        'id': recipientWrap['id'] as String? ?? '',
        'senderPubkeyHex': _currentUserPubkeyHex!,
        'recipientPubkeyHex': recipientPubkeyHex,
        'content': content,
        'createdAt': DateTime.now(),
        'isFromCurrentUser': true,
      };

      if (!_messagesCache.containsKey(recipientPubkeyHex)) {
        _messagesCache[recipientPubkeyHex] = [];
      }
      _messagesCache[recipientPubkeyHex]!.add(optimisticMessage);
      _sortAndCapMessages(recipientPubkeyHex);
      _notifyMessageStream(recipientPubkeyHex);

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

      _fetchMessagesInBackground(otherUserPubkeyHex);

      final subscription = controller.stream.listen(
        (messages) => sink.add(messages),
        onError: (error) => sink.addError(error),
        onDone: () => sink.close(),
      );

      sink.onCancel = () {
        subscription.cancel();
      };
    });
  }

  Future<List<EventModel>> _getDMEvents(String userPubkey, {int? limit}) async {
    try {
      if (userPubkey.isEmpty) return [];
      final db = await _isarService.isar;
      final giftWraps =
          await db.eventModels.where().kindEqualToAnyCreatedAt(1059).findAll();

      final matchingEvents = <EventModel>[];

      for (final event in giftWraps) {
        final pTagValues = event.getTagValues('p');
        if (pTagValues.contains(userPubkey)) {
          matchingEvents.add(event);
        }
      }

      matchingEvents.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (limit != null && matchingEvents.length > limit) {
        return matchingEvents.sublist(0, limit);
      }
      return matchingEvents;
    } catch (e) {
      return [];
    }
  }

  Future<void> _saveEvent(Map<String, dynamic> eventData) async {
    try {
      final eventId = eventData['id'] as String? ?? '';
      if (eventId.isEmpty) return;
      final db = await _isarService.isar;
      final eventModel = EventModel.fromEventData(eventData);
      await db.writeTxn(() async {
        final existing =
            await db.eventModels.where().eventIdEqualTo(eventId).findFirst();
        if (existing == null) {
          await db.eventModels.put(eventModel);
        }
      });
    } catch (_) {}
  }
}
