import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/data_service.dart';
import 'sidebar_event.dart';
import 'sidebar_state.dart';

class SidebarBloc extends Bloc<SidebarEvent, SidebarState> {
  final AuthRepository _authRepository;
  final UserRepository _userRepository;
  final DataService _dataService;

  StreamSubscription<Map<String, dynamic>>? _userSubscription;

  SidebarBloc({
    required AuthRepository authRepository,
    required UserRepository userRepository,
    required DataService dataService,
  })  : _authRepository = authRepository,
        _userRepository = userRepository,
        _dataService = dataService,
        super(const SidebarInitial()) {
    on<SidebarInitialized>(_onSidebarInitialized);
    on<SidebarRefreshed>(_onSidebarRefreshed);
  }

  Future<void> _onSidebarInitialized(
    SidebarInitialized event,
    Emitter<SidebarState> emit,
  ) async {
    emit(const SidebarLoading());

    final npubResult = await _authRepository.getCurrentUserNpub();
    if (npubResult.isError || npubResult.data == null) {
      return;
    }

    final userResult = await _userRepository.getUserProfile(npubResult.data!);
    await userResult.fold(
      (user) async {
        emit(SidebarLoaded(currentUser: user));
        await _loadFollowerCounts(emit, user);
        _setupUserStreamListener(emit);
      },
      (error) async {},
    );
  }

  Future<void> _onSidebarRefreshed(
    SidebarRefreshed event,
    Emitter<SidebarState> emit,
  ) async {
    await _onSidebarInitialized(const SidebarInitialized(), emit);
  }

  void _setupUserStreamListener(Emitter<SidebarState> emit) {
    _userSubscription?.cancel();
    _userSubscription = _userRepository.currentUserStream.listen(
      (updatedUser) {
        final currentState = state;
        if (currentState is SidebarLoaded) {
          final currentNpub = currentState.currentUser['npub'] as String? ?? '';
          final updatedNpub = updatedUser['npub'] as String? ?? '';
          final currentImage = currentState.currentUser['profileImage'] as String? ?? '';
          final updatedImage = updatedUser['profileImage'] as String? ?? '';
          final currentName = currentState.currentUser['name'] as String? ?? '';
          final updatedName = updatedUser['name'] as String? ?? '';
          
          final hasChanges = currentNpub != updatedNpub ||
              currentImage != updatedImage ||
              currentName != updatedName;

          if (hasChanges) {
            emit(currentState.copyWith(currentUser: updatedUser));
            _loadFollowerCounts(emit, updatedUser);
          }
        }
      },
      onError: (error) {
        // Silently handle error - stream error is acceptable
      },
    );
  }

  Future<void> _loadFollowerCounts(Emitter<SidebarState> emit, Map<String, dynamic> user) async {
    final currentState = state;
    if (currentState is! SidebarLoaded) return;

    try {
      final userPubkeyHex = user['pubkeyHex'] as String? ?? '';
      if (userPubkeyHex.isEmpty) return;
      
      final followingResult = await _userRepository.getFollowingListForUser(userPubkeyHex);

      await followingResult.fold(
        (followingUsers) async {
          final followerCount = await _dataService.fetchFollowerCount(userPubkeyHex);
          if (state is SidebarLoaded) {
            emit((state as SidebarLoaded).copyWith(
              followingCount: followingUsers.length,
              followerCount: followerCount,
              isLoadingCounts: false,
            ));

            if (followerCount > 0) {
              await _userRepository.updateUserFollowerCount(userPubkeyHex, followerCount);
            }
          }
        },
        (error) async {
          if (state is SidebarLoaded) {
            emit((state as SidebarLoaded).copyWith(
              followingCount: 0,
              followerCount: 0,
              isLoadingCounts: false,
            ));
          }
        },
      );
    } catch (e) {
      if (state is SidebarLoaded) {
        emit((state as SidebarLoaded).copyWith(
          followingCount: 0,
          followerCount: 0,
          isLoadingCounts: false,
        ));
      }
    }
  }

  @override
  Future<void> close() {
    _userSubscription?.cancel();
    return super.close();
  }
}
