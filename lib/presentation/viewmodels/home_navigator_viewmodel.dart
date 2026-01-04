import 'dart:async';
import '../../core/base/base_view_model.dart';
import '../../data/repositories/notification_repository.dart';

class HomeNavigatorViewModel extends BaseViewModel {
  final NotificationRepository _notificationRepository;

  HomeNavigatorViewModel({
    required NotificationRepository notificationRepository,
  }) : _notificationRepository = notificationRepository {
    _subscribeToNewNotifications();
  }

  bool _hasNewNotifications = false;
  bool get hasNewNotifications => _hasNewNotifications;

  Future<void> _subscribeToNewNotifications() async {
    await executeOperation('subscribeToNewNotifications', () async {
      _hasNewNotifications = await _notificationRepository.hasNewNotifications();
      safeNotifyListeners();

      addSubscription(
        _notificationRepository.hasNewNotificationsStream.listen((hasNew) {
          if (!isDisposed) {
            _hasNewNotifications = hasNew;
            safeNotifyListeners();
          }
        }),
      );
    }, showLoading: false);
  }
}
