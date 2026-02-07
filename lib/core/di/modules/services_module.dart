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

    _preConnectRelays();
  }

  void _preConnectRelays() {
    Future.microtask(() async {
      try {
        final wsManager = WebSocketManager.instance;
        for (final url in wsManager.relayUrls) {
          wsManager.getOrCreateConnection(url);
        }
      } catch (_) {}
    });
  }
}
