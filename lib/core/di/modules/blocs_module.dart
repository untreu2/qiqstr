import '../app_di.dart';
import '../../../presentation/blocs/auth/auth_bloc.dart';
import '../../../presentation/blocs/feed/feed_bloc.dart';
import '../../../presentation/blocs/profile/profile_bloc.dart';
import '../../../presentation/blocs/note/note_bloc.dart';
import '../../../presentation/blocs/dm/dm_bloc.dart';
import '../../../presentation/blocs/notification/notification_bloc.dart';
import '../../../presentation/blocs/wallet/wallet_bloc.dart';
import '../../../presentation/blocs/thread/thread_bloc.dart';
import '../../../presentation/blocs/notification_indicator/notification_indicator_bloc.dart';
import '../../../presentation/blocs/dm_indicator/dm_indicator_bloc.dart';
import '../../../presentation/blocs/sidebar/sidebar_bloc.dart';
import '../../../presentation/blocs/edit_profile/edit_profile_bloc.dart';
import '../../../presentation/blocs/following/following_bloc.dart';
import '../../../presentation/blocs/suggested_follows/suggested_follows_bloc.dart';
import '../../../presentation/blocs/muted/muted_bloc.dart';
import '../../../presentation/blocs/bookmark/bookmark_bloc.dart';
import '../../../presentation/blocs/user_search/user_search_bloc.dart';
import '../../../presentation/blocs/article_quote_widget/article_quote_widget_bloc.dart';
import '../../../presentation/blocs/note_content/note_content_bloc.dart';

import '../../../presentation/blocs/article/article_bloc.dart';
import '../../../presentation/blocs/follow_set/follow_set_bloc.dart';
import '../../../presentation/blocs/onboarding_spark/onboarding_spark_bloc.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/follow_set_service.dart';
import '../../../data/services/spark_service.dart';
import '../../../data/services/dm_service.dart';
import '../../../data/services/nwc_service.dart';
import '../../../data/services/validation_service.dart';
import '../../../data/services/encrypted_mute_service.dart';
import '../../../data/services/interaction_service.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/repositories/following_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/repositories/article_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/vertex_search_service.dart';

