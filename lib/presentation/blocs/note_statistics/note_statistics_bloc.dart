import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/interaction_service.dart';
import '../../../data/services/nostr_service.dart';
import '../../../data/services/relay_service.dart';
import 'note_statistics_event.dart';
import 'note_statistics_state.dart';

class NoteStatisticsBloc
    extends Bloc<NoteStatisticsEvent, NoteStatisticsState> {
  final InteractionRepository _interactionRepository;
  final ProfileRepository _profileRepository;
  final AuthService _authService;
  final InteractionService _interactionService;
  final String noteId;

  NoteStatisticsBloc({
    required InteractionRepository interactionRepository,
    required ProfileRepository profileRepository,
    required AuthService authService,
    required this.noteId,
  })  : _interactionRepository = interactionRepository,
        _profileRepository = profileRepository,
        _authService = authService,
        _interactionService = InteractionService.instance,
        super(const NoteStatisticsInitial()) {
    on<NoteStatisticsInitialized>(_onNoteStatisticsInitialized);
    on<NoteStatisticsRefreshed>(_onNoteStatisticsRefreshed);
  }

  Future<void> _onNoteStatisticsInitialized(
    NoteStatisticsInitialized event,
    Emitter<NoteStatisticsState> emit,
  ) async {
    emit(const NoteStatisticsLoading());

    if (kDebugMode) {
      debugPrint(
          '[NoteStatisticsBloc] Loading interactions for noteId: $noteId');
    }

    var interactions =
        await _interactionRepository.getDetailedInteractions(noteId);

    if (kDebugMode) {
      debugPrint(
          '[NoteStatisticsBloc] Cache returned ${interactions.length} interactions');
    }

    if (interactions.isEmpty) {
      if (kDebugMode) {
        debugPrint('[NoteStatisticsBloc] Cache empty, fetching from relays...');
      }
      await _interactionService.refreshInteractions(noteId);
      await Future.delayed(const Duration(milliseconds: 1000));
      interactions =
          await _interactionRepository.getDetailedInteractions(noteId);
      if (kDebugMode) {
        debugPrint(
            '[NoteStatisticsBloc] After refresh: ${interactions.length} interactions');
      }
    }

    await _buildInteractionsList(emit, interactions);
  }

  Future<void> _onNoteStatisticsRefreshed(
    NoteStatisticsRefreshed event,
    Emitter<NoteStatisticsState> emit,
  ) async {
    await _interactionService.refreshInteractions(noteId);
    await Future.delayed(const Duration(milliseconds: 300));
    final interactions =
        await _interactionRepository.getDetailedInteractions(noteId);
    await _buildInteractionsList(emit, interactions);
  }

  Future<void> _buildInteractionsList(
    Emitter<NoteStatisticsState> emit,
    List<Map<String, dynamic>> detailedInteractions,
  ) async {
    try {
      final allInteractions = <Map<String, dynamic>>[];
      final uniquePubkeys = <String>{};

      for (final interaction in detailedInteractions) {
        final pubkey = interaction['pubkey'] as String? ?? '';
        if (pubkey.isEmpty) continue;

        uniquePubkeys.add(pubkey);

        final npub = _authService.hexToNpub(pubkey) ?? pubkey;

        allInteractions.add({
          'type': interaction['type'],
          'npub': npub,
          'pubkey': pubkey,
          'content': interaction['content'] ?? '',
          'zapAmount': interaction['zapAmount'],
          'createdAt': interaction['createdAt'],
        });
      }

      final users = <String, Map<String, dynamic>>{};

      if (uniquePubkeys.isNotEmpty) {
        final pubkeysList = uniquePubkeys.toList();

        var profiles = await _profileRepository.getProfiles(pubkeysList);

        final missingPubkeys =
            pubkeysList.where((pk) => !profiles.containsKey(pk)).toList();

        if (missingPubkeys.isNotEmpty) {
          try {
            final filter = NostrService.createProfileFilter(
              authors: missingPubkeys,
              limit: missingPubkeys.length,
            );
            final fetchedProfiles =
                await RustRelayService.instance.fetchEvents(filter);

            if (fetchedProfiles.isNotEmpty) {
              final profilesToSave = <String, Map<String, String>>{};

              for (final event in fetchedProfiles) {
                final pubkey = event['pubkey'] as String?;
                if (pubkey == null) continue;

                final contentStr = event['content'] as String? ?? '{}';
                final content =
                    jsonDecode(contentStr) as Map<String, dynamic>? ?? {};

                profilesToSave[pubkey] = {
                  'name': content['name']?.toString() ?? '',
                  'display_name': content['display_name']?.toString() ?? '',
                  'about': content['about']?.toString() ?? '',
                  'profileImage': content['picture']?.toString() ?? '',
                  'banner': content['banner']?.toString() ?? '',
                  'nip05': content['nip05']?.toString() ?? '',
                  'lud16': content['lud16']?.toString() ?? '',
                  'website': content['website']?.toString() ?? '',
                };
              }

              if (profilesToSave.isNotEmpty) {
                await _profileRepository.saveProfiles(profilesToSave);
                profiles = await _profileRepository.getProfiles(pubkeysList);
              }
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint(
                  '[NoteStatisticsBloc] Error fetching missing profiles: $e');
            }
          }
        }

        for (final entry in profiles.entries) {
          final profile = entry.value;
          final userMap = {
            'pubkeyHex': entry.key,
            'npub': _authService.hexToNpub(entry.key) ?? entry.key,
            'name': profile.name ?? profile.displayName ?? '',
            'profileImage': profile.picture ?? '',
            'nip05': profile.nip05 ?? '',
            'nip05Verified': false,
          };
          users[entry.key] = userMap;
        }
      }

      emit(NoteStatisticsLoaded(interactions: allInteractions, users: users));
    } catch (e) {
      emit(NoteStatisticsLoaded(interactions: const [], users: const {}));
    }
  }
}
