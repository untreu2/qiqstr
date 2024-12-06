import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:nostr/nostr.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import 'package:uuid/uuid.dart';

enum DataType { Feed, Profile }

enum MessageType { NewNotes, CacheLoad, Error }

class IsolateMessage {
  final MessageType type;
  final dynamic data;

  IsolateMessage(this.type, this.data);
}

class DataService {
  final String npub;
  final DataType dataType;
  final Function(NoteModel)? onNewNote;
  final Function(String, List<ReactionModel>)? onReactionsUpdated;
  final Function(String, List<ReplyModel>)? onRepliesUpdated;

  final List<NoteModel> notes = [];
  final Set<String> eventIds = {};
  final Map<String, List<ReactionModel>> reactionsMap = {};
  final Map<String, List<ReplyModel>> repliesMap = {};
  final Map<String, Map<String, String>> profileCache = {};
  final Map<String, WebSocket> _webSockets = {};
  bool isConnecting = false;
  Timer? _checkNewNotesTimer;
  int currentLimit = 75;
  int currentOffset = 0;

  final List<String> relayUrls = [
    'wss://relay.damus.io',
    'wss://relay.snort.social',
    'wss://nos.lol',
    'wss://untreu.me',
    'wss://vitor.nostr1.com',
    'wss://nostr.mom'
  ];

  final Map<String, Completer<Map<String, String>>> _pendingProfileRequests = {};
  final Map<String, String> _profileSubscriptionIds = {};

  late Box notesBox;
  late Box reactionsBox;
  late Box repliesBox;

  bool _isInitialized = false;
  bool _isClosed = false;

  late ReceivePort _receivePort;
  late Isolate _isolate;
  late SendPort _sendPort;

  Function(List<NoteModel>)? _onCacheLoad;

  final Completer<void> _sendPortReadyCompleter = Completer<void>();

  final Map<String, DateTime> profileCacheTimestamps = {};

  static const Map<String, String> defaultProfile = {
    'name': 'Anonymous',
    'profileImage': '',
    'about': '',
    'nip05': '',
    'banner': '',
  };

  DataService({
    required this.npub,
    required this.dataType,
    this.onNewNote,
    this.onReactionsUpdated,
    this.onRepliesUpdated,
  });

  Future<void> initialize() async {
    notesBox = await Hive.openBox('notes_${dataType.toString()}_$npub');
    reactionsBox = await Hive.openBox('reactions_${dataType.toString()}_$npub');
    repliesBox = await Hive.openBox('replies_${dataType.toString()}_$npub');
    _isInitialized = true;

    await _initializeIsolate();
    await _loadCaches();
  }

  Future<void> _initializeIsolate() async {
    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_dataProcessor, _receivePort.sendPort);

