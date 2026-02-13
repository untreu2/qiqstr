import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../data/services/auth_service.dart';
import '../data/services/coinos_service.dart';
import '../data/services/rust_database_service.dart';
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
        await _cleanupCurrentSession();

        final nextAccount = remainingAccounts.first;
        await authService.switchAccount(nextAccount.npub);
        await AppDI.resetAndReinitialize();

        if (context.mounted) {
          context.go(
            '/home/feed?npub=${Uri.encodeComponent(nextAccount.npub)}',
          );
        }
      } else {
        await _cleanupEverything(authService);

        if (context.mounted) {
          context.go('/welcome');
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

  static Future<void> _cleanupCurrentSession() async {
    try {
      final coinosService = AppDI.get<CoinosService>();
      await coinosService.clearAuthData();
    } catch (e) {
      if (kDebugMode) print('Error clearing Coinos data: $e');
    }
  }

  static Future<void> _cleanupEverything(AuthService authService) async {
    try {
      final coinosService = AppDI.get<CoinosService>();
      await coinosService.clearAuthData();
    } catch (e) {
      if (kDebugMode) print('Error clearing Coinos data: $e');
    }

    try {
      final dbService = AppDI.get<RustDatabaseService>();
      await dbService.wipe();
    } catch (e) {
      if (kDebugMode) print('Error wiping database: $e');
    }

    await authService.logout();

    const storage = FlutterSecureStorage();
    await storage.deleteAll();
  }
}
