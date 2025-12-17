import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';

enum FloatingBubblePosition {
  top,
  bottom,
}

class FloatingBubbleWidget extends StatelessWidget {
  final Widget child;
  final FloatingBubblePosition position;
  final ValueNotifier<bool>? visibilityNotifier;
  final bool isVisible;
  final VoidCallback? onTap;
  final double? topOffset;
  final double? bottomOffset;
  final Duration animationDuration;
  final EdgeInsets? padding;

  const FloatingBubbleWidget({
    super.key,
    required this.child,
    this.position = FloatingBubblePosition.top,
    this.visibilityNotifier,
    this.isVisible = true,
    this.onTap,
    this.topOffset,
    this.bottomOffset,
    this.animationDuration = const Duration(milliseconds: 200),
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    
    final double effectiveTopOffset = topOffset ?? 8;
    final double effectiveBottomOffset = bottomOffset ?? 14;
    
    Widget bubbleContent = Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.textPrimary,
        borderRadius: BorderRadius.circular(40),
      ),
      child: child,
    );

    if (onTap != null) {
      bubbleContent = GestureDetector(
        onTap: onTap,
        child: bubbleContent,
      );
    }

    Widget buildAnimatedBubble(bool show) {
      return AnimatedOpacity(
        opacity: show ? 1.0 : 0.0,
        duration: animationDuration,
        child: IgnorePointer(
          ignoring: !show,
          child: bubbleContent,
        ),
      );
    }

    if (visibilityNotifier != null) {
      return ValueListenableBuilder<bool>(
        valueListenable: visibilityNotifier!,
        builder: (context, show, _) {
          return Positioned(
            top: position == FloatingBubblePosition.top
                ? topPadding + effectiveTopOffset
                : null,
            bottom: position == FloatingBubblePosition.bottom
                ? bottomPadding + effectiveBottomOffset
                : null,
            left: 0,
            right: 0,
            child: Center(
              child: buildAnimatedBubble(show),
            ),
          );
        },
      );
    }

    return Positioned(
      top: position == FloatingBubblePosition.top
          ? topPadding + effectiveTopOffset
          : null,
      bottom: position == FloatingBubblePosition.bottom
          ? bottomPadding + effectiveBottomOffset
          : null,
      left: 0,
      right: 0,
      child: Center(
        child: buildAnimatedBubble(isVisible),
      ),
    );
  }
}

