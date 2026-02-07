import '../app_di.dart';
import '../../../data/services/isar_database_service.dart';
import '../../../domain/mappers/event_mapper.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/repositories/article_repository.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../../../data/repositories/following_repository.dart';

class RepositoriesModule extends DIModule {
  @override
  Future<void> register() async {
    final db = AppDI.get<IsarDatabaseService>();
    final mapper = AppDI.get<EventMapper>();

    AppDI.registerLazySingleton<FeedRepository>(
        () => FeedRepositoryImpl(db: db, mapper: mapper));
    AppDI.registerLazySingleton<ProfileRepository>(
        () => ProfileRepositoryImpl(db: db, mapper: mapper));
    AppDI.registerLazySingleton<NotificationRepository>(
        () => NotificationRepositoryImpl(db: db, mapper: mapper));
    AppDI.registerLazySingleton<ArticleRepository>(
        () => ArticleRepositoryImpl(db: db, mapper: mapper));
    AppDI.registerLazySingleton<InteractionRepository>(
        () => InteractionRepositoryImpl(db: db, mapper: mapper));
    AppDI.registerLazySingleton<FollowingRepository>(
        () => FollowingRepositoryImpl(db: db, mapper: mapper));
  }
}
