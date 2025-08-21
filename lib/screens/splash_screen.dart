import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../models/repost_model.dart';
import '../models/user_model.dart';
import '../models/following_model.dart';
import '../models/link_preview_model.dart';
import '../models/zap_model.dart';
import '../models/notification_model.dart';
import '../services/data_service.dart';
import '../providers/user_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/interactions_provider.dart';
import '../providers/relay_provider.dart';
import '../providers/network_provider.dart';
import '../providers/media_provider.dart';
import '../providers/notification_provider.dart';
import '../services/memory_manager.dart';
import 'home_navigator.dart';
import 'login_page.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeAppAndNavigate();
  }

  Future<void> _initializeAppAndNavigate() async {
    try {
      // 1. Initialize Hive and adapters
      await _initializeHiveOptimized();

      // 2. Read user credentials
      final secureStorage = const FlutterSecureStorage();
      final credentials = await Future.wait([
        secureStorage.read(key: 'privateKey'),
        secureStorage.read(key: 'npub'),
      ]);

      final privateKey = credentials[0];
      final npub = credentials[1];

      if (privateKey != null && npub != null) {
        // 3. Prepare for main page
        final dataService = DataService(npub: npub, dataType: DataType.feed);

        // 4. Minimal initialization - only essentials for navigation
        await _initializeMinimalForNavigation(npub, dataService);

        // 5. Navigate to main page (background initialization continues)
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => HomeNavigator(
                npub: npub,
                dataService: dataService,
              ),
            ),
          );

          // 6. Perform full initialization in background
          _initializeAppInBackground(npub, dataService);
        }
      } else {
        // Navigate to login page
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginPage()),
          );
        }
      }
    } catch (e) {
      print("Critical error during startup: $e");

      // Navigate to login page on error
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginPage()),
        );
      }
    }
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

  Future<void> _initializeMinimalForNavigation(String npub, DataService dataService) async {
    try {
      // Phase 1: Only critical boxes for immediate navigation
      await _openCriticalBoxes(npub);

      // Phase 2: Lightweight DataService initialization only
      await dataService.initializeLightweight();

      print('[SplashScreen] Minimal initialization completed for navigation');
    } catch (e) {
      print('[SplashScreen] Minimal initialization error: $e');
    }
  }

  Future<void> _initializeAppInBackground(String npub, DataService dataService) async {
    try {
      // Phase 1: Initialize memory manager first
      MemoryManager.instance; // Initialize singleton

      // Phase 2: Open critical boxes first
      await _openCriticalBoxes(npub);

      // Phase 3: Initialize providers in parallel
      final usersBox = Hive.box<UserModel>('users');
      UserProvider.instance.setUsersBox(usersBox);

      await Future.wait([
        UserProvider.instance.initialize(),
        NotesProvider.instance.initialize(npub),
        InteractionsProvider.instance.initialize(npub),
        MediaProvider.instance.initialize(),
      ]);

      // Phase 4: Initialize network providers after settings are loaded
      await Future.wait([
        RelayProvider.instance.initialize(),
        NetworkProvider.instance.initialize(),
        NotificationProvider.instance.initialize(npub, dataService: dataService, userProvider: UserProvider.instance),
      ]);

      // Phase 5: Initialize DataService
      await dataService.initialize();

      // Phase 6: Open remaining boxes in background
      _openRemainingBoxes(npub);

      // Phase 7: Initialize connections (non-blocking)
      Future.microtask(() => dataService.initializeConnections());

      // Phase 8: Setup memory pressure callbacks
      _setupMemoryPressureHandling();
    } catch (e) {
      print('Background initialization error: $e');
    }
  }

  Future<void> _openCriticalBoxes(String npub) async {
    // Only open boxes needed for immediate UI display
    await Future.wait([
      Hive.openBox<UserModel>('users'),
      Hive.openBox<NoteModel>('notes_Feed_$npub'),
      Hive.openBox<FollowingModel>('followingBox'),
    ]);
  }

  void _openRemainingBoxes(String npub) {
    // Open remaining boxes in background without blocking
    Future.microtask(() async {
      final remainingBoxFutures = [
        Hive.openBox<ReactionModel>('reactions_Feed_$npub'),
        Hive.openBox<ReplyModel>('replies_Feed_$npub'),
        Hive.openBox<RepostModel>('reposts_Feed_$npub'),
        Hive.openBox<NoteModel>('notes_Profile_$npub'),
        Hive.openBox<ReactionModel>('reactions_Profile_$npub'),
        Hive.openBox<ReplyModel>('replies_Profile_$npub'),
        Hive.openBox<RepostModel>('reposts_Profile_$npub'),
        Hive.openBox<ZapModel>('zaps_$npub'),
        Hive.openBox<NotificationModel>('notifications_$npub'),
      ];

      await Future.wait(remainingBoxFutures);
    });
  }

  void _setupMemoryPressureHandling() {
    final memoryManager = MemoryManager.instance;

    // Add memory pressure callback to handle provider cleanup
    memoryManager.addMemoryPressureCallback(() {
      // Handle memory pressure in providers
      try {
        MediaProvider.instance.handleMemoryPressure();

        // Notify other providers about memory pressure
        if (memoryManager.currentPressureLevel.index >= 2) {
          // Critical or emergency
          // Force cleanup in critical situations
          Future.microtask(() async {
            try {
              NotesProvider.instance.clearCache();
              InteractionsProvider.instance.clearCache();
            } catch (e) {
              print('Provider cleanup error: $e');
            }
          });
        }
      } catch (e) {
        print('Memory pressure handling error: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Image.asset(
          'assets/main_icon_uni.png',
          width: 120,
          height: 120,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
