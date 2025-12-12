import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'ui/theme/theme_manager.dart' as theme;
import 'ui/screens/home_navigator.dart';
import 'ui/screens/auth/login_page.dart';
import 'services/logging_service.dart';
import 'core/di/app_di.dart';
import 'data/services/nostr_data_service.dart';
import 'data/services/auth_service.dart';
import 'data/repositories/notification_repository.dart';
import 'data/repositories/note_repository.dart';
import 'data/repositories/dm_repository.dart';
import 'models/note_model.dart';
import 'models/dm_message_model.dart';
import 'core/base/result.dart';
import 'services/memory_trimming_service.dart';
import 'services/lifecycle_manager.dart';
import 'services/event_parser_isolate.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

    PaintingBinding.instance.imageCache.maximumSizeBytes = 150 << 20;
    PaintingBinding.instance.imageCache.maximumSize = 600;

    debugProfileBuildsEnabled = false;
    debugPrintRebuildDirtyWidgets = false;

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

    await AppDI.initialize();

    unawaited(EventParserIsolate.instance.initialize());

    final lifecycleManager = LifecycleManager();
    lifecycleManager.initialize();

    final noteRepository = AppDI.get<NoteRepository>();
    lifecycleManager.addOnPauseCallback(() => noteRepository.setPaused(true));
    lifecycleManager.addOnResumeCallback(() => noteRepository.setPaused(false));

    MemoryTrimmingService().startPeriodicTrimming();

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

        await _loadInitialDataBeforeHome(npub);

        FlutterNativeSplash.remove();

        unawaited(_initializeBackgroundServices());

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

Future<void> _loadInitialDataBeforeHome(String npub) async {
  try {
    final noteRepository = AppDI.get<NoteRepository>();
    final dmRepository = AppDI.get<DmRepository>();
    final nostrDataService = AppDI.get<NostrDataService>();

    final cachedNotes = noteRepository.currentNotes;
    if (cachedNotes.isNotEmpty) {
      unawaited(noteRepository.startRealTimeFeed([npub]));
      unawaited(dmRepository.getConversations());
      return;
    }

    unawaited(noteRepository.startRealTimeFeed([npub]));

    try {
      await Future.wait([
        nostrDataService
            .fetchFeedNotes(
              authorNpubs: [npub],
              limit: 15,
            )
            .timeout(const Duration(seconds: 8))
            .then((result) {
              if (result.isSuccess && result.data != null) {
                debugPrint('[Main] Feed loaded during splash: ${result.data!.length} notes');
              }
              return result;
            })
            .catchError((e) {
              debugPrint('[Main] Feed load error: $e');
              return Result<List<NoteModel>>.error(e.toString());
            }),
        dmRepository.getConversations().timeout(const Duration(seconds: 5)).then((result) {
          if (result.isSuccess && result.data != null) {
            debugPrint('[Main] DMs loaded during splash: ${result.data!.length} conversations');
          }
          return result;
        }).catchError((e) {
          debugPrint('[Main] DMs load error: $e');
          return Result<List<DmConversationModel>>.error(e.toString());
        }),
      ]);
    } catch (error) {
      debugPrint('[Main] Error loading initial data (continuing anyway): $error');
    }
  } catch (e) {
    debugPrint('[Main] Error in initial data loading (continuing anyway): $e');
  }
}

Future<void> _initializeBackgroundServices() async {
  await Future.delayed(const Duration(seconds: 3));

  try {
    final notificationRepository = AppDI.get<NotificationRepository>();

    notificationRepository.notificationsStream.listen(
      (notifications) {},
      onError: (error) {},
    );

    unawaited(notificationRepository.getNotifications(limit: 15));
  } catch (e) {
    debugPrint('[Main] Error initializing background services: $e');
  }
}

void unawaited(Future<void> future) {
  future.catchError((error) {});
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
