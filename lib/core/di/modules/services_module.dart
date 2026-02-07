import '../app_di.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/validation_service.dart';
import '../../../data/services/coinos_service.dart';
import '../../../data/services/dm_service.dart';
import '../../../data/services/isar_database_service.dart';
import '../../../data/services/relay_service.dart';
import '../../../domain/mappers/event_mapper.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/sync/publishers/event_publisher.dart';

class ServicesModule extends DIModule {
  @override
  Future<void> register() async {
    await IsarDatabaseService.instance.initialize();

    AppDI.registerLazySingleton<IsarDatabaseService>(
        () => IsarDatabaseService.instance);
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
          db: AppDI.get<IsarDatabaseService>(),
          publisher: AppDI.get<EventPublisher>(),
        ));
    await AuthService.instance.refreshCache();

    _initRelayService();
  }

  void _initRelayService() {
    Future.microtask(() async {
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
        } catch (_) {}

        await RustRelayService.instance.init(privateKeyHex: privateKeyHex);

        if (userPubkeyHex != null) {
          _discoverOutboxRelays(userPubkeyHex);
        }
      } catch (_) {}
    });
  }

  void _discoverOutboxRelays(String userPubkeyHex) {
    Future.microtask(() async {
      try {
        final db = IsarDatabaseService.instance;
        final follows = await db.getFollowingList(userPubkeyHex);
        if (follows != null && follows.isNotEmpty) {
          final allPubkeys = [userPubkeyHex, ...follows];
          await RustRelayService.instance
              .discoverAndConnectOutboxRelays(allPubkeys);
        } else {
          await RustRelayService.instance
              .discoverAndConnectOutboxRelays([userPubkeyHex]);
        }
      } catch (_) {}
    });
  }
}
