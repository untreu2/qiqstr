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
import 'models/notification_model.dart';
import 'models/zap_model.dart';

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
    Hive.registerAdapter(NotificationModelAdapter());
    Hive.registerAdapter(ZapModelAdapter());

    await Hive.openBox<LinkPreviewModel>('link_preview_cache');

    runApp(const ProviderScope(child: QiqstrApp()));
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
        textTheme: ThemeData.dark()
            .textTheme
            .apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            )
            .copyWith(
              bodyLarge: const TextStyle(height: 2.1),
              bodyMedium: const TextStyle(height: 2.1),
              bodySmall: const TextStyle(height: 2.1),
              titleLarge: const TextStyle(height: 2.1),
              titleMedium: const TextStyle(height: 2.1),
              titleSmall: const TextStyle(height: 2.1),
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
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            height: 2.1,
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

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _animation = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _controller.forward().whenComplete(() => _checkStoredNsec());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
        await Hive.openBox<NotificationModel>('notifications_$npub');
        await Hive.openBox<ZapModel>('zaps_$npub');

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
    return Scaffold(
      backgroundColor: Colors.black,
      body: FadeTransition(
        opacity: _animation,
        child: Center(
          child: Image.asset(
            'assets/main_icon.png',
            width: 100,
            height: 100,
          ),
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
        textTheme: ThemeData.dark().textTheme.copyWith(
              bodyLarge: const TextStyle(height: 2.1),
              bodyMedium: const TextStyle(height: 2.1),
            ),
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Initialization Error'),
        ),
        body: const Center(
          child: Text(
            'An error occurred while initializing the application.',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white,
              height: 2.1,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
