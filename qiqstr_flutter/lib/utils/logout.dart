import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../data/services/auth_service.dart';
import '../data/services/spark_service.dart';
import '../data/services/nwc_service.dart';
import '../data/services/dm_service.dart';
import '../data/sync/sync_service.dart';
import '../data/services/pinned_notes_service.dart';
import '../core/di/app_di.dart';
import '../src/rust/api/database.dart' as rust_db;
import '../src/rust/api/relay.dart' as rust_relay;
import '../ui/widgets/common/snackbar_widget.dart';
import '../l10n/app_localizations.dart';

class Logout {
  static Future<void> performLogout(BuildContext context) async {
    try {
      final authService = AuthService.instance;
      final currentNpub = authService.currentUserNpub;

      final remainingAccounts = (await authService.getStoredAccounts())
          .where((account) => account.npub != currentNpub)
          .toList();

      if (remainingAccounts.isNotEmpty) {
        final nextAccount = remainingAccounts.first;
        final switched = await authService.switchAccount(nextAccount.npub);
        if (switched.isError) {
          if (context.mounted) {
            AppSnackbar.error(
              context,
              AppLocalizations.of(context)!.unknownError,
            );
          }
          return;
        }
        await _cleanupCurrentSession();
        if (currentNpub != null) {
          await authService.removeAccountFromList(currentNpub);
        }
        await AppDI.resetAndReinitialize();

        if (context.mounted) {
          context.go(
            '/home/feed?npub=${Uri.encodeComponent(nextAccount.npub)}',
          );
        }
      } else {
        final loggedOut = await authService.logout();
        if (loggedOut.isError) {
          if (context.mounted) {
            AppSnackbar.error(
              context,
              AppLocalizations.of(context)!.unknownError,
            );
          }
          return;
        }
        await _cleanupEverything();
        await AppDI.resetAndReinitialize();

        if (context.mounted) {
          context.go('/welcome');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error during logout: $e');
      }
      if (context.mounted) {
        AppSnackbar.error(context, AppLocalizations.of(context)!.unknownError);
      }
    }
  }

  static Future<void> _cleanupCurrentSession() async {
    AppDI.get<DmService>().reset();
    AppDI.get<SyncService>()
      ..stopPeriodicSync()
      ..stopRealtimeSubscriptions();
    AppDI.get<NwcService>().clearActiveAccount();
    try {
      final spark = AppDI.get<SparkService>();
      await spark.clearActiveAccount();
    } catch (e) {
      if (kDebugMode) print('Error disconnecting Spark SDK: $e');
    }
    PinnedNotesService.instance.clear();
  }

  static Future<void> _cleanupEverything() async {
    await _cleanupCurrentSession();
    try {
      await rust_relay.disconnectRelays();
      try {
        await rust_db.dbWipeDirectory();
      } catch (_) {
        try {
          await rust_db.dbWipe();
        } catch (e) {
          if (kDebugMode) print('Error wiping database: $e');
        }
      }
    } finally {
      await rust_relay.shutdownClient();
    }
  }
}
