import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../colors.dart';
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
import '../services/data_service_manager.dart';
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
    final results = await Future.wait([
      _performInitialization(),
      Future.delayed(const Duration(seconds: 2)),
    ]);

    final initializationResult = results[0] as Map<String, dynamic>?;

    if (!mounted) return;

    if (initializationResult != null) {
      final npub = initializationResult['npub'] as String;
      final dataService = initializationResult['dataService'] as DataService;

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => HomeNavigator(
            npub: npub,
            dataService: dataService,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 750),
        ),
      );

      _initializeAppInBackground(npub, dataService);
    } else {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const LoginPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 750),
        ),
      );
    }
  }

  Future<Map<String, dynamic>?> _performInitialization() async {
    try {
      await _initializeHiveOptimized();

      final secureStorage = const FlutterSecureStorage();
      final credentials = await Future.wait([
        secureStorage.read(key: 'privateKey'),
        secureStorage.read(key: 'npub'),
      ]);

      final privateKey = credentials[0];
      final npub = credentials[1];

      if (privateKey != null && npub != null) {
        final dataService = DataServiceManager.instance.getOrCreateService(
          npub: npub,
          dataType: DataType.feed,
        );
        await _initializeMinimalForNavigation(npub, dataService);
        return {'npub': npub, 'dataService': dataService};
      } else {
        return null;
      }
    } catch (e) {
      print("Critical error during startup: $e");
      return null;
    }
  }

  Future<void> _initializeHiveOptimized() async {
    await Hive.initFlutter();

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
      final typeId = i == 8 ? 12 : i;
      if (!Hive.isAdapterRegistered(typeId)) {
        adapters[i]();
      }
    }

    await Hive.openBox<LinkPreviewModel>('link_preview_cache');
  }

  Future<void> _initializeMinimalForNavigation(String npub, DataService dataService) async {
    try {
      await _openCriticalBoxes(npub);

      await dataService.initializeLightweight();

      print('[SplashScreen] Minimal initialization completed for navigation');
    } catch (e) {
      print('[SplashScreen] Minimal initialization error: $e');
    }
  }

  Future<void> _initializeAppInBackground(String npub, DataService dataService) async {
    try {
      MemoryManager.instance;

      await _openCriticalBoxes(npub);

      await Future.wait([
        UserProvider.instance.initialize(),
        NotesProvider.instance.initialize(npub),
        InteractionsProvider.instance.initialize(npub),
        MediaProvider.instance.initialize(),
      ]);

      await Future.wait([
        RelayProvider.instance.initialize(),
        NetworkProvider.instance.initialize(),
        NotificationProvider.instance.initialize(npub, dataService: dataService, userProvider: UserProvider.instance),
      ]);

      await dataService.initialize();

      _openRemainingBoxes(npub);

      Future.microtask(() => dataService.initializeConnections());

      _setupMemoryPressureHandling();
    } catch (e) {
      print('Background initialization error: $e');
    }
  }

  Future<void> _openCriticalBoxes(String npub) async {
    await Future.wait([
      Hive.openBox<UserModel>('users'),
      Hive.openBox<NoteModel>('notes_Feed_$npub'),
      Hive.openBox<FollowingModel>('followingBox'),
    ]);
  }

  void _openRemainingBoxes(String npub) {
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
    try {
      MediaProvider.instance.handleMemoryPressure();
      MemoryManager.instance.cleanupMemory();
    } catch (e) {
      print('Memory pressure handling error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDarkMode = brightness == Brightness.dark;

    final iconColor = isDarkMode ? AppColors.iconPrimary : AppColorsLight.iconPrimary;

    return Scaffold(
      backgroundColor: isDarkMode ? AppColors.background : AppColorsLight.background,
      body: Center(
        child: SvgPicture.asset(
          'assets/main_icon_white.svg',
          width: 120,
          height: 120,
          fit: BoxFit.contain,
          colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
        ),
      ),
    );
  }
}
