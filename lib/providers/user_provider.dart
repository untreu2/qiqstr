import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/user_model.dart';
import '../services/profile_service.dart';

class UserProvider extends ChangeNotifier {
  static UserProvider? _instance;
  static UserProvider get instance => _instance ??= UserProvider._internal();

  UserProvider._internal();

  final ProfileService _profileService = ProfileService();
  final Map<String, UserModel> _users = {};
  final Set<String> _loadingUsers = {};
  bool _isInitialized = false;

  Map<String, UserModel> get users => Map.unmodifiable(_users);
  bool get isInitialized => _isInitialized;

  void setUsersBox(Box<UserModel> box) {
    _profileService.setUsersBox(box);
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    await _profileService.initialize();
    _isInitialized = true;
    notifyListeners();
  }

  UserModel? getUser(String npub) {
    return _users[npub];
  }

  UserModel getUserOrDefault(String npub) {
    return _users[npub] ??
        UserModel(
          npub: npub,
          name: 'Anonymous',
          about: '',
          nip05: '',
          banner: '',
          profileImage: '',
          lud16: '',
          website: '',
          updatedAt: DateTime.now(),
        );
  }

  Future<UserModel> loadUser(String npub) async {
    // Return cached user if available
    if (_users.containsKey(npub)) {
      return _users[npub]!;
    }

    // Return default if already loading
    if (_loadingUsers.contains(npub)) {
      return getUserOrDefault(npub);
    }

    _loadingUsers.add(npub);

    try {
      final profileData = await _profileService.getCachedUserProfile(npub);
      final user = UserModel.fromCachedProfile(npub, profileData);

      _users[npub] = user;
      notifyListeners();

      return user;
    } catch (e) {
      debugPrint('[UserProvider] Error loading user $npub: $e');
      return getUserOrDefault(npub);
    } finally {
      _loadingUsers.remove(npub);
    }
  }

  Future<void> loadUsers(List<String> npubs) async {
    final npubsToLoad = npubs.where((npub) => !_users.containsKey(npub) && !_loadingUsers.contains(npub)).toList();

    if (npubsToLoad.isEmpty) return;

    // Mark as loading
    _loadingUsers.addAll(npubsToLoad);

    try {
      // Use batch fetching from ProfileService
      await _profileService.batchFetchProfiles(npubsToLoad);

      // Load individual profiles
      final futures = npubsToLoad.map((npub) async {
        try {
          final profileData = await _profileService.getCachedUserProfile(npub);
          final user = UserModel.fromCachedProfile(npub, profileData);
          _users[npub] = user;
        } catch (e) {
          debugPrint('[UserProvider] Error loading user $npub: $e');
          _users[npub] = getUserOrDefault(npub);
        }
      });

      await Future.wait(futures);
      notifyListeners();
    } finally {
      _loadingUsers.removeAll(npubsToLoad);
    }
  }

  void updateUser(String npub, UserModel user) {
    _users[npub] = user;
    notifyListeners();
  }

  void removeUser(String npub) {
    _users.remove(npub);
    notifyListeners();
  }

  void clearCache() {
    _users.clear();
    _loadingUsers.clear();
    _profileService.cleanupCache();
    notifyListeners();
  }

  Map<String, dynamic> getStats() {
    return {
      'cachedUsers': _users.length,
      'loadingUsers': _loadingUsers.length,
      'isInitialized': _isInitialized,
      'profileServiceStats': _profileService.getProfileStats(),
    };
  }

  @override
  void dispose() {
    _profileService.dispose();
    super.dispose();
  }
}
