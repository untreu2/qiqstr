import 'dart:async';
import 'dart:convert';
import '../../core/base/result.dart';
import 'auth_service.dart';
import 'relay_service.dart';
import '../../src/rust/api/nip17.dart' as rust_nip17;
import '../../src/rust/api/database.dart' as rust_db;

class DmService {
  final AuthService _authService;
  String? _currentUserPubkeyHex;
  bool _initialized = false;

  final Map<String, List<Map<String, dynamic>>> _messagesCache = {};
  final Map<String, StreamController<List<Map<String, dynamic>>>>
      _messageStreams = {};
  final Set<String> _failedUnwrapIds = {};
  final Map<String, Map<String, dynamic>?> _decryptedEventCache = {};
  StreamSubscription<Map<String, dynamic>>? _realtimeSubscription;
  Timer? _reconnectTimer;
  Timer? _chatPollTimer;
  String? _activeChatPubkeyHex;
  String? _cachedPrivateKey;

  final StreamController<List<Map<String, dynamic>>>
      _conversationsStreamController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  List<Map<String, dynamic>>? _cachedConversations;
  DateTime? _lastConversationsFetch;
  static const Duration _conversationsCacheDuration = Duration(minutes: 5);

  DmService({
    required AuthService authService,
  }) : _authService = authService;

  List<Map<String, dynamic>>? get cachedConversations => _cachedConversations;

