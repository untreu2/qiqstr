import 'dart:async';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/isar_database_service.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/rust_nostr_bridge.dart';
import 'note_content_event.dart';
import 'note_content_state.dart';

class NoteContentBloc extends Bloc<NoteContentEvent, NoteContentState> {
  final ProfileRepository _profileRepository;
  final AuthService _authService;
  final SyncService? _syncService;
  final IsarDatabaseService _db;

  final Map<String, StreamSubscription> _profileSubscriptions = {};

  NoteContentBloc({
    required ProfileRepository profileRepository,
    required AuthService authService,
    SyncService? syncService,
    IsarDatabaseService? db,
  })  : _profileRepository = profileRepository,
        _authService = authService,
        _syncService = syncService,
        _db = db ?? IsarDatabaseService.instance,
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

      // Use initial profile if available, otherwise placeholder
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

    // Find which pubkeys still need to be fetched from DB
    final pubkeysNeedingFetch = pubkeysToFetch.where((pubkey) {
      final profile = mentionUsers[pubkey];
      if (profile == null) return true;
      final name = profile['name'] as String?;
      return name == null || name.isEmpty || name == pubkey.substring(0, 8);
    }).toList();

    if (pubkeysNeedingFetch.isEmpty) {
      _watchProfiles(pubkeysToFetch);
      return;
    }

    try {
      final profiles =
          await _profileRepository.getProfiles(pubkeysNeedingFetch);

      final updatedMentionUsers =
          Map<String, Map<String, dynamic>>.from(mentionUsers);

      for (final entry in profiles.entries) {
        final profile = entry.value;
        updatedMentionUsers[entry.key] = {
          'pubkeyHex': entry.key,
          'pubkey': entry.key,
          'npub': _authService.hexToNpub(entry.key) ?? entry.key,
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

      emit(NoteContentLoaded(mentionUsers: updatedMentionUsers));

      _watchProfiles(pubkeysToFetch);
      _syncMissingProfiles(pubkeysNeedingFetch, profiles);
    } catch (e) {}
  }

  void _watchProfiles(List<String> pubkeys) {
    for (final pubkey in pubkeys) {
      if (_profileSubscriptions.containsKey(pubkey)) continue;

      _profileSubscriptions[pubkey] = _db.watchProfile(pubkey).listen((event) {
        if (isClosed || event == null) return;

        final content = event.content;
        if (content.isEmpty) return;

        try {
          final parsed = _parseProfileContent(content);
          if (parsed == null) return;

          add(_MentionProfileUpdated(pubkey, {
            'pubkeyHex': pubkey,
            'pubkey': pubkey,
            'npub': _authService.hexToNpub(pubkey) ?? pubkey,
            'name': parsed['name'] ?? '',
            'about': parsed['about'] ?? '',
            'profileImage': parsed['profileImage'] ?? parsed['picture'] ?? '',
            'picture': parsed['picture'] ?? '',
            'banner': parsed['banner'] ?? '',
            'website': parsed['website'] ?? '',
            'nip05': parsed['nip05'] ?? '',
            'lud16': parsed['lud16'] ?? '',
          }));
        } catch (_) {}
      });
    }
  }

  Map<String, String>? _parseProfileContent(String content) {
    if (content.isEmpty) return null;
    try {
      final parsed = jsonDecode(content) as Map<String, dynamic>;
      final result = <String, String>{};
      parsed.forEach((key, value) {
        result[key == 'picture' ? 'profileImage' : key] =
            value?.toString() ?? '';
      });
      return result;
    } catch (_) {
      return null;
    }
  }

  void _syncMissingProfiles(
      List<String> pubkeys, Map<String, dynamic> existingProfiles) {
    if (_syncService == null) return;

    final missingPubkeys = pubkeys
        .where((p) =>
            !existingProfiles.containsKey(p) ||
            (existingProfiles[p] as dynamic)?.name == null)
        .toList();

    if (missingPubkeys.isEmpty) return;

    Future.microtask(() async {
      try {
        await _syncService.syncProfiles(missingPubkeys);
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

  @override
  Future<void> close() {
    for (final sub in _profileSubscriptions.values) {
      sub.cancel();
    }
    _profileSubscriptions.clear();
    return super.close();
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
