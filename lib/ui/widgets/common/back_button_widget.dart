import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';
import 'common_buttons.dart';

enum BackButtonType {
  appBar,
  floating,
}

class BackButtonWidget extends StatelessWidget {
  final BackButtonType type;
  final VoidCallback? onPressed;
  final Color? iconColor;
  final double? iconSize;
  final String? tooltip;
  final String? semanticsLabel;
  final double? topOffset;

  const BackButtonWidget({
    super.key,
    this.type = BackButtonType.floating,
    this.onPressed,
    this.iconColor,
    this.iconSize,
    this.tooltip,
    this.semanticsLabel,
    this.topOffset,
  });

  const BackButtonWidget.appBar({
    super.key,
    this.onPressed,
    this.iconColor,
    this.iconSize = 20,
    this.tooltip = 'Go back',
    this.semanticsLabel = 'Go back to previous screen',
    this.topOffset,
  }) : type = BackButtonType.appBar;

  const BackButtonWidget.floating({
    super.key,
    this.onPressed,
    this.iconColor,
    this.iconSize,
    this.tooltip,
    this.semanticsLabel = 'Go back to previous screen',
    this.topOffset,
  }) : type = BackButtonType.floating;

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case BackButtonType.appBar:
        return _buildAppBarBackButton(context);
      case BackButtonType.floating:
        return _buildFloatingBackButton(context);
    }
  }

  Widget _buildAppBarBackButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Semantics(
        label: semanticsLabel ?? 'Go back to previous screen',
        button: true,
        child: IconActionButton(
          icon: Icons.arrow_back_ios_new_rounded,
          iconColor: iconColor ?? context.colors.textPrimary,
          onPressed: onPressed ?? () => Navigator.pop(context),
          tooltip: tooltip ?? 'Go back',
          size: ButtonSize.small,
        ),
      ),
    );
  }

  Widget _buildFloatingBackButton(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + (topOffset ?? 14),
      left: 16,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: context.colors.textPrimary,
          borderRadius: BorderRadius.circular(22.0),
        ),
        child: GestureDetector(
          onTap: onPressed ?? () => Navigator.pop(context),
          behavior: HitTestBehavior.opaque,
          child: Semantics(
            label: semanticsLabel ?? 'Go back to previous screen',
            button: true,
            child: Icon(
              Icons.arrow_back,
              color: iconColor ?? context.colors.background,
              size: iconSize ?? 20,
            ),
          ),
        ),
      ),
    );
  }
}
