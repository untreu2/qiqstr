import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  Future<void> saveNsecAndNpub(String nsec, String npub) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('privateKey', nsec);
    await prefs.setString('npub', npub);
  }

  Future<String?> getPrivateKey() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('privateKey');
  }

  Future<String?> getNpub() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('npub');
  }
}
