import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:carbon_icons/carbon_icons.dart';
import '../../theme/theme_manager.dart';
import '../../../l10n/app_localizations.dart';

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
  final Widget? customRightWidget;

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
    this.customRightWidget,
  });

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;
    final double effectiveTopOffset = topOffset ?? 14;
    final colors = context.colors;
    final l10n = AppLocalizations.of(context)!;

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
                    label: l10n.goBackToPreviousScreen,
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
          if (customRightWidget != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: customRightWidget!,
            )
          else if (showShareButton)
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
                    label: l10n.share,
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
    final processedBubble = _processCenterBubble(centerBubble!);

    final bubbleWidget = GestureDetector(
      onTap: onCenterBubbleTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: colors.textPrimary,
          borderRadius: BorderRadius.circular(40),
        ),
        child: processedBubble,
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

  Widget _processCenterBubble(Widget widget) {
    return _processWidgetRecursively(widget);
  }

  Widget _processWidgetRecursively(Widget widget) {
    if (widget is Text) {
      final text = widget.data ?? '';
      if (text.length > 15) {
        return Text(
          '${text.substring(0, 15)}...',
          style: widget.style,
          textAlign: widget.textAlign,
          maxLines: widget.maxLines ?? 1,
          overflow: TextOverflow.ellipsis,
        );
      }
      return widget;
    }

    if (widget is Row) {
      return Row(
        mainAxisSize: widget.mainAxisSize,
        mainAxisAlignment: widget.mainAxisAlignment,
        crossAxisAlignment: widget.crossAxisAlignment,
        children: widget.children
            .map((child) => _processWidgetRecursively(child))
            .toList(),
      );
    }

    if (widget is Flexible) {
      return Flexible(
        flex: widget.flex,
        fit: widget.fit,
        child: _processWidgetRecursively(widget.child),
      );
    }

    if (widget is Expanded) {
      return Expanded(
        flex: widget.flex,
        child: _processWidgetRecursively(widget.child),
      );
    }

    if (widget is Padding) {
      final padding = widget;
      return Padding(
        padding: padding.padding,
        child: padding.child != null
            ? _processWidgetRecursively(padding.child!)
            : null,
      );
    }

    if (widget is Container) {
      final container = widget;
      if (container.child != null) {
        return Container(
          key: container.key,
          alignment: container.alignment,
          padding: container.padding,
          color: container.color,
          decoration: container.decoration,
          foregroundDecoration: container.foregroundDecoration,
          constraints: container.constraints,
          margin: container.margin,
          transform: container.transform,
          transformAlignment: container.transformAlignment,
          child: _processWidgetRecursively(container.child!),
        );
      }
    }

    return widget;
  }
}
