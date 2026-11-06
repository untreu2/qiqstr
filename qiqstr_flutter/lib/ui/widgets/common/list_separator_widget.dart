import 'package:flutter/material.dart';

class ListSeparatorWidget extends StatelessWidget {
  const ListSeparatorWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: 20,
      child: Center(
        child: Container(
          height: 4,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      Colors.white.withValues(alpha: 0.12),
                      Colors.white.withValues(alpha: 0.04),
                      Colors.black.withValues(alpha: 0.3),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.9),
                      Colors.grey.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.12),
                    ],
            ),
          ),
        ),
      ),
    );
  }
}
