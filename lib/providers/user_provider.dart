import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nostr_nip19/nostr_nip19.dart';
import '../models/user_model.dart';
import '../services/profile_service.dart';

class UserProvider extends ChangeNotifier {
  static UserProvider? _instance;
  static UserProvider get instance => _instance ??= UserProvider._internal();

  UserProvider._internal();

  final ProfileService _profileService = ProfileService();
  // MEMORY OPTIMIZATION: Single storage instead of duplicate hex+npub
  final Map<String, UserModel> _users = {};
  final Map<String, String> _npubToHexMap = {}; // Quick lookup for conversions
  final Set<String> _loadingUsers = {};
  bool _isInitialized = false;
  String? _currentUserNpub;
  UserModel? _currentUser;

  // Memory management
  static const int _maxUsersCache = 1000;
  DateTime _lastCleanup = DateTime.now();

  Map<String, UserModel> get users => Map.unmodifiable(_users);
  bool get isInitialized => _isInitialized;
  UserModel? get currentUser => _currentUser;
  String? get currentUserNpub => _currentUserNpub;

  void setUsersBox(Box<UserModel> box) {
    _profileService.setUsersBox(box);
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    await _profileService.initialize();
    await _loadCurrentUser();
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> _loadCurrentUser() async {
    try {
      const storage = FlutterSecureStorage();
      final npub = await storage.read(key: 'npub');
      if (npub != null) {
        _currentUserNpub = npub;
        _currentUser = await loadUser(npub);
      }
    } catch (e) {
      debugPrint('[UserProvider] Error loading current user: $e');
    }
  }

  Future<void> setCurrentUser(String npub) async {
    _currentUserNpub = npub;
    _currentUser = await loadUser(npub);
    notifyListeners();
  }

  UserModel? getUser(String identifier) {
    if (identifier.isEmpty) return null;

    // MEMORY OPTIMIZATION: Use primary key (npub) and conversion map
    String primaryKey = _getPrimaryKey(identifier);
    return _users[primaryKey];
  }

  String _getPrimaryKey(String identifier) {
    if (identifier.startsWith('npub1')) {
      return identifier; // Already primary key
    }

    // Check conversion cache first
    final cachedNpub = _npubToHexMap.entries.where((entry) => entry.value == identifier).map((entry) => entry.key).firstOrNull;

    if (cachedNpub != null) return cachedNpub;

    // Convert hex to npub if valid
    if (_isValidHex(identifier)) {
      try {
        final npub = encodeBasicBech32(identifier, 'npub');
        _npubToHexMap[npub] = identifier; // Cache conversion
        return npub;
      } catch (e) {
        debugPrint('[UserProvider] Error converting hex to npub: $e');
      }
    }

    return identifier; // Fallback
  }

  UserModel getUserOrDefault(String identifier) {
    if (identifier.isEmpty) {
      return _createDefaultUser('');
    }

    final user = getUser(identifier);
    if (user != null) return user;

    // Ensure we always have a valid npub
    String npubForDefault = identifier;
    if (!identifier.startsWith('npub1') && _isValidHex(identifier)) {
      try {
        npubForDefault = encodeBasicBech32(identifier, 'npub');
      } catch (e) {
        debugPrint('[UserProvider] Error creating npub for default user: $e');
        npubForDefault = identifier; // Keep original if conversion fails
      }
    }

    return _createDefaultUser(npubForDefault);
  }

  Future<UserModel> loadUser(String identifier) async {
    if (identifier.isEmpty) {
      return _createDefaultUser('');
    }

    // Convert npub to hex if needed for ProfileService
    String hexKey = identifier;
    String npubKey = identifier;

    if (identifier.startsWith('npub1')) {
      try {
        hexKey = decodeBasicBech32(identifier, 'npub');
        npubKey = identifier;
      } catch (e) {
        debugPrint('[UserProvider] Invalid npub format: $identifier');
        return getUserOrDefault(identifier);
      }
    } else if (_isValidHex(identifier)) {
      try {
        npubKey = encodeBasicBech32(identifier, 'npub');
        hexKey = identifier;
      } catch (e) {
        debugPrint('[UserProvider] Invalid hex format: $identifier');
        return getUserOrDefault(identifier);
      }
    } else {
      debugPrint('[UserProvider] Invalid identifier format: $identifier');
      return getUserOrDefault(identifier);
    }

    // Return cached user if available (check both formats)
    final cachedUser = getUser(identifier);
    if (cachedUser != null) {
      // Ensure the returned user has a valid npub
      if (cachedUser.npub.isEmpty && npubKey.isNotEmpty) {
        final updatedUser = UserModel(
          npub: npubKey,
          name: cachedUser.name,
          about: cachedUser.about,
          nip05: cachedUser.nip05,
          banner: cachedUser.banner,
          profileImage: cachedUser.profileImage,
          lud16: cachedUser.lud16,
          website: cachedUser.website,
          updatedAt: cachedUser.updatedAt,
        );

        // MEMORY OPTIMIZATION: Store only once with primary key
        _users[npubKey] = updatedUser;
        _npubToHexMap[npubKey] = hexKey;
        notifyListeners();

        return updatedUser;
      }
      return cachedUser;
    }

    // Return default if already loading
    if (_loadingUsers.contains(hexKey) || _loadingUsers.contains(npubKey)) {
      return getUserOrDefault(identifier);
    }

    _loadingUsers.add(hexKey);

    try {
      // ProfileService expects hex format
      final profileData = await _profileService.getCachedUserProfile(hexKey);
      final user = UserModel.fromCachedProfile(npubKey, profileData);

      // MEMORY OPTIMIZATION: Store only once
      _users[npubKey] = user;
      _npubToHexMap[npubKey] = hexKey;
      _performMemoryCleanup();
      notifyListeners();

      return user;
    } catch (e) {
      debugPrint('[UserProvider] Error loading user $identifier: $e');
      final defaultUser = getUserOrDefault(identifier);

      // Ensure default user has npub if possible
      if (defaultUser.npub.isEmpty && npubKey.isNotEmpty) {
        final correctedUser = UserModel(
          npub: npubKey,
          name: defaultUser.name,
          about: defaultUser.about,
          nip05: defaultUser.nip05,
          banner: defaultUser.banner,
          profileImage: defaultUser.profileImage,
          lud16: defaultUser.lud16,
          website: defaultUser.website,
          updatedAt: defaultUser.updatedAt,
        );
        return correctedUser;
      }

      return defaultUser;
    } finally {
      _loadingUsers.remove(hexKey);
    }
  }

  Future<void> loadUsers(List<String> identifiers) async {
    final hexKeysToLoad = <String>[];
    final npubKeysToLoad = <String>[];

    for (final identifier in identifiers) {
      if (identifier.isEmpty || getUser(identifier) != null) continue; // Already cached

      String hexKey = identifier;
      String npubKey = identifier;

      if (identifier.startsWith('npub1')) {
        try {
          hexKey = decodeBasicBech32(identifier, 'npub');
          npubKey = identifier;
        } catch (e) {
          debugPrint('[UserProvider] Skipping invalid npub: $identifier');
          continue; // Skip invalid npub
        }
      } else if (_isValidHex(identifier)) {
        try {
          npubKey = encodeBasicBech32(identifier, 'npub');
          hexKey = identifier;
        } catch (e) {
          debugPrint('[UserProvider] Skipping invalid hex: $identifier');
          continue; // Skip invalid hex
        }
      } else {
        debugPrint('[UserProvider] Skipping invalid identifier: $identifier');
        continue; // Skip invalid format
      }

      if (!_loadingUsers.contains(hexKey)) {
        hexKeysToLoad.add(hexKey);
        npubKeysToLoad.add(npubKey);
      }
    }

    if (hexKeysToLoad.isEmpty) return;

    // Mark as loading
    _loadingUsers.addAll(hexKeysToLoad);

    try {
      // Use batch fetching from ProfileService (expects hex format)
      await _profileService.batchFetchProfiles(hexKeysToLoad);

      // Load individual profiles
      final futures = List.generate(hexKeysToLoad.length, (index) async {
        final hexKey = hexKeysToLoad[index];
        final npubKey = npubKeysToLoad[index];

        try {
          final profileData = await _profileService.getCachedUserProfile(hexKey);
          final user = UserModel.fromCachedProfile(npubKey, profileData);

          // MEMORY OPTIMIZATION: Store only once
          _users[npubKey] = user;
          _npubToHexMap[npubKey] = hexKey;
        } catch (e) {
          debugPrint('[UserProvider] Error loading user $hexKey: $e');
          final defaultUser = getUserOrDefault(npubKey);
          _users[npubKey] = defaultUser;
          _npubToHexMap[npubKey] = hexKey;
        }
      });

      await Future.wait(futures);
      notifyListeners();
    } finally {
      _loadingUsers.removeAll(hexKeysToLoad);
    }
  }

  void updateUser(String identifier, UserModel user) {
    if (identifier.isEmpty) return;

    // MEMORY OPTIMIZATION: Store only once with primary key
    final primaryKey = _getPrimaryKey(identifier);
    _users[primaryKey] = user;

    if (identifier == _currentUserNpub || primaryKey == _currentUserNpub) {
      _currentUser = user;
    }
    notifyListeners();
  }

  void removeUser(String identifier) {
    if (identifier.isEmpty) return;

    // MEMORY OPTIMIZATION: Remove only primary key and conversion
    final primaryKey = _getPrimaryKey(identifier);
    _users.remove(primaryKey);

    // Clean up conversion map
    if (primaryKey.startsWith('npub1')) {
      _npubToHexMap.remove(primaryKey);
    }

    notifyListeners();
  }

  void _performMemoryCleanup() {
    final now = DateTime.now();
    if (now.difference(_lastCleanup).inMinutes < 5) return; // Only cleanup every 5 minutes

    _lastCleanup = now;

    if (_users.length > _maxUsersCache) {
      // Remove oldest 20% of users (simple cleanup - could be improved with LRU)
      final keysToRemove = _users.keys.take(_users.length ~/ 5).toList();
      for (final key in keysToRemove) {
        _users.remove(key);
        _npubToHexMap.remove(key);
      }
      debugPrint('[UserProvider] Cleaned up ${keysToRemove.length} cached users');
    }
  }

  // Helper methods
  bool _isValidHex(String value) {
    if (value.isEmpty || value.length != 64) return false;
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(value);
  }

  UserModel _createDefaultUser(String identifier) {
    return UserModel(
      npub: identifier,
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

  void clearCache() {
    _users.clear();
    _npubToHexMap.clear();
    _loadingUsers.clear();
    _profileService.cleanupCache();
    notifyListeners();
  }

  @override
  void dispose() {
    _profileService.dispose();
    super.dispose();
  }
}
