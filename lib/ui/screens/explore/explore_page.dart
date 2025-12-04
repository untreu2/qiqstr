import 'package:flutter/material.dart';
import '../../theme/theme_manager.dart';

class ExplorePage extends StatelessWidget {
  const ExplorePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Center(
        child: Text(
          'Soon',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 24,
          ),
        ),
      ),
    );
  }
}

