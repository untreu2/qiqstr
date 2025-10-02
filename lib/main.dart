import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;
import 'colors.dart';
import 'theme/theme_manager.dart' as theme;
import 'screens/home_navigator.dart';
import 'screens/login_page.dart';
import 'services/time_service.dart';
import 'services/logging_service.dart';
import 'core/di/app_di.dart';
import 'data/services/nostr_data_service.dart';
import 'data/services/auth_service.dart';
import 'data/repositories/notification_repository.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize dependency injection
    await AppDI.initialize();

    // Eagerly initialize NostrDataService to start relay connections immediately
    AppDI.get<NostrDataService>();

    timeService.startPeriodicRefresh();

    loggingService.configure(
      level: LogLevel.error,
      enabled: true,
    );

    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exception is SocketException) {
        return;
      }

      FlutterError.presentError(details);
    };

    try {
      PlatformDispatcher.instance.onError = (error, stack) {
        if (error is SocketException) {
          return true;
        }

        logError('Platform error', 'Main', error);
        return true;
      };
    } catch (e) {
      logError('Could not set platform error handler', 'Main', e);
    }

    // Check for existing nsec to determine initial route
    final initialHome = await _determineInitialHome();

    runApp(
      provider.MultiProvider(
        providers: [
          provider.ChangeNotifierProvider(create: (context) => theme.ThemeManager()),
        ],
        child: ProviderScope(
          child: QiqstrApp(home: initialHome),
        ),
      ),
    );
  }, (error, stack) {
    if (error is SocketException) {
      return;
    }

    logError('Unhandled error', 'Main', error);
  });
}

/// Determine the initial home widget based on authentication status
Future<Widget> _determineInitialHome() async {
  try {
    final authService = AppDI.get<AuthService>();

    // Check for stored nsec
    final nsecResult = await authService.getUserNsec();

    if (nsecResult.isSuccess && nsecResult.data != null && nsecResult.data!.isNotEmpty) {
      // nsec exists, get npub and go directly to feed
      final npubResult = await authService.getCurrentUserNpub();

      if (npubResult.isSuccess && npubResult.data != null && npubResult.data!.isNotEmpty) {
        debugPrint(' [Main] Found stored credentials, navigating directly to HomeNavigator');

        // Start listening for notifications automatically for authenticated users
        await _initializeNotifications();

        return HomeNavigator(npub: npubResult.data!);
      }
    }

    debugPrint(' [Main] No valid credentials found, showing LoginPage');
    return const LoginPage();
  } catch (e) {
    debugPrint(' [Main] Error checking authentication: $e, defaulting to LoginPage');
    return const LoginPage();
  }
}

/// Initialize notifications for authenticated users
Future<void> _initializeNotifications() async {
  try {
    debugPrint(' [Main] Initializing notifications...');

    // Initialize notification repository
    final notificationRepository = AppDI.get<NotificationRepository>();

    // Start fetching notifications automatically - this will start listening
    final result = await notificationRepository.getNotifications(limit: 50);

    if (result.isSuccess) {
      debugPrint(' [Main] Notifications initialized successfully: ${result.data?.length ?? 0} notifications');

      // Start background listening for new notifications
      _startBackgroundNotificationListening();
    } else {
      debugPrint(' [Main] Failed to initialize notifications: ${result.error}');
    }
  } catch (e) {
    debugPrint(' [Main] Error initializing notifications: $e');
  }
}

/// Start background notification listening
void _startBackgroundNotificationListening() {
  try {
    debugPrint(' [Main] Starting background notification listening...');

    final notificationRepository = AppDI.get<NotificationRepository>();

    // Listen to notification stream in background
    notificationRepository.notificationsStream.listen(
      (notifications) {
        debugPrint(' [Main] Background notification update: ${notifications.length} notifications');
      },
      onError: (error) {
        debugPrint(' [Main] Background notification error: $error');
      },
    );

    // Periodically refresh notifications every 30 seconds
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      try {
        await notificationRepository.refreshNotifications();
      } catch (e) {
        debugPrint(' [Main] Error in periodic notification refresh: $e');
      }
    });

    debugPrint(' [Main] Background notification listening started successfully');
  } catch (e) {
    debugPrint(' [Main] Error starting background notification listening: $e');
  }
}

class QiqstrApp extends ConsumerWidget {
  final Widget home;
  const QiqstrApp({super.key, required this.home});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return provider.Consumer<theme.ThemeManager>(
      builder: (context, themeManager, child) {
        final colors = themeManager.colors;
        final isDark = themeManager.isDarkMode;

        return MaterialApp(
          title: 'Qiqstr',
          theme: ThemeData(
            brightness: isDark ? Brightness.dark : Brightness.light,
            scaffoldBackgroundColor: colors.background,
            textTheme: (isDark ? ThemeData.dark() : ThemeData.light())
                .textTheme
                .apply(
                  bodyColor: colors.textPrimary,
                  displayColor: colors.textPrimary,
                )
                .copyWith(
                  bodyLarge: TextStyle(height: 2.1, color: colors.textPrimary),
                  bodyMedium: TextStyle(height: 2.1, color: colors.textPrimary),
                  bodySmall: TextStyle(height: 2.1, color: colors.textPrimary),
                  titleLarge: TextStyle(height: 2.1, color: colors.textPrimary),
                  titleMedium: TextStyle(height: 2.1, color: colors.textPrimary),
                  titleSmall: TextStyle(height: 2.1, color: colors.textPrimary),
                ),
            colorScheme: isDark
                ? ColorScheme.dark(
                    primary: colors.primary,
                    secondary: colors.secondary,
                    surface: colors.surface,
                    error: colors.error,
                    onPrimary: colors.background,
                    onSecondary: colors.textPrimary,
                    onSurface: colors.textPrimary,
                    onError: colors.background,
                  )
                : ColorScheme.light(
                    primary: colors.primary,
                    secondary: colors.secondary,
                    surface: colors.surface,
                    error: colors.error,
                    onPrimary: colors.background,
                    onSecondary: colors.textPrimary,
                    onSurface: colors.textPrimary,
                    onError: colors.background,
                  ),
            appBarTheme: AppBarTheme(
              backgroundColor: colors.background,
              elevation: 0,
              centerTitle: true,
              titleTextStyle: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
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
      },
    );
  }
}

class HiveErrorApp extends StatelessWidget {
  const HiveErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.background,
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
              color: AppColors.textPrimary,
              height: 2.1,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
