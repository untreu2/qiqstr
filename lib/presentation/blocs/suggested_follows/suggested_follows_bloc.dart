import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/data_service.dart';
import '../../../data/services/user_batch_fetcher.dart';
import '../../../constants/suggestions.dart';
import 'suggested_follows_event.dart';
import 'suggested_follows_state.dart';

class SuggestedFollowsBloc extends Bloc<SuggestedFollowsEvent, SuggestedFollowsState> {
  final UserRepository _userRepository;
  final DataService _nostrDataService;

  SuggestedFollowsBloc({
    required UserRepository userRepository,
    required DataService nostrDataService,
  })  : _userRepository = userRepository,
        _nostrDataService = nostrDataService,
        super(const SuggestedFollowsInitial()) {
    on<SuggestedFollowsLoadRequested>(_onSuggestedFollowsLoadRequested);
    on<SuggestedFollowsUserToggled>(_onSuggestedFollowsUserToggled);
    on<SuggestedFollowsFollowSelectedRequested>(_onSuggestedFollowsFollowSelectedRequested);
    on<SuggestedFollowsSkipRequested>(_onSuggestedFollowsSkipRequested);
  }

  Future<void> _onSuggestedFollowsLoadRequested(
    SuggestedFollowsLoadRequested event,
    Emitter<SuggestedFollowsState> emit,
  ) async {
    emit(const SuggestedFollowsLoading());

    try {
      final npubs = <String>[];
      for (final pubkeyHex in suggestedUsers) {
        final npub = _nostrDataService.authService.hexToNpub(pubkeyHex);
        if (npub != null) {
          npubs.add(npub);
        }
      }

      final results = await _userRepository.getUserProfiles(
        npubs,
        priority: FetchPriority.high,
      );

      final List<Map<String, dynamic>> users = [];
      for (final entry in results.entries) {
        entry.value.fold(
          (user) => users.add(user),
          (error) {
            final fallbackUser = {
              'pubkeyHex': entry.key,
              'npub': entry.key,
              'name': 'Nostr User',
              'about': 'A Nostr user',
              'profileImage': '',
              'nip05': '',
              'banner': '',
              'lud16': '',
              'website': '',
              'updatedAt': DateTime.now(),
              'nip05Verified': false,
              'followerCount': 0,
            };
            users.add(fallbackUser);
          },
        );
      }

      final selectedUsers = users
          .map((user) => user['npub'] as String? ?? '')
          .where((npub) => npub.isNotEmpty)
          .toSet();

      emit(SuggestedFollowsLoaded(
        suggestedUsers: users,
        selectedUsers: selectedUsers,
      ));
    } catch (e) {
      emit(SuggestedFollowsError('Failed to load suggested users: $e'));
    }
  }

  void _onSuggestedFollowsUserToggled(
    SuggestedFollowsUserToggled event,
    Emitter<SuggestedFollowsState> emit,
  ) {
    final currentState = state;
    if (currentState is! SuggestedFollowsLoaded) return;

    final selectedUsers = Set<String>.from(currentState.selectedUsers);
    if (selectedUsers.contains(event.npub)) {
      selectedUsers.remove(event.npub);
    } else {
      selectedUsers.add(event.npub);
    }

    emit(currentState.copyWith(selectedUsers: selectedUsers));
  }

  Future<void> _onSuggestedFollowsFollowSelectedRequested(
    SuggestedFollowsFollowSelectedRequested event,
    Emitter<SuggestedFollowsState> emit,
  ) async {
    final currentState = state;
    if (currentState is! SuggestedFollowsLoaded || currentState.isProcessing) return;

    emit(currentState.copyWith(isProcessing: true));

    int successCount = 0;
    for (final npub in currentState.selectedUsers) {
      try {
        final result = await _userRepository.followUser(npub);
        result.fold(
          (_) => successCount++,
          (_) {},
        );
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        // Silently handle error - individual follow failure is acceptable
      }
    }

    emit(currentState.copyWith(isProcessing: false));
  }

  void _onSuggestedFollowsSkipRequested(
    SuggestedFollowsSkipRequested event,
    Emitter<SuggestedFollowsState> emit,
  ) {
    final currentState = state;
    if (currentState is! SuggestedFollowsLoaded || currentState.isProcessing) return;

    emit(currentState.copyWith(selectedUsers: {}));
  }
}
