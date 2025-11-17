import 'dart:async';

class StreamSubscriptionManager {
  final List<StreamSubscription> _subscriptions = [];
  final List<Timer> _timers = [];

  void addSubscription(StreamSubscription subscription) {
    _subscriptions.add(subscription);
  }

  void addTimer(Timer timer) {
    _timers.add(timer);
  }

  void cancelAll() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();

    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  void dispose() {
    cancelAll();
  }
}

mixin StreamSubscriptionMixin {
  final StreamSubscriptionManager _subscriptionManager = StreamSubscriptionManager();

  void addSubscription(StreamSubscription subscription) {
    _subscriptionManager.addSubscription(subscription);
  }

  void addTimer(Timer timer) {
    _subscriptionManager.addTimer(timer);
  }

  void disposeSubscriptions() {
    _subscriptionManager.dispose();
  }
}

