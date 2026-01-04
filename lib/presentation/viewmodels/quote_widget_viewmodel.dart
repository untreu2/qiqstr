import 'dart:async';
import '../../core/base/base_view_model.dart';
import '../../data/repositories/note_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../models/note_model.dart';
import '../../models/user_model.dart';
import 'package:nostr_nip19/nostr_nip19.dart';

class QuoteWidgetViewModel extends BaseViewModel {
  final NoteRepository _noteRepository;
  final UserRepository _userRepository;
  final String bech32;

  QuoteWidgetViewModel({
    required NoteRepository noteRepository,
    required UserRepository userRepository,
    required this.bech32,
  })  : _noteRepository = noteRepository,
        _userRepository = userRepository {
    _loadQuoteData();
  }

  NoteModel? _note;
  NoteModel? get note => _note;

  UserModel? _user;
  UserModel? get user => _user;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  bool _hasError = false;
  bool get hasError => _hasError;

  String? _formattedTime;
  String? get formattedTime => _formattedTime;

  Map<String, dynamic>? _parsedContent;
  Map<String, dynamic>? get parsedContent => _parsedContent;

  bool _shouldTruncate = false;
  bool get shouldTruncate => _shouldTruncate;

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

  Future<void> _loadQuoteData() async {
    await executeOperation('loadQuoteData', () async {
      final eventId = _extractEventId(bech32);
      if (eventId == null) {
        _hasError = true;
        _isLoading = false;
        safeNotifyListeners();
        return;
      }

      final result = await _noteRepository.getNoteById(eventId);

      result.fold(
        (note) {
          if (note != null) {
            _note = note;
            _precomputeData(note);
            _loadUser(note.author);
            _isLoading = false;
            _hasError = false;
            safeNotifyListeners();
          } else {
            _hasError = true;
            _isLoading = false;
            safeNotifyListeners();
          }
        },
        (error) {
          _hasError = true;
          _isLoading = false;
          safeNotifyListeners();
        },
      );
    }, showLoading: false);
  }

  void _precomputeData(NoteModel note) {
    try {
      _formattedTime = _formatTime(note.timestamp);
      _parsedContent = note.parsedContentLazy;
      _shouldTruncate = _checkTruncation(_parsedContent!);
    } catch (e) {
      _parsedContent = {
        'textParts': [
          {'type': 'text', 'text': note.content}
        ],
        'mediaUrls': <String>[],
        'linkUrls': <String>[],
        'quoteIds': <String>[],
      };
    }
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

  Future<void> _loadUser(String authorId) async {
    await executeOperation('loadUser', () async {
      final result = await _userRepository.getUserProfile(authorId);
      result.fold(
        (user) {
          if (!isDisposed) {
            _user = user;
            safeNotifyListeners();
          }
        },
        (error) {
          if (!isDisposed) {
            safeNotifyListeners();
          }
        },
      );
    }, showLoading: false);
  }
}
