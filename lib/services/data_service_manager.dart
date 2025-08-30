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

  DataService? _activeService;
  String? _activeServiceKey;

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

    if (_activeService != null && _activeServiceKey == key) {
      debugPrint('[DataServiceManager] Reusing active service for $key');
      return _activeService!;
    }

    _closeActiveService();

    final service = DataService.instance;

    if (dataType == DataType.feed) {
      service.configureForFeed(
        npub: npub,
        onNewNote: onNewNote,
        onReactionsUpdated: onReactionsUpdated,
        onRepliesUpdated: onRepliesUpdated,
        onReactionCountUpdated: onReactionCountUpdated,
        onReplyCountUpdated: onReplyCountUpdated,
        onRepostsUpdated: onRepostsUpdated,
        onRepostCountUpdated: onRepostCountUpdated,
      );
    } else {
      service.configureForProfile(
        npub: npub,
        onNewNote: onNewNote,
        onReactionsUpdated: onReactionsUpdated,
        onRepliesUpdated: onRepliesUpdated,
        onReactionCountUpdated: onReactionCountUpdated,
        onReplyCountUpdated: onReplyCountUpdated,
        onRepostsUpdated: onRepostsUpdated,
        onRepostCountUpdated: onRepostCountUpdated,
      );
    }

    _activeService = service;
    _activeServiceKey = key;

    debugPrint('[DataServiceManager] Configured singleton service for $key');
    return service;
  }

  void _closeActiveService() {
    if (_activeService != null) {
      debugPrint('[DataServiceManager] Closing previous active service: $_activeServiceKey');
      _activeService!.closeConnections();
      _activeService = null;
      _activeServiceKey = null;
    }
  }

  Future<void> releaseService({
    required String npub,
    required DataType dataType,
  }) async {
    final key = _generateKey(npub, dataType);

    if (_activeServiceKey == key) {
      debugPrint('[DataServiceManager] Releasing active service for $key');
      _closeActiveService();
    } else {
      debugPrint('[DataServiceManager] Warning: Trying to release non-active service $key');
    }
  }

  DataService? getExistingService({
    required String npub,
    required DataType dataType,
  }) {
    final key = _generateKey(npub, dataType);
    return _activeServiceKey == key ? _activeService : null;
  }

  bool hasService({
    required String npub,
    required DataType dataType,
  }) {
    final key = _generateKey(npub, dataType);
    return _activeServiceKey == key;
  }

  DataService? get activeService => _activeService;
  String? get activeServiceKey => _activeServiceKey;

  Map<String, dynamic> getStatistics() {
    return {
      'activeService': _activeServiceKey ?? 'none',
      'hasActiveService': _activeService != null,
    };
  }

  Future<void> closeAllServices() async {
    debugPrint('[DataServiceManager] Closing active service');
    _closeActiveService();
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
    _closeActiveService();
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
