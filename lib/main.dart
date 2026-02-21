import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'presentation/blocs/theme/theme_bloc.dart';
import 'presentation/blocs/theme/theme_event.dart';
import 'presentation/blocs/theme/theme_state.dart';
import 'presentation/blocs/locale/locale_bloc.dart';
import 'presentation/blocs/locale/locale_event.dart';
import 'presentation/blocs/locale/locale_state.dart';

import 'data/services/logging_service.dart';
import 'data/services/relay_service.dart';
import 'data/services/auth_service.dart';
import 'data/sync/sync_service.dart';
import 'core/di/app_di.dart';
import 'core/router/app_router.dart';
import 'core/bloc/observers/app_bloc_observer.dart';

import 'src/rust/frb_generated.dart';
import 'l10n/app_localizations.dart';
import 'constants/database.dart';

Future<void> _sanitizeLmdbBeforeRust() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final dbVersion = prefs.getInt('lmdb_version') ?? 0;

    final dir = await getApplicationDocumentsDirectory();
    final dbPath = '${dir.path}/nostr-lmdb';
    final dbDir = Directory(dbPath);

    if (dbVersion < lmdbSchemaVersion && await dbDir.exists()) {
      await dbDir.delete(recursive: true);
      await prefs.setInt('lmdb_version', lmdbSchemaVersion);
      return;
    }

    if (!await dbDir.exists()) {
      await prefs.setInt('lmdb_version', lmdbSchemaVersion);
      return;
    }

    final lockFile = File('$dbPath/lock.mdb');
    if (await lockFile.exists()) {
      await lockFile.delete();
    }

    final dataFile = File('$dbPath/data.mdb');
    if (await dataFile.exists()) {
      final stat = await dataFile.stat();
      if (stat.size == 0) {
        await dbDir.delete(recursive: true);
      }
    }

    await prefs.setInt('lmdb_version', lmdbSchemaVersion);
  } catch (_) {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbDir = Directory('${dir.path}/nostr-lmdb');
      if (await dbDir.exists()) {
        await dbDir.delete(recursive: true);
      }
    } catch (_) {}
  }
}

void main() {
  runZonedGuarded(() async {
    final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

    await _sanitizeLmdbBeforeRust();
    await RustLib.init();
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {}

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

    Bloc.observer = AppBlocObserver();

    FlutterNativeSplash.remove();

    runApp(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeBloc>(
            create: (context) => ThemeBloc()..add(const ThemeInitialized()),
          ),
          BlocProvider<LocaleBloc>(
            create: (context) => LocaleBloc()..add(const LocaleInitialized()),
          ),
        ],
        child: const QiqstrApp(),
      ),
    );
  }, (error, stack) {
    if (error is SocketException) {
      return;
    }
    logError('Unhandled error', 'Main', error);
  });
}

void unawaited(Future<void> future) {
  future.catchError((error) {});
}

class QiqstrApp extends StatefulWidget {
  const QiqstrApp({super.key});

  @override
  State<QiqstrApp> createState() => _QiqstrAppState();
}

class _QiqstrAppState extends State<QiqstrApp> with WidgetsBindingObserver {
  bool _wasBackgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _wasBackgrounded = true;
      _onAppBackgrounded();
    } else if (state == AppLifecycleState.resumed && _wasBackgrounded) {
      _wasBackgrounded = false;
      _onAppResumed();
    }
  }

  void _onAppBackgrounded() {
    try {
      AppDI.get<SyncService>().stopRealtimeSubscriptions();
    } catch (_) {}
  }

  void _onAppResumed() {
    Future.microtask(() async {
      try {
        final relayService = RustRelayService.instance;
        if (!relayService.isInitialized) return;

        await relayService.connect();
        await relayService.waitForReady(timeoutSecs: 3);

        final authService = AuthService.instance;
        final pubResult = await authService.getCurrentUserPublicKeyHex();
        if (pubResult.isError || pubResult.data == null) return;

        final userPubkey = pubResult.data!;
        final syncService = AppDI.get<SyncService>();
        await syncService.startRealtimeSubscriptions(userPubkey);
        syncService.syncFeed(userPubkey, force: true);
        syncService.syncNotifications(userPubkey);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LocaleBloc, LocaleState>(
      builder: (context, localeState) {
        return BlocBuilder<ThemeBloc, ThemeState>(
          builder: (context, themeState) {
            final colors = themeState.colors;
            final isDark = themeState.isDarkMode;

            return MaterialApp.router(
              title: 'Qiqstr',
              routerConfig: AppRouter.router,
              locale: localeState.locale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [
                Locale('en'),
                Locale('tr'),
                Locale('de'),
              ],
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
                      bodyLarge:
                          TextStyle(height: 2.1, color: colors.textPrimary),
                      bodyMedium:
                          TextStyle(height: 2.1, color: colors.textPrimary),
                      bodySmall:
                          TextStyle(height: 2.1, color: colors.textPrimary),
                      titleLarge:
                          TextStyle(height: 2.1, color: colors.textPrimary),
                      titleMedium:
                          TextStyle(height: 2.1, color: colors.textPrimary),
                      titleSmall:
                          TextStyle(height: 2.1, color: colors.textPrimary),
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
            );
          },
        );
      },
    );
  }
}
