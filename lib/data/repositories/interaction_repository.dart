import 'dart:async';
import 'base_repository.dart';

abstract class InteractionRepository {
  Future<Map<String, int>> getInteractionCounts(String noteId);
  Future<Map<String, Map<String, int>>> getBatchInteractionCounts(
      List<String> noteIds);
  Future<List<Map<String, dynamic>>> getDetailedInteractions(String noteId);
  Future<bool> hasUserReacted(String noteId, String userPubkey);
  Future<bool> hasUserReposted(String noteId, String userPubkey);
}

class InteractionRepositoryImpl extends BaseRepository
    implements InteractionRepository {
  InteractionRepositoryImpl({
    required super.db,
    required super.mapper,
  });

  @override
  Future<Map<String, int>> getInteractionCounts(String noteId) async {
    return await db.getInteractionCounts(noteId);
  }

  @override
  Future<Map<String, Map<String, int>>> getBatchInteractionCounts(
      List<String> noteIds) async {
    return await db.getCachedInteractionCounts(noteIds);
  }

  @override
  Future<List<Map<String, dynamic>>> getDetailedInteractions(
      String noteId) async {
    return await db.getDetailedInteractions(noteId);
  }

  @override
  Future<bool> hasUserReacted(String noteId, String userPubkey) async {
    return await db.hasUserReacted(noteId, userPubkey);
  }

  @override
  Future<bool> hasUserReposted(String noteId, String userPubkey) async {
    return await db.hasUserReposted(noteId, userPubkey);
  }
}
