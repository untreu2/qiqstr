import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../screens/login_page.dart';
import '../core/di/app_di.dart';
import '../data/repositories/auth_repository.dart';
import '../widgets/toast_widget.dart';

class Logout {
  static Future<void> performLogout(BuildContext context) async {
    // Store references before async operations
    final navigator = Navigator.of(context);

    try {
      // Clear authentication via repository
      final authRepository = AppDI.get<AuthRepository>();
      await authRepository.logout();

      // Clear secure storage
      const storage = FlutterSecureStorage();
      await storage.deleteAll();
      if (kDebugMode) {
        print('Secure storage cleared successfully.');
      }

      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (Route<dynamic> route) => false,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error during logout: $e');
      }
      if (context.mounted) {
        AppToast.error(context, 'Error during logout. Please try again.');
      }
    }
  }
}
