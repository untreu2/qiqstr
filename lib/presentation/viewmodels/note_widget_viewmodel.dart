import 'dart:async';
import '../../core/base/base_view_model.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/note_widget_calculator.dart';
import '../../models/user_model.dart';
import '../../models/note_model.dart';
import '../../models/note_widget_metrics.dart';

class NoteWidgetState {
  final UserModel? authorUser;
  final UserModel? reposterUser;
  final String? replyText;

  const NoteWidgetState({
    this.authorUser,
    this.reposterUser,
    this.replyText,
  });

  NoteWidgetState copyWith({
    UserModel? authorUser,
    UserModel? reposterUser,
    String? replyText,
  }) {
    return NoteWidgetState(
      authorUser: authorUser ?? this.authorUser,
      reposterUser: reposterUser ?? this.reposterUser,
      replyText: replyText ?? this.replyText,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteWidgetState &&
          authorUser == other.authorUser &&
          reposterUser == other.reposterUser &&
          replyText == other.replyText;

  @override
  int get hashCode => Object.hash(authorUser, reposterUser, replyText);
}

class NoteWidgetViewModel extends BaseViewModel {
  final UserRepository _userRepository;
  final NoteWidgetCalculator _calculator;
  final NoteModel note;
  final Map<String, UserModel> profiles;
  final String authorId;
  final String? reposterId;
  final String? parentId;
  final bool isReply;

  NoteWidgetViewModel({
    required UserRepository userRepository,
    required NoteWidgetCalculator calculator,
    required this.note,
    required this.profiles,
  })  : _userRepository = userRepository,
        _calculator = calculator,
        authorId = note.author,
        reposterId = note.repostedBy,
        parentId = note.parentId,
        isReply = note.isReply {
    _initializeMetrics();
    _loadInitialUserData();
    _setupUserListener();
    _loadUsersAsync();
  }

  NoteWidgetState _state = const NoteWidgetState();
  NoteWidgetState get state => _state;

  NoteWidgetMetrics? _metrics;
  NoteWidgetMetrics? get metrics => _metrics;

  Map<String, dynamic>? _parsedContent;
  Map<String, dynamic>? get parsedContent => _parsedContent;

  bool? _shouldTruncate;
  bool get shouldTruncate => _shouldTruncate ?? false;

  Map<String, dynamic>? _truncatedContent;
  Map<String, dynamic>? get truncatedContent => _truncatedContent;

  void _initializeMetrics() {
    try {
      _metrics = _calculator.getMetrics(note.id);

      if (_metrics == null) {
        _metrics = NoteWidgetCalculator.calculateMetrics(note);
        _calculator.cacheMetrics(_metrics!);
      }

      _parsedContent = _metrics!.parsedContent;
      _shouldTruncate = _metrics!.shouldTruncate;
      _truncatedContent = _metrics!.truncatedContent;
    } catch (e) {
      _parsedContent = note.parsedContentLazy;
      if (_parsedContent != null) {
        _shouldTruncate = _calculateTruncation(_parsedContent!);
        _truncatedContent = (_shouldTruncate ?? false) ? _createTruncatedContent() : null;
      }
    }
  }

  bool _calculateTruncation(Map<String, dynamic> parsedContent) {
    final textParts = parsedContent['textParts'] as List? ?? [];
    int totalLength = 0;
    for (final part in textParts) {
      if (part is Map && part['type'] == 'text') {
        totalLength += (part['text'] as String? ?? '').length;
      }
    }
    return totalLength > 500;
  }

  Map<String, dynamic> _createTruncatedContent() {
    if (_parsedContent == null) return {};
    final textParts = _parsedContent!['textParts'] as List? ?? [];
    final truncated = <String, dynamic>{};
    final truncatedParts = <Map<String, dynamic>>[];
    int totalLength = 0;

    for (final part in textParts) {
      if (part is Map) {
        if (part['type'] == 'text') {
          final text = part['text'] as String? ?? '';
          if (totalLength + text.length > 500) {
            final remaining = 500 - totalLength;
            if (remaining > 0) {
              truncatedParts.add({
                'type': 'text',
                'text': '${text.substring(0, remaining)}...',
              });
            }
            break;
          } else {
            truncatedParts.add(Map<String, dynamic>.from(part));
            totalLength += text.length;
          }
        } else {
          truncatedParts.add(Map<String, dynamic>.from(part));
        }
      }
    }

    truncated['textParts'] = truncatedParts;
    truncated['mediaUrls'] = _parsedContent!['mediaUrls'] ?? <String>[];
    truncated['linkUrls'] = _parsedContent!['linkUrls'] ?? <String>[];
    truncated['quoteIds'] = _parsedContent!['quoteIds'] ?? <String>[];

    return truncated;
  }

  void _loadInitialUserData() {
    try {
      UserModel? authorUser = profiles[authorId];
      UserModel? reposterUser = reposterId != null ? profiles[reposterId] : null;

      authorUser ??= UserModel.create(
        pubkeyHex: authorId,
        name: authorId.length > 8 ? authorId.substring(0, 8) : authorId,
        about: '',
        profileImage: '',
        banner: '',
        website: '',
        nip05: '',
        lud16: '',
        updatedAt: DateTime.now(),
        nip05Verified: false,
      );

      if (reposterId != null && reposterUser == null) {
        reposterUser = UserModel.create(
          pubkeyHex: reposterId!,
          name: reposterId!.length > 8 ? reposterId!.substring(0, 8) : reposterId!,
          about: '',
          profileImage: '',
          banner: '',
          website: '',
          nip05: '',
          lud16: '',
          updatedAt: DateTime.now(),
          nip05Verified: false,
        );
      }

      final replyText = isReply && parentId != null ? 'Reply to...' : null;

      final newState = NoteWidgetState(
        authorUser: authorUser,
        reposterUser: reposterUser,
        replyText: replyText,
      );

      if (_state != newState) {
        _state = newState;
        safeNotifyListeners();
      }
    } catch (e) {
      if (!isDisposed) {
        safeNotifyListeners();
      }
    }
  }

  void _setupUserListener() {
    addSubscription(
      _userRepository.currentUserStream.listen((updatedUser) {
        if (isDisposed) return;

        if (updatedUser.pubkeyHex == authorId || updatedUser.pubkeyHex == reposterId) {
          _updateUserData();
        }
      }),
    );
  }

  Future<void> _loadUsersAsync() async {
    if (isDisposed) return;

    try {
      final currentAuthor = profiles[authorId];
      final currentReposter = reposterId != null ? profiles[reposterId] : null;

      final shouldLoadAuthor = currentAuthor == null ||
          currentAuthor.profileImage.isEmpty ||
          currentAuthor.name.isEmpty ||
          currentAuthor.name == authorId.substring(0, authorId.length > 8 ? 8 : authorId.length);

      if (shouldLoadAuthor) {
        final authorResult = await _userRepository.getUserProfile(authorId);
        authorResult.fold(
          (user) {
            if (!isDisposed) {
              profiles[authorId] = user;
              _updateUserData();
            }
          },
          (error) {
            if (!isDisposed) {
              safeNotifyListeners();
            }
          },
        );
      }

      if (reposterId != null) {
        final shouldLoadReposter = currentReposter == null ||
            currentReposter.profileImage.isEmpty ||
            currentReposter.name.isEmpty ||
            currentReposter.name == reposterId!.substring(0, reposterId!.length > 8 ? 8 : reposterId!.length);

        if (shouldLoadReposter) {
          final reposterResult = await _userRepository.getUserProfile(reposterId!);
          reposterResult.fold(
            (user) {
              if (!isDisposed) {
                profiles[reposterId!] = user;
                _updateUserData();
              }
            },
            (error) {
              if (!isDisposed) {
                safeNotifyListeners();
              }
            },
          );
        }
      }
    } catch (e) {
      if (!isDisposed) {
        safeNotifyListeners();
      }
    }
  }

  void _updateUserData() {
    if (isDisposed) return;

    try {
      UserModel? authorUser = profiles[authorId];
      UserModel? reposterUser = reposterId != null ? profiles[reposterId] : null;

      authorUser ??= UserModel.create(
        pubkeyHex: authorId,
        name: authorId.length > 8 ? authorId.substring(0, 8) : authorId,
        about: '',
        profileImage: '',
        banner: '',
        website: '',
        nip05: '',
        lud16: '',
        updatedAt: DateTime.now(),
        nip05Verified: false,
      );

      if (reposterId != null && reposterUser == null) {
        reposterUser = UserModel.create(
          pubkeyHex: reposterId!,
          name: reposterId!.length > 8 ? reposterId!.substring(0, 8) : reposterId!,
          about: '',
          profileImage: '',
          banner: '',
          website: '',
          nip05: '',
          lud16: '',
          updatedAt: DateTime.now(),
          nip05Verified: false,
        );
      }

      final replyText = isReply && parentId != null ? 'Reply to...' : null;

      final newState = NoteWidgetState(
        authorUser: authorUser,
        reposterUser: reposterUser,
        replyText: replyText,
      );

      if (_state != newState) {
        _state = newState;
        safeNotifyListeners();
      }
    } catch (e) {
      if (!isDisposed) {
        safeNotifyListeners();
      }
    }
  }

  void updateProfiles(Map<String, UserModel> newProfiles) {
    profiles.addAll(newProfiles);
    _updateUserData();
  }
}
