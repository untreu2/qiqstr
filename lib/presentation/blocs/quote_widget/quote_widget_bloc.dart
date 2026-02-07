import 'dart:async';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/feed_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/services/isar_database_service.dart';
import '../../../utils/string_optimizer.dart';
import '../../../data/services/rust_nostr_bridge.dart';
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
  final IsarDatabaseService _db;
  final String bech32;

  StreamSubscription? _profileSubscription;
  String? _authorPubkey;

  QuoteWidgetBloc({
    required FeedRepository feedRepository,
    required ProfileRepository profileRepository,
    required this.bech32,
    IsarDatabaseService? db,
  })  : _feedRepository = feedRepository,
        _profileRepository = profileRepository,
        _db = db ?? IsarDatabaseService.instance,
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
    _authorPubkey = pubkey;
    _profileSubscription?.cancel();
    _profileSubscription = _db.watchProfile(pubkey).listen((event) {
      if (isClosed || event == null) return;

      final profile = _parseProfileContent(event.content);
      if (profile == null) return;

      final user = {
        'pubkeyHex': pubkey,
        'npub': pubkey,
        'name': profile['name'] ?? '',
        'profileImage': profile['profileImage'] ?? '',
        'picture': profile['profileImage'] ?? '',
        'nip05': profile['nip05'] ?? '',
      };

      add(_InternalProfileUpdate(user));
    });
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
      final feedNote = await _feedRepository.getNote(eventId);

      if (feedNote == null) {
        emit(const QuoteWidgetError());
        return;
      }

      final note = feedNote.toMap();
      note['pubkey'] = feedNote.pubkey;

      final noteTimestamp = feedNote.createdAt;
      final formattedTime = noteTimestamp > 0 ? _formatTime(noteTimestamp) : '';
      final noteContent = feedNote.content;
      final parsedContent = stringOptimizer.parseContentOptimized(noteContent);
      final shouldTruncate = _checkTruncation(parsedContent);

      final noteAuthor = feedNote.pubkey;
      Map<String, dynamic>? user;
      if (noteAuthor.isNotEmpty) {
        final profile = await _profileRepository.getProfile(noteAuthor);
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

        // Start watching profile for updates
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
