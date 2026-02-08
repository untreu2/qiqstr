import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/rust_nostr_bridge.dart';
import 'note_content_event.dart';
import 'note_content_state.dart';

class NoteContentBloc extends Bloc<NoteContentEvent, NoteContentState> {
  final ProfileRepository _profileRepository;
  final AuthService _authService;
  final SyncService? _syncService;

  NoteContentBloc({
    required ProfileRepository profileRepository,
    required AuthService authService,
    SyncService? syncService,
  })  : _profileRepository = profileRepository,
        _authService = authService,
        _syncService = syncService,
        super(const NoteContentInitial()) {
    on<NoteContentInitialized>(_onNoteContentInitialized);
    on<_MentionProfileUpdated>(_onMentionProfileUpdated);
  }

  String? extractPubkey(String bech32) {
    try {
      if (bech32.startsWith('npub1')) {
        return decodeBasicBech32(bech32, 'npub');
      } else if (bech32.startsWith('nprofile1')) {
        final result = decodeTlvBech32Full(bech32);
        return result['pubkey'] as String?;
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  static Map<String, dynamic> _createPlaceholderUser(String pubkey) {
    return {
      'pubkeyHex': pubkey,
      'pubkey': pubkey,
      'npub': pubkey,
      'name': pubkey.length > 8 ? pubkey.substring(0, 8) : pubkey,
      'about': '',
      'profileImage': '',
      'picture': '',
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

    final pubkeysToFetch = <String>[];
    final initialProfiles = event.initialProfiles ?? {};

    for (final mentionId in mentionIds) {
      final actualPubkey = extractPubkey(mentionId);
      if (actualPubkey == null) continue;
      pubkeysToFetch.add(actualPubkey);

      final existingProfile = initialProfiles[actualPubkey];
      if (existingProfile != null &&
          (existingProfile['name'] as String?)?.isNotEmpty == true) {
        mentionUsers[actualPubkey] = existingProfile;
      } else {
        mentionUsers[actualPubkey] = _createPlaceholderUser(actualPubkey);
      }
    }

    emit(NoteContentLoaded(mentionUsers: mentionUsers));

    if (pubkeysToFetch.isEmpty) return;

    final pubkeysNeedingFetch = pubkeysToFetch.where((pubkey) {
      final profile = mentionUsers[pubkey];
      if (profile == null) return true;
      final name = profile['name'] as String?;
      return name == null || name.isEmpty || name == pubkey.substring(0, 8);
    }).toList();

    if (pubkeysNeedingFetch.isEmpty) return;

    try {
      final profiles =
          await _profileRepository.getProfiles(pubkeysNeedingFetch);

      final updatedMentionUsers =
          Map<String, Map<String, dynamic>>.from(mentionUsers);
      final stillMissing = <String>[];

      for (final pubkey in pubkeysNeedingFetch) {
        final profile = profiles[pubkey];
        if (profile != null &&
            (profile.name ?? '').isNotEmpty &&
            (profile.name ?? '') !=
                pubkey.substring(0, pubkey.length > 8 ? 8 : pubkey.length)) {
          updatedMentionUsers[pubkey] = _profileToMap(pubkey, profile);
        } else {
          stillMissing.add(pubkey);
        }
      }

      emit(NoteContentLoaded(mentionUsers: updatedMentionUsers));

      if (stillMissing.isNotEmpty) {
        _syncAndApplyProfiles(stillMissing, updatedMentionUsers);
      }
    } catch (e) {
      _syncAndApplyProfiles(pubkeysNeedingFetch, mentionUsers);
    }
  }

  Map<String, dynamic> _profileToMap(String pubkey, dynamic profile) {
    return {
      'pubkeyHex': pubkey,
      'pubkey': pubkey,
      'npub': _authService.hexToNpub(pubkey) ?? pubkey,
      'name': profile.name ?? profile.displayName ?? '',
      'about': profile.about ?? '',
      'profileImage': profile.picture ?? '',
      'picture': profile.picture ?? '',
      'banner': profile.banner ?? '',
      'website': profile.website ?? '',
      'nip05': profile.nip05 ?? '',
      'lud16': profile.lud16 ?? '',
    };
  }

  void _syncAndApplyProfiles(List<String> pubkeys,
      Map<String, Map<String, dynamic>> currentMentionUsers) {
    final syncService = _syncService;
    if (syncService == null || pubkeys.isEmpty) return;

    Future.microtask(() async {
      if (isClosed) return;
      try {
        await syncService.syncProfiles(pubkeys);
        if (isClosed) return;

        final profiles = await _profileRepository.getProfiles(pubkeys);
        if (isClosed) return;

        for (final entry in profiles.entries) {
          final profile = entry.value;
          if ((profile.name ?? '').isNotEmpty) {
            add(_MentionProfileUpdated(
                entry.key, _profileToMap(entry.key, profile)));
          }
        }
      } catch (_) {}
    });
  }

  void _onMentionProfileUpdated(
    _MentionProfileUpdated event,
    Emitter<NoteContentState> emit,
  ) {
    if (state is! NoteContentLoaded) return;
    final currentState = state as NoteContentLoaded;

    final updatedMentionUsers =
        Map<String, Map<String, dynamic>>.from(currentState.mentionUsers);
    updatedMentionUsers[event.pubkey] = event.profileData;

    emit(NoteContentLoaded(mentionUsers: updatedMentionUsers));
  }

  Future<String?> getCurrentUserHex() async {
    final result = await _authService.getCurrentUserPublicKeyHex();
    return result.data;
  }
}

class _MentionProfileUpdated extends NoteContentEvent {
  final String pubkey;
  final Map<String, dynamic> profileData;

  const _MentionProfileUpdated(this.pubkey, this.profileData);

  @override
  List<Object?> get props => [pubkey, profileData];
}
