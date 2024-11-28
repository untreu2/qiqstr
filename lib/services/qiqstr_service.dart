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
  String npub;
  DataType dataType;
  Function(NoteModel)? onNewNote;
  Function(String, List<ReactionModel>)? onReactionsUpdated;
  Function(String, List<ReplyModel>)? onRepliesUpdated;

  List<NoteModel> notes = [];
  Set<String> eventIds = {};
  Map<String, List<ReactionModel>> reactionsMap = {};
  Map<String, List<ReplyModel>> repliesMap = {};
  Map<String, Map<String, String>> profileCache = {};
  Map<String, WebSocket> _webSockets = {};
  bool isConnecting = false;
  Timer? _checkNewNotesTimer;
  int currentLimit = 75;
  int currentOffset = 0;

  List<String> relayUrls = [];
  Map<String, Completer<Map<String, String>>> _pendingProfileRequests = {};
  Map<String, String> _profileSubscriptionIds = {};

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

  DataService({
    required this.npub,
    required this.dataType,
    this.onNewNote,
    this.onReactionsUpdated,
    this.onRepliesUpdated,
  });

  Future<void> initialize() async {
    try {
      notesBox = await Hive.openBox('notes_${dataType.toString()}_$npub');
      reactionsBox = await Hive.openBox('reactions_${dataType.toString()}_$npub');
      repliesBox = await Hive.openBox('replies_${dataType.toString()}_$npub');
      _isInitialized = true;
      print('Hive boxes opened successfully.');

      await _initializeIsolate();
    } catch (e) {
      print('Error initializing Hive boxes: $e');
      rethrow;
    }
  }

  Future<void> _initializeIsolate() async {
    try {
      _receivePort = ReceivePort();
      _isolate = await Isolate.spawn(_dataProcessor, _receivePort.sendPort);
      print('Isolate spawned successfully.');

      _receivePort.listen((message) {
        if (message is SendPort) {
          _sendPort = message;
          if (!_sendPortReadyCompleter.isCompleted) {
            _sendPortReadyCompleter.complete();
            print('SendPort initialized.');
          }
        } else if (message is IsolateMessage) {
          switch (message.type) {
            case MessageType.NewNotes:
              if (message.data is List<NoteModel>) {
                List<NoteModel> newNotes = message.data;
                notes.addAll(newNotes);
                notes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
                if (newNotes.isNotEmpty) {
                  onNewNote?.call(newNotes.last);
                }
                saveNotesToCache();
              } else {
                print('Invalid data type for NewNotes: ${message.data.runtimeType}');
              }
              break;
            case MessageType.CacheLoad:
              if (message.data is List<NoteModel>) {
                List<NoteModel> cachedNotes = message.data;
                if (_onCacheLoad != null) {
                  _onCacheLoad!(cachedNotes);
                  _onCacheLoad = null;
                }
              } else {
                print('Invalid data type for CacheLoad: ${message.data.runtimeType}');
              }
              break;
            case MessageType.Error:
              print('Isolate Error: ${message.data}');
              break;
          }
        } else {
          print('Unknown message type received: ${message.runtimeType}');
        }
      });
    } catch (e) {
      print('Error initializing isolate: $e');
      rethrow;
    }
  }

  static void _dataProcessor(SendPort sendPort) {
    final ReceivePort isolateReceivePort = ReceivePort();
    sendPort.send(isolateReceivePort.sendPort);
    print('IsolateMessage: SendPort sent to main isolate.');

    isolateReceivePort.listen((message) {
      if (message is IsolateMessage) {
        if (message.type == MessageType.CacheLoad && message.data is String) {
          try {
            final List<dynamic> jsonData = json.decode(message.data);
            final List<NoteModel> parsedNotes =
                jsonData.map((json) => NoteModel.fromJson(json)).toList();
            sendPort.send(IsolateMessage(MessageType.CacheLoad, parsedNotes));
            print('IsolateMessage: CacheLoad completed.');
          } catch (e) {
            sendPort.send(IsolateMessage(MessageType.Error, e.toString()));
            print('IsolateMessage: Error during CacheLoad: $e');
          }
        } else if (message.type == MessageType.NewNotes && message.data is String) {
          try {
            final List<dynamic> jsonData = json.decode(message.data);
            final List<NoteModel> parsedNotes =
                jsonData.map((json) => NoteModel.fromJson(json)).toList();
            sendPort.send(IsolateMessage(MessageType.NewNotes, parsedNotes));
            print('IsolateMessage: NewNotes processed.');
          } catch (e) {
            sendPort.send(IsolateMessage(MessageType.Error, e.toString()));
            print('IsolateMessage: Error during NewNotes: $e');
          }
        } else {
          print('IsolateMessage: Unknown IsolateMessage type or data type: ${message.type}, ${message.data.runtimeType}');
        }
      } else if (message is String && message == 'close') {
        isolateReceivePort.close();
        print('IsolateMessage: Close command received. Isolate closing.');
      } else {
        print('IsolateMessage: Unknown message type: ${message.runtimeType}');
      }
    });
  }

  Future<void> initializeConnections() async {
    if (!_isInitialized) {
      await initialize();
    }

    List<String> popularRelays = [
      'wss://relay.damus.io',
      'wss://relay.snort.social',
      'wss://nos.lol',
      'wss://untreu.me',
      'wss://vitor.nostr1.com',
      'wss://nostr.mom'
    ];
    relayUrls = popularRelays;
    print('Relay URLs set.');

    List<String> targetNpubs = dataType == DataType.Feed
        ? await getFollowingList(npub)
        : [npub];
    print('Target Npubs: $targetNpubs');

    if (_isClosed) return;

    await connectToRelays(relayUrls, targetNpubs);
    await fetchNotes(targetNpubs, initialLoad: true);
  }

  Future<void> connectToRelays(List<String> relayList, List<String> targetNpubs) async {
    if (isConnecting || _isClosed) return;
    isConnecting = true;
    print('Connecting to relays...');

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
              print('WebSocket disconnected: $relayUrl');
            },
            onError: (error) {
              _webSockets.remove(relayUrl);
              print('WebSocket error on $relayUrl: $error');
            },
          );
          await _fetchProfiles(webSocket, targetNpubs);
          await _fetchReplies(webSocket, targetNpubs);
          print('Connected to relay: $relayUrl');
        } catch (e) {
          _webSockets.remove(relayUrl);
          print('Error connecting to relay $relayUrl: $e');
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
    print('Fetching notes...');
    for (var relayUrl in _webSockets.keys) {
      final request = Request(generate64RandomHexChars(), [
        Filter(
          authors: targetNpubs,
          kinds: [1],
          limit: currentLimit,
          since: currentOffset,
        ),
      ]);
      _webSockets[relayUrl]?.add(request.serialize());
      print('Sent fetch notes request to relay: $relayUrl');
    }
    if (initialLoad) {
      currentOffset += currentLimit;
      print('Initial load: increased offset to $currentOffset');
    }
  }

  Future<void> saveNotesToCache() async {
    if (notesBox.isOpen) {
      try {
        String jsonString = json.encode(notes.map((note) => note.toJson()).toList());
        await notesBox.put('notes_json', jsonString);
        print('Notes saved to cache.');
      } catch (e) {
        print('Error saving notes to cache: $e');
      }
    }
  }

  Future<void> loadNotesFromCache(Function(List<NoteModel>) onLoad) async {
    if (!notesBox.isOpen) return;
    var cachedData = notesBox.get('notes_json', defaultValue: '');
    if (cachedData is! String) {
      print('Unexpected type for notes_json: ${cachedData.runtimeType}');
      try {
        String jsonString = json.encode(cachedData);
        _onCacheLoad = onLoad;
        await _sendPortReadyCompleter.future;
        _sendPort.send(IsolateMessage(MessageType.CacheLoad, jsonString));
        print('Converted notes_json to JSON string and sent to isolate.');
      } catch (e) {
        print('Error encoding cachedData to JSON string: $e');
      }
    } else {
      String jsonString = cachedData;
      if (jsonString.isEmpty) return;
      _onCacheLoad = onLoad;

      await _sendPortReadyCompleter.future;

      _sendPort.send(IsolateMessage(MessageType.CacheLoad, jsonString));
      print('Sent CacheLoad message to isolate.');
    }
  }

  Future<void> saveReactionsToCache() async {
    if (reactionsBox.isOpen) {
      try {
        Map<String, dynamic> reactionsJson = reactionsMap.map((key, value) {
          return MapEntry(key, value.map((reaction) => reaction.toJson()).toList());
        });
        await reactionsBox.put('reactions', reactionsJson);
        print('Reactions saved to cache.');
      } catch (e) {
        print('Error saving reactions to cache: $e');
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
      print('Reactions loaded from cache.');
    } catch (e) {
      print('Error loading reactions from cache: $e');
    }
  }

  Future<void> saveRepliesToCache() async {
    if (repliesBox.isOpen) {
      try {
        Map<String, dynamic> repliesJson = repliesMap.map((key, value) {
          return MapEntry(key, value.map((reply) => reply.toJson()).toList());
        });
        await repliesBox.put('replies', repliesJson);
        print('Replies saved to cache.');
      } catch (e) {
        print('Error saving replies to cache: $e');
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
      print('Replies loaded from cache.');
    } catch (e) {
      print('Error loading replies from cache: $e');
    }
  }

  String generate64RandomHexChars() {
    var uuid = Uuid();
    return uuid.v4().replaceAll('-', '');
  }

  Future<void> _fetchProfiles(WebSocket webSocket, List<String> targetNpubs) async {
    if (_isClosed) return;
    List<String> profilesToFetch = targetNpubs.where((npub) => !profileCache.containsKey(npub)).toList();
    if (profilesToFetch.isEmpty) return;
    final request = Request(generate64RandomHexChars(), [
      Filter(authors: profilesToFetch, kinds: [0]),
    ]);
    webSocket.add(request.serialize());
    print('Sent profile fetch request for profiles: $profilesToFetch');
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
    print('Sent replies fetch request.');
  }

  Future<void> fetchReactionsForNotes(List<String> noteIds) async {
    if (_isClosed) return;
    for (var relayUrl in _webSockets.keys) {
      final request = Request(generate64RandomHexChars(), [
        Filter(
          kinds: [7],
          e: noteIds,
        ),
      ]);
      _webSockets[relayUrl]?.add(request.serialize());
      print('Sent reactions fetch request for notes: $noteIds to relay: $relayUrl');
    }
  }

  Future<void> fetchRepliesForNotes(List<String> parentIds) async {
    if (_isClosed) return;
    for (var relayUrl in _webSockets.keys) {
      final request = Request(generate64RandomHexChars(), [
        Filter(
          kinds: [1],
          e: parentIds,
        ),
      ]);
      _webSockets[relayUrl]?.add(request.serialize());
      print('Sent replies fetch request for parents: $parentIds to relay: $relayUrl');
    }
  }

  Future<void> _handleEvent(dynamic event, List<String> targetNpubs) async {
    if (_isClosed) return;
    try {
      final decodedEvent = jsonDecode(event);
      if (decodedEvent[0] == 'EVENT') {
        final eventData = decodedEvent[2] as Map<String, dynamic>;
        final kind = eventData['kind'] as int;
        if (kind == 1) {
          final eventId = eventData['id'] as String;
          final author = eventData['pubkey'] as String;
          final contentRaw = eventData['content'];
          String content;

          if (contentRaw is String) {
            content = contentRaw;
          } else if (contentRaw is Map<String, dynamic>) {
            content = jsonEncode(contentRaw);
          } else {
            content = '';
            print('Unexpected content type for note: ${contentRaw.runtimeType}');
          }

          final tags = eventData['tags'] as List<dynamic>;
          bool isReply = tags.any((tag) => tag.length >= 2 && tag[0] == 'e');
          if (eventIds.contains(eventId) || content.trim().isEmpty) {
            return;
          }
          if (!isReply) {
            if (dataType == DataType.Feed &&
                targetNpubs.isNotEmpty &&
                !targetNpubs.contains(author)) {
              return;
            }
          }
          if (isReply) {
            await _handleReplyEvent(eventData);
          } else {
            final authorProfile = await getCachedUserProfile(author);
            final newEvent = NoteModel(
              id: eventId,
              content: content,
              author: author,
              authorName: authorProfile['name'] ?? 'Anonymous',
              authorProfileImage: authorProfile['profileImage'] ?? '',
              timestamp:
                  DateTime.fromMillisecondsSinceEpoch((eventData['created_at'] as int) * 1000),
            );
            notes.add(newEvent);
            notes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
            eventIds.add(eventId);
            saveNotesToCache();
            if (onNewNote != null) {
              onNewNote!(newEvent);
            }
          }
        } else if (kind == 7) {
          await _handleReactionEvent(eventData);
        } else if (kind == 0) {
          final author = eventData['pubkey'] as String;
          final contentRaw = eventData['content'];
          Map<String, dynamic> profileContent;
          if (contentRaw is String) {
            try {
              profileContent = jsonDecode(contentRaw) as Map<String, dynamic>;
            } catch (e) {
              print('Error decoding profile content JSON: $e');
              profileContent = {};
            }
          } else {
            print('Profile content is not a String: ${contentRaw.runtimeType}');
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
          if (_pendingProfileRequests.containsKey(author)) {
            _pendingProfileRequests[author]!.complete(profileCache[author]!);
            _pendingProfileRequests.remove(author);
            print('Profile data loaded for $author.');
          }
        }
      } else if (decodedEvent[0] == 'EOSE') {
        final subscriptionId = decodedEvent[1] as String;
        final npub = _profileSubscriptionIds[subscriptionId];
        if (npub != null && _pendingProfileRequests.containsKey(npub)) {
          profileCache[npub] = {
            'name': 'Anonymous',
            'profileImage': '',
            'about': '',
            'nip05': '',
            'banner': '',
          };
          _pendingProfileRequests[npub]!.complete(profileCache[npub]!);
          _pendingProfileRequests.remove(npub);
          _profileSubscriptionIds.remove(subscriptionId);
          print('Profile EOSE received for $npub.');
        }
      }
    } catch (e) {
      print('Error handling event: $e');
    }
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
        if (onReactionsUpdated != null && reactionsMap[noteId] != null) {
          onReactionsUpdated!(noteId, reactionsMap[noteId]!);
        }
        if (repliesMap.containsKey(noteId)) {
          fetchReactionsForNotes([noteId]);
        }
      }
    } catch (e) {
      print('Error handling reaction event: $e');
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
        if (onRepliesUpdated != null && repliesMap[parentId] != null) {
          onRepliesUpdated!(parentId, repliesMap[parentId]!);
        }
        fetchRepliesForNotes([reply.id]);
        fetchReactionsForNotes([reply.id]);
      }
    } catch (e) {
      print('Error handling reply event: $e');
    }
  }

  Future<Map<String, String>> getCachedUserProfile(String npub) async {
    if (_isClosed) return {
      'name': 'Anonymous',
      'profileImage': '',
      'about': '',
      'nip05': '',
      'banner': '',
    };
    if (profileCache.containsKey(npub)) {
      return profileCache[npub]!;
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
      print('Sent profile request for $npub to relay.');
    }
    Future.delayed(Duration(seconds: 2), () {
      if (!completer.isCompleted) {
        profileCache[npub] = {
          'name': 'Anonymous',
          'profileImage': '',
          'about': '',
          'nip05': '',
          'banner': '',
        };
        completer.complete(profileCache[npub]!);
        _pendingProfileRequests.remove(npub);
        _profileSubscriptionIds.remove(subscriptionId);
        print('Profile request for $npub timed out.');
      }
    });
    return completer.future;
  }

  Future<List<String>> getFollowingList(String npub) async {
    List<String> followingNpubs = [];
    for (var relayUrl in relayUrls) {
      try {
        final webSocket = await WebSocket.connect(relayUrl).timeout(Duration(seconds: 2));
        if (_isClosed) {
          webSocket.close();
          return [];
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
          print('WebSocket error while fetching following list: $error');
        });
        webSocket.add(request.serialize());
        await completer.future.timeout(Duration(seconds: 2), onTimeout: () {
          webSocket.close();
          print('Profile fetch request timed out for relay $relayUrl.');
        });
        await webSocket.close();
        print('Fetched following list from relay $relayUrl.');
      } catch (e) {
        print('Error fetching following list from $relayUrl: $e');
      }
    }
    followingNpubs = followingNpubs.toSet().toList();
    return followingNpubs;
  }

  Future<void> fetchOlderNotes(List<String> targetNpubs, Function(NoteModel) onOlderNote) async {
    if (_isClosed || notes.isEmpty) return;
    for (var relayUrl in _webSockets.keys) {
      final request = Request(generate64RandomHexChars(), [
        Filter(
          authors: targetNpubs,
          kinds: [1],
          limit: currentLimit,
          until: notes.last.timestamp.millisecondsSinceEpoch ~/ 1000,
        ),
      ]);
      _webSockets[relayUrl]?.add(request.serialize());
      print('Sent fetch older notes request to relay: $relayUrl');
    }
  }

  void _startCheckingForNewData(List<String> targetNpubs) {
    _checkNewNotesTimer?.cancel();
    _checkNewNotesTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      if (_isClosed) {
        timer.cancel();
        return;
      }
      Set<String> allParentIds = Set<String>.from(notes.map((note) => note.id));
      allParentIds.addAll(repliesMap.keys);
      allParentIds.toList();
      for (var relayUrl in _webSockets.keys) {
        final webSocket = _webSockets[relayUrl]!;
        fetchNotes(targetNpubs);
        _fetchProfiles(webSocket, targetNpubs);
      }
      print('Checked for new data at ${DateTime.now()}');
    });
  }

  Future<void> closeConnections() async {
    if (_isClosed) return;
    _isClosed = true;
    _checkNewNotesTimer?.cancel();
    print('Closing connections...');

    try {
      await _sendPortReadyCompleter.future;
      _sendPort.send(IsolateMessage(MessageType.Error, 'close'));
      print('Sent close message to isolate.');
    } catch (e) {
      print('Error sending close message to isolate: $e');
    }

    _isolate.kill(priority: Isolate.immediate);
    _receivePort.close();
    print('Isolate killed and ReceivePort closed.');

    for (var ws in _webSockets.values) {
      ws.close();
      print('WebSocket closed.');
    }
    _webSockets.clear();

    if (notesBox.isOpen) await notesBox.close();
    if (reactionsBox.isOpen) await reactionsBox.close();
    if (repliesBox.isOpen) await repliesBox.close();
    print('Hive boxes closed.');
  }
}
