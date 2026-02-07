import 'dart:async';
import '../../domain/entities/user_profile.dart';
import '../services/primal_cache_service.dart';
import 'base_repository.dart';

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
  Future<List<Map<String, dynamic>>> getRandomUsersWithImages({int limit = 50});
}

class ProfileRepositoryImpl extends BaseRepository
    implements ProfileRepository {
  final PrimalCacheService _primalCacheService;

  ProfileRepositoryImpl({
    required super.db,
    required super.mapper,
    PrimalCacheService? primalCacheService,
  }) : _primalCacheService = primalCacheService ?? PrimalCacheService.instance;

  @override
  Stream<UserProfile?> watchProfile(String pubkey) {
    return db.watchProfile(pubkey).map((event) {
      if (event == null) return null;
      return mapper.toUserProfile(event);
    });
  }

  @override
  Future<UserProfile?> getProfile(String pubkey) async {
    final profileData = await db.getUserProfile(pubkey);
    if (profileData == null) return null;

    return UserProfile(
      pubkey: pubkey,
      name: profileData['name'],
      displayName: profileData['display_name'],
      about: profileData['about'],
      picture: profileData['profileImage'],
      banner: profileData['banner'],
      nip05: profileData['nip05'],
      lud16: profileData['lud16'],
      website: profileData['website'],
    );
  }

  @override
  Future<Map<String, UserProfile>> getProfiles(List<String> pubkeys) async {
    if (pubkeys.isEmpty) return {};

    final profilesData = await db.getUserProfiles(pubkeys);
    final result = <String, UserProfile>{};

    for (final entry in profilesData.entries) {
      final pubkey = entry.key;
      final data = entry.value;

      result[pubkey] = UserProfile(
        pubkey: pubkey,
        name: data['name'],
        displayName: data['display_name'],
        about: data['about'],
        picture: data['profileImage'],
        banner: data['banner'],
        nip05: data['nip05'],
        lud16: data['lud16'],
        website: data['website'],
      );
    }

    return result;
  }

  @override
  Future<List<UserProfile>> searchProfiles(String query,
      {int limit = 50}) async {
    final results = await db.searchUserProfiles(query, limit: limit);

    return results.map((data) {
      return UserProfile(
        pubkey: data['pubkeyHex'] ?? '',
        name: data['name'],
        displayName: data['display_name'],
        about: data['about'],
        picture: data['profileImage'],
        banner: data['banner'],
        nip05: data['nip05'],
        lud16: data['lud16'],
        website: data['website'],
      );
    }).toList();
  }

  @override
  Future<void> saveProfile(
      String pubkey, Map<String, String> profileData) async {
    await db.saveUserProfile(pubkey, profileData);
  }

  @override
  Future<void> saveProfiles(Map<String, Map<String, String>> profiles) async {
    await db.saveUserProfiles(profiles);
  }

  @override
  Future<bool> hasProfile(String pubkey) async {
    return await db.hasUserProfile(pubkey);
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
  Future<List<Map<String, dynamic>>> getRandomUsersWithImages(
      {int limit = 50}) async {
    final results = await db.getRandomUsersWithImages(limit: limit);
    return results.map((r) => Map<String, dynamic>.from(r)).toList();
  }
}
