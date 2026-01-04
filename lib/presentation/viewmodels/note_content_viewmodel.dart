import '../../core/base/base_view_model.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/services/user_batch_fetcher.dart';
import '../../models/user_model.dart';
import 'package:nostr_nip19/nostr_nip19.dart';

class NoteContentViewModel extends BaseViewModel {
  final UserRepository _userRepository;
  final AuthRepository _authRepository;
  final List<Map<String, dynamic>> textParts;

  NoteContentViewModel({
    required UserRepository userRepository,
    required AuthRepository authRepository,
    required this.textParts,
  })  : _userRepository = userRepository,
        _authRepository = authRepository {
    _loadMentionUsersSync();
    _preloadMentionUsersAsync();
  }

  final Map<String, UserModel> _mentionUsers = {};
  Map<String, UserModel> get mentionUsers => Map.unmodifiable(_mentionUsers);

  String? extractPubkey(String bech32) {
    try {
      if (bech32.startsWith('npub1')) {
        return decodeBasicBech32(bech32, 'npub');
      } else if (bech32.startsWith('nprofile1')) {
        final result = decodeTlvBech32Full(bech32, 'nprofile');
        return result['type_0_main'];
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  static UserModel _createPlaceholderUser(String pubkey) {
    return UserModel.create(
      pubkeyHex: pubkey,
      name: pubkey.length > 8 ? pubkey.substring(0, 8) : pubkey,
      about: '',
      profileImage: '',
      banner: '',
      website: '',
      nip05: '',
      lud16: '',
      updatedAt: DateTime.now(),
      nip05Verified: false,
    );
  }

  void _loadMentionUsersSync() {
    final mentionIds = textParts.where((part) => part['type'] == 'mention').map((part) => part['id'] as String).toSet();

    for (final mentionId in mentionIds) {
      final actualPubkey = extractPubkey(mentionId);
      if (actualPubkey == null) continue;

      try {
        final npubEncoded = encodeBasicBech32(actualPubkey, 'npub');
        final cachedUser = _userRepository.getCachedUserSync(npubEncoded);

        if (cachedUser != null) {
          _mentionUsers[actualPubkey] = cachedUser;
        } else {
          _mentionUsers[actualPubkey] = _createPlaceholderUser(actualPubkey);
        }
      } catch (e) {
        continue;
      }
    }
    safeNotifyListeners();
  }

  Future<void> _preloadMentionUsersAsync() async {
    final mentionIds = textParts.where((part) => part['type'] == 'mention').map((part) => part['id'] as String).toSet();

    if (mentionIds.isEmpty) return;

    final pubkeyHexToNpubMap = <String, String>{};
    final npubsToFetch = <String>[];

    for (final mentionId in mentionIds) {
      final actualPubkey = extractPubkey(mentionId);
      if (actualPubkey == null) continue;

      try {
        if (!_mentionUsers.containsKey(actualPubkey) || _mentionUsers[actualPubkey]!.name == actualPubkey.substring(0, 8)) {
          final npubEncoded = encodeBasicBech32(actualPubkey, 'npub');
          pubkeyHexToNpubMap[actualPubkey] = npubEncoded;
          npubsToFetch.add(npubEncoded);
        }
      } catch (e) {
        continue;
      }
    }

    if (npubsToFetch.isEmpty) return;

    await executeOperation('preloadMentionUsers', () async {
      try {
        final cachedResults = await _userRepository.getUserProfiles(npubsToFetch, priority: FetchPriority.urgent);

        if (isDisposed) return;

        bool hasUpdates = false;
        for (final entry in cachedResults.entries) {
          final npub = entry.key;
          final result = entry.value;

          final pubkeyHex = pubkeyHexToNpubMap.entries.firstWhere((e) => e.value == npub, orElse: () => MapEntry('', '')).key;

          if (pubkeyHex.isEmpty) continue;

          result.fold(
            (user) {
              if (!_mentionUsers.containsKey(pubkeyHex) ||
                  _mentionUsers[pubkeyHex]!.name == pubkeyHex.substring(0, 8) ||
                  _mentionUsers[pubkeyHex]!.profileImage.isEmpty) {
                _mentionUsers[pubkeyHex] = user;
                hasUpdates = true;
              }
            },
            (_) {},
          );
        }

        if (!isDisposed && hasUpdates) {
          safeNotifyListeners();
        }

        final missingNpubs = cachedResults.entries.where((e) => e.value.isError).map((e) => e.key).toList();

        if (missingNpubs.isNotEmpty) {
          await _loadMentionUsersBatch(missingNpubs, pubkeyHexToNpubMap);
        }
      } catch (e) {
        await _loadMentionUsersBatch(npubsToFetch, pubkeyHexToNpubMap);
      }
    }, showLoading: false);
  }

  Future<void> _loadMentionUsersBatch(List<String> npubs, Map<String, String> pubkeyMap) async {
    if (npubs.isEmpty || isDisposed) return;

    await executeOperation('loadMentionUsersBatch', () async {
      try {
        final results = await _userRepository.getUserProfiles(npubs, priority: FetchPriority.normal);

        if (isDisposed) return;

        bool hasUpdates = false;
        for (final entry in results.entries) {
          final npub = entry.key;
          final result = entry.value;

          final pubkeyHex = pubkeyMap.entries.firstWhere((e) => e.value == npub, orElse: () => MapEntry('', '')).key;

          if (pubkeyHex.isEmpty) continue;

          result.fold(
            (user) {
              if (!_mentionUsers.containsKey(pubkeyHex) ||
                  _mentionUsers[pubkeyHex]!.name == pubkeyHex.substring(0, 8) ||
                  _mentionUsers[pubkeyHex]!.profileImage.isEmpty) {
                _mentionUsers[pubkeyHex] = user;
                hasUpdates = true;
              }
            },
            (_) {
              if (!_mentionUsers.containsKey(pubkeyHex)) {
                _mentionUsers[pubkeyHex] = _createPlaceholderUser(pubkeyHex);
                hasUpdates = true;
              }
            },
          );
        }

        if (!isDisposed && hasUpdates) {
          safeNotifyListeners();
        }
      } catch (e) {
        if (!isDisposed) {
          safeNotifyListeners();
        }
      }
    }, showLoading: false);
  }

  Future<String?> getCurrentUserNpub() async {
    final result = await _authRepository.getCurrentUserNpub();
    return result.fold((npub) => npub, (error) => null);
  }
}
