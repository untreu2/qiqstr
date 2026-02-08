import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qiqstr/constants/relays.dart';
import '../../src/rust/api/relay.dart' as rust_relay;

class RustRelayService {
  static RustRelayService? _instance;
  static RustRelayService get instance {
    _instance ??= RustRelayService._internal();
    return _instance!;
  }

  bool _initialized = false;
  List<String> _currentRelayUrls = [];
  String? _dbPath;

  RustRelayService._internal();

  bool get isInitialized => _initialized;
  List<String> get relayUrls => List.from(_currentRelayUrls);

  Future<String> _getDbPath() async {
    if (_dbPath != null) return _dbPath!;
    
    try {
      final dir = await getApplicationDocumentsDirectory();
      _dbPath = '${dir.path}/nostr-lmdb';
      if (kDebugMode) {
        print('[RustRelayService] DB path: $_dbPath');
      }
      return _dbPath!;
    } catch (e) {
      if (kDebugMode) {
        print('[RustRelayService] Error getting DB path: $e');
      }
      rethrow;
    }
  }

  Future<void> init({
    List<String>? relayUrls,
    String? privateKeyHex,
  }) async {
    try {
      if (kDebugMode) {
        print('[RustRelayService] Starting initialization...');
      }
      
      final urls = relayUrls ?? await getRelaySetMainSockets();
      _currentRelayUrls = List.from(urls);
      
      if (kDebugMode) {
        print('[RustRelayService] Relay URLs: $urls');
      }
      
      final dbPath = await _getDbPath();
      
      if (kDebugMode) {
        print('[RustRelayService] Calling Rust initClient with dbPath: $dbPath');
      }

      await rust_relay.initClient(
        relayUrls: urls,
        privateKeyHex: privateKeyHex,
        dbPath: dbPath,
      );
      
      _initialized = true;

      if (kDebugMode) {
        print('[RustRelayService] Initialized successfully with ${urls.length} relays');
      }

      unawaited(rust_relay.connectRelays().catchError((e) {
        if (kDebugMode) {
          print('[RustRelayService] connectRelays error: $e');
        }
      }));
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('[RustRelayService] INIT ERROR: $e');
        print('[RustRelayService] Stack trace: $stackTrace');
      }
      _initialized = false;
      rethrow;
    }
  }

  Future<void> reinit({
    List<String>? relayUrls,
    String? privateKeyHex,
  }) async {
    _initialized = false;
    await init(relayUrls: relayUrls, privateKeyHex: privateKeyHex);
  }

  Future<void> connect() async {
    await rust_relay.connectRelays();
  }

  Future<void> disconnect() async {
    await rust_relay.disconnectRelays();
  }

  Future<void> updateSigner(String privateKeyHex) async {
    await rust_relay.updateSigner(privateKeyHex: privateKeyHex);
  }

  Future<bool> addRelay(String url) async {
    final added = await rust_relay.addRelay(url: url);
    if (added && !_currentRelayUrls.contains(url)) {
      _currentRelayUrls.add(url);
    }
    return added;
  }

  Future<bool> addRelayWithFlags(String url, {required bool read, required bool write}) async {
    final added = await rust_relay.addRelayWithFlags(url: url, read: read, write: write);
    if (added && !_currentRelayUrls.contains(url)) {
      _currentRelayUrls.add(url);
    }
    return added;
  }

  Future<void> removeRelay(String url) async {
    await rust_relay.removeRelay(url: url);
    _currentRelayUrls.remove(url);
  }

  Future<List<String>> getRelayList() async {
    return await rust_relay.getRelayList();
  }

  Future<int> getConnectedRelayCount() async {
    return await rust_relay.getConnectedRelayCount();
  }

  Future<Map<String, dynamic>> getRelayStatus() async {
    final json = await rust_relay.getRelayStatus();
    return jsonDecode(json) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> fetchEvents(
    Map<String, dynamic> filter, {
    int timeoutSecs = 15,
  }) async {
    try {
      final filterJson = jsonEncode(filter);
      final result = await rust_relay.fetchEvents(
        filterJson: filterJson,
        timeoutSecs: timeoutSecs,
      );
      final decoded = jsonDecode(result) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) {
        print('[RustRelayService] fetchEvents error: $e');
      }
      return [];
    }
  }

  Future<Map<String, dynamic>> sendEvent(String eventJson) async {
    final result = await rust_relay.sendEvent(eventJson: eventJson);
    return jsonDecode(result) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> sendEventTo(
    String eventJson,
    List<String> relayUrls,
  ) async {
    final result = await rust_relay.sendEventTo(
      eventJson: eventJson,
      relayUrls: relayUrls,
    );
    return jsonDecode(result) as Map<String, dynamic>;
  }

  Future<bool> broadcastEvent(Map<String, dynamic> event) async {
    try {
      final eventJson = jsonEncode(event);
      await rust_relay.sendEvent(eventJson: eventJson);
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('[RustRelayService] broadcastEvent error: $e');
      }
      return false;
    }
  }

  Future<Map<String, dynamic>> broadcastEvents(
    List<Map<String, dynamic>> events, {
    List<String>? relayUrls,
  }) async {
    final eventsJson = jsonEncode(events);
    final result = await rust_relay.broadcastEvents(
      eventsJson: eventsJson,
      relayUrls: relayUrls,
    );
    return jsonDecode(result) as Map<String, dynamic>;
  }

  Future<bool> sendMessage(String relayUrl, String serializedEvent) async {
    try {
      final decoded = jsonDecode(serializedEvent) as List<dynamic>;
      if (decoded.isNotEmpty && decoded[0] == 'EVENT' && decoded.length >= 2) {
        final eventData = decoded[1] as Map<String, dynamic>;
        final eventJson = jsonEncode(eventData);
        await rust_relay.sendEventTo(
          eventJson: eventJson,
          relayUrls: [relayUrl],
        );
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('[RustRelayService] sendMessage error: $e');
      }
      return false;
    }
  }

  Future<Map<String, dynamic>> discoverAndConnectOutboxRelays(
      List<String> pubkeysHex) async {
    try {
      final resultJson = await rust_relay.discoverAndConnectOutboxRelays(
        pubkeysHex: pubkeysHex,
      );
      final result = jsonDecode(resultJson) as Map<String, dynamic>;
      if (kDebugMode) {
        print('[RustRelayService] Outbox discovery: '
            'discovered=${result['discoveredRelays']}, '
            'added=${result['addedRelays']}, '
            'totalConnected=${result['totalConnected']}');
      }
      return result;
    } catch (e) {
      if (kDebugMode) {
        print('[RustRelayService] discoverAndConnectOutboxRelays error: $e');
      }
      return {};
    }
  }

  Stream<Map<String, dynamic>> subscribeToEvents(
    Map<String, dynamic> filter,
  ) {
    final filterJson = jsonEncode(filter);
    return rust_relay
        .subscribeToEvents(filterJson: filterJson)
        .map((eventJson) => jsonDecode(eventJson) as Map<String, dynamic>);
  }

  Future<void> reloadCustomRelays() async {
    try {
      final customRelays = await getRelaySetMainSockets();
      final prefs = await SharedPreferences.getInstance();
      final flagsJson = prefs.getString('relay_flags');

      Map<String, Map<String, bool>> relayFlags = {};
      if (flagsJson != null) {
        final decoded = jsonDecode(flagsJson) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          final flags = entry.value as Map<String, dynamic>;
          relayFlags[entry.key] = {
            'read': flags['read'] as bool? ?? true,
            'write': flags['write'] as bool? ?? true,
          };
        }
      }

      await reinit(relayUrls: customRelays);

      final flagFutures = <Future>[];
      for (final url in customRelays) {
        final flags = relayFlags[url];
        if (flags != null) {
          final isRead = flags['read'] ?? true;
          final isWrite = flags['write'] ?? true;
          if (!isRead || !isWrite) {
            flagFutures.add(rust_relay.addRelayWithFlags(url: url, read: isRead, write: isWrite));
          }
        }
      }
      if (flagFutures.isNotEmpty) {
        await Future.wait(flagFutures);
      }

      if (kDebugMode) {
        print('[RustRelayService] Reloaded with ${customRelays.length} relays');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[RustRelayService] reloadCustomRelays error: $e');
      }
    }
  }

}
