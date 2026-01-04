import '../../core/base/base_view_model.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/data_service.dart';
import '../../data/services/mute_cache_service.dart';
import '../../data/services/user_batch_fetcher.dart';
import '../../models/user_model.dart';
import 'package:nostr_nip19/nostr_nip19.dart';

class MutedPageViewModel extends BaseViewModel {
  final UserRepository _userRepository;
  final AuthService _authService;
  final DataService _dataService;
  final MuteCacheService _muteCacheService;

  MutedPageViewModel({
    required UserRepository userRepository,
    required AuthService authService,
    required DataService dataService,
  })  : _userRepository = userRepository,
        _authService = authService,
        _dataService = dataService,
        _muteCacheService = MuteCacheService.instance {
    _loadMutedUsers();
  }

  List<UserModel> _mutedUsers = [];
  List<UserModel> get mutedUsers => _mutedUsers;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  final Map<String, bool> _unmutingStates = {};
  bool isUnmuting(String userNpub) => _unmutingStates[userNpub] ?? false;

  Future<void> _loadMutedUsers() async {
    await executeOperation('loadMutedUsers', () async {
      _isLoading = true;
      _error = null;
      safeNotifyListeners();

      final currentUserResult = await _authService.getCurrentUserNpub();
      if (currentUserResult.isError || currentUserResult.data == null) {
        if (!isDisposed) {
          _error = 'Not authenticated';
          _isLoading = false;
          safeNotifyListeners();
        }
        return;
      }

      final currentUserNpub = currentUserResult.data!;
      String currentUserHex = currentUserNpub;

      if (currentUserNpub.startsWith('npub1')) {
        final hexResult = _authService.npubToHex(currentUserNpub);
        if (hexResult != null) {
          currentUserHex = hexResult;
        }
      }

      final mutedPubkeys = await _muteCacheService.getOrFetch(currentUserHex, () async {
        final result = await _dataService.getMuteList(currentUserHex);
        return result.isSuccess ? result.data : null;
      });

      if (mutedPubkeys == null || mutedPubkeys.isEmpty) {
        if (!isDisposed) {
          _mutedUsers = [];
          _isLoading = false;
          safeNotifyListeners();
        }
        return;
      }

      final npubs = <String>[];
      for (final pubkey in mutedPubkeys) {
        String npub = pubkey;
        try {
          if (!pubkey.startsWith('npub1')) {
            npub = encodeBasicBech32(pubkey, 'npub');
          }
        } catch (e) {
          npub = pubkey;
        }
        npubs.add(npub);
      }

      final userResults = await _userRepository.getUserProfiles(npubs, priority: FetchPriority.high);

      final users = <UserModel>[];
      for (final entry in userResults.entries) {
        entry.value.fold(
          (user) => users.add(user),
          (error) {
            final npub = entry.key;
            final shortName = npub.length > 8 ? npub.substring(0, 8) : npub;
            users.add(UserModel.create(
              pubkeyHex: npub,
              name: shortName,
              about: '',
              profileImage: '',
              banner: '',
              website: '',
              nip05: '',
              lud16: '',
              updatedAt: DateTime.now(),
              nip05Verified: false,
            ));
          },
        );
      }

      if (!isDisposed) {
        _mutedUsers = users;
        _isLoading = false;
        safeNotifyListeners();
      }
    }, showLoading: false);
  }

  Future<void> unmuteUser(String userNpub) async {
    if (_unmutingStates[userNpub] == true || isDisposed) return;

    await executeOperation('unmuteUser', () async {
      _unmutingStates[userNpub] = true;
      safeNotifyListeners();

      final result = await _userRepository.unmuteUser(userNpub);

      result.fold(
        (_) {
          if (!isDisposed) {
            _mutedUsers.removeWhere((u) => u.npub == userNpub);
            _unmutingStates.remove(userNpub);
            safeNotifyListeners();
          }
        },
        (error) {
          if (!isDisposed) {
            _unmutingStates.remove(userNpub);
            safeNotifyListeners();
          }
        },
      );
    }, showLoading: false);
  }

  Future<void> refresh() async {
    await _loadMutedUsers();
  }
}
