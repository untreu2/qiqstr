import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'colors.dart';
import 'theme/theme_manager.dart' as theme;
import 'screens/home_navigator.dart';
import 'screens/login_page.dart';
import 'services/logging_service.dart';
import 'core/di/app_di.dart';
import 'data/services/nostr_data_service.dart';
import 'data/services/auth_service.dart';
import 'data/repositories/notification_repository.dart';
import 'data/repositories/note_repository.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

    await AppDI.initialize();
    
    debugProfileBuildsEnabled = false;
    debugPrintRebuildDirtyWidgets = false;

    AppDI.get<NostrDataService>();

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

    final initialHome = await _determineInitialHomeWithPreloading();

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

Future<Widget> _determineInitialHomeWithPreloading() async {
  try {
    final authService = AppDI.get<AuthService>();

    final nsecResult = await authService.getUserNsec();

    if (nsecResult.isSuccess && nsecResult.data != null && nsecResult.data!.isNotEmpty) {
      final npubResult = await authService.getCurrentUserNpub();

      if (npubResult.isSuccess && npubResult.data != null && npubResult.data!.isNotEmpty) {
        final npub = npubResult.data!;
        
        
        unawaited(_initializeNotifications());

        
        await _loadInitialFeedWithSplash(npub);

        FlutterNativeSplash.remove();

        return HomeNavigator(npub: npub);
      }
    }

    FlutterNativeSplash.remove();
    return const LoginPage();
  } catch (e) {
    FlutterNativeSplash.remove();
    return const LoginPage();
  }
}

Future<bool> _loadInitialFeedWithSplash(String npub) async {
  try {
    final nostrDataService = AppDI.get<NostrDataService>();
    final noteRepository = AppDI.get<NoteRepository>();

    
    unawaited(noteRepository.startRealTimeFeed([npub]));

    
    try {
      final serviceCachedNotes = nostrDataService.cachedNotes;
      if (serviceCachedNotes.isNotEmpty) {
        debugPrint('[Main] Found ${serviceCachedNotes.length} cached notes in service, skipping preload');
        return true;
      }
    } catch (e) {
      debugPrint('[Main] Error checking service cached notes: $e');
    }

    
    try {
      final repoCachedNotes = noteRepository.currentNotes;
      if (repoCachedNotes.isNotEmpty) {
        debugPrint('[Main] Found ${repoCachedNotes.length} cached notes in repository, skipping preload');
        return true;
      }
    } catch (e) {
      debugPrint('[Main] Error checking repository cached notes: $e');
    }

    
    final completer = Completer<bool>();
    Timer(const Duration(seconds: 4), () {
      if (!completer.isCompleted) {
        debugPrint('[Main] Feed preload timeout (4s), continuing anyway');
        completer.complete(false);
      }
    });

    try {
      
      final result = await nostrDataService.fetchFeedNotes(
        authorNpubs: [npub],
        limit: 30,
      );

      if (!completer.isCompleted) {
        final success = result.isSuccess && result.data != null && result.data!.isNotEmpty;
        completer.complete(success);
        if (success) {
          debugPrint('[Main] Feed preload successful: ${result.data!.length} notes');
        }
      }

      return await completer.future;
    } catch (e) {
      debugPrint('[Main] Error preloading feed: $e');
      if (!completer.isCompleted) {
        completer.complete(false);
      }
      return await completer.future;
    }
  } catch (e) {
    debugPrint('[Main] Error in _loadInitialFeedWithSplash: $e');
    return false;
  }
}


void unawaited(Future<void> future) {
  future.catchError((error) {});
}

Future<void> _initializeNotifications() async {
  try {
    final notificationRepository = AppDI.get<NotificationRepository>();

    final result = await notificationRepository.getNotifications(limit: 50);

    if (result.isSuccess) {
      _startBackgroundNotificationListening();
    }
  } catch (e) {
    debugPrint('[Main] Error initializing services: $e');
  }
}

void _startBackgroundNotificationListening() {
  try {
    final notificationRepository = AppDI.get<NotificationRepository>();

    notificationRepository.notificationsStream.listen(
      (notifications) {},
      onError: (error) {
        debugPrint('[Main] Notification stream error: $error');
      },
    );
  } catch (e) {
    debugPrint('[Main] Error starting notification listener: $e');
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
