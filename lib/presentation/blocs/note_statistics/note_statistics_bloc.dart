import 'dart:async';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/data_service.dart';
import 'note_statistics_event.dart';
import 'note_statistics_state.dart';

class NoteStatisticsBloc
    extends Bloc<NoteStatisticsEvent, NoteStatisticsState> {
  final UserRepository _userRepository;
  final DataService _dataService;
  final String noteId;

  StreamSubscription<List<Map<String, dynamic>>>? _notesSubscription;
  String? _lastNoteId;

  NoteStatisticsBloc({
    required UserRepository userRepository,
    required DataService dataService,
    required this.noteId,
  })  : _userRepository = userRepository,
        _dataService = dataService,
        super(const NoteStatisticsInitial()) {
    on<NoteStatisticsInitialized>(_onNoteStatisticsInitialized);
    on<NoteStatisticsRefreshed>(_onNoteStatisticsRefreshed);

    _notesSubscription = _dataService.notesStream.listen((notes) {
      final hasRelevantNote = notes.any((n) {
        final id = n['id'] as String? ?? '';
        return id.isNotEmpty && id == noteId;
      });
      if (hasRelevantNote && _lastNoteId != noteId) {
        _lastNoteId = null;
        add(const NoteStatisticsRefreshed());
      }
    });
  }

  Future<void> _onNoteStatisticsInitialized(
    NoteStatisticsInitialized event,
    Emitter<NoteStatisticsState> emit,
  ) async {
    await _buildInteractionsList(emit);
  }

  Future<void> _onNoteStatisticsRefreshed(
    NoteStatisticsRefreshed event,
    Emitter<NoteStatisticsState> emit,
  ) async {
    await _buildInteractionsList(emit);
  }

  Future<void> _buildInteractionsList(Emitter<NoteStatisticsState> emit) async {
    if (_lastNoteId == noteId && state is NoteStatisticsLoaded) {
      return;
    }

    String targetNoteId = noteId;

    final cachedNotes = _dataService.cachedNotes;
    final note = cachedNotes.firstWhere(
      (n) => (n['id'] as String? ?? '') == noteId,
      orElse: () => <String, dynamic>{},
    );

    final isRepost = note['isRepost'] as bool? ?? false;
    if (isRepost) {
      final rawWs = note['rawWs'] as String? ?? '';
      if (rawWs.isNotEmpty) {
        try {
          final eventData = jsonDecode(rawWs) as Map<String, dynamic>;
          final tags = eventData['tags'] as List<dynamic>? ?? [];
          for (final tag in tags) {
            if (tag is List &&
                tag.isNotEmpty &&
                tag[0] == 'e' &&
                tag.length >= 2) {
              final originalEventId = tag[1] as String?;
              if (originalEventId != null && originalEventId.isNotEmpty) {
                targetNoteId = originalEventId;
                break;
              }
            }
          }
        } catch (e) {
          final rootId = note['rootId'] as String?;
          if (rootId != null && rootId.isNotEmpty) {
            targetNoteId = rootId;
          }
        }
      } else {
        final rootId = note['rootId'] as String?;
        if (rootId != null && rootId.isNotEmpty) {
          targetNoteId = rootId;
        }
      }
    }

    final reactions = _dataService.getReactionsForNote(targetNoteId);
    final reposts = _dataService.getRepostsForNote(targetNoteId);
    final zaps = _dataService.getZapsForNote(targetNoteId);

    final allInteractions = <Map<String, dynamic>>[];
    final seenReactions = <String>{};

    for (final reaction in reactions) {
      final authorValue = reaction['author'];
      final author =
          authorValue is String ? authorValue : (authorValue?.toString() ?? '');
      final contentValue = reaction['content'];
      final content = contentValue is String
          ? contentValue
          : (contentValue?.toString() ?? '');
      final reactionKey = '$author:$content';
      if (!seenReactions.contains(reactionKey)) {
        seenReactions.add(reactionKey);
        final timestampValue = reaction['timestamp'];
        final timestamp =
            timestampValue is DateTime ? timestampValue : DateTime.now();
        allInteractions.add({
          'type': 'reaction',
          'data': reaction,
          'timestamp': timestamp,
          'npub': author,
          'content': content,
        });
      }
    }

    final seenReposts = <String>{};
    for (final repost in reposts) {
      final authorValue = repost['author'];
      final author =
          authorValue is String ? authorValue : (authorValue?.toString() ?? '');
      if (author.isNotEmpty && !seenReposts.contains(author)) {
        seenReposts.add(author);
        final timestampValue = repost['timestamp'];
        final timestamp =
            timestampValue is DateTime ? timestampValue : DateTime.now();
        allInteractions.add({
          'type': 'repost',
          'data': repost,
          'timestamp': timestamp,
          'npub': author,
          'content': 'Reposted',
        });
      }
    }

    final seenZaps = <String>{};
    for (final zap in zaps) {
      final senderValue = zap['sender'];
      final sender =
          senderValue is String ? senderValue : (senderValue?.toString() ?? '');
      if (sender.isNotEmpty && !seenZaps.contains(sender)) {
        seenZaps.add(sender);
        final timestampValue = zap['timestamp'];
        final timestamp =
            timestampValue is DateTime ? timestampValue : DateTime.now();
        final commentValue = zap['comment'];
        final comment = commentValue is String
            ? commentValue
            : (commentValue?.toString() ?? '');
        final amountValue = zap['amount'];
        final amount = amountValue is int
            ? amountValue
            : (amountValue is num ? amountValue.toInt() : 0);
        allInteractions.add({
          'type': 'zap',
          'data': zap,
          'timestamp': timestamp,
          'npub': sender,
          'content': comment,
          'zapAmount': amount,
        });
      }
    }

    allInteractions.sort((a, b) {
      final aTimestampValue = a['timestamp'];
      final bTimestampValue = b['timestamp'];
      final aTimestamp =
          aTimestampValue is DateTime ? aTimestampValue : DateTime.now();
      final bTimestamp =
          bTimestampValue is DateTime ? bTimestampValue : DateTime.now();
      return bTimestamp.compareTo(aTimestamp);
    });

    final uniqueNpubs = <String>{};
    for (final interaction in allInteractions) {
      final npubValue = interaction['npub'];
      final npub =
          npubValue is String ? npubValue : (npubValue?.toString() ?? '');
      if (npub.isNotEmpty) {
        uniqueNpubs.add(npub);
      }
    }

    final users = <String, Map<String, dynamic>>{};
    final missingNpubs = <String>[];

    for (final npub in uniqueNpubs) {
      final cachedUser = await _userRepository.getCachedUser(npub);
      if (cachedUser != null) {
        users[npub] = cachedUser;
      } else {
        users[npub] = {
          'npub': npub,
          'name': npub.length > 8 ? npub.substring(0, 8) : npub,
          'profileImage': '',
          'nip05': '',
          'nip05Verified': false,
        };
        missingNpubs.add(npub);
      }
    }

    _lastNoteId = noteId;
    emit(NoteStatisticsLoaded(interactions: allInteractions, users: users));

    if (missingNpubs.isNotEmpty) {
      final updatedUsers = Map<String, Map<String, dynamic>>.from(users);
      for (final npub in missingNpubs) {
        try {
          final result = await _userRepository.getUserProfile(npub);
          result.fold(
            (user) {
              final userValue = user;
              updatedUsers[npub] = userValue;
            },
            (error) {},
          );
        } catch (e) {}
      }

      if (state is NoteStatisticsLoaded) {
        final currentState = state as NoteStatisticsLoaded;
        emit(currentState.copyWith(users: updatedUsers));
      }
    }
  }

  Future<Map<String, dynamic>> getUser(String npub) async {
    try {
      final result = await _userRepository.getUserProfile(npub);
      return result.fold(
        (user) {
          final userValue = user;
          return {
            'user': userValue,
            'success': true,
          };
        },
        (error) => {
          'user': null,
          'error': error,
          'success': false,
        },
      );
    } catch (e) {
      return {
        'user': null,
        'error': e.toString(),
        'success': false,
      };
    }
  }

  @override
  Future<void> close() {
    _notesSubscription?.cancel();
    return super.close();
  }
}
