import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';

enum ButtonSize {
  small,
  medium,
  large,
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ButtonSize size;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool isLoading;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.size = ButtonSize.medium,
    this.backgroundColor,
    this.foregroundColor,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final config = _getSizeConfig(size);

    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? colors.textPrimary,
        foregroundColor: foregroundColor ?? colors.background,
        padding: config.padding,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(config.borderRadius),
        ),
        elevation: 0,
      ),
      child: isLoading
          ? SizedBox(
              width: config.iconSize,
              height: config.iconSize,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  foregroundColor ?? colors.background,
                ),
              ),
            )
          : icon != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: config.iconSize),
                    SizedBox(width: config.spacing),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: config.fontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: config.fontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ButtonSize size;
  final Color? borderColor;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool isLoading;

  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.size = ButtonSize.medium,
    this.borderColor,
    this.backgroundColor,
    this.foregroundColor,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final config = _getSizeConfig(size);

    return OutlinedButton(
      onPressed: isLoading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide.none,
        backgroundColor: backgroundColor ?? colors.textPrimary,
        foregroundColor: foregroundColor ?? colors.background,
        disabledBackgroundColor: backgroundColor ?? colors.textPrimary,
        disabledForegroundColor:
            (foregroundColor ?? colors.background).withValues(alpha: 0.5),
        padding: config.padding,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(config.borderRadius),
        ),
      ),
      child: isLoading
          ? SizedBox(
              width: config.iconSize,
              height: config.iconSize,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  foregroundColor ?? colors.background,
                ),
              ),
            )
          : icon != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: config.iconSize),
                    SizedBox(width: config.spacing),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: config.fontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: config.fontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
    );
  }
}

class TextActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ButtonSize size;
  final Color? foregroundColor;

  const TextActionButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.size = ButtonSize.medium,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final config = _getSizeConfig(size);

    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: foregroundColor ?? colors.textPrimary,
        minimumSize: Size.zero,
        padding: config.padding,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: icon != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: config.iconSize),
                SizedBox(width: config.spacing),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: config.fontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          : Text(
              label,
              style: TextStyle(
                fontSize: config.fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}

class IconActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final ButtonSize size;
  final Color? backgroundColor;
  final Color? iconColor;
  final String? tooltip;
  final bool isCircular;

  const IconActionButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = ButtonSize.medium,
    this.backgroundColor,
    this.iconColor,
    this.tooltip,
    this.isCircular = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final config = _getSizeConfig(size);

    return IconButton(
      icon: Icon(icon, size: config.iconSize),
      onPressed: onPressed,
      color: iconColor ?? colors.background,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: backgroundColor ?? colors.textPrimary,
        padding: config.padding,
        shape: isCircular
            ? const CircleBorder()
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(config.borderRadius),
              ),
      ),
    );
  }
}

class _ButtonSizeConfig {
  final EdgeInsets padding;
  final double borderRadius;
  final double fontSize;
  final double iconSize;
  final double spacing;

  const _ButtonSizeConfig({
    required this.padding,
    required this.borderRadius,
    required this.fontSize,
    required this.iconSize,
    required this.spacing,
  });
}

_ButtonSizeConfig _getSizeConfig(ButtonSize size) {
  switch (size) {
    case ButtonSize.small:
      return const _ButtonSizeConfig(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        borderRadius: 24,
        fontSize: 13,
        iconSize: 16,
        spacing: 6,
      );
    case ButtonSize.medium:
      return const _ButtonSizeConfig(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        borderRadius: 24,
        fontSize: 14,
        iconSize: 18,
        spacing: 8,
      );
    case ButtonSize.large:
      return const _ButtonSizeConfig(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        borderRadius: 24,
        fontSize: 17,
        iconSize: 20,
        spacing: 10,
      );
  }
}
