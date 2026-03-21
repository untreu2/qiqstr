import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

import '../../src/rust/api/database.dart' as rust_db;
import '../services/encrypted_mute_service.dart';
import '../services/rust_database_service.dart';

abstract class FollowingRepository {
  Future<List<String>?> getFollowing(String userPubkey);
  Stream<List<String>> watchFollowing(String userPubkey);
  Future<void> saveFollowing(String userPubkey, List<String> following);
  Future<List<String>?> getMuted(String userPubkey);
  Future<List<String>> getMutedWords();
  Future<bool> isFollowing(String userPubkey, String targetPubkey);
  Future<bool> isMuted(String userPubkey, String targetPubkey);
  Future<void> follow(String userPubkey, String targetPubkey);
  Future<void> unfollow(String userPubkey, String targetPubkey);
  Future<void> mute(String userPubkey, String targetPubkey);
  Future<void> unmute(String userPubkey, String targetPubkey);
  Future<({int count, List<String> avatarUrls})?> getFollowScore(
      String currentUserPubkey, String targetPubkey);
}

class FollowingRepositoryImpl implements FollowingRepository {
  final RustDatabaseService _events;

  FollowingRepositoryImpl({required RustDatabaseService events})
      : _events = events;

  @override
  Future<List<String>?> getFollowing(String userPubkey) async {
    try {
      final list = await rust_db.dbGetFollowingList(pubkeyHex: userPubkey);
      if (list.isEmpty) return null;
      if (!list.contains(userPubkey)) return [...list, userPubkey];
      return list;
    } catch (e) {
      if (kDebugMode) print('[FollowingRepository] getFollowing error: $e');
      return null;
    }
  }

  @override
  Stream<List<String>> watchFollowing(String userPubkey) {
    return _events.onChange
        .debounceTime(const Duration(milliseconds: 500))
        .startWith(null)
        .asyncMap((_) async {
      final list = await getFollowing(userPubkey);
      return list ?? [];
    });
  }

  @override
  Future<void> saveFollowing(String userPubkey, List<String> following) async {
    try {
      final set = following.toSet()..add(userPubkey);
      await rust_db.dbSaveFollowingList(
          pubkeyHex: userPubkey, followsHex: set.toList());
      _events.notifyChange();
    } catch (e) {
      if (kDebugMode) print('[FollowingRepository] saveFollowing error: $e');
    }
  }

  @override
  Future<List<String>?> getMuted(String userPubkey) async {
    final muteService = EncryptedMuteService.instance;
    if (muteService.isInitialized) {
      final list = muteService.mutedPubkeys;
      return list.isEmpty ? null : list;
    }
    try {
      final list = await rust_db.dbGetMuteList(pubkeyHex: userPubkey);
      return list.isEmpty ? null : list;
    } catch (e) {
      if (kDebugMode) print('[FollowingRepository] getMuted error: $e');
      return null;
    }
  }

  @override
  Future<List<String>> getMutedWords() async {
    return EncryptedMuteService.instance.mutedWords;
  }

  @override
  Future<bool> isFollowing(String userPubkey, String targetPubkey) async {
    final list = await getFollowing(userPubkey);
    if (list == null) return false;
    return list.contains(targetPubkey);
  }

  @override
  Future<bool> isMuted(String userPubkey, String targetPubkey) async {
    final muteService = EncryptedMuteService.instance;
    if (muteService.isInitialized) {
      return muteService.isUserMuted(targetPubkey);
    }
    try {
      final list = await rust_db.dbGetMuteList(pubkeyHex: userPubkey);
      return list.contains(targetPubkey);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> follow(String userPubkey, String targetPubkey) async {
    try {
      final current = await rust_db.dbGetFollowingList(pubkeyHex: userPubkey);
      if (!current.contains(targetPubkey)) {
        await saveFollowing(userPubkey, [...current, targetPubkey]);
      }
    } catch (e) {
      if (kDebugMode) print('[FollowingRepository] follow error: $e');
    }
  }

  @override
  Future<void> unfollow(String userPubkey, String targetPubkey) async {
    if (userPubkey == targetPubkey) return;
    try {
      final current = await rust_db.dbGetFollowingList(pubkeyHex: userPubkey);
      if (current.contains(targetPubkey)) {
        await saveFollowing(
            userPubkey, current.where((p) => p != targetPubkey).toList());
      }
    } catch (e) {
      if (kDebugMode) print('[FollowingRepository] unfollow error: $e');
    }
  }

  @override
  Future<void> mute(String userPubkey, String targetPubkey) async {
    EncryptedMuteService.instance.addMutedPubkey(targetPubkey);
  }

  @override
  Future<void> unmute(String userPubkey, String targetPubkey) async {
    EncryptedMuteService.instance.removeMutedPubkey(targetPubkey);
  }

  @override
  Future<({int count, List<String> avatarUrls})?> getFollowScore(
      String currentUserPubkey, String targetPubkey) async {
    try {
      final json = await rust_db.dbCalculateFollowScore(
        currentUserHex: currentUserPubkey,
        targetHex: targetPubkey,
      );
      final result = jsonDecode(json) as Map<String, dynamic>;
      final count = result['count'] as int? ?? 0;
      if (count == 0) return null;
      final urls = (result['avatarUrls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      return (count: count, avatarUrls: urls);
    } catch (_) {
      return null;
    }
  }
}
