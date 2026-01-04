import 'dart:async';
import '../../core/base/base_view_model.dart';
import '../../core/di/app_di.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/note_repository.dart';
import '../../data/services/data_service.dart';
import '../../models/user_model.dart';

class ShareNoteViewModel extends BaseViewModel {
  final DataService _dataService;
  final UserRepository _userRepository;
  final NoteRepository _noteRepository;
  final String? initialText;
  final String? replyToNoteId;

  ShareNoteViewModel({
    required DataService dataService,
    required UserRepository userRepository,
    required NoteRepository noteRepository,
    this.initialText,
    this.replyToNoteId,
  })  : _dataService = dataService,
        _userRepository = userRepository,
        _noteRepository = noteRepository {
    _loadInitialData();
  }

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;

  List<UserModel> _allUsers = [];
  List<UserModel> get allUsers => _allUsers;

  List<UserModel> _filteredUsers = [];
  List<UserModel> get filteredUsers => _filteredUsers;

  bool _isSearchingUsers = false;
  bool get isSearchingUsers => _isSearchingUsers;

  String _userSearchQuery = '';
  String get userSearchQuery => _userSearchQuery;

  bool _isPosting = false;
  bool get isPosting => _isPosting;

  bool _isMediaUploading = false;
  bool get isMediaUploading => _isMediaUploading;

  final List<String> _mediaUrls = [];
  List<String> get mediaUrls => _mediaUrls;

  final Map<String, String> _mentionMap = {};
  Map<String, String> get mentionMap => _mentionMap;

  DataService get dataService => _dataService;
  UserRepository get userRepository => _userRepository;
  NoteRepository get noteRepository => _noteRepository;

  Future<void> _loadInitialData() async {
    await Future.wait([
      _loadProfile(),
      _loadUsers(),
    ]);
  }

  Future<void> _loadProfile() async {
    try {
      final authRepository = AppDI.get<AuthRepository>();
      final currentUserNpubResult = await authRepository.getCurrentUserNpub();
      if (currentUserNpubResult.isError || currentUserNpubResult.data == null) {
        return;
      }

      final currentUserNpub = currentUserNpubResult.data!;
      final userResult = await _userRepository.getUserProfile(currentUserNpub);
      userResult.fold(
        (user) {
          if (!isDisposed) {
            _currentUser = user;
            safeNotifyListeners();
          }
        },
        (error) {
          if (!isDisposed) {
            safeNotifyListeners();
          }
        },
      );
    } catch (e) {
      if (!isDisposed) {
        safeNotifyListeners();
      }
    }
  }

  Future<void> _loadUsers() async {
    try {
      final usersResult = await _userRepository.getFollowingList();
      usersResult.fold(
        (users) {
          if (!isDisposed) {
            _allUsers = users;
            _filteredUsers = users;
            safeNotifyListeners();
          }
        },
        (error) {
          if (!isDisposed) {
            safeNotifyListeners();
          }
        },
      );
    } catch (e) {
      if (!isDisposed) {
        safeNotifyListeners();
      }
    }
  }

  void searchUsers(String query) {
    if (isDisposed) return;

    _userSearchQuery = query;
    if (query.isEmpty) {
      _filteredUsers = _allUsers;
      _isSearchingUsers = false;
    } else {
      _isSearchingUsers = true;
      final lowerQuery = query.toLowerCase();
      _filteredUsers = _allUsers.where((user) {
        final name = user.name.toLowerCase();
        final npub = user.npub.toLowerCase();
        return name.contains(lowerQuery) || npub.contains(lowerQuery);
      }).toList();
      _isSearchingUsers = false;
    }
    safeNotifyListeners();
  }

  void setPosting(bool value) {
    if (isDisposed) return;
    _isPosting = value;
    safeNotifyListeners();
  }

  void setMediaUploading(bool value) {
    if (isDisposed) return;
    _isMediaUploading = value;
    safeNotifyListeners();
  }

  void addMediaUrl(String url) {
    if (isDisposed) return;
    _mediaUrls.add(url);
    safeNotifyListeners();
  }

  void removeMediaUrl(int index) {
    if (isDisposed) return;
    if (index >= 0 && index < _mediaUrls.length) {
      _mediaUrls.removeAt(index);
      safeNotifyListeners();
    }
  }

  void clearMediaUrls() {
    if (isDisposed) return;
    _mediaUrls.clear();
    safeNotifyListeners();
  }

  void addMention(String npub, String displayName) {
    if (isDisposed) return;
    _mentionMap[npub] = displayName;
    safeNotifyListeners();
  }

  void removeMention(String npub) {
    if (isDisposed) return;
    _mentionMap.remove(npub);
    safeNotifyListeners();
  }

  void clearMentions() {
    if (isDisposed) return;
    _mentionMap.clear();
    safeNotifyListeners();
  }
}
