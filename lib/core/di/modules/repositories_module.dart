import '../app_di.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/note_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../../data/repositories/dm_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/validation_service.dart';
import '../../../data/services/network_service.dart';
import '../../../data/services/data_service.dart';
import '../../../data/services/coinos_service.dart';
import '../../../data/services/follow_cache_service.dart';
import '../../../data/services/feed_loader_service.dart';
import '../../../data/services/dm_service.dart';

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
          nostrDataService: AppDI.get<DataService>(),
          followCacheService: AppDI.get<FollowCacheService>(),
        ));

    AppDI.registerLazySingleton<NoteRepository>(() => NoteRepository(
          networkService: AppDI.get<NetworkService>(),
          nostrDataService: AppDI.get<DataService>(),
          userRepository: AppDI.get<UserRepository>(),
        ));

    AppDI.registerLazySingleton<FeedLoaderService>(() => FeedLoaderService(
          noteRepository: AppDI.get<NoteRepository>(),
          userRepository: AppDI.get<UserRepository>(),
        ));

    AppDI.registerLazySingleton<NotificationRepository>(() => NotificationRepository(
          authService: AppDI.get<AuthService>(),
          networkService: AppDI.get<NetworkService>(),
          validationService: AppDI.get<ValidationService>(),
          nostrDataService: AppDI.get<DataService>(),
        ));

    AppDI.registerLazySingleton<WalletRepository>(() => WalletRepository(
          coinosService: AppDI.get<CoinosService>(),
          authService: AppDI.get<AuthService>(),
          validationService: AppDI.get<ValidationService>(),
        ));

    AppDI.registerLazySingleton<DmRepository>(() => DmRepository(
          dmService: AppDI.get<DmService>(),
          userRepository: AppDI.get<UserRepository>(),
          authService: AppDI.get<AuthService>(),
        ));
  }
}
