import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/data_service.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../models/repost_model.dart';

/// Manages DataService instances to prevent expensive creation/destruction cycles
/// and ensure proper resource management across the application.
class DataServiceManager {
  static final DataServiceManager _instance = DataServiceManager._internal();
  factory DataServiceManager() => _instance;
  DataServiceManager._internal();

  static DataServiceManager get instance => _instance;

  final Map<String, DataService> _services = {};
  final Map<String, int> _referenceCount = {};

  /// Get or create a DataService for the given parameters
  /// Uses a combination of npub and dataType as the key
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
      // Increment reference count
      _referenceCount[key] = (_referenceCount[key] ?? 0) + 1;
      debugPrint('[DataServiceManager] Reusing existing service for $key (refs: ${_referenceCount[key]})');
      return _services[key]!;
    }

    // Create new service
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

  /// Release a reference to a DataService
  /// Only closes the service when all references are released
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
      // No more references, close the service
      final service = _services[key]!;
      await service.closeConnections();

      _services.remove(key);
      _referenceCount.remove(key);

      debugPrint('[DataServiceManager] Closed and removed service for $key');
    }
  }

  /// Get an existing service without creating a new one
  DataService? getExistingService({
    required String npub,
    required DataType dataType,
  }) {
    final key = _generateKey(npub, dataType);
    return _services[key];
  }

  /// Check if a service exists for the given parameters
  bool hasService({
    required String npub,
    required DataType dataType,
  }) {
    final key = _generateKey(npub, dataType);
    return _services.containsKey(key);
  }

  /// Get the reference count for a service
  int getReferenceCount({
    required String npub,
    required DataType dataType,
  }) {
    final key = _generateKey(npub, dataType);
    return _referenceCount[key] ?? 0;
  }

  /// Get all active services (for debugging)
  Map<String, DataService> get activeServices => Map.unmodifiable(_services);

  /// Get service statistics
  Map<String, dynamic> getStatistics() {
    return {
      'totalServices': _services.length,
      'serviceKeys': _services.keys.toList(),
      'referenceCounts': Map.from(_referenceCount),
    };
  }

  /// Force close all services (use with caution)
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

  /// Generate a unique key for the service based on npub and dataType
  String _generateKey(String npub, DataType dataType) {
    return '${npub}_${dataType.toString().split('.').last}';
  }

  /// Clean up services that haven't been used recently (optional optimization)
  Future<void> performMaintenanceCleanup() async {
    // This could be extended to track last access time and clean up
    // services that haven't been used recently, but for now we rely
    // on reference counting only
    debugPrint('[DataServiceManager] Maintenance cleanup completed');
  }
}

/// Extension to make DataServiceManager usage easier
extension DataServiceManagerHelper on DataServiceManager {
  /// Convenience method to get a feed service
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

  /// Convenience method to get a profile service
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

  /// Release a feed service
  Future<void> releaseFeedService(String npub) async {
    await releaseService(npub: npub, dataType: DataType.feed);
  }

  /// Release a profile service
  Future<void> releaseProfileService(String npub) async {
    await releaseService(npub: npub, dataType: DataType.profile);
  }
}
