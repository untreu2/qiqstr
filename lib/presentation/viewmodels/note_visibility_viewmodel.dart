import 'package:flutter/foundation.dart';

class NoteVisibilityViewModel extends ChangeNotifier {
  final Map<String, bool> _visibilityMap = {};
  
  bool isNoteVisible(String noteId) {
    return _visibilityMap[noteId] ?? false;
  }
  
  void updateVisibility(String noteId, bool isVisible) {
    if (_visibilityMap[noteId] != isVisible) {
      _visibilityMap[noteId] = isVisible;
      notifyListeners();
    }
  }
  
  void clearVisibility(String noteId) {
    if (_visibilityMap.containsKey(noteId)) {
      _visibilityMap.remove(noteId);
      notifyListeners();
    }
  }
  
  void clearAll() {
    if (_visibilityMap.isNotEmpty) {
      _visibilityMap.clear();
      notifyListeners();
    }
  }
  
  Set<String> get visibleNoteIds => _visibilityMap.entries
      .where((entry) => entry.value)
      .map((entry) => entry.key)
      .toSet();
  
  int get visibleNotesCount => visibleNoteIds.length;
  
  @override
  void dispose() {
    _visibilityMap.clear();
    super.dispose();
  }
}


