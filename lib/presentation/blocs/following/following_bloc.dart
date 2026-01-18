import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/user_batch_fetcher.dart';
import 'following_event.dart';
import 'following_state.dart';

class FollowingBloc extends Bloc<FollowingEvent, FollowingState> {
  final UserRepository _userRepository;

  FollowingBloc({
    required UserRepository userRepository,
  })  : _userRepository = userRepository,
        super(const FollowingInitial()) {
    on<FollowingLoadRequested>(_onFollowingLoadRequested);
  }

  Future<void> _onFollowingLoadRequested(
    FollowingLoadRequested event,
    Emitter<FollowingState> emit,
  ) async {
    emit(const FollowingLoading());

    final result = await _userRepository.getFollowingListForUser(event.userNpub);

    await result.fold(
      (users) async {
        final loadedUsers = <String, Map<String, dynamic>>{};
        await _loadUserProfilesBatch(users, loadedUsers);

        emit(FollowingLoaded(
          followingUsers: users,
          loadedUsers: loadedUsers,
        ));
      },
      (error) async {
        emit(FollowingError(error));
      },
    );
  }

  Future<void> _loadUserProfilesBatch(
    List<Map<String, dynamic>> users,
    Map<String, Map<String, dynamic>> loadedUsers,
  ) async {
    final npubsToLoad = users
        .where((user) {
          final npub = user['npub'] as String?;
          return npub != null && npub.isNotEmpty && !loadedUsers.containsKey(npub);
        })
        .map((user) => user['npub'] as String? ?? '')
        .where((npub) => npub.isNotEmpty)
        .toList();

    if (npubsToLoad.isEmpty) return;

    try {
      final results = await _userRepository.getUserProfiles(npubsToLoad, priority: FetchPriority.high);

      for (final result in results.values) {
        result.fold(
          (user) {
            final npub = user['npub'] as String? ?? '';
            if (npub.isNotEmpty) {
              loadedUsers[npub] = user;
            }
          },
          (error) {
            // Silently handle error - profile load failure is acceptable
          },
        );
      }
    } catch (e) {
      // Silently handle error - profile load failure is acceptable
    }
  }
}
