import 'package:flutter/foundation.dart';

class ScrollToTopNotifier {
  ScrollToTopNotifier._();

  static final feed = ValueNotifier<int>(0);

  static void triggerFeed() => feed.value++;
}
