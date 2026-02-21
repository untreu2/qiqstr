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
import '../../../presentation/blocs/sidebar/sidebar_bloc.dart';
import '../../../presentation/blocs/edit_profile/edit_profile_bloc.dart';
import '../../../presentation/blocs/following/following_bloc.dart';
import '../../../presentation/blocs/suggested_follows/suggested_follows_bloc.dart';
import '../../../presentation/blocs/muted/muted_bloc.dart';
import '../../../presentation/blocs/bookmark/bookmark_bloc.dart';
import '../../../presentation/blocs/user_search/user_search_bloc.dart';
import '../../../presentation/blocs/note_statistics/note_statistics_bloc.dart';
import '../../../presentation/blocs/edit_new_account_profile/edit_new_account_profile_bloc.dart';
import '../../../presentation/blocs/user_tile/user_tile_bloc.dart';
import '../../../presentation/blocs/quote_widget/quote_widget_bloc.dart';
import '../../../presentation/blocs/note_content/note_content_bloc.dart';
import '../../../presentation/blocs/profile_info/profile_info_bloc.dart';
import '../../../presentation/blocs/article/article_bloc.dart';
import '../../../presentation/blocs/follow_set/follow_set_bloc.dart';
import '../../../presentation/blocs/onboarding_coinos/onboarding_coinos_bloc.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/coinos_service.dart';
import '../../../data/services/dm_service.dart';
import '../../../data/services/nwc_service.dart';
import '../../../data/services/validation_service.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/repositories/following_repository.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/repositories/article_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/rust_database_service.dart';

class BlocsModule extends DIModule {
  @override
  Future<void> register() async {
    AppDI.registerFactory<AuthBloc>(() => AuthBloc(
          authService: AppDI.get<AuthService>(),
          validationService: AppDI.get<ValidationService>(),
        ));

    AppDI.registerLazySingleton<FeedBloc>(() => FeedBloc(
          feedRepository: AppDI.get<FeedRepository>(),
          profileRepository: AppDI.get<ProfileRepository>(),
          syncService: AppDI.get<SyncService>(),
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
          coinosService: AppDI.get<CoinosService>(),
          nwcService: AppDI.get<NwcService>(),
        ));

    AppDI.registerFactory<ThreadBloc>(() => ThreadBloc(
          feedRepository: AppDI.get<FeedRepository>(),
          profileRepository: AppDI.get<ProfileRepository>(),
          syncService: AppDI.get<SyncService>(),
          authService: AppDI.get<AuthService>(),
        ));

    AppDI.registerLazySingleton<NotificationIndicatorBloc>(
        () => NotificationIndicatorBloc(
              syncService: AppDI.get<SyncService>(),
              authService: AppDI.get<AuthService>(),
              db: AppDI.get<RustDatabaseService>(),
            ));

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
          profileRepository: AppDI.get<ProfileRepository>(),
          syncService: AppDI.get<SyncService>(),
          authService: AppDI.get<AuthService>(),
        ));

    AppDI.registerFactory<UserSearchBloc>(() => UserSearchBloc(
          profileRepository: AppDI.get<ProfileRepository>(),
          authService: AppDI.get<AuthService>(),
        ));

    AppDI.registerFactory<NoteStatisticsBloc>(() => NoteStatisticsBloc(
          interactionRepository: AppDI.get<InteractionRepository>(),
          profileRepository: AppDI.get<ProfileRepository>(),
          authService: AppDI.get<AuthService>(),
          noteId: '',
        ));

    AppDI.registerFactory<EditNewAccountProfileBloc>(
        () => EditNewAccountProfileBloc(
              syncService: AppDI.get<SyncService>(),
              npub: '',
            ));

    AppDI.registerFactory<UserTileBloc>(() => UserTileBloc(
          followingRepository: AppDI.get<FollowingRepository>(),
          syncService: AppDI.get<SyncService>(),
          authService: AppDI.get<AuthService>(),
          userNpub: '',
        ));

    AppDI.registerFactory<QuoteWidgetBloc>(() => QuoteWidgetBloc(
          feedRepository: AppDI.get<FeedRepository>(),
          profileRepository: AppDI.get<ProfileRepository>(),
          syncService: AppDI.get<SyncService>(),
          bech32: '',
        ));

    AppDI.registerFactory<NoteContentBloc>(() => NoteContentBloc(
          profileRepository: AppDI.get<ProfileRepository>(),
          authService: AppDI.get<AuthService>(),
        ));

    AppDI.registerFactory<ProfileInfoBloc>(() => ProfileInfoBloc(
          followingRepository: AppDI.get<FollowingRepository>(),
          profileRepository: AppDI.get<ProfileRepository>(),
          syncService: AppDI.get<SyncService>(),
          authService: AppDI.get<AuthService>(),
          userPubkeyHex: '',
        ));

    AppDI.registerFactory<ArticleBloc>(() => ArticleBloc(
          articleRepository: AppDI.get<ArticleRepository>(),
          profileRepository: AppDI.get<ProfileRepository>(),
          followingRepository: AppDI.get<FollowingRepository>(),
          syncService: AppDI.get<SyncService>(),
        ));

    AppDI.registerFactory<FollowSetBloc>(() => FollowSetBloc(
          profileRepository: AppDI.get<ProfileRepository>(),
          followingRepository: AppDI.get<FollowingRepository>(),
          syncService: AppDI.get<SyncService>(),
          authService: AppDI.get<AuthService>(),
        ));

    AppDI.registerFactory<OnboardingCoinosBloc>(() => OnboardingCoinosBloc(
          coinosService: AppDI.get<CoinosService>(),
          authService: AppDI.get<AuthService>(),
          profileRepository: AppDI.get<ProfileRepository>(),
          syncService: AppDI.get<SyncService>(),
        ));
  }
}
