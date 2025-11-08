import '../app_di.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/note_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/validation_service.dart';
import '../../../data/services/network_service.dart';
import '../../../data/services/nostr_data_service.dart';
import '../../../data/services/coinos_service.dart';
import '../../../data/services/follow_cache_service.dart';

class RepositoriesModule extends DIModule {
  @override
  Future<void> register() async {
    AppDI.registerLazySingleton<AuthRepository>(() => AuthRepository(
          authService: AppDI.get<AuthService>(),
          validationService: AppDI.get<ValidationService>(),
        ));

    AppDI.registerLazySingleton<UserRepository>(() => UserRepository(
          authService: AppDI.get<AuthService>(),
          validationService: AppDI.get<ValidationService>(),
          nostrDataService: AppDI.get<NostrDataService>(),
          followCacheService: AppDI.get<FollowCacheService>(),
        ));

    AppDI.registerLazySingleton<NoteRepository>(() => NoteRepository(
          networkService: AppDI.get<NetworkService>(),
          nostrDataService: AppDI.get<NostrDataService>(),
          userRepository: AppDI.get<UserRepository>(),
        ));

    AppDI.registerLazySingleton<NotificationRepository>(() => NotificationRepository(
          authService: AppDI.get<AuthService>(),
          networkService: AppDI.get<NetworkService>(),
          validationService: AppDI.get<ValidationService>(),
          nostrDataService: AppDI.get<NostrDataService>(),
        ));

    AppDI.registerLazySingleton<WalletRepository>(() => WalletRepository(
          coinosService: AppDI.get<CoinosService>(),
          authService: AppDI.get<AuthService>(),
          validationService: AppDI.get<ValidationService>(),
        ));
  }
}
