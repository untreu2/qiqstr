import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../theme/theme_manager.dart';

class TopActionBarWidget extends StatelessWidget {
  final VoidCallback? onBackPressed;
  final Widget? centerBubble;
  final VoidCallback? onCenterBubbleTap;
  final ValueNotifier<bool>? centerBubbleVisibility;
  final bool isCenterBubbleVisible;
  final VoidCallback? onSharePressed;
  final double? topOffset;
  final bool showBackButton;
  final bool showShareButton;

  const TopActionBarWidget({
    super.key,
    this.onBackPressed,
    this.centerBubble,
    this.onCenterBubbleTap,
    this.centerBubbleVisibility,
    this.isCenterBubbleVisible = true,
    this.onSharePressed,
    this.topOffset,
    this.showBackButton = true,
    this.showShareButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;
    final double effectiveTopOffset = topOffset ?? 14;
    final colors = context.colors;

    return Positioned(
      top: topPadding + effectiveTopOffset,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showBackButton)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.textPrimary,
                  borderRadius: BorderRadius.circular(22.0),
                ),
                child: GestureDetector(
                  onTap: onBackPressed ?? () => context.pop(),
                  behavior: HitTestBehavior.opaque,
                  child: Semantics(
                    label: 'Go back to previous screen',
                    button: true,
                    child: Icon(
                      Icons.arrow_back,
                      color: colors.background,
                      size: 20,
                    ),
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 44 + 16),

          if (centerBubble != null)
            Expanded(
              child: Center(
                child: _buildCenterBubble(colors),
              ),
            ),

          if (showShareButton)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.textPrimary,
                  borderRadius: BorderRadius.circular(22.0),
                ),
                child: GestureDetector(
                  onTap: onSharePressed,
                  behavior: HitTestBehavior.opaque,
                  child: Semantics(
                    label: 'Share',
                    button: true,
                    child: Icon(
                      CarbonIcons.share,
                      color: colors.background,
                      size: 20,
                    ),
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 44 + 16),
        ],
      ),
    );
  }

  Widget _buildCenterBubble(dynamic colors) {
    final bubbleWidget = GestureDetector(
      onTap: onCenterBubbleTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: colors.textPrimary,
          borderRadius: BorderRadius.circular(40),
        ),
        child: centerBubble!,
      ),
    );

    if (centerBubbleVisibility != null) {
      return ValueListenableBuilder<bool>(
        valueListenable: centerBubbleVisibility!,
        builder: (context, show, _) {
          return AnimatedOpacity(
            opacity: show ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !show,
              child: bubbleWidget,
            ),
          );
        },
      );
    }

    return AnimatedOpacity(
      opacity: isCenterBubbleVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !isCenterBubbleVisible,
        child: bubbleWidget,
      ),
    );
  }
}

