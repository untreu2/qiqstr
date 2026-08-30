import 'dart:async';
import 'dart:convert';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../utils/string_optimizer.dart';
import '../../../data/services/rust_nostr_bridge.dart';
import '../../../src/rust/api/relay.dart' as rust_relay;
import 'quote_widget_event.dart';
import 'quote_widget_state.dart';

class _InternalProfileUpdate extends QuoteWidgetEvent {
  final Map<String, dynamic> user;
  final int generation;
  const _InternalProfileUpdate(this.user, this.generation);

  @override
  List<Object?> get props => [user, generation];
}

class QuoteWidgetBloc extends Bloc<QuoteWidgetEvent, QuoteWidgetState> {
  final FeedRepository _feedRepository;
  final ProfileRepository _profileRepository;
  final SyncService _syncService;
  final String bech32;

  StreamSubscription? _profileSubscription;
  int _generation = 0;

  QuoteWidgetBloc({
    required FeedRepository feedRepository,
    required ProfileRepository profileRepository,
    required SyncService syncService,
    required this.bech32,
  })  : _feedRepository = feedRepository,
        _profileRepository = profileRepository,
        _syncService = syncService,
        super(const QuoteWidgetInitial()) {
    on<QuoteWidgetLoadRequested>(
      _onQuoteWidgetLoadRequested,
      transformer: restartable(),
    );
    on<_InternalProfileUpdate>(_onInternalProfileUpdate);
  }

  void _onInternalProfileUpdate(
    _InternalProfileUpdate event,
    Emitter<QuoteWidgetState> emit,
  ) {
    if (event.generation != _generation) return;
    final currentState = state;
    if (currentState is QuoteWidgetLoaded) {
      emit(QuoteWidgetLoaded(
        note: currentState.note,
        user: event.user,
        formattedTime: currentState.formattedTime,
        parsedContent: currentState.parsedContent,
        shouldTruncate: currentState.shouldTruncate,
      ));
    }
  }

  void _watchProfile(String pubkey, int generation) {
    _profileSubscription?.cancel();
    _profileSubscription =
        _profileRepository.watchProfile(pubkey).listen((profile) {
      if (isClosed || generation != _generation || profile == null) return;

      final user = {
        'pubkey': pubkey,
        'npub': pubkey,
        'name': profile.name ?? '',
        'picture': profile.picture ?? '',
        'nip05': profile.nip05 ?? '',
      };

      add(_InternalProfileUpdate(user, generation));
    });
  }

  @override
  Future<void> close() {
    _generation++;
    _profileSubscription?.cancel();
    return super.close();
  }

  String? _extractEventId(String bech32) {
    try {
      if (bech32.startsWith('note1')) {
        return decodeBasicBech32(bech32, 'note');
      } else if (bech32.startsWith('nevent1')) {
        final result = decodeTlvBech32Full(bech32);
        return result['id'] as String?;
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  String _formatTime(int timestamp) {
    try {
      final noteTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
      final now = DateTime.now();
      final difference = now.difference(noteTime);

      if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d';
      } else {
        return '${(difference.inDays / 7).floor()}w';
      }
    } catch (e) {
      return '';
    }
  }

  bool _checkTruncation(Map<String, dynamic> parsed) {
    try {
      final textParts = parsed['textParts'] as List? ?? [];
      int totalLength = 0;
      for (final part in textParts) {
        if (part is Map && part['type'] == 'text') {
          totalLength += (part['text'] as String? ?? '').length;
        }
      }
      return totalLength > 140;
    } catch (e) {
      return false;
    }
  }

  Future<void> _onQuoteWidgetLoadRequested(
    QuoteWidgetLoadRequested event,
    Emitter<QuoteWidgetState> emit,
  ) async {
    final generation = ++_generation;
    await _profileSubscription?.cancel();
    _profileSubscription = null;
    if (emit.isDone) return;
    emit(const QuoteWidgetLoading());

    final eventId = _extractEventId(event.bech32);
    if (eventId == null) {
      emit(const QuoteWidgetError());
      return;
    }

    try {
      var feedNote = await _feedRepository.getNote(eventId);
      if (emit.isDone) return;
      Map<String, dynamic>? eventData;

      if (feedNote == null) {
        final eventJson = await rust_relay.fetchEventById(
          eventId: eventId,
          timeoutSecs: 5,
        );
        if (emit.isDone) return;

        if (eventJson != null) {
          eventData = jsonDecode(eventJson) as Map<String, dynamic>;
          await _feedRepository.save([eventData]);
          if (emit.isDone) return;
        } else {
          emit(const QuoteWidgetError());
          return;
        }
      }

      final String noteContent;
      final int noteTimestamp;
      final String noteAuthor;
      final Map<String, dynamic> note;

      if (feedNote != null) {
        note = feedNote.toMap();
        note['pubkey'] = feedNote.pubkey;
        noteContent = feedNote.content;
        noteTimestamp = feedNote.createdAt;
        noteAuthor = feedNote.pubkey;
      } else if (eventData != null) {
        noteContent = eventData['content'] as String? ?? '';
        noteTimestamp = eventData['created_at'] as int? ?? 0;
        noteAuthor = eventData['pubkey'] as String? ?? '';
        note = {
          'id': eventData['id'] ?? eventId,
          'content': noteContent,
          'created_at': noteTimestamp,
          'pubkey': noteAuthor,
          'kind': eventData['kind'] ?? 1,
          'tags': eventData['tags'] ?? [],
        };
      } else {
        emit(const QuoteWidgetError());
        return;
      }

      final formattedTime = noteTimestamp > 0 ? _formatTime(noteTimestamp) : '';
      final parsedContent = stringOptimizer.parseContentOptimized(noteContent);
      final shouldTruncate = _checkTruncation(parsedContent);

      Map<String, dynamic>? user;
      if (noteAuthor.isNotEmpty) {
        final hydratedName = feedNote?.authorName ?? '';
        final hydratedImage = feedNote?.authorImage ?? '';
        final hydratedNip05 = feedNote?.authorNip05 ?? '';

        if (hydratedName.isNotEmpty || hydratedImage.isNotEmpty) {
          user = {
            'pubkey': noteAuthor,
            'npub': noteAuthor,
            'name': hydratedName,
            'picture': hydratedImage,
            'nip05': hydratedNip05,
          };
          _watchProfile(noteAuthor, generation);
        } else {
          var profile = await _profileRepository.getProfile(noteAuthor);
          if (emit.isDone || generation != _generation) return;

          if (profile == null ||
              (profile.name ?? '').isEmpty && (profile.picture ?? '').isEmpty) {
            await _syncService.syncProfile(noteAuthor);
            if (isClosed || emit.isDone || generation != _generation) return;
            profile = await _profileRepository.getProfile(noteAuthor);
            if (emit.isDone || generation != _generation) return;
          }

          if (profile != null) {
            user = {
              'pubkey': noteAuthor,
              'npub': noteAuthor,
              'name': profile.name ?? profile.displayName ?? '',
              'picture': profile.picture ?? '',
              'nip05': profile.nip05 ?? '',
            };
          }

          _watchProfile(noteAuthor, generation);
        }
      }

      if (emit.isDone || generation != _generation) return;
      emit(QuoteWidgetLoaded(
        note: note,
        user: user,
        formattedTime: formattedTime,
        parsedContent: parsedContent,
        shouldTruncate: shouldTruncate,
      ));
    } catch (e) {
      if (!emit.isDone && generation == _generation) {
        emit(const QuoteWidgetError());
      }
    }
  }
}
