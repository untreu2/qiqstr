import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:nostr/nostr.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import 'package:qiqstr/constants/relays.dart';
import 'package:qiqstr/models/zap_model.dart';
import 'package:qiqstr/screens/profile_page.dart';
import 'package:qiqstr/models/notification_model.dart';
import 'package:qiqstr/services/isolate_manager.dart';
import 'package:qiqstr/services/relay_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_model.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../models/repost_model.dart';
import '../models/following_model.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:qiqstr/services/note_processor.dart';
import 'package:crypto/crypto.dart';
import 'nostr_service.dart';
import 'cache_service.dart';
import 'profile_service.dart';
import '../providers/interactions_provider.dart';

enum DataType { feed, profile, note }

class NoteListNotifier extends ValueNotifier<List<NoteModel>> {
  final SplayTreeSet<NoteModel> _itemsTree;
  final DataType _dataType;
  final String _npub;

  List<NoteModel>? _cachedFilteredNotes;
  bool _filterCacheValid = false;

  NoteListNotifier(this._dataType, this._npub)
      : _itemsTree = SplayTreeSet(DataService._compareNotes),
        super([]);

  List<NoteModel> get notes => value;

  SplayTreeSet<NoteModel> get itemsTree => _itemsTree;

  bool addNoteQuietly(NoteModel note) {
    if (_itemsTree.add(note)) {
      _invalidateFilterCache();
      return true;
    }
    return false;
  }

  bool updateNoteQuietly(NoteModel updatedNote) {
    if (_itemsTree.remove(updatedNote)) {
      _itemsTree.add(updatedNote);
      _invalidateFilterCache();
      return true;
    }
    return false;
  }

  bool removeNoteQuietly(NoteModel note) {
    if (_itemsTree.remove(note)) {
      _invalidateFilterCache();
      return true;
    }
    return false;
  }

  void clearQuietly() {
    if (_itemsTree.isNotEmpty) {
      _itemsTree.clear();
      _invalidateFilterCache();
    }
  }

  void notifyListenersWithFilteredList() {
    value = _getFilteredNotesList();
  }

  void _invalidateFilterCache() {
    _filterCacheValid = false;
  }

  List<NoteModel> _getFilteredNotesList() {
    if (_dataType != DataType.profile) {
      return _itemsTree.toList();
    }

    if (_filterCacheValid && _cachedFilteredNotes != null) {
      return _cachedFilteredNotes!;
    }

    final allNotes = _itemsTree.toList();
    _cachedFilteredNotes = allNotes.where((note) {
      return note.author == _npub || (note.isRepost && note.repostedBy == _npub);
    }).toList();

    _filterCacheValid = true;
    return _cachedFilteredNotes!;
  }
}

enum MessageType { newnotes, cacheload, error, close }

class IsolateMessage {
  final MessageType type;
  final dynamic data;
  IsolateMessage(this.type, this.data);
}

class CachedProfile {
  final Map<String, String> data;
  final DateTime fetchedAt;
  CachedProfile(this.data, this.fetchedAt);
}

class DataServiceMetrics {
  int eventsProcessed = 0;
  int notesAdded = 0;
  int profilesFetched = 0;
  int cacheHits = 0;
  int cacheMisses = 0;
  int isolateMessages = 0;
  final Map<String, int> operationCounts = {};
  final Map<String, List<int>> operationTimes = {};

  void recordOperation(String operation, int timeMs) {
    operationCounts[operation] = (operationCounts[operation] ?? 0) + 1;
    operationTimes.putIfAbsent(operation, () => []);
    operationTimes[operation]!.add(timeMs);

    if (operationTimes[operation]!.length > 100) {
      operationTimes[operation]!.removeRange(0, 50);
    }
  }

  Map<String, dynamic> getStats() {
    final stats = <String, dynamic>{
      'eventsProcessed': eventsProcessed,
      'notesAdded': notesAdded,
      'profilesFetched': profilesFetched,
      'cacheHits': cacheHits,
      'cacheMisses': cacheMisses,
      'isolateMessages': isolateMessages,
    };

    for (final entry in operationTimes.entries) {
      if (entry.value.isNotEmpty) {
        final times = entry.value;
        stats['${entry.key}_avg'] = times.reduce((a, b) => a + b) / times.length;
        stats['${entry.key}_count'] = operationCounts[entry.key] ?? 0;
      }
    }

    return stats;
  }
}

class DataService {
  Timer? _uiThrottleTimer;
  bool _hasPendingUiUpdate = false;

  final Set<String> _pendingOptimisticReactionIds = {};
  late Isolate _eventProcessorIsolate;
  late SendPort _eventProcessorSendPort;
  final Completer<void> _eventProcessorReady = Completer<void>();

  late Isolate _fetchProcessorIsolate;
  late SendPort _fetchProcessorSendPort;
  final Completer<void> _fetchProcessorReady = Completer<void>();

  final String npub;
  final DataType dataType;
  final Function(NoteModel)? onNewNote;
  final Function(String, List<ReactionModel>)? onReactionsUpdated;
  final Function(String, List<ReplyModel>)? onRepliesUpdated;
  final Function(String, int)? onReactionCountUpdated;
  final Function(String, int)? onReplyCountUpdated;
  final Function(String, List<RepostModel>)? onRepostsUpdated;
  final Function(String, int)? onRepostCountUpdated;

  List<NoteModel> notes = [];
  final Set<String> eventIds = {};

  final Map<String, List<ReactionModel>> reactionsMap = {};
  final Map<String, List<ReplyModel>> repliesMap = {};
  final Map<String, List<RepostModel>> repostsMap = {};
  final Map<String, List<ZapModel>> zapsMap = {};

  final Map<String, CachedProfile> profileCache = {};

  Box<UserModel>? usersBox;
  Box<NoteModel>? notesBox;
  Box<ReactionModel>? reactionsBox;
  Box<ReplyModel>? repliesBox;
  Box<RepostModel>? repostsBox;
  Box<FollowingModel>? followingBox;
  Box<ZapModel>? zapsBox;
  Box<NotificationModel>? notificationsBox;

  final List<Map<String, dynamic>> _pendingEvents = [];
  Timer? _batchTimer;

  late WebSocketManager _socketManager;
  bool _isInitialized = false;
  bool _isClosed = false;

  bool _isConnecting = false;
  bool _hasActiveConnections = false;
  DateTime? _lastSuccessfulConnection;
  int _connectionRetryCount = 0;
  final int _maxConnectionRetries = 5;

  String? _lastError;
  DateTime? _lastErrorTime;
  bool _isInErrorState = false;
  final ValueNotifier<String?> errorStateNotifier = ValueNotifier(null);
  final ValueNotifier<bool> connectionStateNotifier = ValueNotifier(false);

  Timer? _cacheCleanupTimer;
  Timer? _interactionRefreshTimer;
  int currentLimit = 100;

  final Map<String, Completer<Map<String, String>>> _pendingProfileRequests = {};

  late ReceivePort _receivePort;
  late Isolate _isolate;
  late SendPort _sendPort;
  final Completer<void> _sendPortReadyCompleter = Completer<void>();

  Function(List<NoteModel>)? _onCacheLoad;

  final Duration profileCacheTTL = const Duration(minutes: 30);
  final Duration cacheCleanupInterval = const Duration(hours: 6);

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  late CacheService _cacheService;
  late ProfileService _profileService;

  final DataServiceMetrics _metrics = DataServiceMetrics();

  DataService({
    required this.npub,
    required this.dataType,
    this.onNewNote,
    this.onReactionsUpdated,
    this.onRepliesUpdated,
    this.onReactionCountUpdated,
    this.onReplyCountUpdated,
    this.onRepostsUpdated,
    this.onRepostCountUpdated,
  }) {
    notesNotifier = NoteListNotifier(dataType, npub);
  }

  int get connectedRelaysCount => _socketManager.activeSockets.length;
  int get currentNotesLimit => currentLimit;

  Future<void> initialize() async {
    await initializeLightweight();
    await initializeHeavyOperations();

    await _ensureConnectionsReady();
  }

  Future<void> initializeLightweight() async {
    final stopwatch = Stopwatch()..start();

    try {
      _isInitialized = true;

      notesBox = await _openHiveBox<NoteModel>('notes');
      usersBox = await _openHiveBox<UserModel>('users');

      _cacheService = CacheService();
      _cacheService.notesBox = notesBox;

      _profileService = ProfileService();
      if (usersBox != null) {
        _profileService.setUsersBox(usersBox!);

        await _profileService.initialize();
      }

      await loadNotesFromCache((loadedNotes) {});

      await _preloadProfilesForVisibleNotes();

      _metrics.recordOperation('lightweight_init', stopwatch.elapsedMilliseconds);
      print('[DataService] Lightweight initialization completed in ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      print('[DataService] Lightweight initialization error: $e');
      rethrow;
    }
  }

  Future<void> initializeHeavyOperations() async {
    final stopwatch = Stopwatch()..start();

    try {
      _socketManager = WebSocketManager(relayUrls: relaySetMainSockets);

      final remainingBoxes = await Future.wait([
        _openHiveBox<ReactionModel>('reactions'),
        _openHiveBox<ReplyModel>('replies'),
        _openHiveBox<RepostModel>('reposts'),
        _openHiveBox<ZapModel>('zaps'),
        _openHiveBox<FollowingModel>('followingBox'),
        _openHiveBox<NotificationModel>('notifications_$npub'),
      ]);

      reactionsBox = remainingBoxes[0] as Box<ReactionModel>;
      repliesBox = remainingBoxes[1] as Box<ReplyModel>;
      repostsBox = remainingBoxes[2] as Box<RepostModel>;
      zapsBox = remainingBoxes[3] as Box<ZapModel>;
      followingBox = remainingBoxes[4] as Box<FollowingModel>;
      notificationsBox = remainingBoxes[5] as Box<NotificationModel>;

      _cacheService.reactionsBox = reactionsBox;
      _cacheService.repliesBox = repliesBox;
      _cacheService.repostsBox = repostsBox;
      _cacheService.zapsBox = zapsBox;

      await Future.wait([
        _initializeEventProcessorIsolate(),
        _initializeFetchProcessorIsolate(),
        _initializeIsolate(),
      ]);
      print('[DataService] Isolates initialized');

      Future.microtask(() => _loadCacheDataInBackground());

      Future.microtask(() => _aggressivelyPreloadAllProfiles());

      _startOptimizedTimers();

      Future.microtask(() => _preloadNextBatch());

      Future.microtask(() => enablePreemptiveLoading());

      _metrics.recordOperation('heavy_init', stopwatch.elapsedMilliseconds);
      print('[DataService] Heavy initialization completed in ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      print('[DataService] Heavy initialization error: $e');
    }
  }

  Future<void> _ensureConnectionsReady() async {
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 2);

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('[DataService] Attempting to establish connections (attempt $attempt/$maxRetries)');

        await initializeConnections().timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw TimeoutException('Connection initialization timed out', const Duration(seconds: 15));
          },
        );

