import 'dart:async';
import 'base_repository.dart';

abstract class FollowingRepository {
  Future<List<String>?> getFollowingList(String userPubkey);
  Stream<List<String>> watchFollowingList(String userPubkey);
  Future<void> saveFollowingList(String userPubkey, List<String> followingList);
  Future<bool> hasFollowingList(String userPubkey);
  Future<void> deleteFollowingList(String userPubkey);
  Future<List<String>?> getMuteList(String userPubkey);
  Future<void> saveMuteList(String userPubkey, List<String> muteList);
  Future<bool> hasMuteList(String userPubkey);
  Future<void> deleteMuteList(String userPubkey);
  Future<bool> isFollowing(String userPubkey, String targetPubkey);
  Future<bool> isMuted(String userPubkey, String targetPubkey);
  Future<void> follow(String userPubkey, String targetPubkey);
  Future<void> unfollow(String userPubkey, String targetPubkey);
  Future<void> mute(String userPubkey, String targetPubkey);
  Future<void> unmute(String userPubkey, String targetPubkey);
}

class FollowingRepositoryImpl extends BaseRepository
    implements FollowingRepository {
  FollowingRepositoryImpl({
    required super.db,
    required super.mapper,
  });

  @override
  Future<List<String>?> getFollowingList(String userPubkey) async {
    final list = await db.getFollowingList(userPubkey);
    if (list == null) return null;
    
    if (!list.contains(userPubkey)) {
      return [...list, userPubkey];
    }
    return list;
  }

  @override
  Stream<List<String>> watchFollowingList(String userPubkey) {
    return db.watchFollowingList(userPubkey).map((list) {
      if (!list.contains(userPubkey)) {
        return [...list, userPubkey];
      }
      return list;
    });
  }

  @override
  Future<void> saveFollowingList(
      String userPubkey, List<String> followingList) async {
    final listWithUser = followingList.toSet()..add(userPubkey);
    await db.saveFollowingList(userPubkey, listWithUser.toList());
  }

  @override
  Future<bool> hasFollowingList(String userPubkey) async {
    return await db.hasFollowingList(userPubkey);
  }

  @override
  Future<void> deleteFollowingList(String userPubkey) async {
    await db.deleteFollowingList(userPubkey);
  }

  @override
  Future<List<String>?> getMuteList(String userPubkey) async {
    return await db.getMuteList(userPubkey);
  }

  @override
  Future<void> saveMuteList(String userPubkey, List<String> muteList) async {
    await db.saveMuteList(userPubkey, muteList);
  }

  @override
  Future<bool> hasMuteList(String userPubkey) async {
    return await db.hasMuteList(userPubkey);
  }

  @override
  Future<void> deleteMuteList(String userPubkey) async {
    await db.deleteMuteList(userPubkey);
  }

  @override
  Future<bool> isFollowing(String userPubkey, String targetPubkey) async {
    final followingList = await getFollowingList(userPubkey);
    if (followingList == null) return false;
    return followingList.contains(targetPubkey);
  }

  @override
  Future<bool> isMuted(String userPubkey, String targetPubkey) async {
    final muteList = await db.getMuteList(userPubkey);
    if (muteList == null) return false;
    return muteList.contains(targetPubkey);
  }

  @override
  Future<void> follow(String userPubkey, String targetPubkey) async {
    final currentList = await db.getFollowingList(userPubkey) ?? [];
    if (!currentList.contains(targetPubkey)) {
      final updatedList = [...currentList, targetPubkey];
      await saveFollowingList(userPubkey, updatedList);
    }
  }

  @override
  Future<void> unfollow(String userPubkey, String targetPubkey) async {
    if (userPubkey == targetPubkey) {
      return;
    }
    
    final currentList = await db.getFollowingList(userPubkey) ?? [];
    if (currentList.contains(targetPubkey)) {
      final updatedList = currentList.where((p) => p != targetPubkey).toList();
      await saveFollowingList(userPubkey, updatedList);
    }
  }

  @override
  Future<void> mute(String userPubkey, String targetPubkey) async {
    final currentList = await db.getMuteList(userPubkey) ?? [];
    if (!currentList.contains(targetPubkey)) {
      final updatedList = [...currentList, targetPubkey];
      await db.saveMuteList(userPubkey, updatedList);
    }
  }

  @override
  Future<void> unmute(String userPubkey, String targetPubkey) async {
    final currentList = await db.getMuteList(userPubkey) ?? [];
    if (currentList.contains(targetPubkey)) {
      final updatedList = currentList.where((p) => p != targetPubkey).toList();
      await db.saveMuteList(userPubkey, updatedList);
    }
  }
}
