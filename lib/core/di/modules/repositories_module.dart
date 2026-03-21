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
    final events = AppDI.get<RustDatabaseService>();

    AppDI.registerLazySingleton<FeedRepository>(
        () => FeedRepositoryImpl(events: events));
    AppDI.registerLazySingleton<ProfileRepository>(
        () => ProfileRepositoryImpl(events: events));
    AppDI.registerLazySingleton<NotificationRepository>(
        () => NotificationRepositoryImpl(events: events));
    AppDI.registerLazySingleton<ArticleRepository>(
        () => ArticleRepositoryImpl(events: events));
    AppDI.registerLazySingleton<InteractionRepository>(
        () => const InteractionRepositoryImpl());
    AppDI.registerLazySingleton<FollowingRepository>(
        () => FollowingRepositoryImpl(events: events));
  }
}
