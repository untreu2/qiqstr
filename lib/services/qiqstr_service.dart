import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:nostr/nostr.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import 'package:uuid/uuid.dart';

enum DataType { Feed, Profile }

class DataService {
  final String npub;
  final DataType dataType;
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
  int currentLimit = 100;

  List<String> relayUrls = [];
  Map<String, Completer<Map<String, String>>> _pendingProfileRequests = {};
  Map<String, String> _profileSubscriptionIds = {};

  late Box notesBox;
  late Box reactionsBox;
  late Box repliesBox;

  bool _isInitialized = false;
  bool _isClosed = false;

  DataService({
    required this.npub,
    required this.dataType,
    this.onNewNote,
    this.onReactionsUpdated,
    this.onRepliesUpdated,
  });

  Future<void> initialize() async {
    notesBox = await Hive.openBox('notes_${dataType.toString()}_${npub}');
    reactionsBox = await Hive.openBox('reactions_${dataType.toString()}_${npub}');
    repliesBox = await Hive.openBox('replies_${dataType.toString()}_${npub}');

    _isInitialized = true;
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
    List<String> targetNpubs = [];

    if (dataType == DataType.Feed) {
      targetNpubs = await getFollowingList(npub);
    } else {
      targetNpubs = [npub];
    }

    if (_isClosed) return;

    await connectToRelays(relayUrls, targetNpubs);

    Set<String> allParentIds = Set<String>.from(notes.map((note) => note.id));
    allParentIds.addAll(repliesMap.keys);
    await fetchReactionsForNotes(allParentIds.toList());
    await fetchRepliesForNotes(allParentIds.toList());
  }

