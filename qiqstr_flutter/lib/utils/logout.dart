import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../data/services/auth_service.dart';
import '../data/services/spark_service.dart';
import '../data/services/pinned_notes_service.dart';
import '../core/di/app_di.dart';
import '../src/rust/api/database.dart' as rust_db;
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
      await AppDI.get<SparkService>().disconnectSdk();
    } catch (e) {
      if (kDebugMode) print('Error disconnecting Spark SDK: $e');
    }
    PinnedNotesService.instance.clear();
  }

  static Future<void> _cleanupEverything(AuthService authService) async {
    try {
      await AppDI.get<SparkService>().disconnectSdk();
    } catch (e) {
      if (kDebugMode) print('Error disconnecting Spark SDK: $e');
    }

    PinnedNotesService.instance.clear();

    try {
      await rust_db.dbWipeDirectory();
    } catch (_) {
      try {
        await rust_db.dbWipe();
      } catch (e) {
        if (kDebugMode) print('Error wiping database: $e');
      }
    }

    await authService.logout();
  }
}
