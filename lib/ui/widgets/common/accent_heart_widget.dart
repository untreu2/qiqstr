import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';

class AccentHeartWidget extends StatelessWidget {
  final VoidCallback? onTap;

  const AccentHeartWidget({
    super.key,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: colors.accent.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.favorite,
          size: 24,
          color: colors.accent,
        ),
      ),
    );
  }
}

