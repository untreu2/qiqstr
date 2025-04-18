import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/note_model.dart';
import 'models/reaction_model.dart';
import 'models/reply_model.dart';
import 'models/repost_model.dart';
import 'models/user_model.dart';
import 'models/following_model.dart';
import 'models/link_preview_model.dart';
import 'screens/login_page.dart';
import 'screens/feed_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Hive.initFlutter();
    Hive.registerAdapter(NoteModelAdapter());
    Hive.registerAdapter(ReactionModelAdapter());
    Hive.registerAdapter(ReplyModelAdapter());
    Hive.registerAdapter(RepostModelAdapter());
    Hive.registerAdapter(UserModelAdapter());
    Hive.registerAdapter(FollowingModelAdapter());
    Hive.registerAdapter(LinkPreviewModelAdapter());

    await Hive.openBox<LinkPreviewModel>('link_preview_cache');

    runApp(
      const ProviderScope(
        child: QiqstrApp(),
      ),
    );
  } catch (e) {
    print('Error initializing Hive: $e');
    runApp(const HiveErrorApp());
  }
}

class QiqstrApp extends ConsumerWidget {
  const QiqstrApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Qiqstr',
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.black,
        textTheme: Theme.of(context).textTheme.apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Colors.grey,
          surface: Colors.black,
          error: Colors.redAccent,
          onPrimary: Colors.black,
          onSecondary: Colors.white,
          onSurface: Colors.white,
          onError: Colors.black,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        buttonTheme: const ButtonThemeData(
          buttonColor: Colors.deepPurpleAccent,
          textTheme: ButtonTextTheme.primary,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
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
        await Hive.openBox<RepostModel>('reposts_Feed_$npub');
        await Hive.openBox<NoteModel>('notes_Profile_$npub');
        await Hive.openBox<ReactionModel>('reactions_Profile_$npub');
        await Hive.openBox<ReplyModel>('replies_Profile_$npub');
        await Hive.openBox<RepostModel>('reposts_Profile_$npub');

        await Hive.openBox<UserModel>('users');
        await Hive.openBox<FollowingModel>('followingBox');

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
        const SnackBar(
          content: Text("An error occurred while loading the app."),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(
          color: Colors.deepPurpleAccent,
        ),
      ),
    );
  }
}

class HiveErrorApp extends StatelessWidget {
  const HiveErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        textTheme: ThemeData.dark().textTheme,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Initialization Error'),
        ),
        body: Center(
          child: Text(
            'An error occurred while initializing the application.',
            style: const TextStyle(
              fontSize: 18,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
