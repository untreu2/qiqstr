import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/following_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/relay_service.dart';
import 'sidebar_event.dart';
import 'sidebar_state.dart';

class SidebarBloc extends Bloc<SidebarEvent, SidebarState> {
  final FollowingRepository _followingRepository;
  final ProfileRepository _profileRepository;
  final SyncService _syncService;
  final AuthService _authService;
  String? _currentUserHex;
  String? _currentNpub;
  StreamSubscription? _profileSubscription;
  Timer? _relayCountTimer;
  Timer? _countsTimer;
  Timer? _followingPollTimer;

  SidebarBloc({
    required FollowingRepository followingRepository,
    required ProfileRepository profileRepository,
    required SyncService syncService,
    required AuthService authService,
  })  : _followingRepository = followingRepository,
        _profileRepository = profileRepository,
        _syncService = syncService,
        _authService = authService,
        super(const SidebarInitial()) {
    on<SidebarInitialized>(_onSidebarInitialized);
    on<SidebarRefreshed>(_onSidebarRefreshed);
    on<_SidebarProfileUpdated>(_onSidebarProfileUpdated);
    on<_SidebarCountsUpdated>(_onSidebarCountsUpdated);
    on<_SidebarRelayCountUpdated>(_onSidebarRelayCountUpdated);
    on<_SidebarAccountsLoaded>(_onAccountsLoaded);
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
      _loadStoredAccounts();
    } catch (e) {
      emit(const SidebarLoaded(currentUser: {}));
    }
  }

  void _watchProfile(String userHex) {
    _profileSubscription?.cancel();
    _profileSubscription =
        _profileRepository.watchProfile(userHex).listen((profile) {
      if (isClosed || profile == null) return;
      add(_SidebarProfileUpdated(profile.toMap()));
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
      'pubkey': _currentUserHex ?? '',
      'name': profileData['name'] ?? profileData['display_name'] ?? '',
      'display_name': profileData['display_name'] ?? '',
      'about': profileData['about'] ?? '',
      'picture': profileData['picture'] ?? '',
      'banner': profileData['banner'] ?? '',
      'nip05': profileData['nip05'] ?? '',
      'lud16': profileData['lud16'] ?? '',
      'website': profileData['website'] ?? '',
    };
  }

  void _syncInBackground(String userHex) {
    _syncService.syncProfile(userHex).catchError((_) {});
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
    Future.wait([
      _followingRepository.getFollowing(userPubkeyHex),
      _profileRepository.getFollowerCount(userPubkeyHex),
    ]).then((results) {
      if (isClosed) return;
      final follows = results[0] as List<String>?;
      final followerCount = results[1] as int;
      add(_SidebarCountsUpdated(follows?.length ?? 0, followerCount));
    }).catchError((_) {
      if (!isClosed) add(_SidebarCountsUpdated(0, 0));
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
        final follows = await _followingRepository.getFollowing(pubkeyHex);
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
    RustRelayService.instance.getConnectedRelayCount().then((count) {
      if (!isClosed) add(_SidebarRelayCountUpdated(count));
    }).catchError((_) {});
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

  void _loadStoredAccounts() async {
    if (isClosed) return;
    try {
      final accounts = await _authService.getStoredAccounts();
      if (isClosed) return;

      final profileImages = <String, String>{};
      final futures = accounts.map((account) async {
        final hex = _authService.npubToHex(account.npub);
        if (hex != null) {
          final profile = await _profileRepository.getProfile(hex);
          if (profile != null) {
            final picture = profile.picture ?? '';
            if (picture.isNotEmpty) {
              profileImages[account.npub] = picture;
            }
          }
        }
      });
      await Future.wait(futures);

      if (isClosed) return;
      add(_SidebarAccountsLoaded(accounts, profileImages));
    } catch (_) {}
  }

  void _onAccountsLoaded(
    _SidebarAccountsLoaded event,
    Emitter<SidebarState> emit,
  ) {
    if (state is! SidebarLoaded) return;
    emit((state as SidebarLoaded).copyWith(
      storedAccounts: event.accounts,
      accountProfileImages: event.profileImages,
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

class _SidebarAccountsLoaded extends SidebarEvent {
  final List<StoredAccount> accounts;
  final Map<String, String> profileImages;
  const _SidebarAccountsLoaded(this.accounts, this.profileImages);

  @override
  List<Object?> get props => [accounts, profileImages];
}
