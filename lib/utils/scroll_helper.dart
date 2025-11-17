import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class ScrollHelper {
  static void setupScrollListener({
    required ScrollController controller,
    required void Function(bool shouldShow) onAppBarVisibilityChange,
    Duration debounceDuration = const Duration(milliseconds: 100),
    double threshold = 50.0,
  }) {
    Timer? debounceTimer;

    controller.addListener(() {
      if (!controller.hasClients) return;

      debounceTimer?.cancel();
      debounceTimer = Timer(debounceDuration, () {
        if (!controller.hasClients) return;

        final offset = controller.offset;
        final direction = controller.position.userScrollDirection;

        bool shouldShow;

        if (offset < threshold) {
          shouldShow = true;
        } else if (direction == ScrollDirection.forward) {
          shouldShow = true;
        } else if (direction == ScrollDirection.reverse) {
          shouldShow = false;
        } else {
          shouldShow = offset < threshold;
        }

        onAppBarVisibilityChange(shouldShow);
      });
    });
  }

  static void setupScrollToTop({
    required ScrollController controller,
    required void Function() onScrollToTop,
    double threshold = 100.0,
  }) {
    Timer? debounceTimer;

    controller.addListener(() {
      if (!controller.hasClients) return;

      debounceTimer?.cancel();
      debounceTimer = Timer(const Duration(milliseconds: 100), () {
        if (!controller.hasClients) return;

        if (controller.offset > threshold) {
          onScrollToTop();
        }
      });
    });
  }

  static void animateToTop(ScrollController controller, {Duration duration = const Duration(milliseconds: 300)}) {
    if (controller.hasClients) {
      controller.animateTo(
        0,
        duration: duration,
        curve: Curves.easeOut,
      );
    }
  }
}

