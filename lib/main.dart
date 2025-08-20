import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'colors.dart';
import 'theme/theme_manager.dart' as theme;
import 'models/note_model.dart';
import 'models/reaction_model.dart';
import 'models/reply_model.dart';
import 'models/repost_model.dart';
import 'models/user_model.dart';
import 'models/following_model.dart';
import 'models/link_preview_model.dart';
import 'models/zap_model.dart';
import 'models/notification_model.dart';
import 'screens/splash_screen.dart';
import 'services/data_service.dart';
import 'providers/user_provider.dart';
import 'providers/notes_provider.dart';
import 'providers/interactions_provider.dart';
import 'providers/content_cache_provider.dart';
import 'providers/relay_provider.dart';
import 'providers/network_provider.dart';
import 'providers/media_provider.dart';
import 'providers/notification_provider.dart';
import 'services/memory_manager.dart';

void main() {
  // Set up global error handling for unhandled exceptions
  runZonedGuarded(() {
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

    // Show app immediately with SplashScreen - no blocking operations
    runApp(
      provider.MultiProvider(
        providers: [
          provider.ChangeNotifierProvider(create: (context) => theme.ThemeManager()),
          provider.ChangeNotifierProvider.value(value: UserProvider.instance),
          provider.ChangeNotifierProvider.value(value: NotesProvider.instance),
          provider.ChangeNotifierProvider.value(value: InteractionsProvider.instance),
          provider.ChangeNotifierProvider.value(value: ContentCacheProvider.instance),
          provider.ChangeNotifierProvider.value(value: RelayProvider.instance),
          provider.ChangeNotifierProvider.value(value: NetworkProvider.instance),
          provider.ChangeNotifierProvider.value(value: MediaProvider.instance),
          provider.ChangeNotifierProvider.value(value: NotificationProvider.instance),
        ],
        child: const ProviderScope(
          child: QiqstrApp(home: SplashScreen()),
        ),
      ),
    );
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

// Removed _initializeHiveOptimized and _handleInitializationError functions
// These are now handled in SplashScreen

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

// Removed background initialization functions
// These are now handled in SplashScreen
