import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../lib/data/repositories/notification_repository.dart';
import '../../../../lib/data/services/auth_service.dart';
import '../../../../lib/data/sync/sync_service.dart';
import '../../../../lib/domain/entities/notification_item.dart';
import '../../../../lib/presentation/blocs/notification/notification_bloc.dart';
import '../../../../lib/presentation/blocs/notification/notification_event.dart'
    hide NotificationsLoaded;
import '../../../../lib/presentation/blocs/notification/notification_state.dart';

class _Auth implements AuthService {
  @override
  String? currentUserPubkeyHex = 'user';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Notifications implements NotificationRepository {
  final updates = StreamController<List<NotificationItem>>.broadcast();
  Future<List<NotificationItem>> Function()? onLoadMore;

  @override
  Stream<List<NotificationItem>> watchNotifications(
    String userPubkey, {
    int limit = 200,
  }) => updates.stream;

  @override
  Future<List<NotificationItem>> getNotificationsBefore(
    String userPubkey, {
    required int beforeTimestamp,
    int limit = 100,
  }) async => await onLoadMore?.call() ?? [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sync implements SyncService {
  bool failLoadMore = false;
  int remoteCount = 0;

  @override
  Future<void> syncNotifications(
    String userPubkey, {
    bool force = false,
  }) async {}

  @override
  Future<int> syncOlderNotifications(
    String userPubkey, {
    required int beforeTimestamp,
    int limit = 100,
    int windowDays = 90,
  }) async {
    if (failLoadMore) throw StateError('offline');
    return remoteCount;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NotificationBloc bloc;
  late _Notifications repository;
  late _Sync sync;
  late _Auth auth;
  const notification = NotificationItem(
    id: 'one',
    type: NotificationType.reply,
    fromPubkey: 'author',
    createdAt: 100,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repository = _Notifications();
    sync = _Sync();
    auth = _Auth();
    bloc = NotificationBloc(
      notificationRepository: repository,
      syncService: sync,
      authService: auth,
    );
    await bloc.stream.firstWhere((state) => state is NotificationsLoaded);
    repository.updates.add([notification]);
    await bloc.stream.firstWhere(
      (state) => state is NotificationsLoaded && state.notifications.isNotEmpty,
    );
  });

  tearDown(() async {
    await bloc.close();
    await repository.updates.close();
  });

  for (final failureSource in ['network', 'database']) {
    test(
      'failed $failureSource pagination clears loading and remains retryable',
      () async {
        sync.failLoadMore = failureSource == 'network';
        if (failureSource == 'database') {
          repository.onLoadMore = () => Future.error(StateError('unavailable'));
        }
        bloc.add(const NotificationsLoadMoreRequested());
        await bloc.stream.firstWhere(
          (state) => state is NotificationsLoaded && state.isLoadingMore,
        );
        await bloc.stream.firstWhere(
          (state) => state is NotificationsLoaded && !state.isLoadingMore,
        );
        expect((bloc.state as NotificationsLoaded).hasReachedEnd, isFalse);
        sync.failLoadMore = false;
        repository.onLoadMore = null;
        bloc.add(const NotificationsLoadMoreRequested());
        await bloc.stream.firstWhere(
          (state) => state is NotificationsLoaded && state.hasReachedEnd,
        );
      },
    );
  }

  test('keeps read status when live updates repeat a notification', () async {
    bloc.add(const NotificationRead('one'));
    await bloc.stream.firstWhere(
      (state) => state is NotificationsLoaded && state.unreadCount == 0,
    );
    repository.updates.add([notification]);
    await Future<void>.delayed(Duration.zero);
    expect(
      (bloc.state as NotificationsLoaded).notifications.single['isRead'],
      true,
    );
    expect((bloc.state as NotificationsLoaded).unreadCount, 0);
  });

  test('switching account discards pending pages and read markers', () async {
    final pending = Completer<List<NotificationItem>>();
    repository.onLoadMore = () => pending.future;
    bloc.add(const NotificationsLoadMoreRequested());
    await bloc.stream.firstWhere(
      (state) => state is NotificationsLoaded && state.isLoadingMore,
    );
    auth.currentUserPubkeyHex = 'other';
    bloc.add(const NotificationsLoadRequested());
    await bloc.stream.firstWhere(
      (state) =>
          state is NotificationsLoaded && state.currentUserHex == 'other',
    );
    pending.complete([notification.copyWith(id: 'old-page', createdAt: 50)]);
    await Future<void>.delayed(Duration.zero);
    expect((bloc.state as NotificationsLoaded).notifications, isEmpty);
    expect((bloc.state as NotificationsLoaded).isLoadingMore, isFalse);
  });

  test(
    'watch errors are handled while cached notifications remain visible',
    () async {
      repository.updates.addError(StateError('disconnected'));
      await Future<void>.delayed(Duration.zero);
      expect(
        (bloc.state as NotificationsLoaded).notifications.single['id'],
        'one',
      );
    },
  );
}
