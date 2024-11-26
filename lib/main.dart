import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/note_model.dart';
import 'models/reaction_model.dart';
import 'models/reply_model.dart';
import 'screens/login_page.dart';
import 'screens/feed_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  Hive.registerAdapter(NoteModelAdapter());
  Hive.registerAdapter(ReactionModelAdapter());
  Hive.registerAdapter(ReplyModelAdapter());

  runApp(Qiqstr());
}

class Qiqstr extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Qiqstr',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Colors.grey,
          surface: Colors.black,
          error: Colors.grey,
          onPrimary: Colors.black,
          onSecondary: Colors.white,
          onSurface: Colors.white,
          onError: Colors.black,
        ),
      ),
      home: SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _checkStoredNsec();
  }

  Future<void> _checkStoredNsec() async {
    String? privateKey = await _secureStorage.read(key: 'privateKey');
    String? npub = await _secureStorage.read(key: 'npub');

    if (privateKey != null && npub != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => FeedPage(npub: npub),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const LoginPage(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
