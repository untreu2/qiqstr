import '../app_di.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/validation_service.dart';
import '../../../data/services/network_service.dart';
import '../../../data/services/nostr_data_service.dart';
import '../../../data/services/coinos_service.dart';
import '../../../data/services/follow_cache_service.dart';

class ServicesModule extends DIModule {
  @override
  Future<void> register() async {
    AppDI.registerLazySingleton<AuthService>(() => AuthService.instance);
    AppDI.registerLazySingleton<ValidationService>(() => ValidationService.instance);
    AppDI.registerLazySingleton<NetworkService>(() => NetworkService.instance);
    AppDI.registerLazySingleton<CoinosService>(() => CoinosService());
    AppDI.registerLazySingleton<FollowCacheService>(() => FollowCacheService.instance);
    AppDI.registerLazySingleton<NostrDataService>(() => NostrDataService(
          authService: AppDI.get<AuthService>(),
        ));
  }
}
