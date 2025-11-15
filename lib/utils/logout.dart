import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../ui/screens/auth/login_page.dart';
import '../core/di/app_di.dart';
import '../data/repositories/auth_repository.dart';
import '../ui/widgets/common/snackbar_widget.dart';

class Logout {
  static Future<void> performLogout(BuildContext context) async {
    final navigator = Navigator.of(context);

    try {
      final authRepository = AppDI.get<AuthRepository>();
      await authRepository.logout();

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
        AppSnackbar.error(context, 'Error during logout. Please try again.');
      }
    }
  }
}
