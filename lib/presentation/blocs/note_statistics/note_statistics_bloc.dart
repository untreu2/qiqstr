import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/interaction_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/sync/sync_service.dart';
import 'note_statistics_event.dart';
import 'note_statistics_state.dart';

class NoteStatisticsBloc
    extends Bloc<NoteStatisticsEvent, NoteStatisticsState> {
  final InteractionRepository _interactionRepository;
  final ProfileRepository _profileRepository;
  final AuthService _authService;
  final SyncService _syncService;
  final String noteId;

  NoteStatisticsBloc({
    required InteractionRepository interactionRepository,
    required ProfileRepository profileRepository,
    required AuthService authService,
    required SyncService syncService,
    required this.noteId,
  })  : _interactionRepository = interactionRepository,
        _profileRepository = profileRepository,
        _authService = authService,
        _syncService = syncService,
        super(const NoteStatisticsInitial()) {
    on<NoteStatisticsInitialized>(_onNoteStatisticsInitialized);
    on<NoteStatisticsRefreshed>(_onNoteStatisticsRefreshed);
  }

  Future<void> _onNoteStatisticsInitialized(
    NoteStatisticsInitialized event,
    Emitter<NoteStatisticsState> emit,
  ) async {
    emit(const NoteStatisticsLoading());
    await _syncService.syncInteractionsForNote(noteId);
    final interactions = await _interactionRepository.getDetails(noteId);
    await _buildInteractionsList(emit, interactions);
  }

  Future<void> _onNoteStatisticsRefreshed(
    NoteStatisticsRefreshed event,
    Emitter<NoteStatisticsState> emit,
  ) async {
    await _syncService.syncInteractionsForNote(noteId);
    final interactions = await _interactionRepository.getDetails(noteId);
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
        allInteractions.add({
          'type': interaction['type'],
          'npub': _authService.hexToNpub(pubkey) ?? pubkey,
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
          await _syncService.syncProfiles(missingPubkeys);
          profiles = await _profileRepository.getProfiles(pubkeysList);
        }

        for (final entry in profiles.entries) {
          final profile = entry.value;
          users[entry.key] = {
            'pubkey': entry.key,
            'npub': _authService.hexToNpub(entry.key) ?? entry.key,
            'name': profile.name ?? profile.displayName ?? '',
            'picture': profile.picture ?? '',
            'nip05': profile.nip05 ?? '',
            'nip05Verified': false,
          };
        }
      }

      emit(NoteStatisticsLoaded(interactions: allInteractions, users: users));
    } catch (e) {
      emit(NoteStatisticsLoaded(interactions: const [], users: const {}));
    }
  }
}
