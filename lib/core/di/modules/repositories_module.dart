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
        () => FeedRepository(events: events));
    AppDI.registerLazySingleton<ProfileRepository>(
        () => ProfileRepository(events: events));
    AppDI.registerLazySingleton<NotificationRepository>(
        () => NotificationRepository(events: events));
    AppDI.registerLazySingleton<ArticleRepository>(
        () => ArticleRepository(events: events));
    AppDI.registerLazySingleton<InteractionRepository>(
        () => const InteractionRepository());
    AppDI.registerLazySingleton<FollowingRepository>(
        () => FollowingRepository(events: events));
  }
}
