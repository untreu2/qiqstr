import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../colors.dart';
import '../services/data_service.dart';
import '../services/data_service_manager.dart';
import '../services/in_memory_data_manager.dart';
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
    Map<String, dynamic>? initializationResult;

    Future.microtask(() async {
      initializationResult = await _performInitialization();
    });

    await Future.delayed(const Duration(seconds: 2));

    if (initializationResult == null) {
      initializationResult = await _performInitialization();
    }

    if (!mounted) return;

    if (initializationResult != null) {
      final npub = initializationResult!['npub'] as String;
      final dataService = initializationResult!['dataService'] as DataService;

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
      await _initializeInMemoryStorage();

      final secureStorage = const FlutterSecureStorage();

      String? privateKey, npub;
      Future.microtask(() async {
        final credentialsFuture = Future.wait([
          secureStorage.read(key: 'privateKey'),
          secureStorage.read(key: 'npub'),
        ]);
        final credentials = await credentialsFuture;
        privateKey = credentials[0];
        npub = credentials[1];
      });

      await Future.delayed(const Duration(milliseconds: 10));

      if (privateKey == null || npub == null) {
        final credentials = await Future.wait([
          secureStorage.read(key: 'privateKey'),
          secureStorage.read(key: 'npub'),
        ]);
        privateKey = credentials[0];
        npub = credentials[1];
      }

      if (privateKey != null && npub != null) {
        final dataService = DataServiceManager.instance.getOrCreateService(
          npub: npub!,
          dataType: DataType.feed,
        );
        await _initializeMinimalForNavigation(npub!, dataService);
        return {'npub': npub!, 'dataService': dataService};
      } else {
        return null;
      }
    } catch (e) {
      print("Critical error during startup: $e");
      return null;
    }
  }

  Future<void> _initializeInMemoryStorage() async {
    print('[SplashScreen] Initializing in-memory storage...');
    await InMemoryDataManager.instance.initializeBoxes();
    print('[SplashScreen] In-memory storage initialized successfully');
  }

  Future<void> _initializeMinimalForNavigation(String npub, DataService dataService) async {
    try {
      print('[SplashScreen] Initializing providers and services...');

      await Future.wait([
        UserProvider.instance.initialize(),
        NotesProvider.instance.initialize(npub),
        InteractionsProvider.instance.initialize(npub),
        MediaProvider.instance.initialize(),
      ]);

      await dataService.initializeLightweight();
      await dataService.initializeHeavyOperations();
      await dataService.initializeConnections();

      print('[SplashScreen] Complete initialization completed for navigation');
    } catch (e) {
      print('[SplashScreen] Complete initialization error: $e');
    }
  }

  Future<void> _initializeAppInBackground(String npub, DataService dataService) async {
    try {
      MemoryManager.instance;

      await InMemoryDataManager.instance.initializeNotificationBox(npub);

      Future.microtask(() async {
        try {
          await Future.wait([
            RelayProvider.instance.initialize(),
            NetworkProvider.instance.initialize(),
            NotificationProvider.instance.initialize(npub, dataService: dataService, userProvider: UserProvider.instance),
          ]);
        } catch (e) {
          print('[SplashScreen] Background provider initialization error: $e');
        }
      });

      _setupMemoryPressureHandling();
    } catch (e) {
      print('Background initialization error: $e');
    }
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
