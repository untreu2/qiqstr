import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';

enum IndicatorOrientation {
  horizontal,
  vertical,
}

enum IndicatorSize {
  small,
  big,
}

class IndicatorWidget extends StatelessWidget {
  final IndicatorOrientation orientation;
  final IndicatorSize size;
  final Color? color;

  const IndicatorWidget({
    super.key,
    this.orientation = IndicatorOrientation.vertical,
    this.size = IndicatorSize.small,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeManager>(
      builder: (context, themeManager, child) {
        final double width;
        final double height;
        final double borderRadius;

        if (orientation == IndicatorOrientation.horizontal) {
          if (size == IndicatorSize.small) {
            width = 18;
            height = 3;
            borderRadius = 1.5;
          } else {
            width = 56;
            height = 4;
            borderRadius = 2;
          }
        } else {
          if (size == IndicatorSize.small) {
            width = 5;
            height = 20;
            borderRadius = 2.5;
          } else {
            width = 8;
            height = 40;
            borderRadius = 4;
          }
        }

        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: color ?? themeManager.colors.accent,
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        );
      },
    );
  }
}

