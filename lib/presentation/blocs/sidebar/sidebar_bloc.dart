import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/following_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/rust_database_service.dart';
import '../../../data/services/relay_service.dart';
import 'sidebar_event.dart';
import 'sidebar_state.dart';

class SidebarBloc extends Bloc<SidebarEvent, SidebarState> {
  final FollowingRepository _followingRepository;
  final ProfileRepository _profileRepository;
  final SyncService _syncService;
  final AuthService _authService;
  final RustDatabaseService _db;

  String? _currentUserHex;
  String? _currentNpub;
  StreamSubscription<Map<String, dynamic>?>? _profileSubscription;
  Timer? _relayCountTimer;
  Timer? _countsTimer;
  Timer? _followingPollTimer;

  SidebarBloc({
    required FollowingRepository followingRepository,
    required ProfileRepository profileRepository,
    required SyncService syncService,
    required AuthService authService,
    RustDatabaseService? db,
  })  : _followingRepository = followingRepository,
        _profileRepository = profileRepository,
        _syncService = syncService,
        _authService = authService,
        _db = db ?? RustDatabaseService.instance,
        super(const SidebarInitial()) {
    on<SidebarInitialized>(_onSidebarInitialized);
    on<SidebarRefreshed>(_onSidebarRefreshed);
    on<_SidebarProfileUpdated>(_onSidebarProfileUpdated);
    on<_SidebarCountsUpdated>(_onSidebarCountsUpdated);
    on<_SidebarRelayCountUpdated>(_onSidebarRelayCountUpdated);
  }

  Future<void> _onSidebarInitialized(
    SidebarInitialized event,
    Emitter<SidebarState> emit,
  ) async {
    try {
      final pubkeyResult = await _authService.getCurrentUserPublicKeyHex();
      if (pubkeyResult.isError || pubkeyResult.data == null) {
        return;
      }

      _currentUserHex = pubkeyResult.data!;
      _currentNpub =
          _authService.hexToNpub(_currentUserHex!) ?? _currentUserHex!;

      emit(const SidebarLoaded(currentUser: {}));

      _watchProfile(_currentUserHex!);
      _loadFollowerCounts(_currentUserHex!);
      _syncInBackground(_currentUserHex!);
      _startRelayCountPolling();
    } catch (e) {
      emit(const SidebarLoaded(currentUser: {}));
    }
  }

  void _watchProfile(String userHex) {
    _profileSubscription?.cancel();
    _profileSubscription = _db.watchProfile(userHex).listen((profileData) {
      if (isClosed || profileData == null) return;
      add(_SidebarProfileUpdated(profileData));
    });
  }

  void _onSidebarProfileUpdated(
    _SidebarProfileUpdated event,
    Emitter<SidebarState> emit,
  ) {
    if (state is! SidebarLoaded) return;
    final currentState = state as SidebarLoaded;

    final userMap = _buildUserMapFromProfile(event.profileData);
    emit(currentState.copyWith(currentUser: userMap));
  }

  Map<String, dynamic> _buildUserMapFromProfile(
      Map<String, dynamic> profileData) {
    return {
      'npub': _currentNpub ?? '',
      'pubkeyHex': _currentUserHex ?? '',
      'name': profileData['name'] ?? profileData['display_name'] ?? '',
      'display_name': profileData['display_name'] ?? '',
      'about': profileData['about'] ?? '',
      'picture': profileData['picture'] ?? '',
      'profileImage': profileData['picture'] ?? '',
      'banner': profileData['banner'] ?? '',
      'nip05': profileData['nip05'] ?? '',
      'lud16': profileData['lud16'] ?? '',
      'website': profileData['website'] ?? '',
    };
  }

  void _syncInBackground(String userHex) {
    Future.microtask(() async {
      if (isClosed) return;
      try {
        await _syncService.syncProfile(userHex);
      } catch (_) {}
    });
  }

  Future<void> _onSidebarRefreshed(
    SidebarRefreshed event,
    Emitter<SidebarState> emit,
  ) async {
    if (_currentUserHex == null) return;
    try {
      await _syncService.syncProfile(_currentUserHex!);
      _fetchCounts(_currentUserHex!);
    } catch (_) {}
  }

  void _loadFollowerCounts(String userPubkeyHex) {
    _fetchCounts(userPubkeyHex);
    _startFollowingPoll(userPubkeyHex);
    _countsTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _fetchCounts(userPubkeyHex);
    });
  }

  void _fetchCounts(String userPubkeyHex) {
    Future.microtask(() async {
      if (isClosed) return;
      try {
        final follows =
            await _followingRepository.getFollowingList(userPubkeyHex);
        final followerCount =
            await _profileRepository.getFollowerCount(userPubkeyHex);
        if (isClosed) return;
        add(_SidebarCountsUpdated(follows?.length ?? 0, followerCount));
      } catch (_) {
        if (isClosed) return;
        add(_SidebarCountsUpdated(0, 0));
      }
    });
  }

  void _startFollowingPoll(String pubkeyHex) {
    _followingPollTimer?.cancel();
    int attempts = 0;
    _followingPollTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) async {
      attempts++;
      if (isClosed || attempts > 15) {
        timer.cancel();
        return;
      }
      try {
        final follows =
            await _followingRepository.getFollowingList(pubkeyHex);
        if (follows != null && follows.isNotEmpty) {
          timer.cancel();
          if (!isClosed && state is SidebarLoaded) {
            final followerCount =
                await _profileRepository.getFollowerCount(pubkeyHex);
            if (!isClosed) {
              add(_SidebarCountsUpdated(follows.length, followerCount));
            }
          }
        }
      } catch (_) {}
    });
  }

  void _onSidebarCountsUpdated(
    _SidebarCountsUpdated event,
    Emitter<SidebarState> emit,
  ) {
    if (state is! SidebarLoaded) return;
    emit((state as SidebarLoaded).copyWith(
      followingCount: event.followingCount,
      followerCount: event.followerCount,
      isLoadingCounts: false,
    ));
  }

  void _startRelayCountPolling() {
    _loadRelayCount();
    _relayCountTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadRelayCount();
    });
  }

  void _loadRelayCount() {
    Future.microtask(() async {
      if (isClosed) return;
      try {
        final count = await RustRelayService.instance.getConnectedRelayCount();
        if (isClosed) return;
        add(_SidebarRelayCountUpdated(count));
      } catch (_) {}
    });
  }

  void _onSidebarRelayCountUpdated(
    _SidebarRelayCountUpdated event,
    Emitter<SidebarState> emit,
  ) {
    if (state is! SidebarLoaded) return;
    emit((state as SidebarLoaded).copyWith(
      connectedRelayCount: event.count,
    ));
  }

  @override
  Future<void> close() {
    _profileSubscription?.cancel();
    _relayCountTimer?.cancel();
    _countsTimer?.cancel();
    _followingPollTimer?.cancel();
    return super.close();
  }
}

class _SidebarProfileUpdated extends SidebarEvent {
  final Map<String, dynamic> profileData;
  const _SidebarProfileUpdated(this.profileData);

  @override
  List<Object?> get props => [profileData];
}

class _SidebarCountsUpdated extends SidebarEvent {
  final int followingCount;
  final int followerCount;
  const _SidebarCountsUpdated(this.followingCount, this.followerCount);

  @override
  List<Object?> get props => [followingCount, followerCount];
}

class _SidebarRelayCountUpdated extends SidebarEvent {
  final int count;
  const _SidebarRelayCountUpdated(this.count);

  @override
  List<Object?> get props => [count];
}
