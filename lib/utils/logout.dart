import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/di/app_di.dart';
import '../data/repositories/auth_repository.dart';
import '../ui/widgets/common/snackbar_widget.dart';

class Logout {
  static Future<void> performLogout(BuildContext context) async {
    try {
      final authRepository = AppDI.get<AuthRepository>();
      await authRepository.logout();

      const storage = FlutterSecureStorage();
      await storage.deleteAll();
      if (kDebugMode) {
        print('Secure storage cleared successfully.');
      }

      if (context.mounted) {
        context.go('/login');
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
