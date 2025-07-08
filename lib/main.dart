import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
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
  // Set up global error handling for unhandled exceptions
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    // Set up Flutter error handling
    FlutterError.onError = (FlutterErrorDetails details) {
      // Handle Flutter framework errors
      if (details.exception is SocketException) {
        // Silently handle socket exceptions to prevent spam
        return;
      }
      // Log other Flutter errors
      FlutterError.presentError(details);
    };

    // Set up platform dispatcher error handling
    try {
      PlatformDispatcher.instance.onError = (error, stack) {
        // Handle platform errors
        if (error is SocketException) {
          // Silently handle socket exceptions
          return true;
        }
        // Log other platform errors but don't crash
        print('Platform error: $error');
        return true;
      };
    } catch (e) {
      // Fallback if PlatformDispatcher is not available
      print('Could not set platform error handler: $e');
    }

    try {
      // Initialize Hive with optimized settings
      await _initializeHiveOptimized();

      final secureStorage = const FlutterSecureStorage();
      final credentials = await Future.wait([
        secureStorage.read(key: 'privateKey'),
        secureStorage.read(key: 'npub'),
      ]);
      
      final privateKey = credentials[0];
      final npub = credentials[1];

      if (privateKey != null && npub != null) {
        // Open boxes in parallel for faster startup
        await _openHiveBoxesParallel(npub);

        // Initialize DataService asynchronously
        final dataService = DataService(npub: npub, dataType: DataType.feed);
        
        // Show app immediately, initialize in background
        runApp(ProviderScope(
          child: QiqstrApp(
            home: HomeNavigator(
              npub: npub,
              dataService: dataService,
            ),
          ),
        ));
        
        // Initialize connections in background
        Future.microtask(() async {
          await dataService.initialize();
          await dataService.initializeConnections();
        });
      } else {
        runApp(const ProviderScope(child: QiqstrApp(home: LoginPage())));
      }
    } catch (e) {
      print('Initialization error: $e');
      await _handleInitializationError(e);
    }
  }, (error, stack) {
    // Handle any unhandled errors in the zone
    if (error is SocketException) {
      // Silently handle socket exceptions to prevent spam
      return;
    }
    // Log other unhandled errors but don't crash
    print('Unhandled error: $error');
  });
}

Future<void> _initializeHiveOptimized() async {
  await Hive.initFlutter();

  // Register adapters efficiently
  final adapters = [
    () => Hive.registerAdapter(NoteModelAdapter()),
    () => Hive.registerAdapter(ReactionModelAdapter()),
    () => Hive.registerAdapter(ReplyModelAdapter()),
    () => Hive.registerAdapter(RepostModelAdapter()),
    () => Hive.registerAdapter(UserModelAdapter()),
    () => Hive.registerAdapter(ZapModelAdapter()),
    () => Hive.registerAdapter(FollowingModelAdapter()),
    () => Hive.registerAdapter(LinkPreviewModelAdapter()),
    () => Hive.registerAdapter(NotificationModelAdapter()),
  ];

  for (int i = 0; i < adapters.length; i++) {
    final typeId = i == 8 ? 12 : i; // NotificationModel uses typeId 12
    if (!Hive.isAdapterRegistered(typeId)) {
      adapters[i]();
    }
  }

  // Open link preview cache
  await Hive.openBox<LinkPreviewModel>('link_preview_cache');
}

Future<void> _openHiveBoxesParallel(String npub) async {
  final boxFutures = [
    Hive.openBox<NoteModel>('notes_Feed_$npub'),
    Hive.openBox<ReactionModel>('reactions_Feed_$npub'),
    Hive.openBox<ReplyModel>('replies_Feed_$npub'),
    Hive.openBox<RepostModel>('reposts_Feed_$npub'),
    Hive.openBox<NoteModel>('notes_Profile_$npub'),
    Hive.openBox<ReactionModel>('reactions_Profile_$npub'),
    Hive.openBox<ReplyModel>('replies_Profile_$npub'),
    Hive.openBox<RepostModel>('reposts_Profile_$npub'),
    Hive.openBox<UserModel>('users'),
    Hive.openBox<FollowingModel>('followingBox'),
    Hive.openBox<ZapModel>('zaps_$npub'),
    Hive.openBox<NotificationModel>('notifications_$npub'),
  ];

  await Future.wait(boxFutures);
}

Future<void> _handleInitializationError(dynamic error) async {
  try {
    await Hive.deleteFromDisk();
    print('Hive data deleted. Restarting app...');
    main();
  } catch (deleteError) {
    print('Failed to delete Hive data: $deleteError');
    runApp(const HiveErrorApp());
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
