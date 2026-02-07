enum SyncPriority {
  critical,
  high,
  normal,
  low,
}

enum SyncTaskType {
  fetchFeed,
  fetchProfile,
  fetchProfiles,
  fetchNotifications,
  fetchArticles,
  fetchReplies,
  fetchFollowingList,
  fetchMuteList,
  publishNote,
  publishReaction,
  publishRepost,
  publishDelete,
  publishFollow,
  publishMute,
  publishProfile,
}

class SyncTask {
  final String id;
  final SyncTaskType type;
  final SyncPriority priority;
  final Map<String, dynamic> params;
  final int retryCount;
  final DateTime createdAt;

  SyncTask({
    required this.id,
    required this.type,
    this.priority = SyncPriority.normal,
    this.params = const {},
    this.retryCount = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  SyncTask copyWith({
    String? id,
    SyncTaskType? type,
    SyncPriority? priority,
    Map<String, dynamic>? params,
    int? retryCount,
    DateTime? createdAt,
  }) {
    return SyncTask(
      id: id ?? this.id,
      type: type ?? this.type,
      priority: priority ?? this.priority,
      params: params ?? this.params,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  SyncTask incrementRetry() {
    return copyWith(retryCount: retryCount + 1);
  }
}

class PublishTask extends SyncTask {
  final String eventId;

  PublishTask({
    required this.eventId,
    required super.priority,
    super.retryCount,
  }) : super(
          id: 'publish_$eventId',
          type: SyncTaskType.publishNote,
          params: {'eventId': eventId},
        );
}
