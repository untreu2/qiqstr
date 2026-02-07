import 'dart:async';

typedef EventProcessor = FutureOr<void> Function(
    Map<String, dynamic> eventData);

class EventKindRouterService {
  static EventKindRouterService? _instance;
  static EventKindRouterService get instance =>
      _instance ??= EventKindRouterService._internal();

  EventKindRouterService._internal();

  static const int kindProfile = 0;
  static const int kindNote = 1;
  static const int kindFollow = 3;
  static const int kindDeletion = 5;
  static const int kindRepost = 6;
  static const int kindReaction = 7;
  static const int kindZap = 9735;
  static const int kindMute = 10000;

  static const List<int> notificationKinds = [
    kindNote,
    kindRepost,
    kindReaction,
    kindZap
  ];

  Future<void> routeByKind(
    Map<String, dynamic> eventData,
    Map<int, EventProcessor> processors,
  ) async {
    final kind = eventData['kind'] as int? ?? 0;
    final processor = processors[kind];

    if (processor != null) {
      await processor(eventData);
    }
  }

  bool isNotificationKind(int kind) {
    return notificationKinds.contains(kind);
  }

  String? getNotificationTypeForKind(int kind) {
    switch (kind) {
      case kindNote:
        return 'mention';
      case kindRepost:
        return 'repost';
      case kindReaction:
        return 'reaction';
      case kindZap:
        return 'zap';
      default:
        return null;
    }
  }

  bool isSupportedKind(int kind) {
    return [
      kindProfile,
      kindNote,
      kindFollow,
      kindDeletion,
      kindRepost,
      kindReaction,
      kindZap,
      kindMute,
    ].contains(kind);
  }
}
