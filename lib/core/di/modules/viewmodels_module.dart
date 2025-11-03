import '../app_di.dart';
import '../../../presentation/viewmodels/login_viewmodel.dart';
import '../../../presentation/viewmodels/feed_viewmodel.dart';
import '../../../presentation/viewmodels/profile_viewmodel.dart';
import '../../../presentation/viewmodels/notification_viewmodel.dart';
import '../../../presentation/viewmodels/thread_viewmodel.dart';
import '../../../presentation/viewmodels/compose_viewmodel.dart';
import '../../../presentation/viewmodels/edit_profile_viewmodel.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/note_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../data/services/validation_service.dart';
import '../../../data/services/nostr_data_service.dart';

class ViewModelsModule extends DIModule {
  @override
  Future<void> register() async {
    AppDI.registerFactory<LoginViewModel>(() => LoginViewModel(
          authRepository: AppDI.get<AuthRepository>(),
          validationService: AppDI.get<ValidationService>(),
        ));

    AppDI.registerFactory<FeedViewModel>(() => FeedViewModel(
          noteRepository: AppDI.get<NoteRepository>(),
          authRepository: AppDI.get<AuthRepository>(),
          userRepository: AppDI.get<UserRepository>(),
          nostrDataService: AppDI.get<NostrDataService>(),
        ));

    AppDI.registerFactory<ProfileViewModel>(() => ProfileViewModel(
          userRepository: AppDI.get<UserRepository>(),
          authRepository: AppDI.get<AuthRepository>(),
          noteRepository: AppDI.get<NoteRepository>(),
        ));

    AppDI.registerFactory<NotificationViewModel>(() => NotificationViewModel(
          notificationRepository: AppDI.get<NotificationRepository>(),
          userRepository: AppDI.get<UserRepository>(),
          nostrDataService: AppDI.get<NostrDataService>(),
        ));

    AppDI.registerFactory<ThreadViewModel>(() => ThreadViewModel(
          noteRepository: AppDI.get<NoteRepository>(),
          userRepository: AppDI.get<UserRepository>(),
          nostrDataService: AppDI.get<NostrDataService>(),
        ));

    AppDI.registerFactory<ComposeViewModel>(() => ComposeViewModel(
          noteRepository: AppDI.get<NoteRepository>(),
          authRepository: AppDI.get<AuthRepository>(),
          userRepository: AppDI.get<UserRepository>(),
        ));

    AppDI.registerFactory<EditProfileViewModel>(() => EditProfileViewModel(
          userRepository: AppDI.get<UserRepository>(),
          authRepository: AppDI.get<AuthRepository>(),
        ));
  }
}
