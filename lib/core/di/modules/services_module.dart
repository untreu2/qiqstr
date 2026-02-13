import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_di.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/validation_service.dart';
import '../../../data/services/coinos_service.dart';
import '../../../data/services/dm_service.dart';
import '../../../data/services/rust_database_service.dart';
import '../../../data/services/relay_service.dart';
import '../../../domain/mappers/event_mapper.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/sync/publishers/event_publisher.dart';
import '../../../data/services/favorite_lists_service.dart';
import '../../../data/services/follow_set_service.dart';

class ServicesModule extends DIModule {
  @override
  Future<void> register() async {
    await RustDatabaseService.instance.initialize();

    AppDI.registerLazySingleton<RustDatabaseService>(
        () => RustDatabaseService.instance);
    AppDI.registerLazySingleton<AuthService>(() => AuthService.instance);
    AppDI.registerLazySingleton<ValidationService>(
        () => ValidationService.instance);
    AppDI.registerLazySingleton<CoinosService>(() => CoinosService());
    AppDI.registerLazySingleton<DmService>(() => DmService(
          authService: AppDI.get<AuthService>(),
        ));
    AppDI.registerLazySingleton<EventMapper>(() => EventMapper());
    AppDI.registerLazySingleton<EventPublisher>(() => EventPublisher(
          authService: AppDI.get<AuthService>(),
        ));
    AppDI.registerLazySingleton<SyncService>(() => SyncService(
          db: AppDI.get<RustDatabaseService>(),
          publisher: AppDI.get<EventPublisher>(),
        ));
    await AuthService.instance.refreshCache();
    await FavoriteListsService.instance.load();

    await _initRelayService();
  }

  Future<void> _initRelayService() async {
    try {
      final authService = AuthService.instance;
      String? privateKeyHex;
      String? userPubkeyHex;
      try {
        final pkResult = await authService.getCurrentUserPrivateKey();
        if (!pkResult.isError && pkResult.data != null) {
          privateKeyHex = pkResult.data;
        }
        final pubResult = await authService.getCurrentUserPublicKeyHex();
        if (!pubResult.isError && pubResult.data != null) {
          userPubkeyHex = pubResult.data;
        }
      } catch (e) {
        if (kDebugMode) {
          print('[ServicesModule] Error getting auth keys: $e');
        }
      }

      if (kDebugMode) {
        print('[ServicesModule] Initializing RustRelayService...');
      }

      await RustRelayService.instance.init(privateKeyHex: privateKeyHex);

      if (kDebugMode) {
        print('[ServicesModule] RustRelayService initialized successfully');
      }

      if (userPubkeyHex != null) {
        final prefs = await SharedPreferences.getInstance();
        final gossipEnabled = prefs.getBool('gossip_model_enabled') ?? false;
        if (gossipEnabled) {
          _discoverOutboxRelays(userPubkeyHex);
        }
        _loadFollowSets(userPubkeyHex);
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('[ServicesModule] ERROR initializing RustRelayService: $e');
        print('[ServicesModule] Stack trace: $stackTrace');
      }
      rethrow;
    }
  }

  static Future<void> reinitializeForAccountSwitch() async {
    try {
      final authService = AuthService.instance;
      String? privateKeyHex;
      String? userPubkeyHex;

      final pkResult = await authService.getCurrentUserPrivateKey();
      if (!pkResult.isError && pkResult.data != null) {
        privateKeyHex = pkResult.data;
      }
      final pubResult = await authService.getCurrentUserPublicKeyHex();
      if (!pubResult.isError && pubResult.data != null) {
        userPubkeyHex = pubResult.data;
      }

      await RustRelayService.instance.init(privateKeyHex: privateKeyHex);

      if (userPubkeyHex != null) {
        final prefs = await SharedPreferences.getInstance();
        final gossipEnabled = prefs.getBool('gossip_model_enabled') ?? false;
        if (gossipEnabled) {
          Future.microtask(() async {
            try {
              final db = RustDatabaseService.instance;
              final follows = await db.getFollowingList(userPubkeyHex!);
              if (follows != null && follows.isNotEmpty) {
                final allPubkeys = [userPubkeyHex, ...follows];
                await RustRelayService.instance
                    .discoverAndConnectOutboxRelays(allPubkeys);
              } else {
                await RustRelayService.instance
                    .discoverAndConnectOutboxRelays([userPubkeyHex]);
              }
            } catch (e) {
              if (kDebugMode) {
                print('[ServicesModule] Error discovering outbox relays: $e');
              }
            }
          });
        }
      }

      if (kDebugMode) {
        print('[ServicesModule] Re-initialized for account switch');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[ServicesModule] Error during account switch reinit: $e');
      }
    }
  }

  void _loadFollowSets(String userPubkeyHex) {
    Future.microtask(() async {
      try {
        final service = FollowSetService.instance;
        if (!service.isInitialized) {
          await service.loadFromDatabase(userPubkeyHex: userPubkeyHex);
          final db = RustDatabaseService.instance;
          final follows = await db.getFollowingList(userPubkeyHex);
          if (follows != null && follows.isNotEmpty) {
            await service.loadFollowedUsersSets(followedPubkeys: follows);
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('[ServicesModule] Error loading follow sets: $e');
        }
      }
    });
  }

  void _discoverOutboxRelays(String userPubkeyHex) {
    Future.microtask(() async {
      try {
        final db = RustDatabaseService.instance;
        final follows = await db.getFollowingList(userPubkeyHex);
        if (follows != null && follows.isNotEmpty) {
          final allPubkeys = [userPubkeyHex, ...follows];
          await RustRelayService.instance
              .discoverAndConnectOutboxRelays(allPubkeys);
        } else {
          await RustRelayService.instance
              .discoverAndConnectOutboxRelays([userPubkeyHex]);
        }
      } catch (e) {
        if (kDebugMode) {
          print('[ServicesModule] Error discovering outbox relays: $e');
        }
      }
    });
  }
}
