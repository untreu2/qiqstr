import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:hive/hive.dart';
import '../models/user_model.dart';
import '../constants/relays.dart';

class ProfileService {
  final Map<String, Map<String, String>> _profileCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Map<String, Completer<Map<String, String>>> _pendingRequests = {};

  final Duration _cacheTTL = const Duration(minutes: 30);
  final int _maxCacheSize = 1000;
  Box<UserModel>? _usersBox;

  Future<void> initialize() async {}

  void setUsersBox(Box<UserModel> box) {
    _usersBox = box;
  }

  Future<Map<String, String>> getCachedUserProfile(String npub) async {
    if (_profileCache.containsKey(npub)) {
      final timestamp = _cacheTimestamps[npub];
      if (timestamp != null && DateTime.now().difference(timestamp) < _cacheTTL) {
        return _profileCache[npub]!;
      } else {
        _profileCache.remove(npub);
        _cacheTimestamps.remove(npub);
      }
    }

    if (_pendingRequests.containsKey(npub)) {
      return _pendingRequests[npub]!.future;
    }

    final completer = Completer<Map<String, String>>();
    _pendingRequests[npub] = completer;

    try {
      final user = _usersBox?.get(npub);
      if (user != null && DateTime.now().difference(user.updatedAt) < _cacheTTL) {
        final data = _userModelToMap(user);
        _addToCache(npub, data);
        completer.complete(data);
        return data;
      }

      final profileData = await _fetchUserProfileFromRelay(npub);
      final data = profileData ?? _getDefaultProfile();

      _addToCache(npub, data);

      if (_usersBox != null && _usersBox!.isOpen) {
        final userModel = UserModel.fromCachedProfile(npub, data);
        _saveToHiveAsync(npub, userModel);
      }

      completer.complete(data);
      return data;
    } catch (e) {
      final defaultData = _getDefaultProfile();
      completer.complete(defaultData);
      return defaultData;
    } finally {
      _pendingRequests.remove(npub);
    }
  }

  Future<void> batchFetchProfiles(List<String> npubs) async {
    if (npubs.isEmpty) return;

    final futures = npubs.map((npub) => getCachedUserProfile(npub));
    await Future.wait(futures, eagerError: false);
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

  Map<String, String> _userModelToMap(UserModel user) {
    return {
      'name': user.name,
      'profileImage': user.profileImage,
      'about': user.about,
      'nip05': user.nip05,
      'banner': user.banner,
      'lud16': user.lud16,
      'website': user.website,
    };
  }

  void _addToCache(String npub, Map<String, String> data) {
    if (_profileCache.length >= _maxCacheSize) {
      final oldestKey = _cacheTimestamps.entries.reduce((a, b) => a.value.isBefore(b.value) ? a : b).key;
      _profileCache.remove(oldestKey);
      _cacheTimestamps.remove(oldestKey);
    }

    _profileCache[npub] = data;
    _cacheTimestamps[npub] = DateTime.now();
  }

  Future<Map<String, String>?> _fetchUserProfileFromRelay(String npub) async {
    if (!_isValidHex(npub)) {
      return null;
    }

    final relayUrl = relaySetMainSockets.first;

    try {
      return await _fetchProfileFromSingleRelay(relayUrl, npub);
    } catch (e) {
      print('[ProfileService] Error fetching from relay $relayUrl: $e');
      return null;
    }
  }

  Future<Map<String, String>?> _fetchProfileFromSingleRelay(String relayUrl, String npub) async {
    if (!_isValidHex(npub)) {
      return null;
    }

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
      });

      if (ws.readyState == WebSocket.open) {
        ws.add(request);
      }

      final eventData = await completer.future.timeout(const Duration(seconds: 5), onTimeout: () => null);

      await sub.cancel();
      await ws.close();

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
      }
      return null;
    } catch (e) {
      print('[ProfileService] Error fetching from $relayUrl: $e');
      try {
        await ws?.close();
      } catch (_) {}
      return null;
    }
  }

  void _saveToHiveAsync(String npub, UserModel userModel) {
    Future.microtask(() async {
      try {
        final usersBox = _usersBox;
        if (usersBox != null && usersBox.isOpen) {
          await usersBox.put(npub, userModel);
        }
      } catch (e) {
        print('[ProfileService] Error saving to Hive: $e');
      }
    });
  }

  void cleanupCache() {
    final now = DateTime.now();
    final keysToRemove = <String>[];

    for (final entry in _cacheTimestamps.entries) {
      if (now.difference(entry.value) > _cacheTTL) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      _profileCache.remove(key);
      _cacheTimestamps.remove(key);
    }
  }

  Map<String, UserModel> getProfilesSnapshot() {
    return {for (var entry in _profileCache.entries) entry.key: UserModel.fromCachedProfile(entry.key, entry.value)};
  }

  Map<String, dynamic> getProfileStats() {
    return {
      'cacheSize': _profileCache.length,
      'maxCacheSize': _maxCacheSize,
      'pendingRequests': _pendingRequests.length,
      'status': 'simplified',
    };
  }

  Future<void> dispose() async {
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.complete(_getDefaultProfile());
      }
    }

    _profileCache.clear();
    _cacheTimestamps.clear();
    _pendingRequests.clear();
  }

  bool _isValidHex(String value) {
    if (value.isEmpty || value.length != 64) return false;
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(value);
  }
}