  Future<void> connectToRelays(List<String> relayList, List<String> targetNpubs) async {
    if (isConnecting || _isClosed) return;
    isConnecting = true;

    await Future.wait(relayList.map((relayUrl) async {
      if (_isClosed) return;
      if (!_webSockets.containsKey(relayUrl) || _webSockets[relayUrl]?.readyState == WebSocket.closed) {
        try {
          final webSocket = await WebSocket.connect(relayUrl).timeout(Duration(seconds: 5));
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

          _fetchNotes(webSocket, targetNpubs);
          _fetchProfiles(webSocket, targetNpubs);
          _fetchReplies(webSocket, targetNpubs);
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

  Future<void> saveNotesToCache() async {
    if (notesBox.isOpen) {
      await notesBox.put('notes', notes.map((note) => note.toJson()).toList());
    }
  }

  Future<void> loadNotesFromCache(Function(NoteModel) onLoad) async {
    if (!notesBox.isOpen) return;
    List<dynamic> cachedNotesJson = notesBox.get('notes', defaultValue: []);
    for (var noteJson in cachedNotesJson) {
      final noteModel = NoteModel.fromJson(Map<String, dynamic>.from(noteJson));
      eventIds.add(noteModel.id);
      onLoad(noteModel);
    }
  }

  Future<void> saveReactionsToCache() async {
    if (reactionsBox.isOpen) {
      Map<String, dynamic> reactionsJson = reactionsMap.map((key, value) {
        return MapEntry(key, value.map((reaction) => reaction.toJson()).toList());
      });
      await reactionsBox.put('reactions', reactionsJson);
    }
  }

  Future<void> loadReactionsFromCache() async {
    if (!reactionsBox.isOpen) return;
    Map<dynamic, dynamic> cachedReactionsJson = reactionsBox.get('reactions', defaultValue: {});
    cachedReactionsJson.forEach((key, value) {
      String noteId = key as String;
      List<dynamic> reactionsList = value as List<dynamic>;
      reactionsMap[noteId] = reactionsList
          .map((reactionJson) => ReactionModel.fromJson(Map<String, dynamic>.from(reactionJson as Map)))
          .toList();
    });
  }

  Future<void> saveRepliesToCache() async {
    if (repliesBox.isOpen) {
      Map<String, dynamic> repliesJson = repliesMap.map((key, value) {
        return MapEntry(key, value.map((reply) => reply.toJson()).toList());
      });
      await repliesBox.put('replies', repliesJson);
    }
  }

  Future<void> loadRepliesFromCache() async {
    if (!repliesBox.isOpen) return;
    Map<dynamic, dynamic> cachedRepliesJson = repliesBox.get('replies', defaultValue: {});
    cachedRepliesJson.forEach((key, value) {
      String noteId = key as String;
      List<dynamic> repliesList = value as List<dynamic>;
      repliesMap[noteId] = repliesList
          .map((replyJson) => ReplyModel.fromJson(Map<String, dynamic>.from(replyJson as Map)))
          .toList();
    });
  }

  String generate64RandomHexChars() {
    var uuid = Uuid();
    return uuid.v4().replaceAll('-', '');
  }

  void _fetchNotes(WebSocket webSocket, List<String> targetNpubs) {
    if (_isClosed) return;
    Filter filter;
    if (dataType == DataType.Feed) {
      filter = Filter(authors: targetNpubs, kinds: [1], limit: currentLimit);
    } else {
      filter = Filter(authors: [npub], kinds: [1], limit: currentLimit);
    }
    final request = Request(generate64RandomHexChars(), [filter]);
    webSocket.add(request.serialize());
  }

  void _fetchProfiles(WebSocket webSocket, List<String> targetNpubs) {
    if (_isClosed) return;
    final request = Request(generate64RandomHexChars(), [
      Filter(authors: targetNpubs, kinds: [0]),
    ]);
    webSocket.add(request.serialize());
  }

  void _fetchReplies(WebSocket webSocket, List<String> targetNpubs) {
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
    }
  }

  void _handleEvent(dynamic event, List<String> targetNpubs) async {
    if (_isClosed) return;
    try {
      final decodedEvent = jsonDecode(event);
      if (decodedEvent[0] == 'EVENT') {
        final eventData = decodedEvent[2] as Map<String, dynamic>;
        final kind = eventData['kind'] as int;

        if (kind == 1) {
          final eventId = eventData['id'] as String;
          final author = eventData['pubkey'] as String;
          final content = eventData['content'] as String? ?? '';
          final tags = eventData['tags'] as List<dynamic>;

          bool isReply = tags.any((tag) => tag.length >= 2 && tag[0] == 'e');

          if (eventIds.contains(eventId) || content.trim().isEmpty) {
            return;
          }

          if (!isReply) {
            if (dataType == DataType.Feed && targetNpubs.isNotEmpty && !targetNpubs.contains(author)) {
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
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                  (eventData['created_at'] as int) * 1000),
            );

            notes.add(newEvent);
            notes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
            eventIds.add(eventId);
            await saveNotesToCache();

            if (onNewNote != null) {
              onNewNote!(newEvent);
            }

            fetchReactionsForNotes([eventId]);
            fetchRepliesForNotes([eventId]);
          }
        } else if (kind == 7) {
          await _handleReactionEvent(eventData);
        } else if (kind == 0) {
          final author = eventData['pubkey'] as String;
          final profileContent = jsonDecode(eventData['content'] as String) as Map<String, dynamic>;
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
        }
      }
    } catch (e) {
    }
  }

  Future<void> _handleReactionEvent(Map<String, dynamic> eventData) async {
    if (_isClosed) return;
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
  }

  Future<void> _handleReplyEvent(Map<String, dynamic> eventData) async {
    if (_isClosed) return;
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
      return _pendingProfileRequests[npub]!.future;
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

    Future.delayed(Duration(seconds: 5), () {
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
      }
    });

    return completer.future;
  }

  Future<List<String>> getFollowingList(String npub) async {
    List<String> followingNpubs = [];

    for (var relayUrl in relayUrls) {
      try {
        final webSocket = await WebSocket.connect(relayUrl).timeout(Duration(seconds: 5));
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
        });

        webSocket.add(request.serialize());

        await completer.future.timeout(Duration(seconds: 5), onTimeout: () {
          webSocket.close();
        });

        await webSocket.close();
      } catch (e) {
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
    }
  }

  void _startCheckingForNewData(List<String> targetNpubs) {
    _checkNewNotesTimer?.cancel();
    _checkNewNotesTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      if (_isClosed) {
        timer.cancel();
        return;
      }
      Set<String> allParentIds = Set<String>.from(notes.map((note) => note.id));
      allParentIds.addAll(repliesMap.keys);

      List<String> allIds = allParentIds.toList();

      for (var relayUrl in _webSockets.keys) {
        final webSocket = _webSockets[relayUrl]!;
        _fetchNotes(webSocket, targetNpubs);
        _fetchProfiles(webSocket, targetNpubs);
        fetchReactionsForNotes(allIds);
        fetchRepliesForNotes(allParentIds.toList());
      }
    });
  }

  Future<void> closeConnections() async {
    if (_isClosed) return;
    _isClosed = true;
    _checkNewNotesTimer?.cancel();
    for (var ws in _webSockets.values) {
      ws.close();
    }
    _webSockets.clear();

    if (notesBox.isOpen) await notesBox.close();
    if (reactionsBox.isOpen) await reactionsBox.close();
    if (repliesBox.isOpen) await repliesBox.close();
  }
}
