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
import '../../../presentation/blocs/user_search/user_search_bloc.dart';
import '../../../presentation/blocs/note_statistics/note_statistics_bloc.dart';
import '../../../presentation/blocs/edit_new_account_profile/edit_new_account_profile_bloc.dart';
import '../../../presentation/blocs/user_tile/user_tile_bloc.dart';
import '../../../presentation/blocs/quote_widget/quote_widget_bloc.dart';
import '../../../presentation/blocs/note_content/note_content_bloc.dart';
import '../../../presentation/blocs/profile_info/profile_info_bloc.dart';
import '../../../presentation/blocs/article/article_bloc.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/note_repository.dart';
import '../../../data/repositories/dm_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../../../data/services/validation_service.dart';
import '../../../data/services/feed_loader_service.dart';
import '../../../data/services/data_service.dart';

class BlocsModule extends DIModule {
  @override
  Future<void> register() async {
    AppDI.registerFactory<AuthBloc>(() => AuthBloc(
          authRepository: AppDI.get<AuthRepository>(),
          validationService: AppDI.get<ValidationService>(),
        ));

    AppDI.registerFactory<FeedBloc>(() => FeedBloc(
          noteRepository: AppDI.get<NoteRepository>(),
          authRepository: AppDI.get<AuthRepository>(),
          userRepository: AppDI.get<UserRepository>(),
          feedLoader: AppDI.get<FeedLoaderService>(),
        ));

    AppDI.registerFactory<ProfileBloc>(() => ProfileBloc(
          userRepository: AppDI.get<UserRepository>(),
          authRepository: AppDI.get<AuthRepository>(),
          feedLoader: AppDI.get<FeedLoaderService>(),
        ));

    AppDI.registerFactory<NoteBloc>(() => NoteBloc(
          noteRepository: AppDI.get<NoteRepository>(),
          authRepository: AppDI.get<AuthRepository>(),
          userRepository: AppDI.get<UserRepository>(),
          dataService: AppDI.get<DataService>(),
        ));

    AppDI.registerFactory<DmBloc>(() => DmBloc(
          dmRepository: AppDI.get<DmRepository>(),
          authRepository: AppDI.get<AuthRepository>(),
        ));

    AppDI.registerFactory<NotificationBloc>(() => NotificationBloc(
          notificationRepository: AppDI.get<NotificationRepository>(),
          userRepository: AppDI.get<UserRepository>(),
          authRepository: AppDI.get<AuthRepository>(),
          nostrDataService: AppDI.get<DataService>(),
        ));

    AppDI.registerLazySingleton<WalletBloc>(() => WalletBloc(
          walletRepository: AppDI.get<WalletRepository>(),
        ));

    AppDI.registerFactory<ThreadBloc>(() => ThreadBloc(
          noteRepository: AppDI.get<NoteRepository>(),
          userRepository: AppDI.get<UserRepository>(),
          authRepository: AppDI.get<AuthRepository>(),
        ));

    AppDI.registerLazySingleton<NotificationIndicatorBloc>(() => NotificationIndicatorBloc(
          notificationRepository: AppDI.get<NotificationRepository>(),
        ));

    AppDI.registerLazySingleton<SidebarBloc>(() => SidebarBloc(
          authRepository: AppDI.get<AuthRepository>(),
          userRepository: AppDI.get<UserRepository>(),
          dataService: AppDI.get<DataService>(),
        ));

    AppDI.registerFactory<EditProfileBloc>(() => EditProfileBloc(
          userRepository: AppDI.get<UserRepository>(),
          authRepository: AppDI.get<AuthRepository>(),
          dataService: AppDI.get<DataService>(),
        ));

    AppDI.registerFactory<FollowingBloc>(() => FollowingBloc(
          userRepository: AppDI.get<UserRepository>(),
        ));

    AppDI.registerFactory<SuggestedFollowsBloc>(() => SuggestedFollowsBloc(
          userRepository: AppDI.get<UserRepository>(),
          nostrDataService: AppDI.get<DataService>(),
        ));

    AppDI.registerFactory<MutedBloc>(() => MutedBloc(
          userRepository: AppDI.get<UserRepository>(),
          authService: AppDI.get<AuthService>(),
          dataService: AppDI.get<DataService>(),
        ));

    AppDI.registerFactory<UserSearchBloc>(() => UserSearchBloc(
          userRepository: AppDI.get<UserRepository>(),
        ));

    AppDI.registerFactory<NoteStatisticsBloc>(() => NoteStatisticsBloc(
          userRepository: AppDI.get<UserRepository>(),
          dataService: AppDI.get<DataService>(),
          noteId: '',
        ));

    AppDI.registerFactory<EditNewAccountProfileBloc>(() => EditNewAccountProfileBloc(
          userRepository: AppDI.get<UserRepository>(),
          dataService: AppDI.get<DataService>(),
          npub: '',
        ));

    AppDI.registerFactory<UserTileBloc>(() => UserTileBloc(
          userRepository: AppDI.get<UserRepository>(),
          authRepository: AppDI.get<AuthRepository>(),
          userNpub: '',
        ));

    AppDI.registerFactory<QuoteWidgetBloc>(() => QuoteWidgetBloc(
          noteRepository: AppDI.get<NoteRepository>(),
          userRepository: AppDI.get<UserRepository>(),
          bech32: '',
        ));

    AppDI.registerFactory<NoteContentBloc>(() => NoteContentBloc(
          userRepository: AppDI.get<UserRepository>(),
          authRepository: AppDI.get<AuthRepository>(),
        ));

    AppDI.registerFactory<ProfileInfoBloc>(() => ProfileInfoBloc(
          authRepository: AppDI.get<AuthRepository>(),
          userRepository: AppDI.get<UserRepository>(),
          dataService: AppDI.get<DataService>(),
          userPubkeyHex: '',
        ));

    AppDI.registerFactory<ArticleBloc>(() => ArticleBloc(
          authRepository: AppDI.get<AuthRepository>(),
          userRepository: AppDI.get<UserRepository>(),
          feedLoader: AppDI.get<FeedLoaderService>(),
        ));
  }
}
