import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../src/rust/api/database.dart' as rust_db;

abstract class InteractionRepository {
  Future<Map<String, int>> getCounts(List<String> noteIds);
  Future<Map<String, Map<String, dynamic>>> getData(
      List<String> noteIds, String userPubkey);
  Future<List<Map<String, dynamic>>> getDetails(String noteId);
  Future<bool> hasReacted(String noteId, String userPubkey);
  Future<bool> hasReposted(String noteId, String userPubkey);
  Future<String?> findRepostId(String userPubkey, String noteId);
}

class InteractionRepositoryImpl implements InteractionRepository {
  const InteractionRepositoryImpl();

  @override
  Future<Map<String, int>> getCounts(List<String> noteIds) async {
    if (noteIds.isEmpty) return {};
    try {
      final json = await rust_db.dbGetBatchInteractionCounts(noteIds: noteIds);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final result = <String, int>{};
      for (final entry in decoded.entries) {
        final counts = entry.value as Map<String, dynamic>;
        final reactions = (counts['reactions'] as num?)?.toInt() ?? 0;
        final reposts = (counts['reposts'] as num?)?.toInt() ?? 0;
        final zaps = (counts['zaps'] as num?)?.toInt() ?? 0;
        final replies = (counts['replies'] as num?)?.toInt() ?? 0;
        result[entry.key] = reactions + reposts + zaps + replies;
      }
      return result;
    } catch (e) {
      if (kDebugMode) print('[InteractionRepository] getCounts error: $e');
      return {};
    }
  }

  @override
  Future<Map<String, Map<String, dynamic>>> getData(
      List<String> noteIds, String userPubkey) async {
    if (noteIds.isEmpty) return {};
    try {
      final json = await rust_db.dbGetBatchInteractionData(
          noteIds: noteIds, userPubkeyHex: userPubkey);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return decoded.map((key, value) =>
          MapEntry(key, Map<String, dynamic>.from(value as Map)));
    } catch (e) {
      if (kDebugMode) print('[InteractionRepository] getData error: $e');
      return {};
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getDetails(String noteId) async {
    try {
      final json = await rust_db.dbGetDetailedInteractions(noteId: noteId);
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('[InteractionRepository] getDetails error: $e');
      return [];
    }
  }

  @override
  Future<bool> hasReacted(String noteId, String userPubkey) async {
    try {
      return await rust_db.dbHasUserReacted(
          noteId: noteId, userPubkeyHex: userPubkey);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> hasReposted(String noteId, String userPubkey) async {
    try {
      return await rust_db.dbHasUserReposted(
          noteId: noteId, userPubkeyHex: userPubkey);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> findRepostId(String userPubkey, String noteId) async {
    try {
      return await rust_db.dbFindUserRepostEventId(
          userPubkeyHex: userPubkey, noteId: noteId);
    } catch (_) {
      return null;
    }
  }
}