class BlocsModule extends DIModule {
  @override
  Future<void> register() async {
    AppDI.registerFactory<AuthBloc>(() => AuthBloc(
          authService: AppDI.get<AuthService>(),
          validationService: AppDI.get<ValidationService>(),
        ));

    AppDI.registerLazySingleton<FeedBloc>(() => FeedBloc(
          feedRepository: AppDI.get<FeedRepository>(),
          followingRepository: AppDI.get<FollowingRepository>(),
          profileRepository: AppDI.get<ProfileRepository>(),
          syncService: AppDI.get<SyncService>(),
          followSetService: FollowSetService.instance,
        ));

    AppDI.registerFactory<ProfileBloc>(() => ProfileBloc(
          feedRepository: AppDI.get<FeedRepository>(),
          profileRepository: AppDI.get<ProfileRepository>(),
          followingRepository: AppDI.get<FollowingRepository>(),
          articleRepository: AppDI.get<ArticleRepository>(),
          syncService: AppDI.get<SyncService>(),
          authService: AppDI.get<AuthService>(),
        ));

    AppDI.registerFactory<NoteBloc>(() => NoteBloc(
          profileRepository: AppDI.get<ProfileRepository>(),
          syncService: AppDI.get<SyncService>(),
          authService: AppDI.get<AuthService>(),
        ));

    AppDI.registerLazySingleton<DmBloc>(() => DmBloc(
          dmService: AppDI.get<DmService>(),
          profileRepository: AppDI.get<ProfileRepository>(),
          followingRepository: AppDI.get<FollowingRepository>(),
          authService: AppDI.get<AuthService>(),
          syncService: AppDI.get<SyncService>(),
        ));

    AppDI.registerFactory<NotificationBloc>(() => NotificationBloc(
          notificationRepository: AppDI.get<NotificationRepository>(),
          syncService: AppDI.get<SyncService>(),
          authService: AppDI.get<AuthService>(),
        ));

    AppDI.registerLazySingleton<WalletBloc>(() => WalletBloc(
          sparkService: AppDI.get<SparkService>(),
          nwcService: AppDI.get<NwcService>(),
          authService: AppDI.get<AuthService>(),
          profileRepository: AppDI.get<ProfileRepository>(),
          syncService: AppDI.get<SyncService>(),
        ));

    AppDI.registerFactory<ThreadBloc>(() => ThreadBloc(
          feedRepository: AppDI.get<FeedRepository>(),
          profileRepository: AppDI.get<ProfileRepository>(),
          syncService: AppDI.get<SyncService>(),
          authService: AppDI.get<AuthService>(),
          muteService: EncryptedMuteService.instance,
          interactionService: InteractionService.instance,
        ));

    AppDI.registerLazySingleton<NotificationIndicatorBloc>(
        () => NotificationIndicatorBloc(
              syncService: AppDI.get<SyncService>(),
              authService: AppDI.get<AuthService>(),
              notificationRepository: AppDI.get<NotificationRepository>(),
            ));

    AppDI.registerLazySingleton<DmIndicatorBloc>(
        () => DmIndicatorBloc(dmBloc: AppDI.get<DmBloc>()));

    AppDI.registerLazySingleton<SidebarBloc>(() => SidebarBloc(
          followingRepository: AppDI.get<FollowingRepository>(),
          profileRepository: AppDI.get<ProfileRepository>(),
          syncService: AppDI.get<SyncService>(),
          authService: AppDI.get<AuthService>(),
        ));

    AppDI.registerFactory<EditProfileBloc>(() => EditProfileBloc(
          profileRepository: AppDI.get<ProfileRepository>(),
          syncService: AppDI.get<SyncService>(),
          authService: AppDI.get<AuthService>(),
        ));

    AppDI.registerFactory<FollowingBloc>(() => FollowingBloc(
          followingRepository: AppDI.get<FollowingRepository>(),
          profileRepository: AppDI.get<ProfileRepository>(),
          syncService: AppDI.get<SyncService>(),
          authService: AppDI.get<AuthService>(),
        ));

    AppDI.registerFactory<SuggestedFollowsBloc>(() => SuggestedFollowsBloc(
          followingRepository: AppDI.get<FollowingRepository>(),
          profileRepository: AppDI.get<ProfileRepository>(),
          syncService: AppDI.get<SyncService>(),
          authService: AppDI.get<AuthService>(),
        ));

    AppDI.registerFactory<MutedBloc>(() => MutedBloc(
          followingRepository: AppDI.get<FollowingRepository>(),
          profileRepository: AppDI.get<ProfileRepository>(),
          syncService: AppDI.get<SyncService>(),
          authService: AppDI.get<AuthService>(),
        ));

    AppDI.registerFactory<BookmarkBloc>(() => BookmarkBloc(
          feedRepository: AppDI.get<FeedRepository>(),
          syncService: AppDI.get<SyncService>(),
          authService: AppDI.get<AuthService>(),
        ));

    AppDI.registerFactory<UserSearchBloc>(() => UserSearchBloc(
          profileRepository: AppDI.get<ProfileRepository>(),
          authService: AppDI.get<AuthService>(),
          syncService: AppDI.get<SyncService>(),
          vertexSearchService: AppDI.get<VertexSearchService>(),
        ));

    AppDI.registerFactory<NoteContentBloc>(() => NoteContentBloc(
          profileRepository: AppDI.get<ProfileRepository>(),
          authService: AppDI.get<AuthService>(),
        ));

    AppDI.registerFactory<ArticleQuoteWidgetBloc>(() => ArticleQuoteWidgetBloc(
          articleRepository: AppDI.get<ArticleRepository>(),
          syncService: AppDI.get<SyncService>(),
        ));

    AppDI.registerFactory<ArticleBloc>(() => ArticleBloc(
          articleRepository: AppDI.get<ArticleRepository>(),
          profileRepository: AppDI.get<ProfileRepository>(),
          followingRepository: AppDI.get<FollowingRepository>(),
          syncService: AppDI.get<SyncService>(),
        ));

    AppDI.registerLazySingleton<FollowSetBloc>(() => FollowSetBloc(
          profileRepository: AppDI.get<ProfileRepository>(),
          followingRepository: AppDI.get<FollowingRepository>(),
          syncService: AppDI.get<SyncService>(),
          authService: AppDI.get<AuthService>(),
        ));

    AppDI.registerFactory<OnboardingSparkBloc>(() => OnboardingSparkBloc(
          sparkService: AppDI.get<SparkService>(),
          authService: AppDI.get<AuthService>(),
        ));
  }
}
