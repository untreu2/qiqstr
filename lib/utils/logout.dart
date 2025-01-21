import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qiqstr/screens/login_page.dart';

class Logout {
  static Future<void> performLogout(BuildContext context) async {
    try {
      await Hive.deleteFromDisk();
      print('Hive storage cleared successfully.');

      const storage = FlutterSecureStorage();
      await storage.deleteAll();
      print('Secure storage cleared successfully.');

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => LoginPage()),
        (Route<dynamic> route) => false,
      );
    } catch (e) {
      print('Error during logout: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error during logout. Please try again.')),
      );
    }
  }
}
