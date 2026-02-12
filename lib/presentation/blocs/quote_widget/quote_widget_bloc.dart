import 'dart:async';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/sync/sync_service.dart';
import '../../../data/services/rust_database_service.dart';
import '../../../utils/string_optimizer.dart';
import '../../../data/services/rust_nostr_bridge.dart';
import '../../../src/rust/api/relay.dart' as rust_relay;
import 'quote_widget_event.dart';
import 'quote_widget_state.dart';

class _InternalProfileUpdate extends QuoteWidgetEvent {
  final Map<String, dynamic> user;
  const _InternalProfileUpdate(this.user);

  @override
  List<Object?> get props => [user];
}

class QuoteWidgetBloc extends Bloc<QuoteWidgetEvent, QuoteWidgetState> {
  final FeedRepository _feedRepository;
  final ProfileRepository _profileRepository;
  final SyncService _syncService;
  final RustDatabaseService _db;
  final String bech32;

  StreamSubscription? _profileSubscription;

  QuoteWidgetBloc({
    required FeedRepository feedRepository,
    required ProfileRepository profileRepository,
    required SyncService syncService,
    required this.bech32,
    RustDatabaseService? db,
  })  : _feedRepository = feedRepository,
        _profileRepository = profileRepository,
        _syncService = syncService,
        _db = db ?? RustDatabaseService.instance,
        super(const QuoteWidgetInitial()) {
    on<QuoteWidgetLoadRequested>(_onQuoteWidgetLoadRequested);
    on<_InternalProfileUpdate>(_onInternalProfileUpdate);
  }

  void _onInternalProfileUpdate(
    _InternalProfileUpdate event,
    Emitter<QuoteWidgetState> emit,
  ) {
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

  void _watchProfile(String pubkey) {
    _profileSubscription?.cancel();
    _profileSubscription = _db.watchProfile(pubkey).listen((profileData) {
      if (isClosed || profileData == null) return;

      final user = {
        'pubkeyHex': pubkey,
        'npub': pubkey,
        'name': profileData['name'] ?? '',
        'profileImage': profileData['picture'] ?? '',
        'picture': profileData['picture'] ?? '',
        'nip05': profileData['nip05'] ?? '',
      };

      add(_InternalProfileUpdate(user));
    });
  }


  @override
  Future<void> close() {
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
    emit(const QuoteWidgetLoading());

    final eventId = _extractEventId(event.bech32);
    if (eventId == null) {
      emit(const QuoteWidgetError());
      return;
    }

    try {
      var feedNote = await _feedRepository.getNote(eventId);
      Map<String, dynamic>? eventData;

      if (feedNote == null) {
        final eventJson = await rust_relay.fetchEventById(
          eventId: eventId,
          timeoutSecs: 5,
        );
        
        if (eventJson != null) {
          eventData = jsonDecode(eventJson) as Map<String, dynamic>;
          await _db.saveEvents([eventData]);
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
        var profile = await _profileRepository.getProfile(noteAuthor);

        if (profile == null ||
            (profile.name ?? '').isEmpty &&
                (profile.picture ?? '').isEmpty) {
          await _syncService.syncProfile(noteAuthor);
          if (isClosed) return;
          profile = await _profileRepository.getProfile(noteAuthor);
        }

        if (profile != null) {
          user = {
            'pubkeyHex': noteAuthor,
            'npub': noteAuthor,
            'name': profile.name ?? profile.displayName ?? '',
            'profileImage': profile.picture ?? '',
            'picture': profile.picture ?? '',
            'nip05': profile.nip05 ?? '',
          };
        }

        _watchProfile(noteAuthor);
      }

      emit(QuoteWidgetLoaded(
        note: note,
        user: user,
        formattedTime: formattedTime,
        parsedContent: parsedContent,
        shouldTruncate: shouldTruncate,
      ));
    } catch (e) {
      emit(const QuoteWidgetError());
    }
  }
}
