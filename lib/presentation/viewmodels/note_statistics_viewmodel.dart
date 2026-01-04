import 'dart:async';
import '../../core/base/base_view_model.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/data_service.dart';
import '../../models/user_model.dart';
import '../../models/note_model.dart';

class NoteStatisticsViewModel extends BaseViewModel {
  final UserRepository _userRepository;
  final DataService _dataService;
  final NoteModel note;

  NoteStatisticsViewModel({
    required UserRepository userRepository,
    required DataService dataService,
    required this.note,
  })  : _userRepository = userRepository,
        _dataService = dataService {
    _initialize();
  }

  List<Map<String, dynamic>>? _cachedInteractions;
  List<Map<String, dynamic>>? get cachedInteractions => _cachedInteractions;
  
  bool get isInitialized => _cachedInteractions != null;

  String? _lastNoteId;
  StreamSubscription<List<NoteModel>>? _notesSubscription;

  void _initialize() {
    _buildInteractionsList();
    _notesSubscription = _dataService.notesStream.listen((notes) {
      if (isDisposed) return;

      final hasRelevantNote = notes.any((n) => n.id == note.id);
      if (hasRelevantNote) {
        _lastNoteId = null;
        _buildInteractionsList();
        safeNotifyListeners();
      }
    });
  }

  Future<UserModel> getUser(String npub) async {
    final result = await _userRepository.getUserProfile(npub);
    return result.fold(
      (user) => user,
      (error) => UserModel.create(
        pubkeyHex: npub,
        name: '',
        about: '',
        profileImage: '',
        nip05: '',
        banner: '',
        lud16: '',
        website: '',
        updatedAt: DateTime.now(),
      ),
    );
  }

  void _buildInteractionsList() {
    if (_lastNoteId == note.id && _cachedInteractions != null) {
      return;
    }

    final reactions = _dataService.getReactionsForNote(note.id);
    final reposts = _dataService.getRepostsForNote(note.id);
    final zaps = _dataService.getZapsForNote(note.id);

    final allInteractions = <Map<String, dynamic>>[];
    final seenReactions = <String>{};

    for (final reaction in reactions) {
      final reactionKey = '${reaction.author}:${reaction.content}';
      if (!seenReactions.contains(reactionKey)) {
        seenReactions.add(reactionKey);
        allInteractions.add({
          'type': 'reaction',
          'data': reaction,
          'timestamp': reaction.timestamp,
          'npub': reaction.author,
          'content': reaction.content,
        });
      }
    }

    final seenReposts = <String>{};
    for (final repost in reposts) {
      if (!seenReposts.contains(repost.author)) {
        seenReposts.add(repost.author);
        allInteractions.add({
          'type': 'repost',
          'data': repost,
          'timestamp': repost.timestamp,
          'npub': repost.author,
          'content': 'Reposted',
        });
      }
    }

    final seenZaps = <String>{};
    for (final zap in zaps) {
      if (!seenZaps.contains(zap.sender)) {
        seenZaps.add(zap.sender);
        allInteractions.add({
          'type': 'zap',
          'data': zap,
          'timestamp': zap.timestamp,
          'npub': zap.sender,
          'content': zap.comment ?? '',
          'zapAmount': zap.amount,
        });
      }
    }

    allInteractions.sort((a, b) => (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime));

    if (!isDisposed) {
      _cachedInteractions = allInteractions;
      _lastNoteId = note.id;
      safeNotifyListeners();
    } else {
      _cachedInteractions = allInteractions;
      _lastNoteId = note.id;
    }
  }

  void refresh() {
    _lastNoteId = null;
    _cachedInteractions = null;
    _buildInteractionsList();
  }

  @override
  void dispose() {
    _notesSubscription?.cancel();
    super.dispose();
  }
}
