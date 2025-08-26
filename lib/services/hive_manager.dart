import 'package:hive/hive.dart';
import '../models/user_model.dart';
import '../models/note_model.dart';
import '../models/reaction_model.dart';
import '../models/reply_model.dart';
import '../models/repost_model.dart';
import '../models/following_model.dart';
import '../models/zap_model.dart';
import '../models/notification_model.dart';

class HiveManager {
  static HiveManager? _instance;
  static HiveManager get instance => _instance ??= HiveManager._internal();

  HiveManager._internal();

  Box<UserModel>? _usersBox;
  Box<NoteModel>? _notesBox;
  Box<ReactionModel>? _reactionsBox;
  Box<ReplyModel>? _repliesBox;
  Box<RepostModel>? _repostsBox;
  Box<FollowingModel>? _followingBox;
  Box<ZapModel>? _zapsBox;

  final Map<String, Box<NotificationModel>> _notificationBoxes = {};

  Box<UserModel>? get usersBox => _usersBox;
  Box<NoteModel>? get notesBox => _notesBox;
  Box<ReactionModel>? get reactionsBox => _reactionsBox;
  Box<ReplyModel>? get repliesBox => _repliesBox;
  Box<RepostModel>? get repostsBox => _repostsBox;
  Box<FollowingModel>? get followingBox => _followingBox;
  Box<ZapModel>? get zapsBox => _zapsBox;

  Box<NotificationModel>? getNotificationBox(String npub) {
    return _notificationBoxes['notifications_$npub'];
  }

  Future<void> initializeBoxes() async {
    try {
      print('[HiveManager] Initializing singleton Hive boxes...');

      _usersBox = await _openHiveBox<UserModel>('users');
      _notesBox = await _openHiveBox<NoteModel>('notes');
      _reactionsBox = await _openHiveBox<ReactionModel>('reactions');
      _repliesBox = await _openHiveBox<ReplyModel>('replies');
      _repostsBox = await _openHiveBox<RepostModel>('reposts');
      _followingBox = await _openHiveBox<FollowingModel>('followingBox');
      _zapsBox = await _openHiveBox<ZapModel>('zaps');

      print('[HiveManager] Singleton Hive boxes initialized successfully');
    } catch (e) {
      print('[HiveManager] Error initializing boxes: $e');
      rethrow;
    }
  }

  Future<Box<NotificationModel>> initializeNotificationBox(String npub) async {
    final boxKey = 'notifications_$npub';

    if (_notificationBoxes.containsKey(boxKey)) {
      return _notificationBoxes[boxKey]!;
    }

    try {
      final box = await _openHiveBox<NotificationModel>(boxKey);
      _notificationBoxes[boxKey] = box;
      print('[HiveManager] Notification box initialized for user: $npub');
      return box;
    } catch (e) {
      print('[HiveManager] Error initializing notification box for $npub: $e');
      rethrow;
    }
  }

  Future<Box<T>> _openHiveBox<T>(String boxName) async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box<T>(boxName);
    } else {
      return await Hive.openBox<T>(boxName);
    }
  }

  Future<void> closeAllBoxes() async {
    try {
      print('[HiveManager] Closing all singleton Hive boxes...');

      await _usersBox?.close();
      await _notesBox?.close();
      await _reactionsBox?.close();
      await _repliesBox?.close();
      await _repostsBox?.close();
      await _followingBox?.close();
      await _zapsBox?.close();

      for (final box in _notificationBoxes.values) {
        await box.close();
      }
      _notificationBoxes.clear();

      _usersBox = null;
      _notesBox = null;
      _reactionsBox = null;
      _repliesBox = null;
      _repostsBox = null;
      _followingBox = null;
      _zapsBox = null;

      print('[HiveManager] All singleton Hive boxes closed successfully');
    } catch (e) {
      print('[HiveManager] Error closing boxes: $e');
    }
  }

  bool get isInitialized {
    return _usersBox != null &&
        _notesBox != null &&
        _reactionsBox != null &&
        _repliesBox != null &&
        _repostsBox != null &&
        _followingBox != null &&
        _zapsBox != null;
  }

  Map<String, dynamic> getBoxStatus() {
    return {
      'usersBox': _usersBox?.isOpen ?? false,
      'notesBox': _notesBox?.isOpen ?? false,
      'reactionsBox': _reactionsBox?.isOpen ?? false,
      'repliesBox': _repliesBox?.isOpen ?? false,
      'repostsBox': _repostsBox?.isOpen ?? false,
      'followingBox': _followingBox?.isOpen ?? false,
      'zapsBox': _zapsBox?.isOpen ?? false,
      'notificationBoxes': _notificationBoxes.length,
    };
  }
}
