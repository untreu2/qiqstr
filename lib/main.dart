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
import 'models/zap_model.dart';
import 'models/notification_model.dart';
import 'screens/login_page.dart';
import 'screens/home_navigator.dart';
import 'services/data_service.dart'; 

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
    Hive.registerAdapter(ZapModelAdapter());
    Hive.registerAdapter(NotificationModelAdapter());

    await Hive.openBox<LinkPreviewModel>('link_preview_cache');

    final secureStorage = const FlutterSecureStorage();
    String? privateKey = await secureStorage.read(key: 'privateKey');
    String? npub = await secureStorage.read(key: 'npub');

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
      await Hive.openBox<ZapModel>('zaps_$npub');
      await Hive.openBox<NotificationModel>('notifications_$npub');

      final dataService = DataService(npub: npub, dataType: DataType.feed);
      await dataService.initialize();
      await dataService.initializeConnections();

      runApp(ProviderScope(
        child: QiqstrApp(
          home: HomeNavigator(
            npub: npub,
            dataService: dataService,
          ),
        ),
      ));
    } else {
      runApp(const ProviderScope(child: QiqstrApp(home: LoginPage())));
    }
  } catch (e) {
    print('Hive initialization error: $e');
    try {
      await Hive.deleteFromDisk();
      print('Hive data deleted. Restarting app...');
      main();
    } catch (deleteError) {
      print('Failed to delete Hive data: $deleteError');
      runApp(const HiveErrorApp());
    }
  }
}

class QiqstrApp extends ConsumerWidget {
  final Widget home;
  const QiqstrApp({super.key, required this.home});

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
      home: home,
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
