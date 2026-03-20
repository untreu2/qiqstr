import '../app_di.dart';
import '../../../data/services/rust_database_service.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/repositories/article_repository.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../../../data/repositories/following_repository.dart';

class RepositoriesModule extends DIModule {
  @override
  Future<void> register() async {
    final db = AppDI.get<RustDatabaseService>();

    AppDI.registerLazySingleton<FeedRepository>(
        () => FeedRepositoryImpl(db: db));
    AppDI.registerLazySingleton<ProfileRepository>(
        () => ProfileRepositoryImpl(db: db));
    AppDI.registerLazySingleton<NotificationRepository>(
        () => NotificationRepositoryImpl(db: db));
    AppDI.registerLazySingleton<ArticleRepository>(
        () => ArticleRepositoryImpl(db: db));
    AppDI.registerLazySingleton<InteractionRepository>(
        () => InteractionRepositoryImpl(db: db));
    AppDI.registerLazySingleton<FollowingRepository>(
        () => FollowingRepositoryImpl(db: db));
  }
}
