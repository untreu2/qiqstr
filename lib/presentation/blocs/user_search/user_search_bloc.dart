import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/user_repository.dart';
import 'user_search_event.dart';
import 'user_search_state.dart';

class UserSearchBloc extends Bloc<UserSearchEvent, UserSearchState> {
  final UserRepository _userRepository;

  UserSearchBloc({
    required UserRepository userRepository,
  })  : _userRepository = userRepository,
        super(const UserSearchInitial()) {
    on<UserSearchInitialized>(_onUserSearchInitialized);
    on<UserSearchQueryChanged>(_onUserSearchQueryChanged);
  }

  Future<void> _onUserSearchInitialized(
    UserSearchInitialized event,
    Emitter<UserSearchState> emit,
  ) async {
    emit(const UserSearchLoaded(
      filteredUsers: [],
      randomUsers: [],
      isLoadingRandom: true,
    ));

    final isarService = _userRepository.isarService;

    if (!isarService.isInitialized) {
      await isarService.waitForInitialization();
    }

    final randomIsarProfiles = await isarService.getRandomUsersWithImages(limit: 50);

    final userModels = randomIsarProfiles.map((profileData) {
      final pubkeyHex = profileData['pubkeyHex'] ?? '';
      return <String, dynamic>{
        'pubkeyHex': pubkeyHex,
        'npub': pubkeyHex,
        'name': profileData['name'] ?? '',
        'about': profileData['about'] ?? '',
        'profileImage': profileData['profileImage'] ?? '',
        'banner': profileData['banner'] ?? '',
        'website': profileData['website'] ?? '',
        'nip05': profileData['nip05'] ?? '',
        'lud16': profileData['lud16'] ?? '',
        'updatedAt': DateTime.now(),
        'nip05Verified': false,
        'followerCount': 0,
      };
    }).toList();

    emit(UserSearchLoaded(
      filteredUsers: [],
      randomUsers: userModels,
      isLoadingRandom: false,
    ));
  }

  Future<void> _onUserSearchQueryChanged(
    UserSearchQueryChanged event,
    Emitter<UserSearchState> emit,
  ) async {
    final query = event.query.trim();

    final currentState = state;
    final existingRandomUsers = currentState is UserSearchLoaded ? currentState.randomUsers : const <Map<String, dynamic>>[];

    if (query.isEmpty) {
      if (currentState is UserSearchLoaded) {
        emit(currentState.copyWith(
          filteredUsers: [],
          isSearching: false,
        ));
      } else {
        emit(UserSearchLoaded(
          filteredUsers: [],
          randomUsers: existingRandomUsers,
          isSearching: false,
        ));
      }
      return;
    }

    if (currentState is UserSearchLoaded) {
      emit(currentState.copyWith(isSearching: true));
    } else {
      emit(UserSearchLoaded(
        filteredUsers: [],
        randomUsers: existingRandomUsers,
        isSearching: true,
      ));
    }

    final result = await _userRepository.searchUsers(query);

    result.fold(
      (users) {
        final updatedState = state;
        if (updatedState is UserSearchLoaded) {
          emit(updatedState.copyWith(
            filteredUsers: users,
            isSearching: false,
          ));
        } else {
          emit(UserSearchLoaded(
            filteredUsers: users,
            randomUsers: existingRandomUsers,
            isSearching: false,
          ));
        }
      },
      (error) {
        emit(UserSearchError(error));
      },
    );
  }
}
