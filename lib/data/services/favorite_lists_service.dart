import 'package:shared_preferences/shared_preferences.dart';

class FavoriteListsService {
  static const _key = 'favorite_follow_set_ids';

  static final FavoriteListsService _instance =
      FavoriteListsService._internal();
  static FavoriteListsService get instance => _instance;

  FavoriteListsService._internal();

  List<String> _favoriteIds = [];

  List<String> get favoriteIds => List.unmodifiable(_favoriteIds);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _favoriteIds = prefs.getStringList(_key) ?? [];
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _favoriteIds);
  }

  bool isFavorite(String listId) => _favoriteIds.contains(listId);

  Future<void> toggle(String listId) async {
    if (_favoriteIds.contains(listId)) {
      _favoriteIds = _favoriteIds.where((id) => id != listId).toList();
    } else {
      _favoriteIds = [..._favoriteIds, listId];
    }
    await _save();
  }

  Future<void> add(String listId) async {
    if (!_favoriteIds.contains(listId)) {
      _favoriteIds = [..._favoriteIds, listId];
      await _save();
    }
  }

  Future<void> remove(String listId) async {
    if (_favoriteIds.contains(listId)) {
      _favoriteIds = _favoriteIds.where((id) => id != listId).toList();
      await _save();
    }
  }
}
