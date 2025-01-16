import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/note_model.dart';
import 'models/reaction_model.dart';
import 'models/reply_model.dart';
import 'models/user_model.dart';
import 'screens/login_page.dart';
import 'screens/feed_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Hive.initFlutter();
    Hive.registerAdapter(NoteModelAdapter());
    Hive.registerAdapter(ReactionModelAdapter());
    Hive.registerAdapter(ReplyModelAdapter());
    Hive.registerAdapter(UserModelAdapter());

    const FlutterSecureStorage secureStorage = FlutterSecureStorage();
    String? privateKey = await secureStorage.read(key: 'privateKey');
    String? npub = await secureStorage.read(key: 'npub');

    if (privateKey != null && npub != null) {
      await Hive.openBox<NoteModel>('notes_Feed_$npub');
      await Hive.openBox<ReactionModel>('reactions_Feed_$npub');
      await Hive.openBox<ReplyModel>('replies_Feed_$npub');
      await Hive.openBox<NoteModel>('notes_Profile_$npub');
      await Hive.openBox<ReactionModel>('reactions_Profile_$npub');
      await Hive.openBox<ReplyModel>('replies_Profile_$npub');
      await Hive.openBox<UserModel>('users');
    }

    runApp(Qiqstr(
      isLoggedIn: privateKey != null && npub != null,
      npub: npub,
    ));
  } catch (e) {
    print('Error initializing Hive: $e');
    runApp(const HiveErrorApp());
  }
}

class Qiqstr extends StatelessWidget {
  final bool isLoggedIn;
  final String? npub;

  const Qiqstr({Key? key, required this.isLoggedIn, this.npub}) : super(key: key);

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
      home: isLoggedIn
          ? FeedPage(npub: npub!)
          : const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  SplashScreenState createState() => SplashScreenState();
}

class SplashScreenState extends State<SplashScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _checkStoredNsec();
  }

  Future<void> _checkStoredNsec() async {
    try {
      String? privateKey = await _secureStorage.read(key: 'privateKey');
      String? npub = await _secureStorage.read(key: 'npub');

      if (privateKey != null && npub != null) {
        await Hive.openBox<NoteModel>('notes_Feed_$npub');
        await Hive.openBox<ReactionModel>('reactions_Feed_$npub');
        await Hive.openBox<ReplyModel>('replies_Feed_$npub');
        await Hive.openBox<NoteModel>('notes_Profile_$npub');
        await Hive.openBox<ReactionModel>('reactions_Profile_$npub');
        await Hive.openBox<ReplyModel>('replies_Profile_$npub');
        await Hive.openBox<UserModel>('users');

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
    } catch (e) {
      print('Error reading secure storage or opening boxes: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("An error occurred while loading the app.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class HiveErrorApp extends StatelessWidget {
  const HiveErrorApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Initialization Error'),
        ),
        body: const Center(
          child: Text(
            'An error occurred while initializing the application.',
            style: TextStyle(fontSize: 18),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
