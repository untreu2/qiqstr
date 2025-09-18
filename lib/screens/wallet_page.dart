import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:bounce/bounce.dart';
import '../theme/theme_manager.dart';

class WalletPage extends StatelessWidget {
  const WalletPage({super.key});

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.account_balance_wallet,
                  size: 80,
                  color: context.colors.textSecondary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Wallet',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: context.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Soon',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Lightning wallet integration\ncoming soon!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: topPadding + 8,
            left: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(25.0),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: context.colors.backgroundTransparent,
                    border: Border.all(
                      color: context.colors.borderLight,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(25.0),
                  ),
                  child: Bounce(
                    scaleFactor: 0.85,
                    onTap: () => Navigator.pop(context),
                    behavior: HitTestBehavior.opaque,
                    child: Icon(
                      Icons.arrow_back,
                      color: context.colors.textSecondary,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
