import 'dart:async';
import 'dart:convert';
import 'package:hive/hive.dart';
import '../models/user_model.dart';
import 'relay_service.dart';

class CachedProfile {
  final Map<String, String> data;
  final DateTime fetchedAt;
  CachedProfile(this.data, this.fetchedAt);
}

class ProfileService {
  final Map<String, CachedProfile> _profileCache = {};
  final Map<String, Completer<Map<String, String>>> _pendingRequests = {};
  final Duration _cacheTTL = const Duration(minutes: 30);
  
  Box<UserModel>? _usersBox;
  
  void setUsersBox(Box<UserModel> box) {
    _usersBox = box;
  }

  Future<Map<String, String>> getCachedUserProfile(String npub) async {
    final now = DateTime.now();
    
    // Check memory cache first
    if (_profileCache.containsKey(npub)) {
      final cached = _profileCache[npub]!;
      if (now.difference(cached.fetchedAt) < _cacheTTL) {
        return cached.data;
      } else {
        _profileCache.remove(npub);
      }
    }

    // Check if already fetching
    if (_pendingRequests.containsKey(npub)) {
      return await _pendingRequests[npub]!.future;
    }

    final completer = Completer<Map<String, String>>();
    _pendingRequests[npub] = completer;

    try {
      // Try Primal cache first
      final primal = PrimalCacheClient();
      final primalProfile = await primal.fetchUserProfile(npub);
      if (primalProfile != null) {
        final cached = CachedProfile(primalProfile, DateTime.now());
        _profileCache[npub] = cached;

        if (_usersBox != null && _usersBox!.isOpen) {
          final userModel = UserModel.fromCachedProfile(npub, primalProfile);
          await _usersBox!.put(npub, userModel);
        }

        completer.complete(primalProfile);
        return primalProfile;
      }

      // Fallback to relay fetch
      final fetched = await _fetchUserProfileFromRelay(npub);
      if (fetched != null) {
        _profileCache[npub] = CachedProfile(fetched, DateTime.now());
        await _usersBox?.put(npub, UserModel.fromCachedProfile(npub, fetched));
        completer.complete(fetched);
        return fetched;
      }

      // Return default profile
      final defaultProfile = {
        'name': 'Anonymous',
        'profileImage': '',
        'about': '',
        'nip05': '',
        'banner': '',
        'lud16': '',
        'website': ''
      };
      completer.complete(defaultProfile);
      return defaultProfile;
    } catch (e) {
      final defaultProfile = {
        'name': 'Anonymous',
        'profileImage': '',
        'about': '',
        'nip05': '',
        'banner': '',
        'lud16': '',
        'website': ''
      };
      completer.complete(defaultProfile);
      return defaultProfile;
    } finally {
      _pendingRequests.remove(npub);
    }
  }

  Future<void> batchFetchProfiles(List<String> npubs) async {
    if (npubs.isEmpty) return;

    final primal = PrimalCacheClient();
    final now = DateTime.now();
    final remainingForRelay = <String>[];

    // Process in batches to avoid overwhelming the cache
    const batchSize = 20;
    for (int i = 0; i < npubs.length; i += batchSize) {
      final batch = npubs.skip(i).take(batchSize).toList();
      
      for (final pub in batch.toSet()) {
        // Skip if recently cached
        if (_profileCache.containsKey(pub)) {
          if (now.difference(_profileCache[pub]!.fetchedAt) < _cacheTTL) {
            continue;
          } else {
            _profileCache.remove(pub);
          }
        }

        // Check Hive cache
        final user = _usersBox?.get(pub);
        if (user != null) {
          final data = {
            'name': user.name,
            'profileImage': user.profileImage,
            'about': user.about,
            'nip05': user.nip05,
            'banner': user.banner,
            'lud16': user.lud16,
            'website': user.website,
          };
          _profileCache[pub] = CachedProfile(data, user.updatedAt);
          continue;
        }

        // Try Primal cache
        final primalProfile = await primal.fetchUserProfile(pub);
        if (primalProfile != null) {
          _profileCache[pub] = CachedProfile(primalProfile, now);

          if (_usersBox != null && _usersBox!.isOpen) {
            final userModel = UserModel.fromCachedProfile(pub, primalProfile);
            await _usersBox!.put(pub, userModel);
          }
          continue;
        }

        remainingForRelay.add(pub);
      }

      // Small delay between batches
      if (i + batchSize < npubs.length) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    // Fetch remaining from relays if needed
    if (remainingForRelay.isNotEmpty) {
      await _batchFetchFromRelays(remainingForRelay);
    }
  }

  Future<void> _batchFetchFromRelays(List<String> npubs) async {
    // Implementation for relay batch fetching
    // This would use the existing relay infrastructure
  }

  Future<Map<String, String>?> _fetchUserProfileFromRelay(String npub) async {
    // Implementation for single relay fetch
    // This would use the existing relay infrastructure
    return null;
  }

  void cleanupCache() {
    final now = DateTime.now();
    final cutoffTime = now.subtract(_cacheTTL);
    
    _profileCache.removeWhere((key, cached) => 
        cached.fetchedAt.isBefore(cutoffTime));
  }

  Map<String, UserModel> getProfilesSnapshot() {
    return {
      for (var entry in _profileCache.entries)
        entry.key: UserModel.fromCachedProfile(entry.key, entry.value.data)
    };
  }
}