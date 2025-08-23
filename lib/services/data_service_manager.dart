import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/data_service.dart';
import '../services/relay_service.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../models/repost_model.dart';

class DataServiceManager {
  static final DataServiceManager _instance = DataServiceManager._internal();
  factory DataServiceManager() => _instance;
  DataServiceManager._internal();

  static DataServiceManager get instance => _instance;

  final Map<String, DataService> _services = {};
  final Map<String, int> _referenceCount = {};

  DataService getOrCreateService({
    required String npub,
    required DataType dataType,
    Function(NoteModel)? onNewNote,
    Function(String, List<ReactionModel>)? onReactionsUpdated,
    Function(String, List<ReplyModel>)? onRepliesUpdated,
    Function(String, int)? onReactionCountUpdated,
    Function(String, int)? onReplyCountUpdated,
    Function(String, List<RepostModel>)? onRepostsUpdated,
    Function(String, int)? onRepostCountUpdated,
  }) {
    final key = _generateKey(npub, dataType);

    if (_services.containsKey(key)) {
      _referenceCount[key] = (_referenceCount[key] ?? 0) + 1;
      debugPrint('[DataServiceManager] Reusing existing service for $key (refs: ${_referenceCount[key]})');
      return _services[key]!;
    }

    final service = DataService(
      npub: npub,
      dataType: dataType,
      onNewNote: onNewNote,
      onReactionsUpdated: onReactionsUpdated,
      onRepliesUpdated: onRepliesUpdated,
      onReactionCountUpdated: onReactionCountUpdated,
      onReplyCountUpdated: onReplyCountUpdated,
      onRepostsUpdated: onRepostsUpdated,
      onRepostCountUpdated: onRepostCountUpdated,
    );

    _services[key] = service;
    _referenceCount[key] = 1;

    debugPrint('[DataServiceManager] Created new service for $key');
    return service;
  }

  Future<void> releaseService({
    required String npub,
    required DataType dataType,
  }) async {
    final key = _generateKey(npub, dataType);

    if (!_services.containsKey(key)) {
      debugPrint('[DataServiceManager] Warning: Trying to release non-existent service $key');
      return;
    }

    _referenceCount[key] = (_referenceCount[key] ?? 1) - 1;

    debugPrint('[DataServiceManager] Released reference for $key (refs: ${_referenceCount[key]})');

    if (_referenceCount[key]! <= 0) {
      final service = _services[key]!;
      await service.closeConnections();

      _services.remove(key);
      _referenceCount.remove(key);

      debugPrint('[DataServiceManager] Removed service for $key (WebSocket connections remain open)');
    }
  }

  DataService? getExistingService({
    required String npub,
    required DataType dataType,
  }) {
    final key = _generateKey(npub, dataType);
    return _services[key];
  }

  bool hasService({
    required String npub,
    required DataType dataType,
  }) {
    final key = _generateKey(npub, dataType);
    return _services.containsKey(key);
  }

  int getReferenceCount({
    required String npub,
    required DataType dataType,
  }) {
    final key = _generateKey(npub, dataType);
    return _referenceCount[key] ?? 0;
  }

  Map<String, DataService> get activeServices => Map.unmodifiable(_services);

  Map<String, dynamic> getStatistics() {
    return {
      'totalServices': _services.length,
      'serviceKeys': _services.keys.toList(),
      'referenceCounts': Map.from(_referenceCount),
    };
  }

  Future<void> closeAllServices() async {
    debugPrint('[DataServiceManager] Force closing all ${_services.length} services');

    final futures = <Future>[];
    for (final service in _services.values) {
      futures.add(service.closeConnections());
    }

    await Future.wait(futures);

    _services.clear();
    _referenceCount.clear();

    debugPrint('[DataServiceManager] All services closed');
  }

  Future<void> shutdownForAppTermination() async {
    debugPrint('[DataServiceManager] Shutting down for app termination');

    await closeAllServices();

    await WebSocketManager.instance.forceCloseConnections();

    debugPrint('[DataServiceManager] Complete shutdown completed');
  }

  String _generateKey(String npub, DataType dataType) {
    return '${npub}_${dataType.toString().split('.').last}';
  }

  Future<void> performMaintenanceCleanup() async {
    debugPrint('[DataServiceManager] Maintenance cleanup completed');
  }
}

extension DataServiceManagerHelper on DataServiceManager {
  DataService getOrCreateFeedService({
    required String npub,
    Function(NoteModel)? onNewNote,
    Function(String, List<ReactionModel>)? onReactionsUpdated,
    Function(String, List<ReplyModel>)? onRepliesUpdated,
    Function(String, int)? onReactionCountUpdated,
    Function(String, int)? onReplyCountUpdated,
    Function(String, List<RepostModel>)? onRepostsUpdated,
    Function(String, int)? onRepostCountUpdated,
  }) {
    return getOrCreateService(
      npub: npub,
      dataType: DataType.feed,
      onNewNote: onNewNote,
      onReactionsUpdated: onReactionsUpdated,
      onRepliesUpdated: onRepliesUpdated,
      onReactionCountUpdated: onReactionCountUpdated,
      onReplyCountUpdated: onReplyCountUpdated,
      onRepostsUpdated: onRepostsUpdated,
      onRepostCountUpdated: onRepostCountUpdated,
    );
  }

  DataService getOrCreateProfileService({
    required String npub,
    Function(NoteModel)? onNewNote,
    Function(String, List<ReactionModel>)? onReactionsUpdated,
    Function(String, List<ReplyModel>)? onRepliesUpdated,
    Function(String, int)? onReactionCountUpdated,
    Function(String, int)? onReplyCountUpdated,
    Function(String, List<RepostModel>)? onRepostsUpdated,
    Function(String, int)? onRepostCountUpdated,
  }) {
    return getOrCreateService(
      npub: npub,
      dataType: DataType.profile,
      onNewNote: onNewNote,
      onReactionsUpdated: onReactionsUpdated,
      onRepliesUpdated: onRepliesUpdated,
      onReactionCountUpdated: onReactionCountUpdated,
      onReplyCountUpdated: onReplyCountUpdated,
      onRepostsUpdated: onRepostsUpdated,
      onRepostCountUpdated: onRepostCountUpdated,
    );
  }

  Future<void> releaseFeedService(String npub) async {
    await releaseService(npub: npub, dataType: DataType.feed);
  }

  Future<void> releaseProfileService(String npub) async {
    await releaseService(npub: npub, dataType: DataType.profile);
  }
}
