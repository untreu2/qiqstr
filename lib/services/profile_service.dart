import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/user_model.dart';
import '../constants/relays.dart';
import 'in_memory_data_manager.dart';
import 'nip05_verification_service.dart';
import 'time_service.dart';

class ProfileService {
  static ProfileService? _instance;
  static ProfileService get instance => _instance ??= ProfileService._internal();

  ProfileService._internal();

  final InMemoryDataManager _dataManager = InMemoryDataManager.instance;
  final Nip05VerificationService _nip05Service = Nip05VerificationService.instance;
  final Map<String, Map<String, String>> _profileCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Map<String, Completer<Map<String, String>>> _pendingRequests = {};

  final Duration _cacheTTL = const Duration(minutes: 30);
  final int _maxCacheSize = 1000;

  InMemoryBox<UserModel>? get _usersBox => _dataManager.usersBox;

  Future<void> initialize() async {
    if (!_dataManager.isInitialized) {
      await _dataManager.initializeBoxes();
    }
  }

  Future<Map<String, String>> getCachedUserProfile(String npub) async {
    if (_profileCache.containsKey(npub)) {
      final timestamp = _cacheTimestamps[npub];
      if (timestamp != null && timeService.difference(timestamp) < _cacheTTL) {
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

    Future.microtask(() async {
      try {
        final user = _usersBox?.get(npub);
        if (user != null && timeService.difference(user.updatedAt) < _cacheTTL) {
          final data = _userModelToMap(user);
          _addToCache(npub, data);
          completer.complete(data);
          return;
        }

        final profileData = await _fetchUserProfileFromRelay(npub);

        if (profileData == null) {
          final defaultData = _getDefaultProfile();
          completer.complete(defaultData);
          return;
        }

        _addToCache(npub, profileData);

        if (_usersBox != null && _usersBox!.isOpen) {
          final userModel = UserModel.fromCachedProfile(npub, profileData);
          _saveToHiveAsync(npub, userModel);
        }

        completer.complete(profileData);
      } catch (e) {
        final defaultData = _getDefaultProfile();
        completer.complete(defaultData);
      } finally {
        _pendingRequests.remove(npub);
      }
    });

    return completer.future;
  }

  Future<void> batchFetchProfiles(List<String> npubs) async {
    if (npubs.isEmpty) return;

    const fastBatchSize = 3;
    for (int i = 0; i < npubs.length; i += fastBatchSize) {
      final batch = npubs.skip(i).take(fastBatchSize).toList();

      final futures = batch.map((npub) => Future.microtask(() => getCachedUserProfile(npub)));

      await Future.wait(futures, eagerError: false);

      if (i + fastBatchSize < npubs.length) {
        await Future.delayed(Duration.zero);
      }
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
      'nip05Verified': 'false',
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
      'nip05Verified': user.nip05Verified.toString(),
    };
  }

  void _addToCache(String npub, Map<String, String> data) {
    if (_profileCache.length >= _maxCacheSize) {
      final oldestKey = _cacheTimestamps.entries.reduce((a, b) => a.value.isBefore(b.value) ? a : b).key;
      _profileCache.remove(oldestKey);
      _cacheTimestamps.remove(oldestKey);
    }

    _profileCache[npub] = data;
    _cacheTimestamps[npub] = timeService.now;
  }

  Future<Map<String, String>?> _fetchUserProfileFromRelay(String npub) async {
    if (!_isValidHex(npub)) {
      return null;
    }

    final relaysToTry = relaySetMainSockets.take(2).toList();

    final futures = relaysToTry.map((relayUrl) => _fetchProfileFromSingleRelay(relayUrl, npub).catchError((e) {
          print('[ProfileService] Relay $relayUrl error: $e');
          return null;
        }));

    final results = await Future.wait(futures, eagerError: false);

    for (final result in results) {
      if (result != null) {
        return result;
      }
    }

    print('[ProfileService] Could not fetch user $npub from any relay');
    return null;
  }

  Future<Map<String, String>?> _fetchProfileFromSingleRelay(String relayUrl, String npub) async {
    if (!_isValidHex(npub)) {
      return null;
    }

    WebSocket? ws;
    try {
      ws = await WebSocket.connect(relayUrl).timeout(const Duration(seconds: 3));
      final subscriptionId = timeService.millisecondsSinceEpoch.toString();
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

      final eventData = await completer.future.timeout(const Duration(seconds: 3), onTimeout: () => null);

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

        final nip05 = profileContent['nip05'] ?? '';

        final profileData = <String, String>{
          'name': profileContent['name']?.toString() ?? 'Anonymous',
          'profileImage': profileContent['picture']?.toString() ?? '',
          'about': profileContent['about']?.toString() ?? '',
          'nip05': nip05.toString(),
          'banner': profileContent['banner']?.toString() ?? '',
          'lud16': profileContent['lud16']?.toString() ?? '',
          'website': profileContent['website']?.toString() ?? '',
          'nip05Verified': 'false',
        };

        if (nip05.isNotEmpty) {
          Future.microtask(() async {
            try {
              final nip05Verified = await _nip05Service.verifyNip05(nip05, npub);
              final updatedData = Map<String, String>.from(profileData);
              updatedData['nip05Verified'] = nip05Verified.toString();
              _addToCache(npub, updatedData);
              print('[ProfileService] Background NIP-05 verification for $nip05: $nip05Verified');
            } catch (e) {
              print('[ProfileService] Background NIP-05 verification error for $nip05: $e');
            }
          });
        }

        return profileData;
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
    final now = timeService.now;
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