    _receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        if (!_sendPortReadyCompleter.isCompleted) {
          _sendPortReadyCompleter.complete();
        }
      } else if (message is IsolateMessage) {
        _handleIsolateMessage(message);
      }
    });
  }

  static void _dataProcessor(SendPort sendPort) {
    final ReceivePort isolateReceivePort = ReceivePort();
    sendPort.send(isolateReceivePort.sendPort);

    isolateReceivePort.listen((message) {
      if (message is IsolateMessage) {
        switch (message.type) {
          case MessageType.CacheLoad:
          case MessageType.NewNotes:
            _processJsonMessage(sendPort, message);
            break;
          case MessageType.Error:
            break;
        }
      } else if (message is String && message == 'close') {
        isolateReceivePort.close();
      }
    });
  }

  static void _processJsonMessage(SendPort sendPort, IsolateMessage message) {
    try {
      final List<dynamic> jsonData = json.decode(message.data);
      final List<NoteModel> parsedNotes =
          jsonData.map((json) => NoteModel.fromJson(json)).toList();
      sendPort.send(IsolateMessage(message.type, parsedNotes));
    } catch (e) {
      sendPort.send(IsolateMessage(MessageType.Error, e.toString()));
    }
  }

  void _handleIsolateMessage(IsolateMessage message) {
    switch (message.type) {
      case MessageType.NewNotes:
        if (message.data is List<NoteModel>) {
          List<NoteModel> newNotes = message.data;
          _addNewNotes(newNotes);
        }
        break;
      case MessageType.CacheLoad:
        if (message.data is List<NoteModel>) {
          List<NoteModel> cachedNotes = message.data;
          _onCacheLoad?.call(cachedNotes);
          _onCacheLoad = null;
        }
        break;
      case MessageType.Error:
        break;
    }
  }

  static String generate64RandomHexChars() {
    return Uuid().v4().replaceAll('-', '');
  }

  Future<void> _loadCaches() async {
    await loadNotesFromCache((loadedNotes) {
      notes.addAll(loadedNotes);
      notes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    });
    await loadReactionsFromCache();
    await loadRepliesFromCache();
  }

  Future<void> initializeConnections() async {
    if (!_isInitialized) {
      await initialize();
    }

    List<String> targetNpubs = dataType == DataType.Feed
        ? await getFollowingList(npub)
        : [npub];

    if (_isClosed) return;

    await connectToRelays(relayUrls, targetNpubs);
    await fetchNotes(targetNpubs, initialLoad: true);
  }

  Future<void> connectToRelays(List<String> relayList, List<String> targetNpubs) async {
    if (isConnecting || _isClosed) return;
    isConnecting = true;

    await Future.wait(relayList.map((relayUrl) async {
      if (_isClosed) return;
      if (!_webSockets.containsKey(relayUrl) || _webSockets[relayUrl]?.readyState == WebSocket.closed) {
        try {
          final webSocket = await WebSocket.connect(relayUrl).timeout(Duration(seconds: 2));
          if (_isClosed) {
            webSocket.close();
            return;
          }
          _webSockets[relayUrl] = webSocket;
          webSocket.listen(
            (event) => _handleEvent(event, targetNpubs),
            onDone: () {
              _webSockets.remove(relayUrl);
            },
            onError: (error) {
              _webSockets.remove(relayUrl);
            },
          );
          await _fetchProfiles(webSocket, targetNpubs);
          await _fetchReplies(webSocket, targetNpubs);
        } catch (e) {
          _webSockets.remove(relayUrl);
        }
      }
    }));

    isConnecting = false;

    if (_webSockets.isNotEmpty) {
      _startCheckingForNewData(targetNpubs);
    }
  }

  Future<void> fetchNotes(List<String> targetNpubs, {bool initialLoad = false}) async {
    if (_isClosed) return;
    for (var webSocket in _webSockets.values) {
      final request = Request(generate64RandomHexChars(), [
        Filter(
          authors: targetNpubs,
          kinds: [1, 6],
          limit: currentLimit,
          since: currentOffset,
        ),
      ]);
      webSocket.add(request.serialize());
    }
    if (initialLoad) {
      currentOffset += currentLimit;
    }
  }

  Future<void> saveNotesToCache() async {
    if (notesBox.isOpen) {
      try {
        final notesJson = {for (var note in notes) note.id: note.toJson()};
        await notesBox.putAll(notesJson);
      } catch (e) {
      }
    }
  }

  Future<void> loadNotesFromCache(Function(List<NoteModel>) onLoad) async {
    if (!notesBox.isOpen) return;
    try {
      final allNotes = notesBox.values
          .map((json) => NoteModel.fromJson(Map<String, dynamic>.from(json)))
          .toList();
      _onCacheLoad = onLoad;
      await _sendPortReadyCompleter.future;
      _sendPort.send(IsolateMessage(MessageType.CacheLoad, json.encode(allNotes.map((note) => note.toJson()).toList())));
    } catch (e) {
    }
  }

  Future<void> saveReactionsToCache() async {
    if (reactionsBox.isOpen) {
      try {
        Map<String, dynamic> reactionsJson = reactionsMap.map((key, value) {
          return MapEntry(key, value.map((reaction) => reaction.toJson()).toList());
        });
        await reactionsBox.put('reactions', reactionsJson);
      } catch (e) {
      }
    }
  }

  Future<void> loadReactionsFromCache() async {
    if (!reactionsBox.isOpen) return;
    try {
      Map<dynamic, dynamic> cachedReactionsJson = reactionsBox.get('reactions', defaultValue: {});
      cachedReactionsJson.forEach((key, value) {
        String noteId = key as String;
        List<dynamic> reactionsList = value as List<dynamic>;
        reactionsMap[noteId] = reactionsList
            .map((reactionJson) => ReactionModel.fromJson(Map<String, dynamic>.from(reactionJson as Map)))
            .toList();
      });
    } catch (e) {
    }
  }

  Future<void> saveRepliesToCache() async {
    if (repliesBox.isOpen) {
      try {
        Map<String, dynamic> repliesJson = repliesMap.map((key, value) {
          return MapEntry(key, value.map((reply) => reply.toJson()).toList());
        });
        await repliesBox.put('replies', repliesJson);
      } catch (e) {
      }
    }
  }

  Future<void> loadRepliesFromCache() async {
    if (!repliesBox.isOpen) return;
    try {
      Map<dynamic, dynamic> cachedRepliesJson = repliesBox.get('replies', defaultValue: {});
      cachedRepliesJson.forEach((key, value) {
        String noteId = key as String;
        List<dynamic> repliesList = value as List<dynamic>;
        repliesMap[noteId] = repliesList
            .map((replyJson) => ReplyModel.fromJson(Map<String, dynamic>.from(replyJson as Map)))
            .toList();
      });
    } catch (e) {
    }
  }

  Future<void> fetchReactionsForNotes(List<String> noteIds) async {
    if (_isClosed) return;
    for (var webSocket in _webSockets.values) {
      final request = Request(generate64RandomHexChars(), [
        Filter(
          kinds: [7],
          e: noteIds,
        ),
      ]);
      webSocket.add(request.serialize());
    }
  }

  Future<void> fetchRepliesForNotes(List<String> parentIds) async {
    if (_isClosed) return;
    for (var webSocket in _webSockets.values) {
      final request = Request(generate64RandomHexChars(), [
        Filter(
          kinds: [1],
          e: parentIds,
        ),
      ]);
      webSocket.add(request.serialize());
    }
  }

  Future<void> _handleEvent(dynamic event, List<String> targetNpubs) async {
    if (_isClosed) return;
    try {
      final decodedEvent = jsonDecode(event);
      if (decodedEvent[0] == 'EVENT') {
        await _processNostrEvent(decodedEvent, targetNpubs);
      } else if (decodedEvent[0] == 'EOSE') {
        await _handleEndOfStoredEvents(decodedEvent);
      }
    } catch (e) {
    }
  }

  Future<void> _processNostrEvent(List<dynamic> decodedEvent, List<String> targetNpubs) async {
    Map<String, dynamic> eventData = decodedEvent[2] as Map<String, dynamic>;
    final kind = eventData['kind'] as int;
    switch (kind) {
      case 1:
      case 6:
        await _handleNoteOrRepostEvent(eventData, targetNpubs);
        break;
      case 7:
        await _handleReactionEvent(eventData);
        break;
      case 0:
        await _handleProfileEvent(eventData);
        break;
      default:
        break;
    }
  }

  Future<void> _handleNoteOrRepostEvent(Map<String, dynamic> eventData, List<String> targetNpubs) async {
    final kind = eventData['kind'] as int;
    final isRepost = kind == 6;
    String? repostedByPubkey;
    Map<String, dynamic>? originalEventData;
    String? originalAuthorPubkey;

    if (isRepost) {
      repostedByPubkey = eventData['pubkey'] as String?;
      final contentRaw = eventData['content'];
      if (contentRaw is String && contentRaw.isNotEmpty) {
        try {
          originalEventData = jsonDecode(contentRaw) as Map<String, dynamic>;
        } catch (e) {
        }
      }

      if (originalEventData == null) {
        String? originalEventId;
        for (var tag in eventData['tags']) {
          if (tag.length >= 2 && tag[0] == 'e') {
            originalEventId = tag[1] as String;
            break;
          }
        }
        if (originalEventId != null) {
          originalEventData = await _fetchEventById(originalEventId);
        }
      }

      if (originalEventData == null) {
        return;
      }

      originalAuthorPubkey = originalEventData['pubkey'] as String;
    } else {
      originalAuthorPubkey = eventData['pubkey'] as String;
    }

    final noteId = eventData['id'] as String;
    final noteAuthor = originalAuthorPubkey;
    final noteContentRaw = originalEventData != null ? originalEventData['content'] : eventData['content'];
    String noteContent = '';

    if (noteContentRaw is String) {
      noteContent = noteContentRaw;
    } else if (noteContentRaw is Map<String, dynamic>) {
      noteContent = jsonEncode(noteContentRaw);
    }

    final tags = originalEventData != null ? originalEventData['tags'] as List<dynamic> : eventData['tags'] as List<dynamic>;
    final isReply = tags.any((tag) => tag.length >= 2 && tag[0] == 'e');

    if (eventIds.contains(noteId) || noteContent.trim().isEmpty) {
      return;
    }

    if (!isReply) {
      if (dataType == DataType.Feed &&
          targetNpubs.isNotEmpty &&
          !targetNpubs.contains(noteAuthor) &&
          !(isRepost && repostedByPubkey != null && targetNpubs.contains(repostedByPubkey))) {
        return;
      }
    }

    if (isRepost) {
      if (repostedByPubkey == null) {
        return;
      }
      final authorProfile = await getCachedUserProfile(noteAuthor);
      final repostedByProfile = await getCachedUserProfile(repostedByPubkey);
      final newEvent = NoteModel(
        id: noteId,
        content: noteContent,
        author: noteAuthor,
        authorName: authorProfile['name'] ?? 'Anonymous',
        authorProfileImage: authorProfile['profileImage'] ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(((eventData['created_at'] as int)) * 1000),
        isRepost: isRepost,
        repostedBy: repostedByPubkey,
        repostedByName: repostedByProfile['name'] ?? 'Anonymous',
        repostedByProfileImage: repostedByProfile['profileImage'] ?? '',
      );
      _addNewNote(newEvent);
    } else {
      final authorProfile = await getCachedUserProfile(noteAuthor);
      final newEvent = NoteModel(
        id: noteId,
        content: noteContent,
        author: noteAuthor,
        authorName: authorProfile['name'] ?? 'Anonymous',
        authorProfileImage: authorProfile['profileImage'] ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(((eventData['created_at'] as int)) * 1000),
        isRepost: isRepost,
      );
      _addNewNote(newEvent);
    }
  }

  void _addNewNotes(List<NoteModel> newNotes) {
    for (var note in newNotes) {
      if (!eventIds.contains(note.id) && note.content.trim().isNotEmpty) {
        _addNewNote(note);
      }
    }
    saveNotesToCache();
  }

  void _addNewNote(NoteModel newNote) {
    int index = notes.indexWhere((note) => note.timestamp.isBefore(newNote.timestamp));
    if (index == -1) {
      notes.add(newNote);
    } else {
      notes.insert(index, newNote);
    }
    eventIds.add(newNote.id);
    onNewNote?.call(newNote);
  }

  Future<void> _handleReactionEvent(Map<String, dynamic> eventData) async {
    if (_isClosed) return;
    try {
      final reactionPubKey = eventData['pubkey'] as String;
      final reactionProfile = await getCachedUserProfile(reactionPubKey);
      String? noteId;
      for (var tag in eventData['tags']) {
        if (tag.length >= 2 && tag[0] == 'e') {
          noteId = tag[1] as String;
          break;
        }
      }
      if (noteId == null) return;
      final reaction = ReactionModel.fromEvent(eventData, reactionProfile);
      reactionsMap.putIfAbsent(noteId, () => []);
      if (!reactionsMap[noteId]!.any((r) => r.id == reaction.id)) {
        reactionsMap[noteId]!.add(reaction);
        await saveReactionsToCache();
        onReactionsUpdated?.call(noteId, reactionsMap[noteId]!);
        if (repliesMap.containsKey(noteId)) {
          fetchReactionsForNotes([noteId]);
        }
      }
    } catch (e) {
    }
  }

  Future<void> _handleReplyEvent(Map<String, dynamic> eventData) async {
    if (_isClosed) return;
    try {
      final replyPubKey = eventData['pubkey'] as String;
      final replyProfile = await getCachedUserProfile(replyPubKey);
      String? parentId;
      List<String> eTags = [];
      for (var tag in eventData['tags']) {
        if (tag.length >= 2 && tag[0] == 'e') {
          eTags.add(tag[1]);
        }
      }
      if (eTags.isNotEmpty) {
        parentId = eTags.last;
      }
      if (parentId == null || parentId.isEmpty) return;
      final reply = ReplyModel.fromEvent(eventData, replyProfile);
      repliesMap.putIfAbsent(parentId, () => []);
      if (!repliesMap[parentId]!.any((r) => r.id == reply.id)) {
        repliesMap[parentId]!.add(reply);
        await saveRepliesToCache();
        onRepliesUpdated?.call(parentId, repliesMap[parentId]!);
        fetchRepliesForNotes([reply.id]);
        fetchReactionsForNotes([reply.id]);
      }
    } catch (e) {
    }
  }

  Future<void> _handleProfileEvent(Map<String, dynamic> eventData) async {
    if (_isClosed) return;
    try {
      final author = eventData['pubkey'] as String;
      final contentRaw = eventData['content'];
      Map<String, dynamic> profileContent;
      if (contentRaw is String) {
        try {
          profileContent = jsonDecode(contentRaw) as Map<String, dynamic>;
        } catch (e) {
          profileContent = {};
        }
      } else {
        profileContent = {};
      }

      final userName = profileContent['name'] as String? ?? 'Anonymous';
      final profileImage = profileContent['picture'] as String? ?? '';
      final about = profileContent['about'] as String? ?? '';
      final nip05 = profileContent['nip05'] as String? ?? '';
      final banner = profileContent['banner'] as String? ?? '';
      profileCache[author] = {
        'name': userName,
        'profileImage': profileImage,
        'about': about,
        'nip05': nip05,
        'banner': banner,
      };
      profileCacheTimestamps[author] = DateTime.now();

      if (_pendingProfileRequests.containsKey(author)) {
        _pendingProfileRequests[author]!.complete(profileCache[author]!);
        _pendingProfileRequests.remove(author);
      }
    } catch (e) {
    }
  }

  Future<Map<String, String>> getCachedUserProfile(String npub) async {
    if (_isClosed) return defaultProfile;

    if (profileCache.containsKey(npub)) {
      if (profileCacheTimestamps.containsKey(npub)) {
        final elapsed = DateTime.now().difference(profileCacheTimestamps[npub]!);
        if (elapsed < Duration(hours: 1)) {
          return profileCache[npub]!;
        } else {
          profileCache.remove(npub);
          profileCacheTimestamps.remove(npub);
        }
      } else {
        profileCache.remove(npub);
      }
    }

    if (_pendingProfileRequests.containsKey(npub)) {
      return await _pendingProfileRequests[npub]!.future;
    }

    Completer<Map<String, String>> completer = Completer<Map<String, String>>();
    _pendingProfileRequests[npub] = completer;
    String subscriptionId = generate64RandomHexChars();
    _profileSubscriptionIds[subscriptionId] = npub;

    final request = Request(subscriptionId, [
      Filter(authors: [npub], kinds: [0], limit: 1),
    ]);

    for (var webSocket in _webSockets.values) {
      webSocket.add(request.serialize());
    }

    Future.delayed(Duration(seconds: 2), () {
      if (!completer.isCompleted) {
        profileCache[npub] = defaultProfile;
        profileCacheTimestamps[npub] = DateTime.now();
        completer.complete(profileCache[npub]!);
        _pendingProfileRequests.remove(npub);
        _profileSubscriptionIds.remove(subscriptionId);
      }
    });

    return completer.future;
  }

  Future<List<String>> getFollowingList(String npub) async {
    List<String> followingNpubs = [];
    await Future.wait(relayUrls.map((relayUrl) async {
      try {
        final webSocket = await WebSocket.connect(relayUrl).timeout(Duration(seconds: 2));
        if (_isClosed) {
          webSocket.close();
          return;
        }
        final request = Request(generate64RandomHexChars(), [
          Filter(authors: [npub], kinds: [3], limit: 1),
        ]);
        Completer<void> completer = Completer<void>();
        webSocket.listen((event) {
          final decodedEvent = jsonDecode(event);
          if (decodedEvent[0] == 'EVENT') {
            for (var tag in decodedEvent[2]['tags']) {
              if (tag.isNotEmpty && tag[0] == 'p') {
                followingNpubs.add(tag[1] as String);
              }
            }
            completer.complete();
          }
        }, onDone: () {
          if (!completer.isCompleted) completer.complete();
        }, onError: (error) {
          if (!completer.isCompleted) completer.complete();
        });
        webSocket.add(request.serialize());
        await completer.future.timeout(Duration(seconds: 2), onTimeout: () {
          webSocket.close();
        });
        await webSocket.close();
      } catch (e) {
      }
    }));

    followingNpubs = followingNpubs.toSet().toList();
    return followingNpubs;
  }

  Future<void> fetchOlderNotes(List<String> targetNpubs, Function(NoteModel) onOlderNote) async {
    if (_isClosed || notes.isEmpty) return;
    for (var webSocket in _webSockets.values) {
      final request = Request(generate64RandomHexChars(), [
        Filter(
          authors: targetNpubs,
          kinds: [1, 6],
          limit: currentLimit,
          until: notes.last.timestamp.millisecondsSinceEpoch ~/ 1000,
        ),
      ]);
      webSocket.add(request.serialize());
    }
  }

  void _startCheckingForNewData(List<String> targetNpubs) {
    _checkNewNotesTimer?.cancel();
    _checkNewNotesTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (_isClosed) {
        timer.cancel();
        return;
      }
      for (var webSocket in _webSockets.values) {
        fetchNotes(targetNpubs);
        _fetchProfiles(webSocket, targetNpubs);
      }
    });
  }

  Future<void> closeConnections() async {
    if (_isClosed) return;
    _isClosed = true;
    _checkNewNotesTimer?.cancel();

    try {
      await _sendPortReadyCompleter.future;
      _sendPort.send(IsolateMessage(MessageType.Error, 'close'));
    } catch (e) {
    }

    _isolate.kill(priority: Isolate.immediate);
    _receivePort.close();

    for (var ws in _webSockets.values) {
      ws.close();
    }
    _webSockets.clear();

    try {
      if (notesBox.isOpen) await notesBox.close();
      if (reactionsBox.isOpen) await reactionsBox.close();
      if (repliesBox.isOpen) await repliesBox.close();
    } catch (e) {
    }
  }

  Future<Map<String, dynamic>?> _fetchEventById(String eventId) async {
    if (_isClosed) return null;
    Completer<Map<String, dynamic>?> completer = Completer<Map<String, dynamic>?>();
    String subscriptionId = generate64RandomHexChars();

    final request = Request(subscriptionId, [
      Filter(ids: [eventId], limit: 1),
    ]);

    for (var webSocket in _webSockets.values) {
      StreamSubscription? sub;
      sub = webSocket.listen((event) {
        final decodedEvent = jsonDecode(event);
        if (decodedEvent[0] == 'EVENT' && decodedEvent[1] == subscriptionId) {
          Map<String, dynamic> eventData = decodedEvent[2] as Map<String, dynamic>;
          completer.complete(eventData);
          sub?.cancel();
        } else if (decodedEvent[0] == 'EOSE' && decodedEvent[1] == subscriptionId) {
          if (!completer.isCompleted) {
            completer.complete(null);
          }
          sub?.cancel();
        }
      }, onError: (error) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
        sub?.cancel();
      });

      webSocket.add(request.serialize());
    }

    return completer.future.timeout(Duration(seconds: 2), onTimeout: () {
      return null;
    });
  }

  Future<void> _handleEndOfStoredEvents(List<dynamic> decodedEvent) async {
    final subscriptionId = decodedEvent[1] as String;
    final npub = _profileSubscriptionIds[subscriptionId];
    if (npub != null && _pendingProfileRequests.containsKey(npub)) {
      profileCache[npub] = defaultProfile;
      profileCacheTimestamps[npub] = DateTime.now();
      _pendingProfileRequests[npub]!.complete(profileCache[npub]!);
      _pendingProfileRequests.remove(npub);
      _profileSubscriptionIds.remove(subscriptionId);
    }
  }

  Future<void> _fetchProfiles(WebSocket webSocket, List<String> targetNpubs) async {
    if (_isClosed) return;
    final request = Request(generate64RandomHexChars(), [
      Filter(authors: targetNpubs, kinds: [0]),
    ]);
    webSocket.add(request.serialize());
  }

  Future<void> _fetchReplies(WebSocket webSocket, List<String> targetNpubs) async {
    if (_isClosed) return;
    final parentIds = notes.map((note) => note.id).toList();
    parentIds.addAll(repliesMap.keys);
    final request = Request(generate64RandomHexChars(), [
      Filter(
        kinds: [1],
        e: parentIds,
      ),
    ]);
    webSocket.add(request.serialize());
  }

  Future<void> fetchProfilesInBulk(List<String> npubs) async {
    final missingNpubs = npubs.where((npub) => !profileCache.containsKey(npub)).toList();
    if (missingNpubs.isEmpty) return;

    final request = Request(generate64RandomHexChars(), [
      Filter(authors: missingNpubs, kinds: [0], limit: 1),
    ]);

    for (var webSocket in _webSockets.values) {
      webSocket.add(request.serialize());
    }
  }
}