  Stream<List<Map<String, dynamic>>> get conversationsStream =>
      _conversationsStreamController.stream;

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
    final events = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    for (final filter in filters) {
      final results = await RustRelayService.instance.fetchEvents(
        filter,
        timeoutSecs: timeout.inSeconds,
      );
      for (final eventMap in results) {
        final id = eventMap['id'] as String?;
        if (id != null && seenIds.add(id)) {
          events.add(eventMap);
        }
      }
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

      if (rumorKind != 14 && rumorKind != 15) return null;

      final content = rumor['content'] as String? ?? '';
      final rumorCreatedAt = rumor['created_at'] as int? ?? 0;
      final rumorId = rumor['id'] as String? ?? eventId;
      final tags = rumor['tags'] as List<dynamic>? ?? [];

      String? recipientPubkey;
      String? mimeType;
      String? encryptionKey;
      String? encryptionNonce;
      String? encryptedHash;
      String? originalHash;
      int? fileSize;

      for (final tag in tags) {
        if (tag is List && tag.isNotEmpty) {
          final tagName = tag[0] as String?;
          if (tagName == 'p' && tag.length > 1) {
            recipientPubkey = tag[1] as String?;
          } else if (tagName == 'file-type' && tag.length > 1) {
            mimeType = tag[1] as String?;
          } else if (tagName == 'decryption-key' && tag.length > 1) {
            encryptionKey = tag[1] as String?;
          } else if (tagName == 'decryption-nonce' && tag.length > 1) {
            encryptionNonce = tag[1] as String?;
          } else if (tagName == 'x' && tag.length > 1) {
            encryptedHash = tag[1] as String?;
          } else if (tagName == 'ox' && tag.length > 1) {
            originalHash = tag[1] as String?;
          } else if (tagName == 'size' && tag.length > 1) {
            fileSize = int.tryParse(tag[1] as String? ?? '');
          }
        }
      }

      final isFromCurrentUser = sender == _currentUserPubkeyHex;
      final otherUserPubkeyHex =
          isFromCurrentUser ? (recipientPubkey ?? '') : sender;

      if (otherUserPubkeyHex.isEmpty) return null;

      final message = <String, dynamic>{
        'id': rumorId,
        'senderPubkeyHex': sender,
        'recipientPubkeyHex': otherUserPubkeyHex,
        'content': content,
        'createdAt':
            DateTime.fromMillisecondsSinceEpoch(rumorCreatedAt * 1000),
        'isFromCurrentUser': isFromCurrentUser,
        'kind': rumorKind,
      };

      if (rumorKind == 15) {
        if (mimeType != null) message['mimeType'] = mimeType;
        if (encryptionKey != null) message['encryptionKey'] = encryptionKey;
        if (encryptionNonce != null) message['encryptionNonce'] = encryptionNonce;
        if (encryptedHash != null) message['encryptedHash'] = encryptedHash;
        if (originalHash != null) message['originalHash'] = originalHash;
        if (fileSize != null) message['fileSize'] = fileSize;
      }

      return message;
    } catch (_) {
      if (eventId.isNotEmpty) _failedUnwrapIds.add(eventId);
      return null;
    }
  }

  Map<String, dynamic>? _unwrapGiftWrapCached(
    Map<String, dynamic> eventData,
    String privateKey,
  ) {
    final eventId = eventData['id'] as String? ?? '';
    if (eventId.isNotEmpty && _decryptedEventCache.containsKey(eventId)) {
      return _decryptedEventCache[eventId];
    }
    final result = _unwrapGiftWrap(eventData, privateKey);
    if (eventId.isNotEmpty) {
      _decryptedEventCache[eventId] = result;
    }
    return result;
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

    final cachedDMs = await _getDMEvents(_currentUserPubkeyHex!, limit: 500);

    for (final eventData in cachedDMs) {
      try {
        final message = _unwrapGiftWrapCached(eventData, privateKey);
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
            'limit': 200
          },
        ],
      );

      final Set<String> processedEventIds = {};

      for (final eventData in relayEvents) {
        final eventId = eventData['id'] as String? ?? '';
        if (processedEventIds.contains(eventId)) continue;
        processedEventIds.add(eventId);

        final message = _unwrapGiftWrapCached(eventData, privateKey);
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

        _saveEvent(eventData);
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
    if (msgs.length > 500) {
      _messagesCache[key] = msgs.sublist(msgs.length - 500);
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
      final privateKey = await _getPrivateKey();
      if (privateKey == null) return;

      final relayEvents = await _queryDmRelays(
        filters: [
          {
            'kinds': [1059],
            '#p': [_currentUserPubkeyHex!],
            'limit': 200
          },
        ],
      );

      if (relayEvents.isEmpty) return;

      final Map<String, Map<String, dynamic>> conversationsMap = {};

      if (_cachedConversations != null) {
        for (final conv in _cachedConversations!) {
          final key = conv['otherUserPubkeyHex'] as String? ?? '';
          if (key.isNotEmpty) conversationsMap[key] = Map.from(conv);
        }
      }

      bool hasNewData = false;

      for (final eventData in relayEvents) {
        final message = _unwrapGiftWrapCached(eventData, privateKey);
        if (message == null) continue;

        final otherUserPubkeyHex = message['isFromCurrentUser'] == true
            ? message['recipientPubkeyHex'] as String
            : message['senderPubkeyHex'] as String;

        if (otherUserPubkeyHex.isEmpty) continue;

        final messageTime = message['createdAt'] as DateTime?;

        if (!conversationsMap.containsKey(otherUserPubkeyHex)) {
          conversationsMap[otherUserPubkeyHex] = <String, dynamic>{
            'otherUserPubkeyHex': otherUserPubkeyHex,
            'lastMessage': message,
            'lastMessageTime': messageTime,
          };
          hasNewData = true;
        } else {
          final existing = conversationsMap[otherUserPubkeyHex]!;
          final existingLastTime = existing['lastMessageTime'] as DateTime?;
          if (existingLastTime == null ||
              (messageTime != null && messageTime.isAfter(existingLastTime))) {
            conversationsMap[otherUserPubkeyHex] = <String, dynamic>{
              ...existing,
              'lastMessage': message,
              'lastMessageTime': messageTime,
            };
            hasNewData = true;
          }
        }

        _saveEvent(eventData);
      }

      if (hasNewData) {
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
      }
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _loadMessagesFromDb(
      String otherUserPubkeyHex, String privateKey) async {
    try {
      final cachedDMs = await _getDMEvents(_currentUserPubkeyHex!, limit: 1000);
      final messages = <Map<String, dynamic>>[];

      for (var i = 0; i < cachedDMs.length; i++) {
        if (i > 0 && i % 5 == 0) {
          await Future.delayed(Duration.zero);
        }

        final message = _unwrapGiftWrapCached(cachedDMs[i], privateKey);
        if (message == null) continue;

        final msgOther = message['isFromCurrentUser'] == true
            ? message['recipientPubkeyHex'] as String
            : message['senderPubkeyHex'] as String;
        if (msgOther != otherUserPubkeyHex) continue;

        messages.add(message);
      }

      return messages;
    } catch (_) {
      return [];
    }
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

    final dbMessages =
        await _loadMessagesFromDb(otherUserPubkeyHex, privateKey);
    if (dbMessages.isNotEmpty) {
      final merged = _mergeAndCapMessages(otherUserPubkeyHex, dbMessages);
      _fetchMessagesInBackground(otherUserPubkeyHex);
      return Result.success(merged);
    }

    try {
      final relayEvents = await _queryDmRelays(
        filters: [
          {
            'kinds': [1059],
            '#p': [_currentUserPubkeyHex!],
            'limit': 200
          },
        ],
        timeout: const Duration(seconds: 8),
      );

      final Map<String, Map<String, dynamic>> messagesMap = {};

      for (final eventData in relayEvents) {
        final eventId = eventData['id'] as String? ?? '';
        if (messagesMap.containsKey(eventId)) continue;

        final message = _unwrapGiftWrapCached(eventData, privateKey);
        if (message == null) continue;

        final msgOther = message['isFromCurrentUser'] == true
            ? message['recipientPubkeyHex'] as String
            : message['senderPubkeyHex'] as String;
        if (msgOther != otherUserPubkeyHex) continue;

        messagesMap[message['id'] as String? ?? eventId] = message;
        _saveEvent(eventData);
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
            'limit': 200
          },
        ],
        timeout: const Duration(seconds: 5),
      );

      final Map<String, Map<String, dynamic>> messagesMap = {};

      for (final eventData in relayEvents) {
        final eventId = eventData['id'] as String? ?? '';
        if (messagesMap.containsKey(eventId)) continue;

        final message = _unwrapGiftWrapCached(eventData, privateKey);
        if (message == null) continue;

        final msgOther = message['isFromCurrentUser'] == true
            ? message['recipientPubkeyHex'] as String
            : message['senderPubkeyHex'] as String;
        if (msgOther != otherUserPubkeyHex) continue;

        messagesMap[message['id'] as String? ?? eventId] = message;
        _saveEvent(eventData);
      }

      if (messagesMap.isNotEmpty) {
        _mergeAndCapMessages(otherUserPubkeyHex, messagesMap.values,
            notify: true);
      }
    } catch (_) {}
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
        merged.length > 500 ? merged.sublist(merged.length - 500) : merged;

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

      await RustRelayService.instance.broadcastEvent(recipientWrap);
      await RustRelayService.instance.broadcastEvent(senderWrap);

      final optimisticMessage = <String, dynamic>{
        'id': recipientWrap['id'] as String? ?? '',
        'senderPubkeyHex': _currentUserPubkeyHex!,
        'recipientPubkeyHex': recipientPubkeyHex,
        'content': content,
        'createdAt': DateTime.now(),
        'isFromCurrentUser': true,
        'kind': 14,
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

  Future<Result<void>> sendEncryptedMediaMessage({
    required String recipientPubkeyHex,
    required String encryptedFileUrl,
    required String mimeType,
    required String encryptionKey,
    required String encryptionNonce,
    required String encryptedHash,
    required String originalHash,
    required int fileSize,
  }) async {
    final initResult = await _ensureInitialized();
    if (initResult.isError) {
      return Result.error(initResult.error!);
    }

    final privateKey = await _getPrivateKey();
    if (privateKey == null) {
      return Result.error('Not authenticated');
    }

    try {
      final recipientWrapJson = rust_nip17.createGiftWrapFileMessage(
        senderPrivateKeyHex: privateKey,
        receiverPubkeyHex: recipientPubkeyHex,
        fileUrl: encryptedFileUrl,
        mimeType: mimeType,
        encryptionKeyHex: encryptionKey,
        encryptionNonceHex: encryptionNonce,
        encryptedHash: encryptedHash,
        originalHash: originalHash,
        fileSize: BigInt.from(fileSize),
      );

      final senderWrapJson = rust_nip17.createGiftWrapFileMessageForSender(
        senderPrivateKeyHex: privateKey,
        receiverPubkeyHex: recipientPubkeyHex,
        fileUrl: encryptedFileUrl,
        mimeType: mimeType,
        encryptionKeyHex: encryptionKey,
        encryptionNonceHex: encryptionNonce,
        encryptedHash: encryptedHash,
        originalHash: originalHash,
        fileSize: BigInt.from(fileSize),
      );

      final recipientWrap =
          jsonDecode(recipientWrapJson) as Map<String, dynamic>;
      final senderWrap = jsonDecode(senderWrapJson) as Map<String, dynamic>;

      await RustRelayService.instance.broadcastEvent(recipientWrap);
      await RustRelayService.instance.broadcastEvent(senderWrap);

      final optimisticMessage = <String, dynamic>{
        'id': recipientWrap['id'] as String? ?? '',
        'senderPubkeyHex': _currentUserPubkeyHex!,
        'recipientPubkeyHex': recipientPubkeyHex,
        'content': encryptedFileUrl,
        'createdAt': DateTime.now(),
        'isFromCurrentUser': true,
        'kind': 15,
        'mimeType': mimeType,
        'encryptionKey': encryptionKey,
        'encryptionNonce': encryptionNonce,
        'encryptedHash': encryptedHash,
        'originalHash': originalHash,
        'fileSize': fileSize,
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
      return Result.error('Failed to send encrypted media: $e');
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

    startRealtimeSubscription();
    _startChatPolling(otherUserPubkeyHex);

    return Stream.multi((sink) {
      if (cachedMessages.isNotEmpty) {
        sink.add(List.from(cachedMessages));
        _fetchMessagesInBackground(otherUserPubkeyHex);
      } else {
        _loadDbThenFetchRelay(otherUserPubkeyHex, sink);
      }

      final subscription = controller.stream.listen(
        (messages) => sink.add(messages),
        onError: (error) => sink.addError(error),
        onDone: () => sink.close(),
      );

      sink.onCancel = () {
        subscription.cancel();
        _stopChatPolling();
      };
    });
  }

  void _startChatPolling(String otherUserPubkeyHex) {
    _stopChatPolling();
    _activeChatPubkeyHex = otherUserPubkeyHex;
    _chatPollTimer =
        Timer.periodic(const Duration(seconds: 8), (_) {
      if (_activeChatPubkeyHex != null) {
        _fetchMessagesInBackground(_activeChatPubkeyHex!);
      }
    });
  }

  void _stopChatPolling() {
    _chatPollTimer?.cancel();
    _chatPollTimer = null;
    _activeChatPubkeyHex = null;
  }

  Future<void> _loadDbThenFetchRelay(
      String otherUserPubkeyHex, Sink<List<Map<String, dynamic>>> sink) async {
    try {
      final privateKey = await _getPrivateKey();
      if (privateKey != null) {
        final dbMessages =
            await _loadMessagesFromDb(otherUserPubkeyHex, privateKey);
        if (dbMessages.isNotEmpty) {
          final merged = _mergeAndCapMessages(otherUserPubkeyHex, dbMessages);
          sink.add(merged);
        }
      }
    } catch (_) {}
    _fetchMessagesInBackground(otherUserPubkeyHex);
  }

  Future<void> startRealtimeSubscription() async {
    if (_realtimeSubscription != null) return;

    final initResult = await _ensureInitialized();
    if (initResult.isError || _currentUserPubkeyHex == null) return;

    _cachedPrivateKey = await _getPrivateKey();
    if (_cachedPrivateKey == null) return;

    _connectRealtimeSubscription();
  }

  void _connectRealtimeSubscription() {
    if (_cachedPrivateKey == null || _currentUserPubkeyHex == null) return;

    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;

    try {
      final since =
          DateTime.now().millisecondsSinceEpoch ~/ 1000 - 259200;
      final filter = {
        'kinds': [1059],
        '#p': [_currentUserPubkeyHex!],
        'since': since,
      };

      final stream = RustRelayService.instance.subscribeToEvents(filter);

      _realtimeSubscription = stream.listen(
        (eventData) {
          _handleRealtimeEvent(eventData, _cachedPrivateKey!);
        },
        onError: (_) {
          _realtimeSubscription = null;
          _scheduleReconnect();
        },
        onDone: () {
          _realtimeSubscription = null;
          _scheduleReconnect();
        },
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      _connectRealtimeSubscription();
    });
  }

  void _handleRealtimeEvent(
      Map<String, dynamic> eventData, String privateKey) {
    try {
      final message = _unwrapGiftWrapCached(eventData, privateKey);
      if (message == null) return;

      final otherUserPubkeyHex = message['isFromCurrentUser'] == true
          ? message['recipientPubkeyHex'] as String
          : message['senderPubkeyHex'] as String;

      if (otherUserPubkeyHex.isEmpty) return;

      if (!_messagesCache.containsKey(otherUserPubkeyHex)) {
        _messagesCache[otherUserPubkeyHex] = [];
      }

      final existingMessages = _messagesCache[otherUserPubkeyHex]!;
      final msgId = message['id'] as String? ?? '';
      if (msgId.isNotEmpty &&
          !existingMessages.any((m) => (m['id'] as String? ?? '') == msgId)) {
        existingMessages.add(message);
        _sortAndCapMessages(otherUserPubkeyHex);
        _notifyMessageStream(otherUserPubkeyHex);
      }

      _updateConversationCache(otherUserPubkeyHex, message);
      _notifyConversationsStream();
      _saveEvent(eventData);
    } catch (_) {}
  }

  void _notifyConversationsStream() {
    if (_cachedConversations != null &&
        !_conversationsStreamController.isClosed) {
      _conversationsStreamController.add(List.from(_cachedConversations!));
    }
  }

  Future<List<Map<String, dynamic>>> _getDMEvents(String userPubkey,
      {int? limit}) async {
    try {
      if (userPubkey.isEmpty) return [];
      final filterJson = jsonEncode({
        'kinds': [1059],
        '#p': [userPubkey],
        'limit': limit ?? 100,
      });
      final json =
          await rust_db.dbQueryEvents(filterJson: filterJson, limit: limit ?? 100);
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  void _saveEvent(Map<String, dynamic> eventData) {
    // SDK auto-saves events during fetch/subscribe — explicit save is not needed.
  }

  void dispose() {
    _stopChatPolling();
    _reconnectTimer?.cancel();
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    _conversationsStreamController.close();
    for (final controller in _messageStreams.values) {
      controller.close();
    }
    _messageStreams.clear();
    _messagesCache.clear();
    _decryptedEventCache.clear();
    _cachedConversations = null;
  }
}
