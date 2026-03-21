import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

import '../../domain/entities/user_profile.dart';
import '../../src/rust/api/database.dart' as rust_db;
import '../services/primal_cache_service.dart';
import '../services/rust_database_service.dart';

abstract class ProfileRepository {
  Stream<UserProfile?> watchProfile(String pubkey);
  Future<UserProfile?> getProfile(String pubkey);
  Future<Map<String, UserProfile>> getProfiles(List<String> pubkeys);
  Future<List<UserProfile>> searchProfiles(String query, {int limit = 50});
  Future<void> saveProfile(String pubkey, Map<String, String> profileData);
  Future<void> saveProfiles(Map<String, Map<String, String>> profiles);
  Future<bool> hasProfile(String pubkey);
  Future<int> getFollowerCount(String pubkeyHex);
  Future<Map<String, int>> getFollowerCounts(List<String> pubkeyHexes);
  Future<List<Map<String, dynamic>>> getSuggestedUsers({int limit = 50});
}

class ProfileRepositoryImpl implements ProfileRepository {
  final RustDatabaseService _events;
  final PrimalCacheService _primalCacheService;

  ProfileRepositoryImpl({
    required RustDatabaseService events,
    PrimalCacheService? primalCacheService,
  })  : _events = events,
        _primalCacheService = primalCacheService ?? PrimalCacheService.instance;

  UserProfile _toProfile(String pubkey, Map<String, dynamic> m) {
    return UserProfile(
      pubkey: pubkey,
      name: m['name'] as String?,
      displayName: m['display_name'] as String?,
      about: m['about'] as String?,
      picture: m['picture'] as String?,
      banner: m['banner'] as String?,
      nip05: m['nip05'] as String?,
      lud16: m['lud16'] as String?,
      website: m['website'] as String?,
      location: m['location'] as String?,
    );
  }

  @override
  Stream<UserProfile?> watchProfile(String pubkey) {
    return _events.onChange
        .debounceTime(const Duration(milliseconds: 500))
        .startWith(null)
        .asyncMap((_) => getProfile(pubkey));
  }

  @override
  Future<UserProfile?> getProfile(String pubkey) async {
    try {
      final json = await rust_db.dbGetProfile(pubkeyHex: pubkey);
      if (json == null) return null;
      final m = jsonDecode(json) as Map<String, dynamic>;
      return _toProfile(pubkey, m);
    } catch (e) {
      if (kDebugMode) print('[ProfileRepository] getProfile error: $e');
      return null;
    }
  }

  @override
  Future<Map<String, UserProfile>> getProfiles(List<String> pubkeys) async {
    if (pubkeys.isEmpty) return {};
    try {
      final json = await rust_db.dbGetProfiles(pubkeysHex: pubkeys);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return decoded.map((key, value) =>
          MapEntry(key, _toProfile(key, value as Map<String, dynamic>)));
    } catch (e) {
      if (kDebugMode) print('[ProfileRepository] getProfiles error: $e');
      return {};
    }
  }

  @override
  Future<List<UserProfile>> searchProfiles(String query,
      {int limit = 50}) async {
    try {
      final json = await rust_db.dbSearchProfiles(query: query, limit: limit);
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>().map((m) {
        final pubkey = (m['pubkey'] ?? m['pubkey'] ?? '') as String;
        return UserProfile(
          pubkey: pubkey,
          name: m['name'] as String?,
          displayName: m['display_name'] as String?,
          about: m['about'] as String?,
          picture: (m['picture'] ?? m['picture']) as String?,
          banner: m['banner'] as String?,
          nip05: m['nip05'] as String?,
          lud16: m['lud16'] as String?,
          website: m['website'] as String?,
          location: m['location'] as String?,
        );
      }).toList();
    } catch (e) {
      if (kDebugMode) print('[ProfileRepository] searchProfiles error: $e');
      return [];
    }
  }

  @override
  Future<void> saveProfile(
      String pubkey, Map<String, String> profileData) async {
    try {
      await rust_db.dbSaveProfile(
          pubkeyHex: pubkey, profileJson: jsonEncode(profileData));
      _events.notifyChange();
    } catch (e) {
      if (kDebugMode) print('[ProfileRepository] saveProfile error: $e');
    }
  }

  @override
  Future<void> saveProfiles(Map<String, Map<String, String>> profiles) async {
    if (profiles.isEmpty) return;
    try {
      await rust_db.dbSaveProfilesBatch(profilesJson: jsonEncode(profiles));
      _events.notifyChange();
    } catch (e) {
      if (kDebugMode) print('[ProfileRepository] saveProfiles error: $e');
    }
  }

  @override
  Future<bool> hasProfile(String pubkey) async {
    try {
      return await rust_db.dbHasProfile(pubkeyHex: pubkey);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<int> getFollowerCount(String pubkeyHex) async {
    return await _primalCacheService.fetchFollowerCount(pubkeyHex);
  }

  @override
  Future<Map<String, int>> getFollowerCounts(List<String> pubkeyHexes) async {
    return await _primalCacheService.fetchFollowerCounts(pubkeyHexes);
  }

  @override
  Future<List<Map<String, dynamic>>> getSuggestedUsers({int limit = 50}) async {
    try {
      final json = await rust_db.dbGetRandomProfiles(limit: limit);
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('[ProfileRepository] getSuggestedUsers error: $e');
      return [];
    }
  }
}
