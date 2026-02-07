import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';

part 'event_model.g.dart';

enum SyncStatus {
  pending,
  synced,
  failed,
}

@collection
class EventModel {
  Id id = Isar.autoIncrement;

  @Index(unique: true, type: IndexType.hash)
  late String eventId;

  @Index(composite: [CompositeIndex('kind'), CompositeIndex('createdAt')])
  late String pubkey;

  @Index(composite: [CompositeIndex('createdAt')])
  late int kind;

  @Index()
  late int createdAt;

  late String content;
  late List<String> tags;
  late String sig;
  late String rawEvent;

  @Index()
  late DateTime cachedAt;

  String? relayUrl;

  @Index()
  String? dTag;

  @enumerated
  SyncStatus syncStatus = SyncStatus.synced;

  DateTime? lastSyncedAt;

  EventModel();

  static EventModel fromEventData(Map<String, dynamic> eventData,
      {String? relayUrl}) {
    final tags = eventData['tags'] as List<dynamic>? ?? [];
    final tagsSerialized = tags.map((tag) {
      if (tag is List) {
        return jsonEncode(tag);
      }
      return tag.toString();
    }).toList();

    String? dTagValue;
    for (final tag in tags) {
      if (tag is List && tag.isNotEmpty && tag[0] == 'd' && tag.length > 1) {
        dTagValue = tag[1]?.toString();
        break;
      }
    }

    return EventModel()
      ..eventId = eventData['id'] as String? ?? ''
      ..pubkey = eventData['pubkey'] as String? ?? ''
      ..kind = eventData['kind'] as int? ?? 0
      ..createdAt = eventData['created_at'] as int? ?? 0
      ..content = eventData['content'] as String? ?? ''
      ..tags = tagsSerialized
      ..sig = eventData['sig'] as String? ?? ''
      ..rawEvent = jsonEncode(eventData)
      ..cachedAt = DateTime.now()
      ..relayUrl = relayUrl
      ..dTag = dTagValue
      ..syncStatus = SyncStatus.synced
      ..lastSyncedAt = DateTime.now();
  }

  Map<String, dynamic> toEventData() {
    try {
      return jsonDecode(rawEvent) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[EventModel] Error parsing rawEvent: $e');
      return {
        'id': eventId,
        'pubkey': pubkey,
        'kind': kind,
        'created_at': createdAt,
        'content': content,
        'tags': tags.map((t) => jsonDecode(t) as List<dynamic>).toList(),
        'sig': sig,
      };
    }
  }

  List<List<String>> getTags() {
    return tags.map((tag) {
      try {
        final decoded = jsonDecode(tag) as List<dynamic>;
        return decoded.map((e) => e.toString()).toList();
      } catch (e) {
        return [tag];
      }
    }).toList();
  }

  String? getTagValue(String tagType, {int index = 1}) {
    final tagList = getTags();
    for (final tag in tagList) {
      if (tag.isNotEmpty && tag[0] == tagType && tag.length > index) {
        return tag[index];
      }
    }
    return null;
  }

  List<String> getTagValues(String tagType) {
    final tagList = getTags();
    final result = <String>[];
    for (final tag in tagList) {
      if (tag.isNotEmpty && tag[0] == tagType && tag.length > 1) {
        result.add(tag[1]);
      }
    }
    return result;
  }

  DateTime get createdAtDateTime {
    return DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
  }

  bool isExpired(Duration ttl) {
    return DateTime.now().difference(cachedAt) > ttl;
  }

  EventModel copyWith({
    String? eventId,
    String? pubkey,
    int? kind,
    int? createdAt,
    String? content,
    List<String>? tags,
    String? sig,
    String? rawEvent,
    DateTime? cachedAt,
    String? relayUrl,
    String? dTag,
    SyncStatus? syncStatus,
    DateTime? lastSyncedAt,
  }) {
    return EventModel()
      ..eventId = eventId ?? this.eventId
      ..pubkey = pubkey ?? this.pubkey
      ..kind = kind ?? this.kind
      ..createdAt = createdAt ?? this.createdAt
      ..content = content ?? this.content
      ..tags = tags ?? this.tags
      ..sig = sig ?? this.sig
      ..rawEvent = rawEvent ?? this.rawEvent
      ..cachedAt = cachedAt ?? this.cachedAt
      ..relayUrl = relayUrl ?? this.relayUrl
      ..dTag = dTag ?? this.dTag
      ..syncStatus = syncStatus ?? this.syncStatus
      ..lastSyncedAt = lastSyncedAt ?? this.lastSyncedAt;
  }
}
