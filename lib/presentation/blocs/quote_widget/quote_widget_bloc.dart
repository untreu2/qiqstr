import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/note_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../utils/string_optimizer.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import 'quote_widget_event.dart';
import 'quote_widget_state.dart';

class QuoteWidgetBloc extends Bloc<QuoteWidgetEvent, QuoteWidgetState> {
  final NoteRepository _noteRepository;
  final UserRepository _userRepository;
  final String bech32;

  QuoteWidgetBloc({
    required NoteRepository noteRepository,
    required UserRepository userRepository,
    required this.bech32,
  })  : _noteRepository = noteRepository,
        _userRepository = userRepository,
        super(const QuoteWidgetInitial()) {
    on<QuoteWidgetLoadRequested>(_onQuoteWidgetLoadRequested);
  }

  String? _extractEventId(String bech32) {
    try {
      if (bech32.startsWith('note1')) {
        return decodeBasicBech32(bech32, 'note');
      } else if (bech32.startsWith('nevent1')) {
        final result = decodeTlvBech32Full(bech32, 'nevent');
        return result['type_0_main'];
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  String _formatTime(DateTime timestamp) {
    try {
      final now = DateTime.now();
      final difference = now.difference(timestamp);

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

    final result = await _noteRepository.getNoteById(eventId);

    await result.fold(
      (note) async {
        if (note == null) {
          emit(const QuoteWidgetError());
          return;
        }

        try {
          final noteTimestamp = note['timestamp'] as DateTime? ?? DateTime.now();
          final formattedTime = _formatTime(noteTimestamp);
          final noteContent = note['content'] as String? ?? '';
          final parsedContent = stringOptimizer.parseContentOptimized(noteContent);
          final shouldTruncate = _checkTruncation(parsedContent);

          final noteAuthor = note['author'] as String? ?? '';
          final userResult = await _userRepository.getUserProfile(noteAuthor);
          final user = userResult.fold((u) => u, (_) => null);

          emit(QuoteWidgetLoaded(
            note: note,
            user: user,
            formattedTime: formattedTime,
            parsedContent: parsedContent,
            shouldTruncate: shouldTruncate,
          ));
        } catch (e) {
          final noteContent = note['content'] as String? ?? '';
          final parsedContent = {
            'textParts': [
              {'type': 'text', 'text': noteContent}
            ],
            'mediaUrls': <String>[],
            'linkUrls': <String>[],
            'quoteIds': <String>[],
          };

          final noteAuthor = note['author'] as String? ?? '';
          final userResult = await _userRepository.getUserProfile(noteAuthor);
          final user = userResult.fold((u) => u, (_) => null);

          emit(QuoteWidgetLoaded(
            note: note,
            user: user,
            formattedTime: '',
            parsedContent: parsedContent,
            shouldTruncate: false,
          ));
        }
      },
      (_) async {
        emit(const QuoteWidgetError());
      },
    );
  }
}
