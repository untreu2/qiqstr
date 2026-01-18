import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/services/user_batch_fetcher.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import 'note_content_event.dart';
import 'note_content_state.dart';

class NoteContentBloc extends Bloc<NoteContentEvent, NoteContentState> {
  final UserRepository _userRepository;
  final AuthRepository _authRepository;

  NoteContentBloc({
    required UserRepository userRepository,
    required AuthRepository authRepository,
  })  : _userRepository = userRepository,
        _authRepository = authRepository,
        super(const NoteContentInitial()) {
    on<NoteContentInitialized>(_onNoteContentInitialized);
  }

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

  static Map<String, dynamic> _createPlaceholderUser(String pubkey) {
    return {
      'pubkeyHex': pubkey,
      'npub': pubkey,
      'name': pubkey.length > 8 ? pubkey.substring(0, 8) : pubkey,
      'about': '',
      'profileImage': '',
      'banner': '',
      'website': '',
      'nip05': '',
      'lud16': '',
      'updatedAt': DateTime.now(),
      'nip05Verified': false,
      'followerCount': 0,
    };
  }

  Future<void> _onNoteContentInitialized(
    NoteContentInitialized event,
    Emitter<NoteContentState> emit,
  ) async {
    final mentionUsers = <String, Map<String, dynamic>>{};
    final mentionIds = event.textParts
        .where((part) => part['type'] == 'mention')
        .map((part) => part['id'] as String)
        .toSet();

    for (final mentionId in mentionIds) {
      final actualPubkey = extractPubkey(mentionId);
      if (actualPubkey == null) continue;

      try {
        final npubEncoded = encodeBasicBech32(actualPubkey, 'npub');
        final cachedUser = await _userRepository.getCachedUser(npubEncoded);

        if (cachedUser != null) {
          mentionUsers[actualPubkey] = cachedUser;
        } else {
          mentionUsers[actualPubkey] = _createPlaceholderUser(actualPubkey);
        }
      } catch (e) {
        continue;
      }
    }

    emit(NoteContentLoaded(mentionUsers: mentionUsers));

    final pubkeyHexToNpubMap = <String, String>{};
    final npubsToFetch = <String>[];

    for (final mentionId in mentionIds) {
      final actualPubkey = extractPubkey(mentionId);
      if (actualPubkey == null) continue;

      try {
        final existingUser = mentionUsers[actualPubkey];
        final existingName = existingUser?['name'] as String? ?? '';
        if (!mentionUsers.containsKey(actualPubkey) ||
            existingName == actualPubkey.substring(0, 8)) {
          final npubEncoded = encodeBasicBech32(actualPubkey, 'npub');
          pubkeyHexToNpubMap[actualPubkey] = npubEncoded;
          npubsToFetch.add(npubEncoded);
        }
      } catch (e) {
        continue;
      }
    }

    if (npubsToFetch.isEmpty) return;

    try {
      final cachedResults = await _userRepository.getUserProfiles(npubsToFetch,
          priority: FetchPriority.urgent);

      final updatedMentionUsers =
          Map<String, Map<String, dynamic>>.from(mentionUsers);
      bool hasUpdates = false;

      for (final entry in cachedResults.entries) {
        final npub = entry.key;
        final result = entry.value;

        final pubkeyHex = pubkeyHexToNpubMap.entries
            .firstWhere((e) => e.value == npub, orElse: () => MapEntry('', ''))
            .key;

        if (pubkeyHex.isEmpty) continue;

        result.fold(
          (user) {
            final existingUser = updatedMentionUsers[pubkeyHex];
            final existingName = existingUser?['name'] as String? ?? '';
            final existingImage =
                existingUser?['profileImage'] as String? ?? '';
            if (!updatedMentionUsers.containsKey(pubkeyHex) ||
                existingName == pubkeyHex.substring(0, 8) ||
                existingImage.isEmpty) {
              updatedMentionUsers[pubkeyHex] = user;
              hasUpdates = true;
            }
          },
          (_) {
            // Silently handle error - user fetch failure is acceptable
          },
        );
      }

      if (hasUpdates) {
        emit(NoteContentLoaded(mentionUsers: updatedMentionUsers));
      }

      final missingNpubs = cachedResults.entries
          .where((e) => e.value.isError)
          .map((e) => e.key)
          .toList();

      if (missingNpubs.isNotEmpty) {
        final results = await _userRepository.getUserProfiles(missingNpubs,
            priority: FetchPriority.normal);

        final finalMentionUsers =
            Map<String, Map<String, dynamic>>.from(updatedMentionUsers);
        bool finalHasUpdates = false;

        for (final entry in results.entries) {
          final npub = entry.key;
          final result = entry.value;

          final pubkeyHex = pubkeyHexToNpubMap.entries
              .firstWhere((e) => e.value == npub,
                  orElse: () => MapEntry('', ''))
              .key;

          if (pubkeyHex.isEmpty) continue;

          result.fold(
            (user) {
              final existingUser = finalMentionUsers[pubkeyHex];
              final existingName = existingUser?['name'] as String? ?? '';
              final existingImage =
                  existingUser?['profileImage'] as String? ?? '';
              if (!finalMentionUsers.containsKey(pubkeyHex) ||
                  existingName == pubkeyHex.substring(0, 8) ||
                  existingImage.isEmpty) {
                finalMentionUsers[pubkeyHex] = user;
                finalHasUpdates = true;
              }
            },
            (_) {
              if (!finalMentionUsers.containsKey(pubkeyHex)) {
                finalMentionUsers[pubkeyHex] =
                    _createPlaceholderUser(pubkeyHex);
                finalHasUpdates = true;
              }
            },
          );
        }

        if (finalHasUpdates) {
          emit(NoteContentLoaded(mentionUsers: finalMentionUsers));
        }
      }
    } catch (e) {
      // Silently handle error - user fetch failure is acceptable
    }
  }

  Future<String?> getCurrentUserNpub() async {
    final result = await _authRepository.getCurrentUserNpub();
    return result.fold((npub) => npub, (error) => null);
  }
}
