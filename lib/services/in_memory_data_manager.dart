import '../models/user_model.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../models/repost_model.dart';
import '../models/following_model.dart';
import '../models/zap_model.dart';
import '../models/notification_model.dart';
import '../models/link_preview_model.dart';

class InMemoryDataManager {
  static InMemoryDataManager? _instance;
  static InMemoryDataManager get instance => _instance ??= InMemoryDataManager._internal();

  InMemoryDataManager._internal();

  final Map<String, UserModel> _users = {};
  final Map<String, NoteModel> _notes = {};
  final Map<String, ReactionModel> _reactions = {};
  final Map<String, ReplyModel> _replies = {};
  final Map<String, RepostModel> _reposts = {};
  final Map<String, FollowingModel> _following = {};
  final Map<String, ZapModel> _zaps = {};
  final Map<String, LinkPreviewModel> _linkPreviews = {};

  final Map<String, Map<String, NotificationModel>> _notifications = {};

  bool _isInitialized = false;

  InMemoryBox<UserModel>? get usersBox => _isInitialized ? InMemoryBox<UserModel>(_users) : null;
  InMemoryBox<NoteModel>? get notesBox => _isInitialized ? InMemoryBox<NoteModel>(_notes) : null;
  InMemoryBox<ReactionModel>? get reactionsBox => _isInitialized ? InMemoryBox<ReactionModel>(_reactions) : null;
  InMemoryBox<ReplyModel>? get repliesBox => _isInitialized ? InMemoryBox<ReplyModel>(_replies) : null;
  InMemoryBox<RepostModel>? get repostsBox => _isInitialized ? InMemoryBox<RepostModel>(_reposts) : null;
  InMemoryBox<FollowingModel>? get followingBox => _isInitialized ? InMemoryBox<FollowingModel>(_following) : null;
  InMemoryBox<ZapModel>? get zapsBox => _isInitialized ? InMemoryBox<ZapModel>(_zaps) : null;

  InMemoryBox<NotificationModel>? getNotificationBox(String npub) {
    if (!_isInitialized) return null;

    final boxKey = 'notifications_$npub';
    _notifications[boxKey] ??= {};
    return InMemoryBox<NotificationModel>(_notifications[boxKey]!);
  }

  InMemoryBox<LinkPreviewModel>? getLinkPreviewBox() {
    return _isInitialized ? InMemoryBox<LinkPreviewModel>(_linkPreviews) : null;
  }

  Future<void> initializeBoxes() async {
    try {
      print('[InMemoryDataManager] Initializing in-memory storage...');

      _users.clear();
      _notes.clear();
      _reactions.clear();
      _replies.clear();
      _reposts.clear();
      _following.clear();
      _zaps.clear();
      _linkPreviews.clear();
      _notifications.clear();

      _isInitialized = true;
      print('[InMemoryDataManager] In-memory storage initialized successfully');
    } catch (e) {
      print('[InMemoryDataManager] Error initializing storage: $e');
      rethrow;
    }
  }

  Future<InMemoryBox<NotificationModel>> initializeNotificationBox(String npub) async {
    final boxKey = 'notifications_$npub';

    if (_notifications.containsKey(boxKey)) {
      return InMemoryBox<NotificationModel>(_notifications[boxKey]!);
    }

    try {
      _notifications[boxKey] = {};
      print('[InMemoryDataManager] Notification storage initialized for user: $npub');
      return InMemoryBox<NotificationModel>(_notifications[boxKey]!);
    } catch (e) {
      print('[InMemoryDataManager] Error initializing notification storage for $npub: $e');
      rethrow;
    }
  }

  Future<void> closeAllBoxes() async {
    try {
      print('[InMemoryDataManager] Clearing all in-memory storage...');

      _users.clear();
      _notes.clear();
      _reactions.clear();
      _replies.clear();
      _reposts.clear();
      _following.clear();
      _zaps.clear();
      _linkPreviews.clear();
      _notifications.clear();

      _isInitialized = false;
      print('[InMemoryDataManager] All in-memory storage cleared successfully');
    } catch (e) {
      print('[InMemoryDataManager] Error clearing storage: $e');
    }
  }

  bool get isInitialized => _isInitialized;

  Map<String, dynamic> getBoxStatus() {
    return {
      'usersBox': _isInitialized,
      'notesBox': _isInitialized,
      'reactionsBox': _isInitialized,
      'repliesBox': _isInitialized,
      'repostsBox': _isInitialized,
      'followingBox': _isInitialized,
      'zapsBox': _isInitialized,
      'notificationBoxes': _notifications.length,
      'linkPreviewBox': _isInitialized,
    };
  }

  void printStorageStats() {
    print('[InMemoryDataManager] Storage Stats:');
    print('  Users: ${_users.length}');
    print('  Notes: ${_notes.length}');
    print('  Reactions: ${_reactions.length}');
    print('  Replies: ${_replies.length}');
    print('  Reposts: ${_reposts.length}');
    print('  Following: ${_following.length}');
    print('  Zaps: ${_zaps.length}');
    print('  Link Previews: ${_linkPreviews.length}');
    print('  Notification Boxes: ${_notifications.length}');
  }

  int get totalItemsInMemory {
    return _users.length +
        _notes.length +
        _reactions.length +
        _replies.length +
        _reposts.length +
        _following.length +
        _zaps.length +
        _linkPreviews.length +
        _notifications.values.fold(0, (sum, map) => sum + map.length);
  }
}

class InMemoryBox<T> {
  final Map<String, T> _data;
  bool _isOpen = true;

  InMemoryBox(this._data);

  bool get isOpen => _isOpen;

  Iterable<T> get values => _data.values;
  Iterable<String> get keys => _data.keys;
  int get length => _data.length;
  bool get isEmpty => _data.isEmpty;
  bool get isNotEmpty => _data.isNotEmpty;

  T? get(String key) => _data[key];

  Future<void> put(String key, T value) async {
    _data[key] = value;
  }

  Future<void> putAll(Map<String, T> entries) async {
    _data.addAll(entries);
  }

  T? getAt(int index) {
    if (index >= 0 && index < _data.length) {
      return _data.values.elementAt(index);
    }
    return null;
  }

  String? keyAt(int index) {
    if (index >= 0 && index < _data.length) {
      return _data.keys.elementAt(index);
    }
    return null;
  }

  Future<void> delete(String key) async {
    _data.remove(key);
  }

  Future<void> deleteAt(int index) async {
    if (index >= 0 && index < _data.length) {
      final key = _data.keys.elementAt(index);
      _data.remove(key);
    }
  }

  Future<void> clear() async {
    _data.clear();
  }

  Future<void> close() async {
    _isOpen = false;
  }

  bool containsKey(String key) => _data.containsKey(key);

  List<T> toList() => _data.values.toList();
  Map<String, T> toMap() => Map.from(_data);
}