        if (_socketManager.activeSockets.isNotEmpty) {
          print('[DataService] Connections established successfully with ${_socketManager.activeSockets.length} active relays');
          _updateConnectionState(true);
          return;
        } else {
          throw Exception('No active relay connections after initialization');
        }
      } catch (e) {
        print('[DataService] Connection attempt $attempt failed: $e');

        if (attempt < maxRetries) {
          print('[DataService] Retrying connection in ${retryDelay.inSeconds} seconds...');
          await Future.delayed(retryDelay);
        } else {
          print('[DataService] Failed to establish connections after $maxRetries attempts');
          _handleConnectionError('Failed to establish connections', e);

          await _emergencyConnectionSetup();
        }
      }
    }
  }

  Future<void> _emergencyConnectionSetup() async {
    try {
      print('[DataService] Attempting emergency connection setup');

      final emergencyRelays = relaySetMainSockets.take(2).toList();
      _socketManager = WebSocketManager(relayUrls: emergencyRelays);

      List<String> targetNpubs = [npub];
      if (dataType == DataType.feed) {
        try {
          final following = await getFollowingList(npub);
          if (following.isNotEmpty) {
            following.add(npub);
            targetNpubs = following.toSet().toList();
          }
        } catch (e) {
          print('[DataService] Emergency: Failed to get following list, using own npub only');
        }
      }

      await _socketManager.connectRelays(
        targetNpubs,
        onEvent: (event, relayUrl) => _handleEvent(event, targetNpubs),
        onDisconnected: (relayUrl) => _socketManager.reconnectRelay(relayUrl, targetNpubs),
      );

      if (dataType == DataType.profile) {
        await _fetchProfileNotesDirectly(npub);
      } else {
        await fetchNotes(targetNpubs, initialLoad: true);
      }

      print('[DataService] Emergency connection setup completed');
      _updateConnectionState(true);
    } catch (e) {
      print('[DataService] Emergency connection setup failed: $e');
      _handleConnectionError('Emergency connection setup failed', e);

      _enableOfflineMode();
    }
  }

  void _updateConnectionState(bool isConnected) {
    _hasActiveConnections = isConnected;
    connectionStateNotifier.value = isConnected;

    if (isConnected) {
      _lastSuccessfulConnection = DateTime.now();
      _connectionRetryCount = 0;
      _clearErrorState();
    }

    print('[DataService] Connection state updated: $isConnected');
  }

  void _handleConnectionError(String message, dynamic error) {
    _lastError = '$message: $error';
    _lastErrorTime = DateTime.now();
    _isInErrorState = true;
    _connectionRetryCount++;

    errorStateNotifier.value = _getErrorMessage();
    _updateConnectionState(false);

    print('[DataService] Connection error handled: $_lastError');

    if (_connectionRetryCount < _maxConnectionRetries) {
      final delay = Duration(seconds: _connectionRetryCount * 2);
      print(
          '[DataService] Auto-retry scheduled in ${delay.inSeconds} seconds (attempt ${_connectionRetryCount + 1}/$_maxConnectionRetries)');

      Future.delayed(delay, () {
        if (!_isClosed && !_hasActiveConnections) {
          _attemptReconnection();
        }
      });
    } else {
      print('[DataService] Max connection retries exceeded, enabling offline mode');
      _enableOfflineMode();
    }
  }

  void _clearErrorState() {
    _lastError = null;
    _lastErrorTime = null;
    _isInErrorState = false;
    errorStateNotifier.value = null;
  }

  String _getErrorMessage() {
    if (_lastError == null) return 'Unknown connection error';

    if (_connectionRetryCount >= _maxConnectionRetries) {
      return 'Unable to connect to relays. Using cached data only.';
    }

    return 'Connection issues detected. Retrying... (${_connectionRetryCount}/$_maxConnectionRetries)';
  }

  void _enableOfflineMode() {
    print('[DataService] Enabling offline mode - using cached data only');
    errorStateNotifier.value = 'Offline mode: Using cached data only';

    Future.microtask(() async {
      try {
        await _loadCacheDataInBackground();
        print('[DataService] Offline mode: Cached data loaded successfully');
      } catch (e) {
        print('[DataService] Offline mode: Error loading cached data: $e');
      }
    });
  }

  Future<void> _attemptReconnection() async {
    if (_isConnecting || _isClosed) return;

    _isConnecting = true;
    print('[DataService] Attempting manual reconnection...');

    try {
      await _ensureConnectionsReady();
      print('[DataService] Manual reconnection successful');
    } catch (e) {
      print('[DataService] Manual reconnection failed: $e');
      _handleConnectionError('Manual reconnection failed', e);
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> retryConnection() async {
    if (_isClosed) return;

    _connectionRetryCount = 0;
    await _attemptReconnection();
  }

  bool get isHealthy {
    if (_isClosed) return false;
    if (!_hasActiveConnections) return false;
    if (_isInErrorState) return false;

    if (_lastSuccessfulConnection != null) {
      final timeSinceLastConnection = DateTime.now().difference(_lastSuccessfulConnection!);
      if (timeSinceLastConnection > const Duration(minutes: 5)) {
        return false;
      }
    }

    return true;
  }

  Map<String, dynamic> getConnectionStatus() {
    return {
      'isConnected': _hasActiveConnections,
      'isHealthy': isHealthy,
      'isInErrorState': _isInErrorState,
      'lastError': _lastError,
      'lastErrorTime': _lastErrorTime?.toIso8601String(),
      'lastSuccessfulConnection': _lastSuccessfulConnection?.toIso8601String(),
      'retryCount': _connectionRetryCount,
      'maxRetries': _maxConnectionRetries,
      'activeRelays': _socketManager.activeSockets.length,
    };
  }

  Future<void> _loadCacheDataInBackground() async {
    try {
      await Future.wait([
        loadReactionsFromCache(),
        loadRepliesFromCache(),
        loadRepostsFromCache(),
        loadZapsFromCache(),
        _loadNotificationsFromCache(),
      ]);

      print('[DataService] Background cache loading completed');
    } catch (e) {
      print('[DataService] Error in background cache loading: $e');
    }
  }

  void _startOptimizedTimers() {
    _startCacheCleanup();
    _startInteractionRefresh();
    _startEventProcessing();
  }

  void _startEventProcessing() {}

  Future<Map<String, String>> resolveMentions(List<String> ids) async {
    final Map<String, String> results = {};

    for (final id in ids) {
      try {
        String? pubHex;
        if (id.startsWith('npub1')) {
          pubHex = decodeBasicBech32(id, 'npub');
        } else if (id.startsWith('nprofile1')) {
          pubHex = decodeTlvBech32Full(id, 'nprofile')['type_0_main'];
        }
        if (pubHex != null) {
          final profile = await getCachedUserProfile(pubHex);
          final user = UserModel.fromCachedProfile(pubHex, profile);
          if (user.name.isNotEmpty) {
            results[id] = user.name;
          }
        }
      } catch (_) {}
    }

    return results;
  }

  Future<void> _initializeEventProcessorIsolate() async {
    final ReceivePort receivePort = ReceivePort();

    _eventProcessorIsolate = await Isolate.spawn(
      IsolateManager.eventProcessorEntryPoint,
      receivePort.sendPort,
    );

    receivePort.listen((dynamic message) {
      if (message is SendPort) {
        _eventProcessorSendPort = message;
        _eventProcessorReady.complete();
      } else if (message is Map<String, dynamic>) {
        if (message.containsKey('error')) {
          print('[Event Isolate ERROR] ${message['error']}');
        } else if (message.containsKey('type') && message['type'] == 'batch_results') {
          final results = message['results'] as List<dynamic>? ?? [];
          for (final result in results) {
            if (result is Map<String, dynamic> && !result.containsKey('error')) {
              _processParsedEvent(result);
            }
          }
        } else {
          _processParsedEvent(message);
        }
      }
    });
  }

  Future<void> _initializeFetchProcessorIsolate() async {
    final ReceivePort receivePort = ReceivePort();

    _fetchProcessorIsolate = await Isolate.spawn(
      IsolateManager.fetchProcessorEntryPoint,
      receivePort.sendPort,
    );

    receivePort.listen((dynamic message) {
      if (message is SendPort) {
        _fetchProcessorSendPort = message;
        _fetchProcessorReady.complete();
      } else if (message is Map<String, dynamic>) {
        if (message.containsKey('error')) {
          print('[Fetch Isolate ERROR] ${message['error']}');
        } else {
          _handleFetchedData(message);
        }
      }
    });
  }

  Future<Box<T>> _openHiveBox<T>(String boxName) async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box<T>(boxName);
    } else {
      return await Hive.openBox<T>(boxName);
    }
  }

  Future<void> _initializeIsolate() async {
    _receivePort = ReceivePort();

    _isolate = await Isolate.spawn(
      IsolateManager.dataProcessorEntryPoint,
      _receivePort.sendPort,
    );

    _receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        if (!_sendPortReadyCompleter.isCompleted) {
          _sendPortReadyCompleter.complete();
          print('[DataService] Isolate initialized successfully.');
        }
      } else if (message is IsolateMessage) {
        switch (message.type) {
          case MessageType.newnotes:
            _handleNewNotes(message.data);
            break;
          case MessageType.cacheload:
            _handleCacheLoad(message.data);
            break;
          case MessageType.error:
            print('[DataService ERROR] Isolate error: ${message.data}');
            break;
          case MessageType.close:
            print('[DataService] Isolate received close message.');
            break;
        }
      }
    });
  }

  Map<String, dynamic> parseContent(String content) {
    final RegExp mediaRegExp = RegExp(
      r'(https?:\/\/\S+\.(?:jpg|jpeg|png|webp|gif|mp4|mov))',
      caseSensitive: false,
    );
    final mediaMatches = mediaRegExp.allMatches(content);
    final List<String> mediaUrls = mediaMatches.map((m) => m.group(0)!).toList();

    final RegExp linkRegExp = RegExp(r'(https?:\/\/\S+)', caseSensitive: false);
    final linkMatches = linkRegExp.allMatches(content);
    final List<String> linkUrls = linkMatches
        .map((m) => m.group(0)!)
        .where((u) => !mediaUrls.contains(u) && !u.toLowerCase().endsWith('.mp4') && !u.toLowerCase().endsWith('.mov'))
        .toList();

    final RegExp quoteRegExp = RegExp(
      r'(?:nostr:)?(note1[0-9a-z]+|nevent1[0-9a-z]+)',
      caseSensitive: false,
    );
    final quoteMatches = quoteRegExp.allMatches(content);
    final List<String> quoteIds = quoteMatches.map((m) => m.group(1)!).toList();

    String cleanedText = content;
    for (final m in [...mediaMatches, ...quoteMatches]) {
      cleanedText = cleanedText.replaceFirst(m.group(0)!, '');
    }
    cleanedText = cleanedText.trim();

    final RegExp mentionRegExp = RegExp(
      r'nostr:(npub1[0-9a-z]+|nprofile1[0-9a-z]+)',
      caseSensitive: false,
    );
    final mentionMatches = mentionRegExp.allMatches(cleanedText);

    final List<Map<String, dynamic>> textParts = [];
    int lastEnd = 0;
    for (final m in mentionMatches) {
      if (m.start > lastEnd) {
        textParts.add({
          'type': 'text',
          'text': cleanedText.substring(lastEnd, m.start),
        });
      }

      final id = m.group(1)!;
      textParts.add({'type': 'mention', 'id': id});
      lastEnd = m.end;
    }

    if (lastEnd < cleanedText.length) {
      textParts.add({
        'type': 'text',
        'text': cleanedText.substring(lastEnd),
      });
    }

    return {
      'mediaUrls': mediaUrls,
      'linkUrls': linkUrls,
      'quoteIds': quoteIds,
      'textParts': textParts,
    };
  }

  Future<void> openUserProfile(BuildContext context, String bech32OrHex) async {
    try {
      String? pubHex;

      if (bech32OrHex.startsWith('npub1')) {
        pubHex = decodeBasicBech32(bech32OrHex, 'npub');
      } else if (bech32OrHex.startsWith('nprofile1')) {
        pubHex = decodeTlvBech32Full(bech32OrHex, 'nprofile')['type_0_main'];
      } else {
        pubHex = bech32OrHex;
      }

      if (pubHex == null) return;

      UserModel user;
      if (profileCache.containsKey(pubHex)) {
        user = UserModel.fromCachedProfile(pubHex, profileCache[pubHex]!.data);
      } else if (usersBox?.get(pubHex) != null) {
        user = usersBox!.get(pubHex)!;
      } else {
        user = UserModel(
          npub: pubHex,
          name: 'Loading...',
          about: '',
          profileImage: '',
          nip05: '',
          banner: '',
          lud16: '',
          website: '',
          updatedAt: DateTime.now(),
        );
      }

      if (!context.mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProfilePage(user: user)),
      );

      if (!profileCache.containsKey(pubHex) || DateTime.now().difference(profileCache[pubHex]!.fetchedAt) > profileCacheTTL) {
        Future.microtask(() async {
          try {
            final data = await getCachedUserProfile(pubHex!);
            final fullUser = UserModel.fromCachedProfile(pubHex, data);

            profileCache[pubHex] = CachedProfile(data, DateTime.now());
            profilesNotifier.value = {
              ...profilesNotifier.value,
              pubHex: fullUser,
            };
          } catch (e) {
            print('[DataService] Background profile fetch error: $e');
          }
        });
      }
    } catch (e) {
      print('[DataService] Error in openUserProfile: $e');
    }
  }

  void _startRealTimeSubscription(List<String> targetNpubs) {
    final sinceTimestamp = (notes.isNotEmpty)
        ? (notes.first.timestamp.millisecondsSinceEpoch ~/ 1000)
        : (DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000);

    final filterNotes = NostrService.createNotesFilter(
      authors: targetNpubs,
      kinds: [1],
      since: sinceTimestamp,
    );
    final requestNotes = NostrService.createRequest(filterNotes);
    _safeBroadcast(NostrService.serializeRequest(requestNotes));

    final filterReposts = NostrService.createNotesFilter(
      authors: targetNpubs,
      kinds: [6],
      since: sinceTimestamp,
    );
    final requestReposts = NostrService.createRequest(filterReposts);
    _safeBroadcast(NostrService.serializeRequest(requestReposts));

    _startRealTimeInteractionSubscription();

    print('[DataService] Started enhanced real-time subscription for notes, reposts, and interactions.');
  }

  void _startRealTimeInteractionSubscription() {
    if (notesNotifier.notes.isEmpty) return;

    const int limit = 100;
    final latestNotes = notesNotifier.notes.take(limit).toList();
    final allEventIds = latestNotes.map((note) => note.id).toList();
    final sinceTimestamp = DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000;

    if (allEventIds.isEmpty) return;

    final reactionFilter = NostrService.createReactionFilter(
      eventIds: allEventIds,
      since: sinceTimestamp,
    );
    _safeBroadcast(NostrService.serializeRequest(NostrService.createRequest(reactionFilter)));

    final replyFilter = NostrService.createReplyFilter(
      eventIds: allEventIds,
      since: sinceTimestamp,
    );
    _safeBroadcast(NostrService.serializeRequest(NostrService.createRequest(replyFilter)));

    final repostFilter = NostrService.createRepostFilter(
      eventIds: allEventIds,
      since: sinceTimestamp,
    );
    _safeBroadcast(NostrService.serializeRequest(NostrService.createRequest(repostFilter)));

    final zapFilter = NostrService.createZapFilter(
      eventIds: allEventIds,
      since: sinceTimestamp,
    );
    _safeBroadcast(NostrService.serializeRequest(NostrService.createRequest(zapFilter)));
  }

  Future<void> _subscribeToFollowing() async {
    final filter = NostrService.createFollowingFilter(
      authors: [npub],
    );
    final request = NostrService.serializeRequest(NostrService.createRequest(filter));
    await _safeBroadcast(request);
    print('[DataService] Subscribed to following events (kind 3).');
  }

  Future<void> initializeConnections() async {
    if (!_isInitialized) return;

    const maxRetries = 2;
    const retryDelay = Duration(milliseconds: 500);

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('[DataService] Initializing connections (attempt $attempt/$maxRetries)');

        List<String> targetNpubs;
        if (dataType == DataType.feed) {
          try {
            final following = await getFollowingList(npub).timeout(
              const Duration(seconds: 8),
              onTimeout: () {
                print('[DataService] Following list fetch timed out, using cached or minimal list');
                return [npub];
              },
            );
            following.add(npub);
            targetNpubs = following.toSet().toList();
            print('[DataService] Feed mode: ${targetNpubs.length} target npubs');
          } catch (e) {
            print('[DataService] Error getting following list: $e, using own npub only');
            targetNpubs = [npub];
          }
        } else {
          targetNpubs = [npub];
          print('[DataService] Profile mode: single target npub');
        }

        if (_isClosed) return;

        try {
          await _socketManager
              .connectRelays(
            targetNpubs,
            onEvent: (event, relayUrl) => _handleEvent(event, targetNpubs),
            onDisconnected: (relayUrl) => _socketManager.reconnectRelay(relayUrl, targetNpubs),
          )
              .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('Relay connection timed out', const Duration(seconds: 10));
            },
          );

          print('[DataService] Connected to ${_socketManager.activeSockets.length} relays');
        } catch (e) {
          if (attempt < maxRetries) {
            print('[DataService] Relay connection failed (attempt $attempt): $e, retrying...');
            await Future.delayed(retryDelay);
            continue;
          } else {
            throw Exception('Failed to connect to relays after $maxRetries attempts: $e');
          }
        }

        if (_socketManager.activeSockets.isEmpty) {
          throw Exception('No active relay connections established');
        }

        try {
          if (dataType == DataType.profile) {
            await _fetchProfileNotesDirectly(npub).timeout(
              const Duration(seconds: 8),
              onTimeout: () {
                print('[DataService] Profile notes fetch timed out, continuing with cached data');
              },
            );
          } else {
            await fetchNotes(targetNpubs, initialLoad: true).timeout(
              const Duration(seconds: 8),
              onTimeout: () {
                print('[DataService] Feed notes fetch timed out, continuing with cached data');
              },
            );
          }
        } catch (e) {
          print('[DataService] Note fetching error: $e, continuing with cached data');
        }

        Future.microtask(() async {
          try {
            await Future.wait([
              loadReactionsFromCache(),
              loadRepliesFromCache(),
              loadRepostsFromCache(),
            ], eagerError: false);
            print('[DataService] Cached interactions loaded');
          } catch (e) {
            print('[DataService] Error loading cached interactions: $e');
          }
        });

        Future.microtask(() async {
          try {
            await Future.wait([
              _subscribeToNotifications(),
            ], eagerError: false);
            print('[DataService] Interaction subscriptions completed');
          } catch (e) {
            print('[DataService] Error subscribing to interactions: $e');
          }
        });

        _scheduleInteractionRefresh();

        if (dataType == DataType.feed) {
          Future.microtask(() {
            try {
              _startRealTimeSubscription(targetNpubs);
              _subscribeToFollowing();
            } catch (e) {
              print('[DataService] Error starting real-time subscriptions: $e');
            }
          });
        }

        Future.microtask(() async {
          try {
            await getCachedUserProfile(npub);
          } catch (e) {
            print('[DataService] Error fetching user profile: $e');
          }
        });

        print('[DataService] Connection initialization completed successfully');
        return;
      } catch (e) {
        print('[DataService] Connection initialization attempt $attempt failed: $e');

        if (attempt < maxRetries) {
          print('[DataService] Retrying connection initialization in ${retryDelay.inMilliseconds}ms...');
          await Future.delayed(retryDelay);
        } else {
          print('[DataService] Connection initialization failed after $maxRetries attempts');
          rethrow;
        }
      }
    }
  }

  Future<void> _fetchProfileNotesDirectly(String userNpub, {int? limit, DateTime? until}) async {
    if (_isClosed) return;

    final noteLimit = limit ?? currentLimit;
    print('[DataService] Fetching profile notes directly for $userNpub with limit: $noteLimit, until: $until');

    final filter = NostrService.createNotesFilter(
      authors: [userNpub],
      kinds: [1, 6],
      limit: noteLimit,
      until: until != null ? until.millisecondsSinceEpoch ~/ 1000 : null,
    );

    final request = NostrService.serializeRequest(NostrService.createRequest(filter));
    await _safeBroadcast(request);

    print('[DataService] Optimized profile notes request sent for $userNpub (until: $until)');

    if (dataType == DataType.profile && notes.isNotEmpty) {
      Future.microtask(() => _fetchInteractionsForProfileNotes());
    }

    if (dataType == DataType.profile) {
      Future.microtask(() async {
        await Future.delayed(const Duration(milliseconds: 500));
      });
    }
  }

  Future<void> _fetchInteractionsForProfileNotes() async {
    if (_isClosed || notes.isEmpty) return;

    final profileNoteIds =
        notes.where((note) => note.author == npub || (note.isRepost && note.repostedBy == npub)).map((note) => note.id).toList();

    if (profileNoteIds.isEmpty) return;

    print('[DataService] Fetching interactions for ${profileNoteIds.length} profile notes');

    final futures = <Future>[];

    const batchSize = 15;
    for (int i = 0; i < profileNoteIds.length; i += batchSize) {
      final batch = profileNoteIds.skip(i).take(batchSize).toList();

      futures.add(_fetchReactionsForBatchWithRetry(batch));
      futures.add(_fetchRepliesForBatchWithRetry(batch));
      futures.add(_fetchRepostsForBatchWithRetry(batch));
      futures.add(_fetchZapsForBatchWithRetry(batch));

      if (futures.length >= 6) {
        await Future.wait(futures, eagerError: false);
        futures.clear();
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures, eagerError: false);
    }

    await Future.delayed(const Duration(milliseconds: 200));

    print('[DataService] Profile interaction fetching completed');
  }

  Future<void> _fetchReactionsForBatchWithRetry(List<String> noteIds, {int retries = 2}) async {
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        final filter = NostrService.createReactionFilter(eventIds: noteIds, limit: 500);
        await _broadcastRequest(NostrService.serializeRequest(NostrService.createRequest(filter)));
        return;
      } catch (e) {
        if (attempt == retries) {
          print('[DataService] Failed to fetch reactions after $retries retries: $e');
        } else {
          await Future.delayed(Duration(milliseconds: 100 * (attempt + 1)));
        }
      }
    }
  }

  Future<void> _fetchRepliesForBatchWithRetry(List<String> noteIds, {int retries = 2}) async {
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        final filter = NostrService.createReplyFilter(eventIds: noteIds, limit: 500);
        await _broadcastRequest(NostrService.serializeRequest(NostrService.createRequest(filter)));
        return;
      } catch (e) {
        if (attempt == retries) {
          print('[DataService] Failed to fetch replies after $retries retries: $e');
        } else {
          await Future.delayed(Duration(milliseconds: 100 * (attempt + 1)));
        }
      }
    }
  }

  Future<void> _fetchRepostsForBatchWithRetry(List<String> noteIds, {int retries = 2}) async {
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        final filter = NostrService.createRepostFilter(eventIds: noteIds, limit: 500);
        await _broadcastRequest(NostrService.serializeRequest(NostrService.createRequest(filter)));
        return;
      } catch (e) {
        if (attempt == retries) {
          print('[DataService] Failed to fetch reposts after $retries retries: $e');
        } else {
          await Future.delayed(Duration(milliseconds: 100 * (attempt + 1)));
        }
      }
    }
  }

  Future<void> _fetchZapsForBatchWithRetry(List<String> noteIds, {int retries = 2}) async {
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        final filter = NostrService.createZapFilter(eventIds: noteIds, limit: 500);
        await _broadcastRequest(NostrService.serializeRequest(NostrService.createRequest(filter)));
        return;
      } catch (e) {
        if (attempt == retries) {
          print('[DataService] Failed to fetch zaps after $retries retries: $e');
        } else {
          await Future.delayed(Duration(milliseconds: 100 * (attempt + 1)));
        }
      }
    }
  }

  Future<void> _broadcastRequest(String serializedRequest) async => await _safeBroadcast(serializedRequest);

  Future<void> _preloadProfilesForVisibleNotes() async {
    if (notes.isEmpty) return;

    final stopwatch = Stopwatch()..start();

    final visibleNotes = notes.take(50).toList();
    final authorsToPreload = <String>{};

    for (final note in visibleNotes) {
      authorsToPreload.add(note.author);
      if (note.repostedBy != null) {
        authorsToPreload.add(note.repostedBy!);
      }
    }

    await fetchProfilesBatch(authorsToPreload.toList());

    print('[DataService] Preloaded ${authorsToPreload.length} profiles for visible notes in ${stopwatch.elapsedMilliseconds}ms');
  }

  Future<void> _fetchProfilesForVisibleNotes(List<NoteModel> notes) async {
    if (notes.isEmpty) return;

    final authorsToFetch = <String>{};

    for (final note in notes) {
      authorsToFetch.add(note.author);
      if (note.repostedBy != null) {
        authorsToFetch.add(note.repostedBy!);
      }
    }

    await fetchProfilesBatch(authorsToFetch.toList());
  }

  Future<void> _aggressivelyPreloadAllProfiles() async {
    final stopwatch = Stopwatch()..start();

    final allAuthors = <String>{};

    for (final note in notes) {
      allAuthors.add(note.author);
      if (note.repostedBy != null) {
        allAuthors.add(note.repostedBy!);
      }
    }

    for (final reactions in reactionsMap.values) {
      for (final reaction in reactions) {
        allAuthors.add(reaction.author);
      }
    }

    for (final replies in repliesMap.values) {
      for (final reply in replies) {
        allAuthors.add(reply.author);
      }
    }

    for (final reposts in repostsMap.values) {
      for (final repost in reposts) {
        allAuthors.add(repost.repostedBy);
      }
    }

    final uncachedAuthors = allAuthors.where((author) {
      return !profileCache.containsKey(author) || DateTime.now().difference(profileCache[author]!.fetchedAt) > profileCacheTTL;
    }).toList();

    if (uncachedAuthors.isNotEmpty) {
      const batchSize = 50;
      for (int i = 0; i < uncachedAuthors.length; i += batchSize) {
        final batch = uncachedAuthors.skip(i).take(batchSize).toList();
        await fetchProfilesBatch(batch);

        if (i + batchSize < uncachedAuthors.length) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    }

    print('[DataService] Aggressively preloaded ${uncachedAuthors.length} profiles in ${stopwatch.elapsedMilliseconds}ms');
  }

  Future<void> _safeBroadcast(String message) async {
    try {
      await _socketManager.broadcast(message);
    } catch (e) {}
  }

  Future<void> fetchNotes(List<String> targetNpubs, {bool initialLoad = false}) async {
    if (_isClosed) return;

    DateTime? sinceTimestamp;
    if (!initialLoad && notes.isNotEmpty) {
      sinceTimestamp = notes.first.timestamp;
    }

    final filter = NostrService.createNotesFilter(
      authors: targetNpubs,
      kinds: [1, 6],
      limit: currentLimit,
      since: sinceTimestamp != null ? sinceTimestamp.millisecondsSinceEpoch ~/ 1000 : null,
    );

    await _broadcastRequest(NostrService.serializeRequest(NostrService.createRequest(filter)));
    print('[DataService] Fetched notes with filter: $filter');
  }

  final Map<String, Future<void>> _pendingProfileFetches = {};

  Future<void> fetchProfilesBatch(List<String> npubs) async {
    if (_isClosed || npubs.isEmpty) return;

    final now = DateTime.now();
    final uniqueNpubs = npubs.toSet().toList();
    final List<String> needsFetching = [];

    for (final pub in uniqueNpubs) {
      if (_pendingProfileFetches.containsKey(pub)) continue;

      if (profileCache.containsKey(pub)) {
        if (now.difference(profileCache[pub]!.fetchedAt) < profileCacheTTL) {
          continue;
        } else {
          profileCache.remove(pub);
        }
      }

      final user = usersBox?.get(pub);
      if (user != null && now.difference(user.updatedAt) < profileCacheTTL) {
        final data = {
          'name': user.name,
          'profileImage': user.profileImage,
          'about': user.about,
          'nip05': user.nip05,
          'banner': user.banner,
          'lud16': user.lud16,
          'website': user.website,
        };
        profileCache[pub] = CachedProfile(data, user.updatedAt);
        continue;
      }

      needsFetching.add(pub);
    }

    if (needsFetching.isEmpty) {
      profilesNotifier.value = {
        for (var entry in profileCache.entries) entry.key: UserModel.fromCachedProfile(entry.key, entry.value.data)
      };
      return;
    }

    final fetchFuture = _batchFetchProfiles(needsFetching);
    for (final pub in needsFetching) {
      _pendingProfileFetches[pub] = fetchFuture;
    }

    try {
      await fetchFuture;
    } finally {
      for (final pub in needsFetching) {
        _pendingProfileFetches.remove(pub);
      }
    }
  }

  Future<void> _batchFetchProfiles(List<String> npubs) async {
    final stillRemaining = npubs.toList();

    if (stillRemaining.isNotEmpty) {
      final filter = NostrService.createProfileFilter(
        authors: stillRemaining,
        limit: stillRemaining.length,
      );
      await _broadcastRequest(NostrService.serializeRequest(NostrService.createRequest(filter)));
      print('[DataService] Relay profile fetch for ${stillRemaining.length} npubs.');
    }

    profilesNotifier.value = {for (var entry in profileCache.entries) entry.key: UserModel.fromCachedProfile(entry.key, entry.value.data)};
  }

  Future<void> _handleEvent(dynamic event, List<String> targetNpubs) async {
    if (_isClosed) return;
    try {
      await _eventProcessorReady.future;

      _pendingEvents.add({
        'eventRaw': event,
        'targetNpubs': targetNpubs,
        'priority': 1,
      });

      if (_pendingEvents.length >= 50) {
        _flushPendingEvents();
      } else {
        _batchTimer ??= Timer(const Duration(milliseconds: 25), _flushPendingEvents);
      }
    } catch (e) {}
  }

  void _flushPendingEvents() {
    if (_pendingEvents.isNotEmpty) {
      final batch = List<Map<String, dynamic>>.from(_pendingEvents);
      _pendingEvents.clear();

      Future.microtask(() => _eventProcessorSendPort.send(batch));
    }
    _batchTimer?.cancel();
    _batchTimer = null;
  }

  Future<void> _handleFollowingEvent(Map<String, dynamic> eventData) async {
    try {
      List<String> newFollowing = [];
      final tags = eventData['tags'] as List<dynamic>;
      for (var tag in tags) {
        if (tag is List && tag.isNotEmpty && tag[0] == 'p') {
          if (tag.length > 1) {
            newFollowing.add(tag[1] as String);
          }
        }
      }
      if (followingBox != null && followingBox!.isOpen) {
        final model = FollowingModel(pubkeys: newFollowing, updatedAt: DateTime.now(), npub: npub);
        await followingBox!.put('following', model);
        print('[DataService] Following model updated with new event.');
      }
    } catch (e) {
      print('[DataService ERROR] Error handling following event: $e');
    }
  }

  Future<void> _handleReactionEvent(Map<String, dynamic> eventData) async {
    if (_isClosed) return;
    try {
      final targetEventId = (eventData['tags'] as List<dynamic>?)
          ?.firstWhere((tag) => tag is List && tag.length >= 2 && tag[0] == 'e', orElse: () => null)?[1] as String?;

      if (targetEventId == null) return;

      final reaction = ReactionModel.fromEvent(eventData);

      if (_pendingOptimisticReactionIds.contains(reaction.id)) {
        _pendingOptimisticReactionIds.remove(reaction.id);
        return;
      }

      reactionsMap.putIfAbsent(targetEventId, () => []);

      if (!reactionsMap[targetEventId]!.any((r) => r.id == reaction.id)) {
        reactionsMap[targetEventId]!.add(reaction);

        final note = notes.firstWhereOrNull((n) => n.id == targetEventId);
        if (note != null) {
          note.reactionCount = reactionsMap[targetEventId]!.length;
        }

        InteractionsProvider.instance.updateReactions(targetEventId, reactionsMap[targetEventId]!);

        reactionsBox?.put(reaction.id, reaction).catchError((e) {/* silent */});
        fetchProfilesBatch([reaction.author]);

        _hasPendingUiUpdate = true;
      }
    } catch (e) {
      print('[DataService ERROR] Error handling reaction event: $e');
    }
  }

  Future<void> _handleRepostEvent(Map<String, dynamic> eventData) async {
    if (_isClosed) return;
    try {
      final originalNoteId = (eventData['tags'] as List<dynamic>?)
          ?.firstWhere((tag) => tag is List && tag.length >= 2 && tag[0] == 'e', orElse: () => null)?[1] as String?;

      if (originalNoteId == null) return;

      final repost = RepostModel.fromEvent(eventData, originalNoteId);
      repostsMap.putIfAbsent(originalNoteId, () => []);

      if (!repostsMap[originalNoteId]!.any((r) => r.id == repost.id)) {
        repostsMap[originalNoteId]!.add(repost);

        final note = notes.firstWhereOrNull((n) => n.id == originalNoteId);
        if (note != null) {
          note.repostCount = repostsMap[originalNoteId]!.length;
        }

        InteractionsProvider.instance.updateReposts(originalNoteId, repostsMap[originalNoteId]!);

        repostsBox?.put(repost.id, repost).catchError((e) {/* silent */});
        fetchProfilesBatch([repost.repostedBy]);

        _hasPendingUiUpdate = true;
      }
    } catch (e) {
      print('[DataService ERROR] Error handling repost event: $e');
    }
  }

  Future<void> _handleReplyEvent(Map<String, dynamic> eventData, String parentEventId) async {
    if (_isClosed) return;
    try {
      final reply = ReplyModel.fromEvent(eventData);
      repliesMap.putIfAbsent(parentEventId, () => []);

      if (!repliesMap[parentEventId]!.any((r) => r.id == reply.id)) {
        repliesMap[parentEventId]!.add(reply);
        final parentNote = notes.firstWhereOrNull((n) => n.id == parentEventId);
        if (parentNote != null) {
          parentNote.replyCount = repliesMap[parentEventId]!.length;
        }

        InteractionsProvider.instance.updateReplies(parentEventId, repliesMap[parentEventId]!);

        final noteModel = NoteModel(
          id: reply.id,
          content: reply.content,
          author: reply.author,
          timestamp: reply.timestamp,
          isReply: true,
          parentId: parentEventId,
          rootId: reply.rootEventId,
          rawWs: jsonEncode(eventData),
        );

        if (eventIds.add(noteModel.id)) {
          notes.add(noteModel);
          notesNotifier.addNoteQuietly(noteModel);
        }

        repliesBox?.put(reply.id, reply).catchError((e) {/* silent */});
        notesBox?.put(noteModel.id, noteModel).catchError((e) {/* silent */});
        fetchProfilesBatch([reply.author]);

        _hasPendingUiUpdate = true;
      }
    } catch (e) {
      print('[DataService ERROR] Error handling reply event: $e');
    }
  }

  Future<void> _handleProfileEvent(Map<String, dynamic> eventData) async {
    if (_isClosed) return;
    try {
      final author = eventData['pubkey'] as String;
      final createdAt = DateTime.fromMillisecondsSinceEpoch((eventData['created_at'] as int) * 1000);

      final cachedProfile = profileCache[author];
      if (cachedProfile != null && createdAt.isBefore(cachedProfile.fetchedAt)) {
        return;
      }

      Map<String, dynamic> profileContent;
      try {
        profileContent = jsonDecode(eventData['content'] as String) as Map<String, dynamic>;
      } catch (e) {
        profileContent = {};
      }

      final dataToCache = {
        'name': profileContent['name'] as String? ?? 'Anonymous',
        'profileImage': profileContent['picture'] as String? ?? '',
        'about': profileContent['about'] as String? ?? '',
        'nip05': profileContent['nip05'] as String? ?? '',
        'banner': profileContent['banner'] as String? ?? '',
        'lud16': profileContent['lud16'] as String? ?? '',
        'website': profileContent['website'] as String? ?? '',
      };

      profileCache[author] = CachedProfile(dataToCache, createdAt);

      if (usersBox != null && usersBox!.isOpen) {
        final userModel = UserModel.fromCachedProfile(author, dataToCache);
        usersBox!.put(author, userModel);
      }

      if (_pendingProfileRequests.containsKey(author)) {
        _pendingProfileRequests[author]?.complete(dataToCache);
        _pendingProfileRequests.remove(author);
      }

      _hasPendingUiUpdate = true;
    } catch (e) {
      print('[DataService ERROR] Error handling profile event: $e');
    }
  }

  Future<Map<String, String>> getCachedUserProfile(String npub) async {
    if (_isClosed) return _getDefaultProfile();

    try {
      return await _profileService.getCachedUserProfile(npub);
    } catch (e) {
      print('[DataService] ProfileService error, using fallback: $e');

      final now = DateTime.now();

      if (profileCache.containsKey(npub)) {
        final cached = profileCache[npub]!;
        if (now.difference(cached.fetchedAt) < profileCacheTTL) {
          return cached.data;
        } else {
          profileCache.remove(npub);
        }
      }

      if (usersBox != null && usersBox!.isOpen) {
        try {
          final user = usersBox!.get(npub);
          if (user != null && now.difference(user.updatedAt) < profileCacheTTL) {
            final data = {
              'name': user.name,
              'profileImage': user.profileImage,
              'about': user.about,
              'nip05': user.nip05,
              'banner': user.banner,
              'lud16': user.lud16,
              'website': user.website,
            };
            profileCache[npub] = CachedProfile(data, user.updatedAt);
            return data;
          }
        } catch (e) {
          print('[DataService] Error reading from usersBox: $e');
        }
      }

      return _getDefaultProfile();
    }
  }

  Map<String, String> _getDefaultProfile() {
    return {
      'name': 'Anonymous',
      'profileImage': '',
      'about': '',
      'nip05': '',
      'banner': '',
      'lud16': '',
      'website': '',
    };
  }

  Future<NoteModel?> getCachedNote(String eventIdHex) async {
    final inMemory = notes.firstWhereOrNull((n) => n.id == eventIdHex);
    if (inMemory != null) return inMemory;

    if (notesBox != null && notesBox!.isOpen) {
      final inHive = notesBox!.get(eventIdHex);
      if (inHive != null) {
        if (!eventIds.contains(inHive.id)) {
          inHive.hasMedia = inHive.hasMediaLazy;
          notes.add(inHive);
          eventIds.add(inHive.id);
          addNote(inHive);
        }
        return inHive;
      }
    }

    final fetchedNote = await fetchNoteByIdIndependently(eventIdHex);
    if (fetchedNote == null) return null;

    fetchedNote.hasMedia = fetchedNote.hasMediaLazy;
    notes.add(fetchedNote);
    eventIds.add(fetchedNote.id);
    await notesBox?.put(fetchedNote.id, fetchedNote);
    addNote(fetchedNote);

    print('[DataService] Fetched and added note to cache: ${fetchedNote.id}');
    return fetchedNote;
  }

  Future<List<String>> getFollowingList(String targetNpub) async {
    if (targetNpub != npub) {
      print('[DataService] Skipping following fetch for non-logged-in user: $targetNpub');
      return [];
    }

    if (followingBox != null && followingBox!.isOpen) {
      final cachedFollowing = followingBox!.get('following_$targetNpub');
      if (cachedFollowing != null) {
        print('[DataService] Using cached following list for $targetNpub.');
        return cachedFollowing.pubkeys;
      }
    }

    List<String> following = [];
    final limitedRelays = _socketManager.relayUrls.take(3).toList();

    await Future.wait(limitedRelays.map((relayUrl) async {
      WebSocket? ws;
      StreamSubscription? sub;
      try {
        ws = await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 3));
        if (_isClosed) {
          try {
            await ws.close();
          } catch (_) {}
          return;
        }
        final filter = NostrService.createFollowingFilter(authors: [targetNpub], limit: 1000);
        final request = NostrService.serializeRequest(NostrService.createRequest(filter));
        final completer = Completer<void>();

        sub = ws.listen((event) {
          try {
            if (completer.isCompleted) return;
            final decoded = jsonDecode(event);
            if (decoded[0] == 'EVENT') {
              for (var tag in decoded[2]['tags']) {
                if (tag is List && tag.isNotEmpty && tag[0] == 'p') {
                  following.add(tag[1] as String);
                }
              }
              completer.complete();
            }
          } catch (e) {
            if (!completer.isCompleted) completer.complete();
          }
        }, onDone: () {
          if (!completer.isCompleted) completer.complete();
        }, onError: (error) {
          if (!completer.isCompleted) completer.complete();
        }, cancelOnError: true);

        if (ws.readyState == WebSocket.open) {
          ws.add(request);
        }

        await completer.future.timeout(const Duration(seconds: 3), onTimeout: () {});

        try {
          await sub.cancel();
        } catch (_) {}

        try {
          await ws.close();
        } catch (_) {}
      } catch (e) {
        try {
          await sub?.cancel();
        } catch (_) {}
        try {
          await ws?.close();
        } catch (_) {}
      }
    }));

    following = following.toSet().toList();

    if (followingBox != null && followingBox!.isOpen) {
      final newFollowingModel = FollowingModel(pubkeys: following, updatedAt: DateTime.now(), npub: targetNpub);
      await followingBox!.put('following_$targetNpub', newFollowingModel);
      print('[DataService] Updated Hive following model for $targetNpub.');
    }
    return following;
  }

  Future<List<String>> getGlobalFollowers(String targetNpub) async {
    if (_isClosed) {
      print('[DataService] Service is closed. Skipping global follower fetch.');
      return [];
    }

    List<String> followers = [];
    final allRelays = _socketManager.relayUrls;

    await Future.wait(allRelays.map((relayUrl) async {
      WebSocket? ws;
      StreamSubscription? sub;
      try {
        ws = await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 2));

        if (_isClosed) {
          try {
            await ws.close();
          } catch (_) {}
          return;
        }

        final filter = NostrService.createFollowingFilter(
          authors: [targetNpub],
          limit: 1000,
        );

        final request = NostrService.serializeRequest(NostrService.createRequest(filter));
        final completer = Completer<void>();

        sub = ws.listen((event) {
          try {
            if (completer.isCompleted) return;
            final decoded = jsonDecode(event);
            if (decoded[0] == 'EVENT') {
              final author = decoded[2]['pubkey'];
              followers.add(author);
            }
            if (decoded[0] == 'EOSE') {
              completer.complete();
            }
          } catch (e) {
            if (!completer.isCompleted) completer.complete();
          }
        }, onDone: () {
          if (!completer.isCompleted) completer.complete();
        }, onError: (error) {
          if (!completer.isCompleted) completer.complete();
        }, cancelOnError: true);

        if (ws.readyState == WebSocket.open) {
          ws.add(request);
        }

        await completer.future.timeout(const Duration(seconds: 3), onTimeout: () {});

        try {
          await sub.cancel();
        } catch (_) {}

        try {
          await ws.close();
        } catch (_) {}
      } catch (e) {
        try {
          await sub?.cancel();
        } catch (_) {}
        try {
          await ws?.close();
        } catch (_) {}
      }
    }));

    followers = followers.toSet().toList();

    return followers;
  }

  bool _isLoadingMore = false;
  final Map<String, List<NoteModel>> _preloadedNotes = {};

  bool _infiniteScrollEnabled = true;
  Timer? _scrollDebounceTimer;
  final ValueNotifier<bool> isLoadingNotifier = ValueNotifier(false);

  Future<void> loadMoreNotes() async {
    if (_isClosed || _isLoadingMore) return;

    _isLoadingMore = true;
    final stopwatch = Stopwatch()..start();

    try {
      final cacheKey = '${dataType.toString()}_$npub';
      if (_preloadedNotes.containsKey(cacheKey) && _preloadedNotes[cacheKey]!.isNotEmpty) {
        final preloaded = _preloadedNotes[cacheKey]!.take(25).toList();
        _preloadedNotes[cacheKey]!.removeRange(0, preloaded.length.clamp(0, _preloadedNotes[cacheKey]!.length));

        for (final note in preloaded) {
          if (!eventIds.contains(note.id)) {
            notes.add(note);
            eventIds.add(note.id);
            addNote(note);
          }
        }

        print('[DataService] INSTANT: Added ${preloaded.length} preloaded notes in ${stopwatch.elapsedMilliseconds}ms');

        _preloadNextBatch();
        return;
      }

      List<String> targetNpubs;
      if (dataType == DataType.feed) {
        final following = await getFollowingList(npub);
        following.add(npub);
        targetNpubs = following.toSet().toList();
      } else {
        targetNpubs = [npub];
      }

      final until = _getOldestNoteTimestamp();
      final increment = 75;

      print('[DataService] FAST: Loading $increment notes, until=$until');

      final fetchFutures = <Future>[];

      if (dataType == DataType.profile) {
        fetchFutures.add(_fetchProfileNotesDirectly(npub, limit: increment, until: until));
        fetchFutures.add(_checkCacheForOlderNotes(npub, until));
      } else {
        fetchFutures.add(_parallelFeedFetch(targetNpubs, increment, until));
        fetchFutures.add(_checkCacheForOlderNotes(null, until));
      }

      await Future.wait(fetchFutures, eagerError: false);

      _preloadNextBatch();

      print('[DataService] FAST: Load more completed in ${stopwatch.elapsedMilliseconds}ms');

      if (notes.length > 500) {
        Future.microtask(() => _performMemoryPressureRelief());
      }
    } finally {
      _isLoadingMore = false;
    }
  }

  DateTime? _getOldestNoteTimestamp() {
    if (notes.isEmpty) return null;
    final sortedNotes = notes.toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return sortedNotes.first.timestamp;
  }

  Future<void> _parallelFeedFetch(List<String> targetNpubs, int limit, DateTime? until) async {
    final filter = NostrService.createNotesFilter(
      authors: targetNpubs,
      kinds: [1, 6],
      limit: limit,
      until: until != null ? until.millisecondsSinceEpoch ~/ 1000 : null,
    );

    final request = NostrService.serializeRequest(NostrService.createRequest(filter));
    final activeSockets = _socketManager.activeSockets;

    final futures = activeSockets.map((ws) {
      if (ws.readyState == WebSocket.open) {
        ws.add(request);
      }
      return Future.value();
    }).toList();

    await Future.wait(futures, eagerError: false);
  }

  Future<void> _checkCacheForOlderNotes(String? specificNpub, DateTime? until) async {
    if (notesBox == null || !notesBox!.isOpen) return;

    try {
      final cachedNotes = notesBox!.values.where((note) {
        if (until != null && note.timestamp.isAfter(until)) return false;

        if (dataType == DataType.profile && specificNpub != null) {
          return note.author == specificNpub || (note.isRepost && note.repostedBy == specificNpub);
        }

        return true;
      }).toList();

      cachedNotes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final relevantCached = cachedNotes.take(25).toList();

      for (final note in relevantCached) {
        if (!eventIds.contains(note.id)) {
          note.hasMedia = note.hasMediaLazy;
          notes.add(note);
          eventIds.add(note.id);
          addNote(note);
        }
      }

      if (relevantCached.isNotEmpty) {
        print('[DataService] CACHE: Added ${relevantCached.length} cached notes');
      }
    } catch (e) {
      print('[DataService] Cache check error: $e');
    }
  }

  void _preloadNextBatch() {
    if (_isClosed) return;

    Future.microtask(() async {
      try {
        final cacheKey = '${dataType.toString()}_$npub';
        if (_preloadedNotes[cacheKey]?.isNotEmpty == true) return;

        final until = _getOldestNoteTimestamp();
        if (until == null) return;

        if (notesBox != null && notesBox!.isOpen) {
          final preloadCandidates = notesBox!.values.where((note) {
            if (note.timestamp.isAfter(until)) return false;
            if (eventIds.contains(note.id)) return false;

            if (dataType == DataType.profile) {
              return note.author == npub || (note.isRepost && note.repostedBy == npub);
            }
            return true;
          }).toList();

          preloadCandidates.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          _preloadedNotes[cacheKey] = preloadCandidates.take(50).toList();

          if (_preloadedNotes[cacheKey]!.isNotEmpty) {
            print('[DataService] PRELOAD: Prepared ${_preloadedNotes[cacheKey]!.length} notes for next load');
          }
        }
      } catch (e) {
        print('[DataService] Preload error: $e');
      }
    });
  }

  void onScrollPositionChanged(double scrollPosition, double maxScrollExtent) {
    if (!_infiniteScrollEnabled || _isClosed) return;

    _scrollDebounceTimer?.cancel();

    _scrollDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      _checkScrollThreshold(scrollPosition, maxScrollExtent);
    });
  }

  void _checkScrollThreshold(double scrollPosition, double maxScrollExtent) {
    if (_isClosed || _isLoadingMore) return;

    final threshold = maxScrollExtent * 0.8;

    if (scrollPosition >= threshold && scrollPosition > 0) {
      print('[DataService] INFINITE SCROLL: Triggered at ${(scrollPosition / maxScrollExtent * 100).toInt()}%');
      _triggerAutoLoad();
    }
  }

  void _triggerAutoLoad() {
    if (_isLoadingMore || _isClosed) return;

    isLoadingNotifier.value = true;

    loadMoreNotes().then((_) {
      isLoadingNotifier.value = false;
    }).catchError((e) {
      isLoadingNotifier.value = false;
      print('[DataService] Auto-load error: $e');
    });
  }

  void enablePreemptiveLoading() {
    if (_isClosed) return;

    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_isClosed) {
        timer.cancel();
        return;
      }

      final cacheKey = '${dataType.toString()}_$npub';
      final preloadedCount = _preloadedNotes[cacheKey]?.length ?? 0;

      if (preloadedCount < 20 && !_isLoadingMore) {
        _preloadNextBatch();
      }
    });
  }

  void enableInfiniteScroll() => _infiniteScrollEnabled = true;
  void disableInfiniteScroll() => _infiniteScrollEnabled = false;
  bool get isInfiniteScrollEnabled => _infiniteScrollEnabled;

  bool _isRefreshing = false;
  final ValueNotifier<bool> isRefreshingNotifier = ValueNotifier(false);
  DateTime? _lastRefreshTime;
  final Duration _refreshCooldown = const Duration(seconds: 2);

  Future<void> refreshNotes() async {
    if (_isClosed || _isRefreshing) return;

    if (_lastRefreshTime != null) {
      final timeSinceLastRefresh = DateTime.now().difference(_lastRefreshTime!);
      if (timeSinceLastRefresh < _refreshCooldown) {
        print('[DataService] REFRESH: Cooldown active, skipping refresh');
        return;
      }
    }

    _isRefreshing = true;
    isRefreshingNotifier.value = true;
    _lastRefreshTime = DateTime.now();

    final stopwatch = Stopwatch()..start();

    try {
      print('[DataService] REFRESH: Starting pull to refresh');

      _preloadedNotes.clear();

      List<String> targetNpubs;
      if (dataType == DataType.feed) {
        final following = await getFollowingList(npub);
        following.add(npub);
        targetNpubs = following.toSet().toList();
      } else {
        targetNpubs = [npub];
      }

      DateTime? since;
      if (notes.isNotEmpty) {
        final sortedNotes = notes.toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        since = sortedNotes.first.timestamp;
      }

      final refreshFutures = <Future>[];

      if (dataType == DataType.profile) {
        refreshFutures.add(_refreshProfileNotes(npub, since));
      } else {
        refreshFutures.add(_refreshFeedNotes(targetNpubs, since));
      }

      refreshFutures.add(_refreshInteractionsForCurrentNotes());

      refreshFutures.add(_refreshProfilesInBackground());

      await Future.wait(refreshFutures, eagerError: false);

      Future.microtask(() => _preloadNextBatch());

      print('[DataService] REFRESH: Completed in ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      print('[DataService] REFRESH: Error during refresh: $e');
    } finally {
      _isRefreshing = false;
      isRefreshingNotifier.value = false;
    }
  }

  Future<void> _refreshProfileNotes(String userNpub, DateTime? since) async {
    final filter = NostrService.createNotesFilter(
      authors: [userNpub],
      kinds: [1, 6],
      limit: 100,
      since: since != null ? since.millisecondsSinceEpoch ~/ 1000 : null,
    );

    final request = NostrService.serializeRequest(NostrService.createRequest(filter));
    final activeSockets = _socketManager.activeSockets;

    final futures = activeSockets.map((ws) {
      if (ws.readyState == WebSocket.open) {
        ws.add(request);
      }
      return Future.value();
    }).toList();

    await Future.wait(futures, eagerError: false);
    print('[DataService] REFRESH: Profile notes request sent to ${activeSockets.length} relays');
  }

  Future<void> _refreshFeedNotes(List<String> targetNpubs, DateTime? since) async {
    final filter = NostrService.createNotesFilter(
      authors: targetNpubs,
      kinds: [1, 6],
      limit: 100,
      since: since != null ? since.millisecondsSinceEpoch ~/ 1000 : null,
    );

    final request = NostrService.serializeRequest(NostrService.createRequest(filter));
    final activeSockets = _socketManager.activeSockets;

    final futures = activeSockets.map((ws) {
      if (ws.readyState == WebSocket.open) {
        ws.add(request);
      }
      return Future.value();
    }).toList();

    await Future.wait(futures, eagerError: false);
    print('[DataService] REFRESH: Feed notes request sent to ${activeSockets.length} relays');
  }

  Future<void> _refreshInteractionsForCurrentNotes() async {
    if (notes.isEmpty) return;

    final recentNotes = notes.where((note) {
      return DateTime.now().difference(note.timestamp).inHours < 24;
    }).toList();

    if (recentNotes.isEmpty) return;

    final noteIds = recentNotes.map((note) => note.id).toList();

    final interactionFutures = [
      _refreshReactionsForNotes(noteIds),
      _refreshRepliesForNotes(noteIds),
      _refreshRepostsForNotes(noteIds),
      _refreshZapsForNotes(noteIds),
    ];

    await Future.wait(interactionFutures, eagerError: false);
    print('[DataService] REFRESH: Interactions refreshed for ${noteIds.length} recent notes');
  }

  Future<void> _refreshReactionsForNotes(List<String> noteIds) async {
    final filter = NostrService.createReactionFilter(eventIds: noteIds, limit: 500);
    await _broadcastRequest(NostrService.serializeRequest(NostrService.createRequest(filter)));
  }

  Future<void> _refreshRepliesForNotes(List<String> noteIds) async {
    final filter = NostrService.createReplyFilter(eventIds: noteIds, limit: 500);
    await _broadcastRequest(NostrService.serializeRequest(NostrService.createRequest(filter)));
  }

  Future<void> _refreshRepostsForNotes(List<String> noteIds) async {
    final filter = NostrService.createRepostFilter(eventIds: noteIds, limit: 500);
    await _broadcastRequest(NostrService.serializeRequest(NostrService.createRequest(filter)));
  }

  Future<void> _refreshZapsForNotes(List<String> noteIds) async {
    final filter = NostrService.createZapFilter(eventIds: noteIds, limit: 500);
    await _broadcastRequest(NostrService.serializeRequest(NostrService.createRequest(filter)));
  }

  Future<void> _refreshProfilesInBackground() async {
    final recentAuthors =
        notes.where((note) => DateTime.now().difference(note.timestamp).inHours < 6).map((note) => note.author).toSet().toList();

    if (recentAuthors.isNotEmpty) {
      await fetchProfilesBatch(recentAuthors);
      print('[DataService] REFRESH: Profiles refreshed for ${recentAuthors.length} authors');
    }
  }

  Future<void> forceRefresh() async {
    _lastRefreshTime = null;
    await refreshNotes();
  }

  bool get canRefresh {
    if (_lastRefreshTime == null) return true;
    final timeSinceLastRefresh = DateTime.now().difference(_lastRefreshTime!);
    return timeSinceLastRefresh >= _refreshCooldown;
  }

  Duration? get timeUntilNextRefresh {
    if (_lastRefreshTime == null) return null;
    final timeSinceLastRefresh = DateTime.now().difference(_lastRefreshTime!);
    if (timeSinceLastRefresh >= _refreshCooldown) return null;
    return _refreshCooldown - timeSinceLastRefresh;
  }

  Future<void> _performMemoryPressureRelief() async {
    if (notes.length <= 1000) return;

    print('[DataService] Performing memory pressure relief: ${notes.length} notes');

    final sortedNotes = notes.toList()
      ..sort((a, b) {
        final aTime = a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
        final bTime = b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
        return bTime.compareTo(aTime);
      });

    final notesToKeep = sortedNotes.take(500).toList();
    final notesToRemove = sortedNotes.skip(500).toList();

    notes.clear();
    eventIds.clear();
    _itemsTree.clear();

    for (final note in notesToKeep) {
      notes.add(note);
      eventIds.add(note.id);
      _itemsTree.add(note);
    }

    final removedIds = notesToRemove.map((n) => n.id).toSet();

    if (removedIds.isNotEmpty) {
      reactionsMap.removeWhere((noteId, reactions) => removedIds.contains(noteId));
      repliesMap.removeWhere((noteId, replies) => removedIds.contains(noteId));
      repostsMap.removeWhere((noteId, reposts) => removedIds.contains(noteId));
      zapsMap.removeWhere((noteId, zaps) => removedIds.contains(noteId));

      print('[DataService] Cleared interactions for ${removedIds.length} removed notes from memory.');
    }

    _invalidateFilterCache();
    notesNotifier.value = notesNotifier._getFilteredNotesList();

    print('[DataService] Memory relief completed: ${notes.length} notes remaining');
  }

  final SplayTreeSet<NoteModel> _itemsTree = SplayTreeSet(_compareNotes);
  late final NoteListNotifier notesNotifier;
  final ValueNotifier<Map<String, UserModel>> profilesNotifier = ValueNotifier({});
  final ValueNotifier<List<NotificationModel>> notificationsNotifier = ValueNotifier([]);
  final ValueNotifier<int> unreadNotificationsCountNotifier = ValueNotifier(0);

  static int _compareNotes(NoteModel a, NoteModel b) {
    final aTime = a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
    final bTime = b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
    final result = bTime.compareTo(aTime);
    return result == 0 ? a.id.compareTo(b.id) : result;
  }

  void addNote(NoteModel note) {
    _itemsTree.add(note);

    notesNotifier.addNoteQuietly(note);
  }

  void _invalidateFilterCache() => notesNotifier._invalidateFilterCache();

  void _startCacheCleanup() {
    _cacheCleanupTimer?.cancel();
    _cacheCleanupTimer = Timer.periodic(cacheCleanupInterval, (timer) async {
      if (_isClosed) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      final cutoffTime = now.subtract(profileCacheTTL);

      profileCache.removeWhere((key, cached) => cached.fetchedAt.isBefore(cutoffTime));

      final expiredReactionKeys = <String>[];
      final expiredReplyKeys = <String>[];

      if (reactionsBox?.isOpen == true) {
        for (final key in reactionsBox!.keys) {
          final reaction = reactionsBox!.get(key);
          if (reaction?.fetchedAt.isBefore(cutoffTime) == true) {
            expiredReactionKeys.add(key);
          }
        }
      }

      if (repliesBox?.isOpen == true) {
        for (final key in repliesBox!.keys) {
          final reply = repliesBox!.get(key);
          if (reply?.fetchedAt.isBefore(cutoffTime) == true) {
            expiredReplyKeys.add(key);
          }
        }
      }

      final cleanupFutures = <Future>[];
      if (expiredReactionKeys.isNotEmpty) {
        cleanupFutures.add(reactionsBox!.deleteAll(expiredReactionKeys));
      }
      if (expiredReplyKeys.isNotEmpty) {
        cleanupFutures.add(repliesBox!.deleteAll(expiredReplyKeys));
      }

      if (cleanupFutures.isNotEmpty) {
        await Future.wait(cleanupFutures);
      }

      reactionsMap.removeWhere((eventId, reactions) {
        reactions.removeWhere((reaction) => reaction.fetchedAt.isBefore(cutoffTime));
        return reactions.isEmpty;
      });

      repliesMap.removeWhere((eventId, replies) {
        replies.removeWhere((reply) => reply.fetchedAt.isBefore(cutoffTime));
        return replies.isEmpty;
      });
    });
  }

  void _startInteractionRefresh() {
    _interactionRefreshTimer?.cancel();
    _interactionRefreshTimer = Timer.periodic(const Duration(minutes: 2), (timer) async {
      if (_isClosed) {
        timer.cancel();
        return;
      }
      await _refreshAllInteractions();
    });
  }

  void _scheduleInteractionRefresh() {
    Future.delayed(const Duration(seconds: 30), () {
      if (!_isClosed) {
        _refreshAllInteractions();
      }
    });
  }

  Future<void> _refreshAllInteractions() async {
    if (_isClosed || notes.isEmpty) return;

    print('[DataService] Refreshing all interactions...');

    final allEventIds = notes.map((note) => note.id).toList();

    const batchSize = 25;
    final futures = <Future>[];

    for (int i = 0; i < allEventIds.length; i += batchSize) {
      final endIndex = (i + batchSize > allEventIds.length) ? allEventIds.length : i + batchSize;
      final batch = allEventIds.sublist(i, endIndex);

      if (batch.isNotEmpty) {
        final reactionFilter = NostrService.createReactionFilter(eventIds: batch, limit: 500);
        futures.add(_broadcastRequest(NostrService.serializeRequest(NostrService.createRequest(reactionFilter))));

        final replyFilter = NostrService.createReplyFilter(eventIds: batch, limit: 500);
        futures.add(_broadcastRequest(NostrService.serializeRequest(NostrService.createRequest(replyFilter))));

        final repostFilter = NostrService.createRepostFilter(eventIds: batch, limit: 500);
        futures.add(_broadcastRequest(NostrService.serializeRequest(NostrService.createRequest(repostFilter))));

        final zapFilter = NostrService.createZapFilter(eventIds: batch, limit: 500);
        futures.add(_broadcastRequest(NostrService.serializeRequest(NostrService.createRequest(zapFilter))));
      }

      if (futures.length >= 8) {
        await Future.wait(futures);
        futures.clear();
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }

    print('[DataService] Interaction refresh completed for ${allEventIds.length} notes.');
  }

  Future<void> forceRefreshInteractions() async {
    await _refreshAllInteractions();
  }

  Future<void> shareNote(String noteContent) async {
    if (_isClosed) return;
    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final event = NostrService.createNoteEvent(
        content: noteContent,
        privateKey: privateKey,
      );
      final serializedEvent = NostrService.serializeEvent(event);
      await initializeConnections();
      await _socketManager.broadcast(serializedEvent);

      final timestamp = DateTime.now();
      final eventJson = NostrService.eventToJson(event);
      final newNote = NoteModel(
        id: eventJson['id'],
        content: noteContent,
        author: npub,
        timestamp: timestamp,
        isRepost: false,
      );
      notes.add(newNote);
      eventIds.add(newNote.id);
      if (notesBox != null && notesBox!.isOpen) {
        await notesBox!.put(newNote.id, newNote);
      }
      onNewNote?.call(newNote);
      print('[DataService] Note shared successfully and added to cache.');
    } catch (e) {
      print('[DataService ERROR] Error sharing note: $e');
      throw e;
    }
  }

  Future<String> sendMedia(String filePath, String blossomUrl) async {
    final privateKey = await _secureStorage.read(key: 'privateKey');
    if (privateKey == null || privateKey.isEmpty) {
      throw Exception('Private key not found.');
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    final fileBytes = await file.readAsBytes();
    final sha256Hash = sha256.convert(fileBytes).toString();

    String mimeType = 'application/octet-stream';
    final lowerPath = filePath.toLowerCase();
    if (lowerPath.endsWith('.jpg') || lowerPath.endsWith('.jpeg')) {
      mimeType = 'image/jpeg';
    } else if (lowerPath.endsWith('.png')) {
      mimeType = 'image/png';
    } else if (lowerPath.endsWith('.gif')) {
      mimeType = 'image/gif';
    } else if (lowerPath.endsWith('.mp4')) {
      mimeType = 'video/mp4';
    }

    final expiration = DateTime.now().add(Duration(minutes: 10)).millisecondsSinceEpoch ~/ 1000;

    final authEvent = Event.from(
      kind: 24242,
      content: 'Upload ${file.uri.pathSegments.last}',
      tags: [
        ['t', 'upload'],
        ['x', sha256Hash],
        ['expiration', expiration.toString()],
      ],
      privkey: privateKey,
    );

    final encodedAuth = base64.encode(utf8.encode(jsonEncode(authEvent.toJson())));
    final authHeader = 'Nostr $encodedAuth';

    final cleanedUrl = blossomUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$cleanedUrl/upload');

    final httpClient = HttpClient();
    final request = await httpClient.putUrl(uri);

    request.headers.set(HttpHeaders.authorizationHeader, authHeader);
    request.headers.set(HttpHeaders.contentTypeHeader, mimeType);
    request.headers.set(HttpHeaders.contentLengthHeader, fileBytes.length);

    request.add(fileBytes);

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      throw Exception('Upload failed with status ${response.statusCode}: $responseBody');
    }

    final decoded = jsonDecode(responseBody);
    if (decoded is Map && decoded.containsKey('url')) {
      return decoded['url'];
    }

    throw Exception('Upload succeeded but response does not contain a valid URL.');
  }

  Future<void> sendProfileEdit({
    required String name,
    required String about,
    required String picture,
    String nip05 = '',
    String banner = '',
    String lud16 = '',
    String website = '',
  }) async {
    if (_isClosed) return;

    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final Map<String, dynamic> profileContent = {
        'name': name,
        'about': about,
        'picture': picture,
      };

      if (nip05.isNotEmpty) profileContent['nip05'] = nip05;
      if (banner.isNotEmpty) profileContent['banner'] = banner;
      if (lud16.isNotEmpty) profileContent['lud16'] = lud16;
      if (website.isNotEmpty) profileContent['website'] = website;

      final event = NostrService.createProfileEvent(
        profileContent: profileContent,
        privateKey: privateKey,
      );
      await initializeConnections();
      await _socketManager.broadcast(NostrService.serializeEvent(event));

      final eventJson = NostrService.eventToJson(event);
      final updatedAt = DateTime.fromMillisecondsSinceEpoch(eventJson['created_at'] * 1000);

      final userModel = UserModel(
        npub: eventJson['pubkey'],
        name: name,
        about: about,
        profileImage: picture,
        nip05: nip05,
        banner: banner,
        lud16: lud16,
        website: website,
        updatedAt: updatedAt,
      );

      profileCache[eventJson['pubkey']] = CachedProfile(
        profileContent.map((key, value) => MapEntry(key, value.toString())),
        updatedAt,
      );

      if (usersBox != null && usersBox!.isOpen) {
        await usersBox!.put(eventJson['pubkey'], userModel);
      }

      profilesNotifier.value = {
        ...profilesNotifier.value,
        eventJson['pubkey']: userModel,
      };

      print('[DataService] Profile updated and sent successfully.');
    } catch (e, st) {
      print('[DataService ERROR] Error sending profile edit: $e\n$st');
      throw e;
    }
  }

  Future<void> sendFollow(String followNpub) async {
    if (_isClosed) return;

    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final currentFollowing = await getFollowingList(npub);
      if (currentFollowing.contains(followNpub)) {
        print('[DataService] Already following $followNpub');
        return;
      }

      currentFollowing.add(followNpub);

      currentFollowing.map((pubkey) => ['p', pubkey, '']).toList();

      final event = NostrService.createFollowEvent(
        followingPubkeys: currentFollowing,
        privateKey: privateKey,
      );
      await initializeConnections();

      await _socketManager.broadcast(NostrService.serializeEvent(event));

      final updatedFollowingModel = FollowingModel(
        pubkeys: currentFollowing,
        updatedAt: DateTime.now(),
        npub: npub,
      );
      await followingBox?.put('following_$npub', updatedFollowingModel);

      print('[DataService] Follow event sent and following list updated.');
    } catch (e) {
      print('[DataService ERROR] Error sending follow: $e');
      throw e;
    }
  }

  Future<void> sendUnfollow(String unfollowNpub) async {
    if (_isClosed) return;

    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final currentFollowing = await getFollowingList(npub);
      if (!currentFollowing.contains(unfollowNpub)) {
        print('[DataService] Not following $unfollowNpub');
        return;
      }

      currentFollowing.remove(unfollowNpub);

      currentFollowing.map((pubkey) => ['p', pubkey, '']).toList();

      final event = NostrService.createFollowEvent(
        followingPubkeys: currentFollowing,
        privateKey: privateKey,
      );
      await initializeConnections();

      await _socketManager.broadcast(NostrService.serializeEvent(event));

      final updatedFollowingModel = FollowingModel(
        pubkeys: currentFollowing,
        updatedAt: DateTime.now(),
        npub: npub,
      );
      await followingBox?.put('following_$npub', updatedFollowingModel);

      print('[DataService] Unfollow event sent and following list updated.');
    } catch (e) {
      print('[DataService ERROR] Error sending unfollow: $e');
      throw e;
    }
  }

  Future<String> sendZap({
    required String recipientPubkey,
    required String lud16,
    required int amountSats,
    String? noteId,
    String content = '',
  }) async {
    final privateKey = await _secureStorage.read(key: 'privateKey');
    if (privateKey == null || privateKey.isEmpty) {
      throw Exception('Private key not found.');
    }

    if (!lud16.contains('@')) {
      throw Exception('Invalid lud16 format.');
    }

    final parts = lud16.split('@');
    if (parts.length != 2 || parts.any((p) => p.isEmpty)) {
      throw Exception('Invalid lud16 format.');
    }

    final display_name = parts[0];
    final domain = parts[1];

    final uri = Uri.parse('https://$domain/.well-known/lnurlp/$display_name');
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('LNURL fetch failed with status: ${response.statusCode}');
    }

    final lnurlJson = jsonDecode(response.body);
    if (lnurlJson['allowsNostr'] != true || lnurlJson['nostrPubkey'] == null) {
      throw Exception('Recipient does not support zaps.');
    }

    final callback = lnurlJson['callback'];
    if (callback == null || callback.isEmpty) {
      throw Exception('Zap callback is missing.');
    }

    final lnurlBech32 = lnurlJson['lnurl'] ?? '';
    final amountMillisats = (amountSats * 1000).toString();
    final relays = relaySetMainSockets;

    if (relays.isEmpty) {
      throw Exception('No relays available for zap.');
    }

    final List<List<String>> tags = [
      ['relays', ...relays.map((e) => e.toString())],
      ['amount', amountMillisats],
      if (lnurlBech32.isNotEmpty) ['lnurl', lnurlBech32],
      ['p', recipientPubkey],
    ];

    if (noteId != null && noteId.isNotEmpty) {
      tags.add(['e', noteId]);
    }

    final zapRequest = NostrService.createZapRequestEvent(
      tags: tags,
      content: content,
      privateKey: privateKey,
    );

    final encodedZap = Uri.encodeComponent(jsonEncode(NostrService.eventToJson(zapRequest)));
    final zapUrl = Uri.parse(
      '$callback?amount=$amountMillisats&nostr=$encodedZap${lnurlBech32.isNotEmpty ? '&lnurl=$lnurlBech32' : ''}',
    );

    final invoiceResponse = await http.get(zapUrl);
    if (invoiceResponse.statusCode != 200) {
      throw Exception('Zap callback failed: ${invoiceResponse.body}');
    }

    final invoiceJson = jsonDecode(invoiceResponse.body);
    final invoice = invoiceJson['pr'];
    if (invoice == null || invoice.toString().isEmpty) {
      throw Exception('Invoice not returned by zap server.');
    }

    print('[sendZap] Invoice ready: $invoice');
    return invoice;
  }

  Future<void> sendReaction(String targetEventId, String reactionContent) async {
    if (_isClosed) return;
    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final event = NostrService.createReactionEvent(
        targetEventId: targetEventId,
        content: reactionContent,
        privateKey: privateKey,
      );
      await initializeConnections();
      await _socketManager.broadcast(NostrService.serializeEvent(event));

      final reaction = ReactionModel.fromEvent(NostrService.eventToJson(event));
      reactionsMap.putIfAbsent(targetEventId, () => []);
      reactionsMap[targetEventId]!.add(reaction);
      await reactionsBox?.put(reaction.id, reaction);

      final note = notes.firstWhereOrNull((n) => n.id == targetEventId);
      if (note != null) {
        note.reactionCount = reactionsMap[targetEventId]!.length;
      }

      onReactionsUpdated?.call(targetEventId, reactionsMap[targetEventId]!);
      _invalidateFilterCache();
      _invalidateFilterCache();
      notesNotifier.value = notesNotifier.notes;
    } catch (e) {
      print('[DataService ERROR] Error sending reaction: $e');
      throw e;
    }
  }

  Future<void> sendReactionInstantly(String targetEventId, String reactionContent) async {
    if (_isClosed) return;
    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final event = NostrService.createReactionEvent(
        targetEventId: targetEventId,
        content: reactionContent,
        privateKey: privateKey,
      );

      final serializedEvent = NostrService.serializeEvent(event);
      final activeSockets = _socketManager.activeSockets;
      for (final ws in activeSockets) {
        if (ws.readyState == WebSocket.open) {
          ws.add(serializedEvent);
        }
      }
      print('[DataService] Reaction broadcasted to ${activeSockets.length} relays');

      final reaction = ReactionModel.fromEvent(NostrService.eventToJson(event));

      _pendingOptimisticReactionIds.add(reaction.id);

      reactionsMap.putIfAbsent(targetEventId, () => []);
      reactionsMap[targetEventId]!.add(reaction);

      if (reactionsBox != null) {
        reactionsBox!.put(reaction.id, reaction).catchError((error) {
          print('[DataService] Error saving optimistic reaction to cache: $error');
        });
      }

      final note = notes.firstWhereOrNull((n) => n.id == targetEventId);
      if (note != null) {
        note.reactionCount = reactionsMap[targetEventId]!.length;
      }

      onReactionsUpdated?.call(targetEventId, reactionsMap[targetEventId]!);
      notesNotifier.value = notesNotifier.notes;
    } catch (e) {
      print('[DataService ERROR] Error sending reaction instantly: $e');
      throw e;
    }
  }

  Future<void> sendReplyInstantly(String parentEventId, String replyContent) async {
    if (_isClosed) return;
    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final parentNote = notes.firstWhereOrNull((note) => note.id == parentEventId);
      if (parentNote == null) {
        throw Exception('Parent note not found.');
      }

      String rootId;
      String replyId = parentEventId;

      if (parentNote.isReply && parentNote.rootId != null) {
        rootId = parentNote.rootId!;
      } else {
        rootId = parentEventId;
      }

      List<List<String>> tags = [];

      if (rootId != replyId) {
        tags.add(['e', rootId, '', 'root']);
        tags.add(['e', replyId, '', 'reply']);
      } else {
        tags.add(['e', rootId, '', 'root']);
      }

      tags.add(['p', parentNote.author, '', 'mention']);

      for (final relayUrl in relaySetMainSockets) {
        tags.add(['r', relayUrl]);
      }

      final event = NostrService.createReplyEvent(
        content: replyContent,
        privateKey: privateKey,
        tags: tags,
      );

      final serializedEvent = NostrService.serializeEvent(event);
      final activeSockets = _socketManager.activeSockets;

      for (final ws in activeSockets) {
        if (ws.readyState == WebSocket.open) {
          ws.add(serializedEvent);
        }
      }

      final reply = ReplyModel.fromEvent(NostrService.eventToJson(event));
      repliesMap.putIfAbsent(parentEventId, () => []);
      repliesMap[parentEventId]!.add(reply);

      if (repliesBox != null) {
        repliesBox!.put(reply.id, reply).catchError((error) {
          print('[DataService] Error saving reply to cache: $error');
        });
      }

      final replyNoteModel = NoteModel(
        id: reply.id,
        content: reply.content,
        author: reply.author,
        timestamp: reply.timestamp,
        isReply: true,
        parentId: parentEventId,
        rootId: rootId,
        rawWs: jsonEncode(NostrService.eventToJson(event)),
      );

      replyNoteModel.hasMedia = replyNoteModel.hasMediaLazy;

      if (!eventIds.contains(replyNoteModel.id)) {
        notes.add(replyNoteModel);
        eventIds.add(replyNoteModel.id);
        if (notesBox != null) {
          notesBox!.put(replyNoteModel.id, replyNoteModel).catchError((error) {
            print('[DataService] Error saving reply note to cache: $error');
          });
        }
        addNote(replyNoteModel);
      }

      final note = notes.firstWhereOrNull((n) => n.id == parentEventId);
      if (note != null) {
        note.replyCount = repliesMap[parentEventId]!.length;
        if (!note.replyIds.contains(reply.id)) {
          note.replyIds.add(reply.id);
        }
      }

      if (rootId != parentEventId) {
        final rootNote = notes.firstWhereOrNull((n) => n.id == rootId);
        if (rootNote != null && !rootNote.replyIds.contains(reply.id)) {
          rootNote.replyIds.add(reply.id);
        }
      }

      onRepliesUpdated?.call(parentEventId, repliesMap[parentEventId]!);
      onNewNote?.call(replyNoteModel);
      _invalidateFilterCache();
      _invalidateFilterCache();
      notesNotifier.value = notesNotifier.notes;

      print('[DataService] Reply broadcasted to ${activeSockets.length} relays');
    } catch (e) {
      print('[DataService ERROR] Error sending reply: $e');
      throw e;
    }
  }

  Future<void> sendRepostInstantly(NoteModel note) async {
    if (_isClosed) return;
    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final content = note.rawWs ??
          jsonEncode({
            'id': note.id,
            'pubkey': note.author,
            'content': note.content,
            'created_at': note.timestamp.millisecondsSinceEpoch ~/ 1000,
            'kind': note.isRepost ? 6 : 1,
            'tags': [],
          });

      final event = NostrService.createRepostEvent(
        noteId: note.id,
        noteAuthor: note.author,
        content: content,
        privateKey: privateKey,
      );

      final serializedEvent = NostrService.serializeEvent(event);
      final activeSockets = _socketManager.activeSockets;

      for (final ws in activeSockets) {
        if (ws.readyState == WebSocket.open) {
          ws.add(serializedEvent);
        }
      }

      final repost = RepostModel.fromEvent(NostrService.eventToJson(event), note.id);
      repostsMap.putIfAbsent(note.id, () => []);
      repostsMap[note.id]!.add(repost);

      if (repostsBox != null) {
        repostsBox!.put(repost.id, repost).catchError((error) {
          print('[DataService] Error saving repost to cache: $error');
        });
      }

      final updatedNote = notes.firstWhereOrNull((n) => n.id == note.id);
      if (updatedNote != null) {
        updatedNote.repostCount = repostsMap[note.id]!.length;
      }

      onRepostsUpdated?.call(note.id, repostsMap[note.id]!);
      notesNotifier.value = notesNotifier.notes;

      print('[DataService] Repost broadcasted to ${activeSockets.length} relays');
    } catch (e) {
      print('[DataService ERROR] Error sending repost: $e');
      throw e;
    }
  }

  Future<void> shareNoteInstantly(String noteContent) async {
    if (_isClosed) return;
    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final event = NostrService.createNoteEvent(
        content: noteContent,
        privateKey: privateKey,
      );

      final serializedEvent = NostrService.serializeEvent(event);
      final activeSockets = _socketManager.activeSockets;

      for (final ws in activeSockets) {
        if (ws.readyState == WebSocket.open) {
          ws.add(serializedEvent);
        }
      }

      final timestamp = DateTime.now();
      final eventJson = NostrService.eventToJson(event);
      final newNote = NoteModel(
        id: eventJson['id'],
        content: noteContent,
        author: npub,
        timestamp: timestamp,
        isRepost: false,
      );

      newNote.hasMedia = newNote.hasMediaLazy;

      notes.add(newNote);
      eventIds.add(newNote.id);

      if (notesBox != null) {
        notesBox!.put(newNote.id, newNote).catchError((error) {
          print('[DataService] Error saving note to cache: $error');
        });
      }

      addNote(newNote);
      onNewNote?.call(newNote);

      print('[DataService] Note broadcasted to ${activeSockets.length} relays');
    } catch (e) {
      print('[DataService ERROR] Error sharing note: $e');
      throw e;
    }
  }

  Future<void> sendReply(String parentEventId, String replyContent) async {
    if (_isClosed) return;
    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final parentNote = notes.firstWhereOrNull((note) => note.id == parentEventId);
      if (parentNote == null) {
        throw Exception('Parent note not found.');
      }

      String rootId;
      String replyId = parentEventId;

      if (parentNote.isReply && parentNote.rootId != null) {
        rootId = parentNote.rootId!;
      } else {
        rootId = parentEventId;
      }

      List<List<String>> tags = [];

      if (rootId != replyId) {
        tags.add(['e', rootId, '', 'root']);
        tags.add(['e', replyId, '', 'reply']);
      } else {
        tags.add(['e', rootId, '', 'root']);
      }

      tags.add(['p', parentNote.author, '', 'mention']);

      for (final relayUrl in relaySetMainSockets) {
        tags.add(['r', relayUrl]);
      }

      final event = NostrService.createReplyEvent(
        content: replyContent,
        privateKey: privateKey,
        tags: tags,
      );
      await initializeConnections();
      await _socketManager.broadcast(NostrService.serializeEvent(event));

      final reply = ReplyModel.fromEvent(NostrService.eventToJson(event));
      repliesMap.putIfAbsent(parentEventId, () => []);
      repliesMap[parentEventId]!.add(reply);
      await repliesBox?.put(reply.id, reply);

      final replyNoteModel = NoteModel(
        id: reply.id,
        content: reply.content,
        author: reply.author,
        timestamp: reply.timestamp,
        isReply: true,
        parentId: parentEventId,
        rootId: rootId,
        rawWs: jsonEncode(NostrService.eventToJson(event)),
      );

      replyNoteModel.hasMedia = replyNoteModel.hasMediaLazy;

      if (!eventIds.contains(replyNoteModel.id)) {
        notes.add(replyNoteModel);
        eventIds.add(replyNoteModel.id);
        await notesBox?.put(replyNoteModel.id, replyNoteModel);
        addNote(replyNoteModel);
      }

      final note = notes.firstWhereOrNull((n) => n.id == parentEventId);
      if (note != null) {
        note.replyCount = repliesMap[parentEventId]!.length;

        if (!note.replyIds.contains(reply.id)) {
          note.replyIds.add(reply.id);
        }
      }

      if (rootId != parentEventId) {
        final rootNote = notes.firstWhereOrNull((n) => n.id == rootId);
        if (rootNote != null && !rootNote.replyIds.contains(reply.id)) {
          rootNote.replyIds.add(reply.id);
        }
      }

      onRepliesUpdated?.call(parentEventId, repliesMap[parentEventId]!);
      onNewNote?.call(replyNoteModel);
      _invalidateFilterCache();
      _invalidateFilterCache();
      notesNotifier.value = notesNotifier.notes;

      print('[DataService] Reply sent and added to local notes: ${reply.id}');
    } catch (e) {
      print('[DataService ERROR] Error sending reply: $e');
      throw e;
    }
  }

  Future<void> sendRepost(NoteModel note) async {
    if (_isClosed) return;
    try {
      final privateKey = await _secureStorage.read(key: 'privateKey');
      if (privateKey == null || privateKey.isEmpty) {
        throw Exception('Private key not found.');
      }

      final content = note.rawWs ??
          jsonEncode({
            'id': note.id,
            'pubkey': note.author,
            'content': note.content,
            'created_at': note.timestamp.millisecondsSinceEpoch ~/ 1000,
            'kind': note.isRepost ? 6 : 1,
            'tags': [],
          });

      final event = NostrService.createRepostEvent(
        noteId: note.id,
        noteAuthor: note.author,
        content: content,
        privateKey: privateKey,
      );
      await initializeConnections();
      await _socketManager.broadcast(NostrService.serializeEvent(event));

      final repost = RepostModel.fromEvent(NostrService.eventToJson(event), note.id);
      repostsMap.putIfAbsent(note.id, () => []);
      repostsMap[note.id]!.add(repost);
      await repostsBox?.put(repost.id, repost);

      final updatedNote = notes.firstWhereOrNull((n) => n.id == note.id);
      if (updatedNote != null) {
        updatedNote.repostCount = repostsMap[note.id]!.length;
      }

      onRepostsUpdated?.call(note.id, repostsMap[note.id]!);
      notesNotifier.value = notesNotifier.notes;
    } catch (e) {
      print('[DataService ERROR] Error sending repost: $e');
      throw e;
    }
  }

  Future<void> saveNotesToCache() async {
    if (notesBox?.isOpen != true || notes.isEmpty) return;

    try {
      final notesToSave = notes.take(150).toList();
      final notesMap = <String, NoteModel>{};

      for (final note in notesToSave) {
        notesMap[note.id] = note;
      }

      await notesBox!.clear();
      await notesBox!.putAll(notesMap);
    } catch (e) {}
  }

  Future<void> loadNotesFromCache(Function(List<NoteModel>) onLoad) async {
    if (notesBox?.isOpen != true) return;

    try {
      final allNotes = notesBox!.values.cast<NoteModel>().toList();
      if (allNotes.isEmpty) return;

      List<NoteModel> filteredNotes;
      if (dataType == DataType.profile) {
        filteredNotes = allNotes.where((note) {
          return note.author == npub || (note.isRepost && note.repostedBy == npub);
        }).toList();
      } else {
        filteredNotes = allNotes;
      }

      filteredNotes.sort((a, b) {
        final aTime = a.isRepost ? (a.repostTimestamp ?? a.timestamp) : a.timestamp;
        final bTime = b.isRepost ? (b.repostTimestamp ?? b.timestamp) : b.timestamp;
        return bTime.compareTo(aTime);
      });

      final limitedNotes = filteredNotes.take(100).toList();
      final newNotes = <NoteModel>[];

      const batchSize = 25;
      for (int i = 0; i < limitedNotes.length; i += batchSize) {
        final batch = limitedNotes.skip(i).take(batchSize);

        for (final note in batch) {
          if (!eventIds.contains(note.id)) {
            note.hasMedia = note.hasMediaLazy;
            notes.add(note);
            eventIds.add(note.id);
            addNote(note);
            newNotes.add(note);
          }

          note.reactionCount = reactionsMap[note.id]?.length ?? 0;
          note.replyCount = repliesMap[note.id]?.length ?? 0;
          note.repostCount = repostsMap[note.id]?.length ?? 0;
          note.zapAmount = zapsMap[note.id]?.fold<int>(0, (sum, zap) => sum + zap.amount) ?? 0;
        }

        if (i % (batchSize * 2) == 0) {
          await Future.delayed(Duration.zero);
        }
      }

      if (newNotes.isNotEmpty) {
        _invalidateFilterCache();
        notesNotifier.value = notesNotifier.notes;
        onLoad(newNotes);

        final cachedEventIds = newNotes.map((note) => note.id).toList();

        await _fetchProfilesForVisibleNotes(newNotes);

        Future.microtask(() => fetchInteractionsForEvents(cachedEventIds));

        profilesNotifier.value = {
          for (var entry in profileCache.entries) entry.key: UserModel.fromCachedProfile(entry.key, entry.value.data),
        };
      }
    } catch (e) {
      print('[DataService ERROR] Error loading notes from cache: $e');
    }
  }

  Future<void> loadZapsFromCache() async {
    if (zapsBox == null || !zapsBox!.isOpen) return;
    try {
      final allZaps = zapsBox!.values.cast<ZapModel>().toList();
      if (allZaps.isEmpty) return;

      for (var zap in allZaps) {
        zapsMap.putIfAbsent(zap.targetEventId, () => []);
        if (!zapsMap[zap.targetEventId]!.any((r) => r.id == zap.id)) {
          zapsMap[zap.targetEventId]!.add(zap);
        }
      }

      await _updateInteractionsProvider();
      for (final entry in zapsMap.entries) {
        InteractionsProvider.instance.updateZaps(entry.key, entry.value);
      }
    } catch (e) {
      print('[DataService ERROR] Error loading zaps from cache: $e');
    }
  }

  Future<void> _handleZapEvent(Map<String, dynamic> eventData) async {
    if (_isClosed) return;
    try {
      final zap = ZapModel.fromEvent(eventData);
      final key = zap.targetEventId;

      if (key.isEmpty) {
        return;
      }

      if (!zapsMap.containsKey(key)) {
        zapsMap[key] = [];
      }

      if (zapsMap[key]!.any((z) => z.id == zap.id)) return;

      zapsMap[key]!.add(zap);
      await zapsBox?.put(zap.id, zap);

      await _updateInteractionsProvider();
      InteractionsProvider.instance.updateZaps(key, zapsMap[key]!);

      final note = notes.firstWhereOrNull((n) => n.id == key);
      if (note != null) {
        note.zapAmount = zapsMap[key]!.fold(0, (sum, z) => sum + z.amount);
        _invalidateFilterCache();
        notesNotifier.value = notesNotifier.notes;
      }
    } catch (e) {
      print('[DataService ERROR] Error handling zap event: $e');
    }
  }

  Future<void> fetchInteractionsForEvents(List<String> eventIdsToFetch) async {
    if (_isClosed) return;
    await _fetchProcessorReady.future;

    final kindsToFetch = [
      {'type': 'reaction', 'kind': 7},
      {'type': 'reply', 'kind': 1},
      {'type': 'repost', 'kind': 6},
      {'type': 'zap', 'kind': 9735},
    ];

    for (final interaction in kindsToFetch) {
      final type = interaction['type'] as String;

      _fetchProcessorSendPort.send({
        'type': type,
        'eventIds': eventIdsToFetch,
        'priority': 2,
      });

      for (final eventId in eventIdsToFetch) {
        if (type == 'reaction') {
          final reactions = reactionsMap[eventId] ?? [];
          onReactionsUpdated?.call(eventId, reactions);
          final note = notes.firstWhereOrNull((n) => n.id == eventId);
          if (note != null) note.reactionCount = reactions.length;
        } else if (type == 'reply') {
          final replies = repliesMap[eventId] ?? [];
          onRepliesUpdated?.call(eventId, replies);
          final note = notes.firstWhereOrNull((n) => n.id == eventId);
          if (note != null) note.replyCount = replies.length;
        } else if (type == 'repost') {
          final reposts = repostsMap[eventId] ?? [];
          onRepostsUpdated?.call(eventId, reposts);
          final note = notes.firstWhereOrNull((n) => n.id == eventId);
          if (note != null) note.repostCount = reposts.length;
        } else if (type == 'zap') {
          final zaps = zapsMap[eventId] ?? [];
          final note = notes.firstWhereOrNull((n) => n.id == eventId);
          if (note != null) {
            note.zapAmount = zaps.fold<int>(0, (sum, z) => sum + z.amount);
          }
        }
      }
    }

    notesNotifier.value = notesNotifier.notes;
  }

  Future<void> loadReactionsFromCache() async {
    if (reactionsBox == null || !reactionsBox!.isOpen) return;
    try {
      final allReactions = reactionsBox!.values.cast<ReactionModel>().toList();
      if (allReactions.isEmpty) return;

      const batchSize = 100;
      final Map<String, List<ReactionModel>> tempMap = {};

      for (int i = 0; i < allReactions.length; i += batchSize) {
        final batch = allReactions.skip(i).take(batchSize);

        for (var reaction in batch) {
          tempMap.putIfAbsent(reaction.targetEventId, () => []);
          if (!tempMap[reaction.targetEventId]!.any((r) => r.id == reaction.id)) {
            tempMap[reaction.targetEventId]!.add(reaction);
          }
        }

        if (i % (batchSize * 5) == 0) {
          await Future.delayed(Duration.zero);
        }
      }

      for (final entry in tempMap.entries) {
        reactionsMap.putIfAbsent(entry.key, () => []);
        for (final reaction in entry.value) {
          if (!reactionsMap[entry.key]!.any((r) => r.id == reaction.id)) {
            reactionsMap[entry.key]!.add(reaction);
          }
        }

        await _updateInteractionsProvider();
        InteractionsProvider.instance.updateReactions(entry.key, reactionsMap[entry.key]!);
        onReactionsUpdated?.call(entry.key, reactionsMap[entry.key]!);
      }

      print('[DataService] Reactions cache loaded with ${allReactions.length} reactions.');
    } catch (e) {
      print('[DataService ERROR] Error loading reactions from cache: $e');
    }
  }

  Future<void> loadRepliesFromCache() async {
    if (repliesBox == null || !repliesBox!.isOpen) return;
    try {
      final allReplies = repliesBox!.values.cast<ReplyModel>().toList();
      if (allReplies.isEmpty) return;

      const batchSize = 100;
      final Map<String, List<ReplyModel>> tempMap = {};
      final List<NoteModel> replyNotes = [];

      for (int i = 0; i < allReplies.length; i += batchSize) {
        final batch = allReplies.skip(i).take(batchSize);

        for (var reply in batch) {
          tempMap.putIfAbsent(reply.parentEventId, () => []);
          if (!tempMap[reply.parentEventId]!.any((r) => r.id == reply.id)) {
            tempMap[reply.parentEventId]!.add(reply);

            if (!eventIds.contains(reply.id)) {
              final replyNoteModel = NoteModel(
                id: reply.id,
                content: reply.content,
                author: reply.author,
                timestamp: reply.timestamp,
                isReply: true,
                parentId: reply.parentEventId,
                rootId: reply.rootEventId,
                rawWs: '',
              );

              replyNoteModel.hasMedia = replyNoteModel.hasMediaLazy;
              replyNotes.add(replyNoteModel);
              notes.add(replyNoteModel);
              eventIds.add(replyNoteModel.id);
              addNote(replyNoteModel);
            }
          }
        }

        if (i % (batchSize * 5) == 0) {
          await Future.delayed(Duration.zero);
        }
      }

      for (final entry in tempMap.entries) {
        repliesMap.putIfAbsent(entry.key, () => []);
        for (final reply in entry.value) {
          if (!repliesMap[entry.key]!.any((r) => r.id == reply.id)) {
            repliesMap[entry.key]!.add(reply);
          }
        }

        await _updateInteractionsProvider();
        InteractionsProvider.instance.updateReplies(entry.key, repliesMap[entry.key]!);
      }

      print('[DataService] Replies cache loaded with ${allReplies.length} replies, ${replyNotes.length} added as notes.');

      final replyIds = allReplies.map((r) => r.id).toList();
      if (replyIds.isNotEmpty) {
        Future.microtask(() => fetchInteractionsForEvents(replyIds));
      }
    } catch (e) {
      print('[DataService ERROR] Error loading replies from cache: $e');
    }
  }

  Future<void> loadRepostsFromCache() async {
    if (repostsBox == null || !repostsBox!.isOpen) return;
    try {
      final allReposts = repostsBox!.values.cast<RepostModel>().toList();
      if (allReposts.isEmpty) return;

      const batchSize = 100;
      final Map<String, List<RepostModel>> tempMap = {};

      for (int i = 0; i < allReposts.length; i += batchSize) {
        final batch = allReposts.skip(i).take(batchSize);

        for (var repost in batch) {
          tempMap.putIfAbsent(repost.originalNoteId, () => []);
          if (!tempMap[repost.originalNoteId]!.any((r) => r.id == repost.id)) {
            tempMap[repost.originalNoteId]!.add(repost);
          }
        }

        if (i % (batchSize * 5) == 0) {
          await Future.delayed(Duration.zero);
        }
      }

      for (final entry in tempMap.entries) {
        repostsMap.putIfAbsent(entry.key, () => []);
        for (final repost in entry.value) {
          if (!repostsMap[entry.key]!.any((r) => r.id == repost.id)) {
            repostsMap[entry.key]!.add(repost);
          }
        }

        await _updateInteractionsProvider();
        InteractionsProvider.instance.updateReposts(entry.key, repostsMap[entry.key]!);
        onRepostsUpdated?.call(entry.key, repostsMap[entry.key]!);
      }

      print('[DataService] Reposts cache loaded with ${allReposts.length} reposts.');
    } catch (e) {
      print('[DataService ERROR] Error loading reposts from cache: $e');
    }
  }

  Future<void> _loadNotificationsFromCache() async {
    if (notificationsBox == null || !notificationsBox!.isOpen) return;
    try {
      final allNotifications = notificationsBox!.values.toList();
      allNotifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      notificationsNotifier.value = allNotifications;
      _updateUnreadNotificationCount();
      final count = allNotifications.length;
      print('[DataService] Notifications cache contains $count notifications.');
    } catch (e) {
      print('[DataService ERROR] Error loading notifications from cache: $e');
    }
  }

  void _updateUnreadNotificationCount() {
    if (notificationsBox != null && notificationsBox!.isOpen) {
      final unreadCount = notificationsBox!.values.where((n) => !n.isRead).length;
      unreadNotificationsCountNotifier.value = unreadCount;
    }
  }

  Future<void> refreshUnreadNotificationCount() async {
    _updateUnreadNotificationCount();
  }

  Future<void> markAllUserNotificationsAsRead() async {
    if (notificationsBox == null || !notificationsBox!.isOpen) return;

    List<Future<void>> saveFutures = [];
    bool madeChanges = false;

    final relevantNotifications = notificationsBox!.values.where((n) => ['mention', 'reaction', 'repost', 'zap'].contains(n.type)).toList();

    for (final notification in relevantNotifications) {
      if (!notification.isRead) {
        notification.isRead = true;
        saveFutures.add(notification.save());
        madeChanges = true;
      }
    }

    if (saveFutures.isNotEmpty) {
      await Future.wait(saveFutures);
      print('[DataService] Marked ${saveFutures.length} notifications as read.');
    }

    _updateUnreadNotificationCount();

    if (madeChanges) {
      final allNotifications = notificationsBox!.values.toList();
      allNotifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      notificationsNotifier.value = allNotifications;
    }
  }

  Future<void> _subscribeToNotifications() async {
    if (_isClosed || npub.isEmpty || notificationsBox == null || !notificationsBox!.isOpen) return;

    int? sinceTimestamp;
    try {
      if (notificationsBox!.isNotEmpty) {
        final List<NotificationModel> sortedNotifications = notificationsBox!.values.toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        sinceTimestamp = (sortedNotifications.first.timestamp.millisecondsSinceEpoch ~/ 1000) + 1;
      }
    } catch (e) {
      print('[DataService ERROR] Error getting latest notification timestamp from cache: $e');
    }

    sinceTimestamp ??= DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000;

    final filter = NostrService.createNotificationFilter(
      pubkeys: [npub],
      kinds: [1, 6, 7, 9735],
      since: sinceTimestamp,
      limit: 50,
    );

    final request = NostrService.serializeRequest(NostrService.createRequest(filter));

    try {
      await _broadcastRequest(request);
      print('[DataService] Subscribed to notifications for $npub since $sinceTimestamp with filter: ${filter.toJson()}');
    } catch (e) {
      print('[DataService ERROR] Failed to subscribe to notifications: $e');
    }
  }

  Future<void> _handleNewNotes(dynamic data) async {
    if (data is List<NoteModel> && data.isNotEmpty) {
      final newNoteIds = <String>[];

      for (var note in data) {
        if (!eventIds.contains(note.id)) {
          bool shouldProcess = true;

          shouldProcess = true;

          if (shouldProcess) {
            note.hasMedia = note.hasMediaLazy;
            notes.add(note);
            eventIds.add(note.id);
            newNoteIds.add(note.id);

            await notesBox?.put(note.id, note);
            addNote(note);
          }
        }
      }

      print('[DataService] Handled new notes: ${data.length} notes processed, ${newNoteIds.length} added.');

      if (newNoteIds.isNotEmpty) {
        _subscribeToInteractionsForNewNotes(newNoteIds);
      }
    }
  }

  void _subscribeToInteractionsForNewNotes(List<String> newNoteIds) {
    if (_isClosed || newNoteIds.isEmpty) return;

    final sinceTimestamp = DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000;

    final reactionFilter = NostrService.createReactionFilter(
      eventIds: newNoteIds,
      since: sinceTimestamp,
    );
    _safeBroadcast(NostrService.serializeRequest(NostrService.createRequest(reactionFilter)));

    final replyFilter = NostrService.createReplyFilter(
      eventIds: newNoteIds,
      since: sinceTimestamp,
    );
    _safeBroadcast(NostrService.serializeRequest(NostrService.createRequest(replyFilter)));

    final repostFilter = NostrService.createRepostFilter(
      eventIds: newNoteIds,
      since: sinceTimestamp,
    );
    _safeBroadcast(NostrService.serializeRequest(NostrService.createRequest(repostFilter)));

    final zapFilter = NostrService.createZapFilter(
      eventIds: newNoteIds,
      since: sinceTimestamp,
    );
    _safeBroadcast(NostrService.serializeRequest(NostrService.createRequest(zapFilter)));

    print('[DataService] Subscribed to interactions for ${newNoteIds.length} new notes.');
  }

  Future<void> _processParsedEvent(Map<String, dynamic> parsedData) async {
    try {
      final int? kind = parsedData['kind'] as int?;
      final Map<String, dynamic>? eventData = parsedData['eventData'] as Map<String, dynamic>?;
      final List<String> targetNpubs = List<String>.from(parsedData['targetNpubs'] ?? []);

      if (kind == null || eventData == null) {
        print('[DataService] Skipped event with null kind or data.');
        return;
      }

      final String eventAuthor = eventData['pubkey'] as String? ?? '';
      if (eventAuthor.isNotEmpty && eventAuthor != npub) {
        final List<dynamic> eventTags = List<dynamic>.from(eventData['tags'] ?? []);
        bool isUserPMentioned = eventTags.any((tag) {
          return tag is List && tag.length >= 2 && tag[0] == 'p' && tag[1] == npub;
        });

        if (isUserPMentioned && [1, 6, 7, 9735].contains(kind)) {
          String notificationType;
          if (kind == 1)
            notificationType = "mention";
          else if (kind == 6)
            notificationType = "repost";
          else if (kind == 7)
            notificationType = "reaction";
          else if (kind == 9735)
            notificationType = "zap";
          else
            return;

          final notification = NotificationModel.fromEvent(eventData, notificationType);
          if (notificationsBox != null && notificationsBox!.isOpen) {
            if (!notificationsBox!.containsKey(notification.id)) {
              notificationsBox!.put(notification.id, notification);
              print("[DataService] New $notificationType notification stored: ${notification.id}");
              _hasPendingUiUpdate = true;
            }
          }
        }
      }

      if (kind == 0) {
        await _handleProfileEvent(eventData);
      } else if (kind == 3) {
        await _handleFollowingEvent(eventData);
      } else if (kind == 7) {
        await _handleReactionEvent(eventData);
      } else if (kind == 9735) {
        await _handleZapEvent(eventData);
      } else if (kind == 6) {
        await _handleRepostEvent(eventData);

        await NoteProcessor.processNoteEvent(this, eventData, targetNpubs, rawWs: jsonEncode(eventData['content']));
      } else if (kind == 1) {
        final tags = List<dynamic>.from(eventData['tags'] ?? []);
        final replyETags = tags.where((tag) {
          if (tag is List && tag.isNotEmpty && tag[0] == 'e') {
            return !(tag.length >= 4 && tag[3] == 'mention');
          }
          return false;
        }).toList();

        if (replyETags.isNotEmpty) {
          final lastETag = replyETags.last;
          if (lastETag is List && lastETag.length >= 2) {
            final parentId = lastETag[1] as String;
            await _handleReplyEvent(eventData, parentId);
          }
        } else {
          await NoteProcessor.processNoteEvent(this, eventData, targetNpubs, rawWs: jsonEncode(eventData));
        }
      }
    } catch (e, stacktrace) {
      print('[DataService ERROR] Event processing failed: $e');
      print(stacktrace);
    }

    if (_hasPendingUiUpdate && (_uiThrottleTimer == null || !_uiThrottleTimer!.isActive)) {
      _uiThrottleTimer = Timer(const Duration(milliseconds: 250), () {
        if (_isClosed) {
          return;
        }

        print('[DataService] Throttled UI update executed for all pending changes.');

        notesNotifier.value = notesNotifier._getFilteredNotesList();

        profilesNotifier.value = {
          for (var entry in profileCache.entries) entry.key: UserModel.fromCachedProfile(entry.key, entry.value.data)
        };

        if (notificationsBox != null && notificationsBox!.isOpen) {
          final allNotifications = notificationsBox!.values.toList();
          allNotifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          notificationsNotifier.value = allNotifications;
          _updateUnreadNotificationCount();
        }

        _hasPendingUiUpdate = false;
      });
    }
  }

  Future<void> _handleFetchedData(Map<String, dynamic> fetchData) async {
    try {
      final String type = fetchData['type'];
      final List<String> eventIds = List<String>.from(fetchData['eventIds']);

      String request;
      if (type == 'reaction') {
        final filter = NostrService.createReactionFilter(eventIds: eventIds, limit: 1000);
        request = NostrService.serializeRequest(NostrService.createRequest(filter));
      } else if (type == 'reply') {
        final filter = NostrService.createReplyFilter(eventIds: eventIds, limit: 1000);
        request = NostrService.serializeRequest(NostrService.createRequest(filter));
      } else if (type == 'repost') {
        final filter = NostrService.createRepostFilter(eventIds: eventIds, limit: 1000);
        request = NostrService.serializeRequest(NostrService.createRequest(filter));
      } else if (type == 'zap') {
        final filter = NostrService.createZapFilter(eventIds: eventIds, limit: 1000);
        request = NostrService.serializeRequest(NostrService.createRequest(filter));
      } else {
        return;
      }

      await _broadcastRequest(request);
    } catch (e) {
      print('[DataService ERROR] Error handling fetched data: $e');
    }
  }

  void _handleCacheLoad(dynamic data) {
    if (data is List<NoteModel>) {
      if (_onCacheLoad != null) {
        _onCacheLoad!(data);
        _onCacheLoad = null;
      }
    }
  }

  Future<NoteModel?> fetchNoteByIdIndependently(String eventId) async {
    final fetchTasks = relaySetIndependentFetch.map((relayUrl) => _fetchFromSingleRelay(relayUrl, eventId)).toList();

    try {
      final result = await Future.any(fetchTasks);
      return result;
    } catch (e) {
      print('[fetchNoteByIdIndependently] All fetch attempts failed: $e');
      return null;
    }
  }

  Future<Map<String, String>?> fetchUserProfileIndependently(String npub) async {
    try {
      return await _profileService.getCachedUserProfile(npub);
    } catch (e) {
      print('[DataService] ProfileService error in independent fetch: $e');
    }

    for (final relayUrl in relaySetIndependentFetch) {
      final result = await _fetchProfileFromSingleRelay(relayUrl, npub);
      if (result != null) {
        print('[DataService] Emergency relay fallback successful for: $npub');
        return result;
      }
    }
    print('[fetchUserProfileIndependently] No result from any source.');
    return null;
  }

  Future<Map<String, String>?> _fetchProfileFromSingleRelay(String relayUrl, String npub) async {
    WebSocket? ws;
    try {
      ws = await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 5));
      final subscriptionId = DateTime.now().millisecondsSinceEpoch.toString();
      final request = jsonEncode([
        "REQ",
        subscriptionId,
        {
          "authors": [npub],
          "kinds": [0],
          "limit": 1
        }
      ]);

      final completer = Completer<Map<String, dynamic>?>();

      late StreamSubscription sub;
      sub = ws.listen((event) {
        try {
          if (completer.isCompleted) return;
          final decoded = jsonDecode(event);
          if (decoded is List && decoded.length >= 2) {
            if (decoded[0] == 'EVENT' && decoded[1] == subscriptionId) {
              completer.complete(decoded[2]);
            } else if (decoded[0] == 'EOSE' && decoded[1] == subscriptionId) {
              completer.complete(null);
            }
          }
        } catch (e) {
          if (!completer.isCompleted) completer.complete(null);
        }
      }, onError: (error) {
        if (!completer.isCompleted) completer.complete(null);
      }, onDone: () {
        if (!completer.isCompleted) completer.complete(null);
      }, cancelOnError: true);

      if (ws.readyState == WebSocket.open) {
        ws.add(request);
      }

      final eventData = await completer.future.timeout(const Duration(seconds: 5), onTimeout: () => null);

      try {
        await sub.cancel();
      } catch (_) {}

      try {
        await ws.close();
      } catch (_) {}

      if (eventData != null) {
        final contentRaw = eventData['content'];
        Map<String, dynamic> profileContent = {};
        if (contentRaw is String && contentRaw.isNotEmpty) {
          try {
            profileContent = jsonDecode(contentRaw);
          } catch (_) {}
        }

        return {
          'name': profileContent['name'] ?? 'Anonymous',
          'profileImage': profileContent['picture'] ?? '',
          'about': profileContent['about'] ?? '',
          'nip05': profileContent['nip05'] ?? '',
          'banner': profileContent['banner'] ?? '',
          'lud16': profileContent['lud16'] ?? '',
          'website': profileContent['website'] ?? '',
        };
      } else {
        return null;
      }
    } catch (e) {
      print('[fetchProfileFromSingleRelay] Error fetching from $relayUrl: $e');
      try {
        await ws?.close();
      } catch (_) {}
      return null;
    }
  }

  Future<NoteModel?> _fetchFromSingleRelay(String relayUrl, String eventId) async {
    WebSocket? ws;

    try {
      ws = await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 5));
      final subscriptionId = DateTime.now().millisecondsSinceEpoch.toString();
      final request = jsonEncode([
        "REQ",
        subscriptionId,
        {
          "ids": [eventId]
        }
      ]);

      final completer = Completer<Map<String, dynamic>?>();

      late StreamSubscription sub;
      sub = ws.listen((event) {
        try {
          if (completer.isCompleted) return;
          final decoded = jsonDecode(event);

          if (decoded is List && decoded.length >= 2) {
            if (decoded[0] == 'EVENT' && decoded[1] == subscriptionId) {
              completer.complete(decoded[2]);
            } else if (decoded[0] == 'EOSE' && decoded[1] == subscriptionId) {
              completer.complete(null);
            }
          }
        } catch (e) {
          if (!completer.isCompleted) completer.complete(null);
        }
      }, onError: (error) {
        try {
          if (!completer.isCompleted) completer.complete(null);
        } catch (e) {}
      }, onDone: () {
        try {
          if (!completer.isCompleted) completer.complete(null);
        } catch (e) {}
      }, cancelOnError: false);

      if (ws.readyState == WebSocket.open) {
        ws.add(request);
      }

      final eventData = await completer.future.timeout(const Duration(seconds: 5), onTimeout: () => null);

      try {
        await sub.cancel();
      } catch (_) {}

      try {
        if (ws.readyState == WebSocket.open || ws.readyState == WebSocket.connecting) {
          await ws.close();
        }
      } catch (_) {}

      if (eventData != null) {
        return NoteModel(
          id: eventData['id'],
          content: eventData['content'] is String ? eventData['content'] : jsonEncode(eventData['content']),
          author: eventData['pubkey'],
          timestamp: DateTime.fromMillisecondsSinceEpoch(eventData['created_at'] * 1000),
          isRepost: eventData['kind'] == 6,
          rawWs: jsonEncode(eventData),
        );
      } else {
        return null;
      }
    } catch (e) {
      print('[fetchFromSingleRelay] Error fetching from $relayUrl: $e');
      try {
        if (ws != null && (ws.readyState == WebSocket.open || ws.readyState == WebSocket.connecting)) {
          await ws.close();
        }
      } catch (_) {}
      return null;
    }
  }

  String generateUUID() => NostrService.generateUUID();

  List<NoteModel> getThreadReplies(String rootNoteId) {
    final List<NoteModel> threadReplies = [];

    for (final note in notes) {
      if (note.isReply && (note.rootId == rootNoteId || note.parentId == rootNoteId)) {
        threadReplies.add(note);
      }
    }

    threadReplies.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return threadReplies;
  }

  List<NoteModel> getDirectReplies(String noteId) {
    final List<NoteModel> directReplies = [];

    for (final note in notes) {
      if (note.isReply && note.parentId == noteId) {
        directReplies.add(note);
      }
    }

    directReplies.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return directReplies;
  }

  Map<String, List<NoteModel>> buildThreadHierarchy(String rootNoteId) {
    final Map<String, List<NoteModel>> hierarchy = {};
    final threadReplies = getThreadReplies(rootNoteId);

    for (final reply in threadReplies) {
      final parentId = reply.parentId ?? rootNoteId;
      hierarchy.putIfAbsent(parentId, () => []);
      hierarchy[parentId]!.add(reply);
    }

    hierarchy.forEach((key, replies) {
      replies.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    });

    return hierarchy;
  }

  Future<void> closeConnections() async {
    if (_isClosed) return;
    _isClosed = true;

    _preloadedNotes.clear();
    _scrollDebounceTimer?.cancel();
    isLoadingNotifier.value = false;

    _isRefreshing = false;
    isRefreshingNotifier.value = false;

    _cacheCleanupTimer?.cancel();
    _interactionRefreshTimer?.cancel();

    try {
      if (_sendPortReadyCompleter.isCompleted) {
        _sendPort.send(IsolateMessage(MessageType.close, 'close'));
      }
    } catch (e) {}

    try {
      _eventProcessorIsolate.kill(priority: Isolate.immediate);
    } catch (e) {
      print('[DataService] Failed to kill eventProcessorIsolate: $e');
    }

    try {
      _fetchProcessorIsolate.kill(priority: Isolate.immediate);
    } catch (e) {
      print('[DataService] Failed to kill fetchProcessorIsolate: $e');
    }

    _isolate.kill(priority: Isolate.immediate);
    _receivePort.close();
    await _socketManager.closeConnections();

    print('[DataService] All connections closed. Hive boxes remain open.');
  }

  Future<void> _updateInteractionsProvider() async {
    try {
      await InteractionsProvider.instance.initialize(npub);
    } catch (e) {
      print('[DataService] Error updating InteractionsProvider: $e');
    }
  }
}
