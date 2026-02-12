import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../data/services/auth_service.dart';
import '../core/di/app_di.dart';
import '../ui/widgets/common/snackbar_widget.dart';

class Logout {
  static Future<void> performLogout(BuildContext context) async {
    try {
      final authService = AuthService.instance;
      final currentNpub = authService.currentUserNpub;

      if (currentNpub != null) {
        await authService.removeAccountFromList(currentNpub);
      }

      final remainingAccounts = await authService.getStoredAccounts();

      if (remainingAccounts.isNotEmpty) {
        final nextAccount = remainingAccounts.first;
        await authService.switchAccount(nextAccount.npub);
        await AppDI.resetAndReinitialize();

        if (context.mounted) {
          context.go(
            '/home/feed?npub=${Uri.encodeComponent(nextAccount.npub)}',
          );
        }
      } else {
        await authService.logout();

        const storage = FlutterSecureStorage();
        await storage.deleteAll();

        if (context.mounted) {
          context.go('/login');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error during logout: $e');
      }
      if (context.mounted) {
        AppSnackbar.error(context, 'Error during logout. Please try again.');
      }
    }
  }
}
