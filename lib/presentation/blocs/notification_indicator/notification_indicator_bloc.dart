import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../domain/entities/notification_item.dart';
import 'notification_indicator_event.dart';
import 'notification_indicator_state.dart';

class NotificationIndicatorBloc
    extends Bloc<NotificationIndicatorEvent, NotificationIndicatorState> {
  final SyncService _syncService;
  final AuthService _authService;
  final NotificationRepository _notificationRepository;

  static const String _lastCheckedKey = 'notification_last_checked_timestamp';

  int _lastCheckedTimestamp = 0;
  int _latestNotificationTimestamp = 0;
  StreamSubscription<List<NotificationItem>>? _notificationSubscription;
  String? _currentUserHex;
  int _watchGeneration = 0;

  NotificationIndicatorBloc({
    required SyncService syncService,
    required AuthService authService,
    required NotificationRepository notificationRepository,
  })  : _syncService = syncService,
        _authService = authService,
        _notificationRepository = notificationRepository,
        super(const NotificationIndicatorInitial()) {
    on<NotificationIndicatorInitialized>(
      _onInitialized,
      transformer: restartable(),
    );
    on<NotificationIndicatorNewReceived>(_onNewNotificationReceived);
    on<NotificationIndicatorChecked>(_onChecked);
    on<_NotificationDataUpdated>(_onDataUpdated);
  }

  Future<void> _onInitialized(
    NotificationIndicatorInitialized event,
    Emitter<NotificationIndicatorState> emit,
  ) async {
    final userHex = _authService.currentUserPubkeyHex;
    final generation = ++_watchGeneration;
    _currentUserHex = userHex;
    _latestNotificationTimestamp = 0;
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    if (generation != _watchGeneration || emit.isDone) return;
    if (userHex == null || userHex.isEmpty) {
      _lastCheckedTimestamp = 0;
      emit(const NotificationIndicatorLoaded(hasNewNotifications: false));
      return;
    }

    _lastCheckedTimestamp = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastCheckedTimestamp = prefs.getInt(_keyForUser(userHex)) ?? 0;

      final notifications =
          await _notificationRepository.getNotifications(userHex, limit: 50);
      if (isClosed || generation != _watchGeneration || emit.isDone) return;

      if (notifications.isNotEmpty) {
        final latestTimestamp = notifications
            .map((e) => e.createdAt)
            .reduce((a, b) => a > b ? a : b);
        _latestNotificationTimestamp = latestTimestamp;

        if (_lastCheckedTimestamp == 0) {
          _lastCheckedTimestamp = latestTimestamp;
          await prefs.setInt(
            _keyForUser(userHex),
            _lastCheckedTimestamp,
          );
          if (isClosed || generation != _watchGeneration || emit.isDone) {
            return;
          }
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

      _watchNotifications(userHex, generation);
      _syncInBackground(userHex, generation);
    } catch (e) {
      if (!emit.isDone &&
          generation == _watchGeneration &&
          _currentUserHex == userHex) {
        emit(const NotificationIndicatorLoaded(hasNewNotifications: false));
        _watchNotifications(userHex, generation);
        _syncInBackground(userHex, generation);
      }
    }
  }

  String _keyForUser(String userHex) => '${_lastCheckedKey}_$userHex';

  void _watchNotifications(String userHex, int generation) {
    _notificationSubscription =
        _notificationRepository.watchNotifications(userHex, limit: 50).listen(
      (notifications) {
        if (isClosed ||
            generation != _watchGeneration ||
            _currentUserHex != userHex) {
          return;
        }
        add(_NotificationDataUpdated(notifications, userHex, generation));
      },
    );
  }

  void _syncInBackground(String userHex, int generation) {
    Future.microtask(() async {
      if (isClosed ||
          generation != _watchGeneration ||
          _currentUserHex != userHex) {
        return;
      }
      try {
        await _syncService.syncNotifications(userHex);
      } catch (_) {}
    });
  }

  void _onDataUpdated(
    _NotificationDataUpdated event,
    Emitter<NotificationIndicatorState> emit,
  ) {
    if (event.generation != _watchGeneration ||
        event.userHex != _currentUserHex) {
      return;
    }
    if (event.notifications.isEmpty) return;

    final latestTimestamp = event.notifications
        .map((e) => e.createdAt)
        .reduce((a, b) => a > b ? a : b);
    if (latestTimestamp > _latestNotificationTimestamp) {
      _latestNotificationTimestamp = latestTimestamp;
    }

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
    final userHex = _currentUserHex;
    final generation = _watchGeneration;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final checkedTimestamp =
        _latestNotificationTimestamp > 0 ? _latestNotificationTimestamp : now;
    _lastCheckedTimestamp = checkedTimestamp;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (userHex != null) {
        await prefs.setInt(_keyForUser(userHex), checkedTimestamp);
      }
    } catch (_) {}

    if (!emit.isDone &&
        generation == _watchGeneration &&
        _currentUserHex == userHex) {
      emit(const NotificationIndicatorLoaded(hasNewNotifications: false));
    }
  }

  @override
  Future<void> close() {
    _watchGeneration++;
    _notificationSubscription?.cancel();
    return super.close();
  }
}

class _NotificationDataUpdated extends NotificationIndicatorEvent {
  final List<NotificationItem> notifications;
  final String userHex;
  final int generation;

  const _NotificationDataUpdated(
    this.notifications,
    this.userHex,
    this.generation,
  );

  @override
  List<Object?> get props => [notifications, userHex, generation];
}
