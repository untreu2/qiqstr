import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/services/feed_loader_service.dart';
import 'profile_event.dart';
import 'profile_state.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final UserRepository _userRepository;
  final AuthRepository _authRepository;
  final FeedLoaderService _feedLoader;

  static const int _pageSize = 30;
  bool _isLoadingMore = false;
  final List<StreamSubscription> _subscriptions = [];

  ProfileBloc({
    required UserRepository userRepository,
    required AuthRepository authRepository,
    required FeedLoaderService feedLoader,
  })  : _userRepository = userRepository,
        _authRepository = authRepository,
        _feedLoader = feedLoader,
        super(const ProfileInitial()) {
    on<ProfileLoadRequested>(_onProfileLoaded);
    on<ProfileRefreshed>(_onProfileRefreshed);
    on<ProfileFollowToggled>(_onProfileFollowToggled);
    on<ProfileEditRequested>(_onProfileEditRequested);
    on<ProfileFollowingListRequested>(_onProfileFollowingListRequested);
    on<ProfileFollowersListRequested>(_onProfileFollowersListRequested);
    on<ProfileNotesLoaded>(_onProfileNotesLoaded);
    on<ProfileLoadMoreNotesRequested>(_onProfileLoadMoreNotesRequested);
    on<ProfileUserUpdated>(_onProfileUserUpdated);
  }

  Future<void> _onProfileLoaded(
    ProfileLoadRequested event,
    Emitter<ProfileState> emit,
  ) async {
    emit(const ProfileLoading());

    final currentUserResult = await _authRepository.getCurrentUserNpub();
    final currentUserNpub = currentUserResult.fold(
      (npub) => npub,
      (_) => null,
    );

    final profileResult = await _userRepository.getUserProfile(event.pubkeyHex.length == 64 ? _authRepository.hexToNpub(event.pubkeyHex) ?? event.pubkeyHex : event.pubkeyHex);

    await profileResult.fold(
      (user) async {
        final userNpub = user['npub'] as String? ?? '';
        final isCurrentUser = currentUserNpub != null && currentUserNpub == userNpub;
        bool isFollowing = false;

        if (!isCurrentUser && currentUserNpub != null && userNpub.isNotEmpty) {
          final followingResult = await _userRepository.isFollowing(userNpub);
          isFollowing = followingResult.fold((following) => following, (_) => false);
        }

        emit(ProfileLoaded(
          user: user,
          isFollowing: isFollowing,
          isCurrentUser: isCurrentUser,
          profiles: {userNpub: user},
          notes: const [],
          currentProfileNpub: userNpub,
          currentUserNpub: currentUserNpub ?? '',
        ));

        if (userNpub.isNotEmpty) {
          _subscribeToUserUpdates(emit, userNpub);
          add(ProfileNotesLoaded(userNpub));
        }
      },
      (error) async {
        emit(ProfileError(error));
      },
    );
  }

  Future<void> _onProfileRefreshed(
    ProfileRefreshed event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;

    final currentState = state as ProfileLoaded;
    final targetUserNpub = currentState.currentProfileNpub;
    
    if (targetUserNpub.isEmpty) {
      return;
    }

    final params = FeedLoadParams(
      type: FeedType.profile,
      targetUserNpub: targetUserNpub,
      limit: _pageSize,
      skipCache: true,
    );

    final result = await _feedLoader.loadFeed(params);

    if (result.isSuccess) {
      emit(currentState.copyWith(notes: result.notes));

      _feedLoader.loadProfilesAndInteractionsForNotes(
        result.notes,
        Map.from(currentState.profiles),
        (profiles) {
          if (state is ProfileLoaded) {
            final updatedState = state as ProfileLoaded;
            emit(updatedState.copyWith(profiles: profiles));
          }
        },
      );
    }
  }

  Future<void> _onProfileFollowToggled(
    ProfileFollowToggled event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;

    final currentState = state as ProfileLoaded;
    if (currentState.isCurrentUser) return;

    final wasFollowing = currentState.isFollowing;
    emit(currentState.copyWith(isFollowing: !wasFollowing));

    final result = wasFollowing
        ? await _userRepository.unfollowUser(currentState.currentProfileNpub)
        : await _userRepository.followUser(currentState.currentProfileNpub);

    result.fold(
      (_) {},
      (error) {
        emit(currentState.copyWith(isFollowing: wasFollowing));
        emit(ProfileError('Failed to ${wasFollowing ? 'unfollow' : 'follow'} user: $error'));
      },
    );
  }

  void _onProfileEditRequested(
    ProfileEditRequested event,
    Emitter<ProfileState> emit,
  ) {
  }

  Future<void> _onProfileFollowingListRequested(
    ProfileFollowingListRequested event,
    Emitter<ProfileState> emit,
  ) async {
    final result = await _userRepository.getFollowingList();

    result.fold(
      (users) => emit(ProfileFollowingListLoaded(users)),
      (error) => emit(ProfileError(error)),
    );
  }

  Future<void> _onProfileFollowersListRequested(
    ProfileFollowersListRequested event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;

    emit(ProfileError('Followers list is not available'));
  }

  Future<void> _onProfileNotesLoaded(
    ProfileNotesLoaded event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;

    final currentState = state as ProfileLoaded;

    if (event.pubkeyHex.isEmpty) {
      emit(ProfileError('NPUB cannot be empty'));
      return;
    }

    final targetUserNpub = event.pubkeyHex.length == 64 
        ? (_authRepository.hexToNpub(event.pubkeyHex) ?? event.pubkeyHex)
        : event.pubkeyHex;

    if (targetUserNpub.isEmpty) {
      emit(ProfileError('NPUB cannot be empty'));
      return;
    }

    final params = FeedLoadParams(
      type: FeedType.profile,
      targetUserNpub: targetUserNpub,
      limit: _pageSize,
      skipCache: true,
    );

    final result = await _feedLoader.loadFeed(params);

    if (result.isSuccess) {
      if (result.notes.isNotEmpty) {
        emit(currentState.copyWith(notes: result.notes));

        _feedLoader.loadProfilesAndInteractionsForNotes(
          result.notes,
          Map.from(currentState.profiles),
          (profiles) {
            if (state is ProfileLoaded) {
              final updatedState = state as ProfileLoaded;
              emit(updatedState.copyWith(profiles: profiles));
            }
          },
        );
      }
    } else {
      emit(ProfileError(result.error ?? 'Failed to load notes'));
    }
  }

  Future<void> _onProfileLoadMoreNotesRequested(
    ProfileLoadMoreNotesRequested event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is! ProfileLoaded) return;

    final currentState = state as ProfileLoaded;
    if (_isLoadingMore || !currentState.canLoadMore) return;

    final currentNotes = currentState.notes;
    if (currentNotes.isEmpty) return;

    _isLoadingMore = true;
    emit(currentState.copyWith(isLoadingMore: true));

    final oldestNote = currentNotes.reduce((a, b) {
      final aTimestamp = a['timestamp'] as DateTime? ?? DateTime(2000);
      final bTimestamp = b['timestamp'] as DateTime? ?? DateTime(2000);
      return aTimestamp.isBefore(bTimestamp) ? a : b;
    });
    final oldestTimestamp = oldestNote['timestamp'] as DateTime? ?? DateTime(2000);
    final until = oldestTimestamp.subtract(const Duration(milliseconds: 100));

    final params = FeedLoadParams(
      type: FeedType.profile,
      targetUserNpub: currentState.currentProfileNpub,
      limit: _pageSize,
      until: until,
      skipCache: true,
    );

    final result = await _feedLoader.loadFeed(params);

    if (result.isSuccess && result.notes.isNotEmpty) {
      final currentIds = currentNotes.map((n) => n['id'] as String? ?? '').where((id) => id.isNotEmpty).toSet();
      final uniqueNewNotes = result.notes.where((n) {
        final noteId = n['id'] as String? ?? '';
        return noteId.isNotEmpty && !currentIds.contains(noteId);
      }).toList();

      if (uniqueNewNotes.isNotEmpty) {
        final allNotes = [...currentNotes, ...uniqueNewNotes];
        final allSeenIds = <String>{};
        final deduplicatedNotes = <Map<String, dynamic>>[];

        for (final note in allNotes) {
          final noteId = note['id'] as String? ?? '';
          if (noteId.isNotEmpty && !allSeenIds.contains(noteId)) {
            allSeenIds.add(noteId);
            deduplicatedNotes.add(note);
          }
        }

        emit(currentState.copyWith(notes: deduplicatedNotes, isLoadingMore: false));

        _feedLoader.loadProfilesAndInteractionsForNotes(
          uniqueNewNotes,
          Map.from(currentState.profiles),
          (profiles) {
            if (state is ProfileLoaded) {
              final updatedState = state as ProfileLoaded;
              emit(updatedState.copyWith(profiles: profiles));
            }
          },
        );
      } else {
        emit(currentState.copyWith(isLoadingMore: false));
      }
    } else {
      emit(currentState.copyWith(isLoadingMore: false));
    }

    _isLoadingMore = false;
  }

  void _onProfileUserUpdated(
    ProfileUserUpdated event,
    Emitter<ProfileState> emit,
  ) {
    if (state is ProfileLoaded) {
      final currentState = state as ProfileLoaded;
      final updatedProfiles = Map<String, Map<String, dynamic>>.from(currentState.profiles);
      final userNpub = event.user['npub'] as String? ?? '';
      if (userNpub.isNotEmpty) {
        updatedProfiles[userNpub] = event.user;
        emit(currentState.copyWith(profiles: updatedProfiles));
      }
    }
  }

  void _subscribeToUserUpdates(Emitter<ProfileState> emit, String npub) {
    _subscriptions.add(
      _userRepository.currentUserStream.listen((updatedUser) {
        if (state is ProfileLoaded) {
          final currentState = state as ProfileLoaded;
          final updatedUserNpub = updatedUser['npub'] as String? ?? '';
          if (updatedUserNpub.isNotEmpty && currentState.currentProfileNpub == updatedUserNpub) {
            final updatedProfiles = Map<String, Map<String, dynamic>>.from(currentState.profiles);
            updatedProfiles[updatedUserNpub] = updatedUser;
            emit(currentState.copyWith(user: updatedUser, profiles: updatedProfiles));
          }
        }
      }),
    );
  }

  @override
  Future<void> close() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    return super.close();
  }
}
