import 'package:flutter_bloc/flutter_bloc.dart';
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

  int _lastCheckedTimestamp = 0;

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
      await _syncService.syncNotifications(userHex);

      final notifications =
          await _db.getCachedNotifications(userHex, limit: 50);

      if (notifications.isNotEmpty) {
        final latestTimestamp = notifications
            .map((e) => (e['created_at'] as int?) ?? 0)
            .reduce((a, b) => a > b ? a : b);

        final hasNew = _lastCheckedTimestamp > 0 &&
            latestTimestamp > _lastCheckedTimestamp;

        if (_lastCheckedTimestamp == 0) {
          _lastCheckedTimestamp = latestTimestamp;
        }

        emit(NotificationIndicatorLoaded(
          hasNewNotifications: hasNew,
          notificationCount: notifications.length,
        ));
      } else {
        emit(const NotificationIndicatorLoaded(hasNewNotifications: false));
      }
    } catch (e) {
      emit(const NotificationIndicatorLoaded(hasNewNotifications: false));
    }
  }

  void _onNewNotificationReceived(
    NotificationIndicatorNewReceived event,
    Emitter<NotificationIndicatorState> emit,
  ) {
    emit(const NotificationIndicatorLoaded(hasNewNotifications: true));
  }

  void _onChecked(
    NotificationIndicatorChecked event,
    Emitter<NotificationIndicatorState> emit,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _lastCheckedTimestamp = now;
    emit(const NotificationIndicatorLoaded(hasNewNotifications: false));
  }
}
