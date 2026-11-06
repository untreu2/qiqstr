import 'dart:async';

enum DbChangeType { feed, notification, profile, interaction, generic }

class DbChangeEvent {
  final DbChangeType type;
  final List<String> ids;

  const DbChangeEvent({required this.type, this.ids = const []});
}

class RustDatabaseService {
  static final RustDatabaseService _instance = RustDatabaseService._internal();
  static RustDatabaseService get instance => _instance;

  RustDatabaseService._internal();

  final _changeController = StreamController<DbChangeEvent>.broadcast();

  Stream<DbChangeEvent> get onDbChange => _changeController.stream;

  Stream<void> get onChange => _changeController.stream.map<void>((_) {});

  Stream<void> get onFeedChange => _changeController.stream
      .where(
          (e) => e.type == DbChangeType.feed || e.type == DbChangeType.generic)
      .map<void>((_) {});

  Stream<void> get onNotificationChange => _changeController.stream
      .where((e) =>
          e.type == DbChangeType.notification || e.type == DbChangeType.generic)
      .map<void>((_) {});

  Stream<void> get onProfileChange => _changeController.stream
      .where((e) =>
          e.type == DbChangeType.profile || e.type == DbChangeType.generic)
      .map<void>((_) {});

  Stream<void> get onInteractionChange => _changeController.stream
      .where((e) =>
          e.type == DbChangeType.interaction || e.type == DbChangeType.generic)
      .map<void>((_) {});

  void notifyChange() {
    if (!_changeController.isClosed) {
      _changeController.add(const DbChangeEvent(type: DbChangeType.generic));
    }
  }

  void notifyFeedChange({List<String> ids = const []}) {
    if (!_changeController.isClosed) {
      _changeController.add(DbChangeEvent(type: DbChangeType.feed, ids: ids));
    }
  }

  void notifyNotificationChange({List<String> ids = const []}) {
    if (!_changeController.isClosed) {
      _changeController
          .add(DbChangeEvent(type: DbChangeType.notification, ids: ids));
    }
  }

  void notifyProfileChange({List<String> ids = const []}) {
    if (!_changeController.isClosed) {
      _changeController
          .add(DbChangeEvent(type: DbChangeType.profile, ids: ids));
    }
  }

  void notifyInteractionChange({List<String> ids = const []}) {
    if (!_changeController.isClosed) {
      _changeController
          .add(DbChangeEvent(type: DbChangeType.interaction, ids: ids));
    }
  }

  Future<void> close() async {
    await _changeController.close();
  }
}
