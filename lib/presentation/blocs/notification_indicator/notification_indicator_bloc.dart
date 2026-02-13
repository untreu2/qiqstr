import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/rust_database_service.dart';
import 'notification_indicator_event.dart';
import 'notification_indicator_state.dart';

class NotificationIndicatorBloc
    extends Bloc<NotificationIndicatorEvent, NotificationIndicatorState> {
  final SyncService _syncService;
  final AuthService _authService;
  final RustDatabaseService _db;

  static const String _lastCheckedKey = 'notification_last_checked_timestamp';

  int _lastCheckedTimestamp = 0;
  StreamSubscription<List<Map<String, dynamic>>>? _notificationSubscription;

  NotificationIndicatorBloc({
    required SyncService syncService,
    required AuthService authService,
    required RustDatabaseService db,
  })  : _syncService = syncService,
        _authService = authService,
        _db = db,
        super(const NotificationIndicatorInitial()) {
    on<NotificationIndicatorInitialized>(_onInitialized);
    on<NotificationIndicatorNewReceived>(_onNewNotificationReceived);
    on<NotificationIndicatorChecked>(_onChecked);
    on<_NotificationDataUpdated>(_onDataUpdated);
  }

  Future<void> _onInitialized(
    NotificationIndicatorInitialized event,
    Emitter<NotificationIndicatorState> emit,
  ) async {
    final userHex = _authService.currentUserPubkeyHex;
    if (userHex == null || userHex.isEmpty) {
      emit(const NotificationIndicatorLoaded(hasNewNotifications: false));
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      _lastCheckedTimestamp = prefs.getInt(_lastCheckedKey) ?? 0;

      await _syncService.syncNotifications(userHex);

      final notifications =
          await _db.getCachedNotifications(userHex, limit: 50);

      if (notifications.isNotEmpty) {
        final latestTimestamp = notifications
            .map((e) => (e['created_at'] as int?) ?? 0)
            .reduce((a, b) => a > b ? a : b);

        if (_lastCheckedTimestamp == 0) {
          _lastCheckedTimestamp = latestTimestamp;
          await prefs.setInt(_lastCheckedKey, _lastCheckedTimestamp);
          emit(const NotificationIndicatorLoaded(hasNewNotifications: false));
        } else {
          final hasNew = latestTimestamp > _lastCheckedTimestamp;
          emit(NotificationIndicatorLoaded(
            hasNewNotifications: hasNew,
            notificationCount: notifications.length,
          ));
        }
      } else {
        emit(const NotificationIndicatorLoaded(hasNewNotifications: false));
      }

      _watchNotifications(userHex);
    } catch (e) {
      emit(const NotificationIndicatorLoaded(hasNewNotifications: false));
    }
  }

  void _watchNotifications(String userHex) {
    _notificationSubscription?.cancel();
    _notificationSubscription =
        _db.watchNotifications(userHex, limit: 50).listen((notifications) {
      if (isClosed) return;
      add(_NotificationDataUpdated(notifications));
    });
  }

  void _onDataUpdated(
    _NotificationDataUpdated event,
    Emitter<NotificationIndicatorState> emit,
  ) {
    if (event.notifications.isEmpty) return;

    final latestTimestamp = event.notifications
        .map((e) => (e['created_at'] as int?) ?? 0)
        .reduce((a, b) => a > b ? a : b);

    if (_lastCheckedTimestamp > 0 && latestTimestamp > _lastCheckedTimestamp) {
      emit(NotificationIndicatorLoaded(
        hasNewNotifications: true,
        notificationCount: event.notifications.length,
      ));
    }
  }

  void _onNewNotificationReceived(
    NotificationIndicatorNewReceived event,
    Emitter<NotificationIndicatorState> emit,
  ) {
    emit(const NotificationIndicatorLoaded(hasNewNotifications: true));
  }

  Future<void> _onChecked(
    NotificationIndicatorChecked event,
    Emitter<NotificationIndicatorState> emit,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _lastCheckedTimestamp = now;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastCheckedKey, _lastCheckedTimestamp);
    } catch (_) {}

    emit(const NotificationIndicatorLoaded(hasNewNotifications: false));
  }

  @override
  Future<void> close() {
    _notificationSubscription?.cancel();
    return super.close();
  }
}

class _NotificationDataUpdated extends NotificationIndicatorEvent {
  final List<Map<String, dynamic>> notifications;
  const _NotificationDataUpdated(this.notifications);

  @override
  List<Object?> get props => [notifications];
}
