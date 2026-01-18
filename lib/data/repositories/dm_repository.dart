import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/base/result.dart';
import '../services/dm_service.dart';
import '../services/user_batch_fetcher.dart';
import '../services/auth_service.dart';
import 'user_repository.dart';

class DmRepository {
  final DmService _dmService;
  final UserRepository _userRepository;
  final AuthService _authService;

  List<Map<String, dynamic>>? _lastResult;

  final StreamController<List<Map<String, dynamic>>> _conversationsController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  Stream<List<Map<String, dynamic>>> get conversationsStream =>
      _conversationsController.stream;

  DmRepository({
    required DmService dmService,
    required UserRepository userRepository,
    required AuthService authService,
  })  : _dmService = dmService,
        _userRepository = userRepository,
        _authService = authService;

  List<Map<String, dynamic>>? get cachedConversations => _lastResult;

  void dispose() {
    _conversationsController.close();
  }

  Future<Result<List<Map<String, dynamic>>>> getConversations(
      {bool forceRefresh = false}) async {
    if (!forceRefresh && _lastResult != null) {
      _enrichConversationsInBackground(_lastResult!);
      return Result.success(_lastResult!);
    }

    final result =
        await _dmService.getConversations(forceRefresh: forceRefresh);

    if (result.isError) {
      return Result.error(result.error!);
    }

    final conversations = result.data!;
    if (conversations.isEmpty) {
      _lastResult = conversations;
      return Result.success(conversations);
    }

    for (var i = 0; i < conversations.length; i++) {
      final conversation = conversations[i];
      final otherUserPubkeyHex =
          conversation['otherUserPubkeyHex'] as String? ?? '';
      final npub =
          _authService.hexToNpub(otherUserPubkeyHex) ?? otherUserPubkeyHex;

      final cachedUser = await _userRepository.getCachedUser(npub);

      if (cachedUser != null) {
        final userName = cachedUser['name'] as String? ?? '';
        final userProfileImage = cachedUser['profileImage'] as String? ?? '';
        conversations[i] = Map<String, dynamic>.from(conversation)
          ..['otherUserName'] = userName.isNotEmpty
              ? userName
              : (npub.length > 12 ? npub.substring(0, 12) : npub)
          ..['otherUserProfileImage'] = userProfileImage;
      } else {
        conversations[i] = Map<String, dynamic>.from(conversation)
          ..['otherUserName'] = npub.length > 12 ? npub.substring(0, 12) : npub;
      }
    }

    _lastResult = conversations;

    _enrichConversationsInBackground(conversations);

    return Result.success(conversations);
  }

  Future<void> _enrichConversationsInBackground(
      List<Map<String, dynamic>> conversations) async {
    try {
      final npubsToFetch = <String>[];

      for (final conversation in conversations) {
        final otherUserPubkeyHex =
            conversation['otherUserPubkeyHex'] as String? ?? '';
        final npub =
            _authService.hexToNpub(otherUserPubkeyHex) ?? otherUserPubkeyHex;

        final cachedUser = await _userRepository.getCachedUser(npub);
        final cachedUserName = cachedUser?['name'] as String? ?? '';
        if (cachedUser == null ||
            cachedUserName.isEmpty ||
            cachedUserName.length <= 12) {
          npubsToFetch.add(npub);
        }
      }

      if (npubsToFetch.isEmpty) return;

      final profiles = await _userRepository.getUserProfiles(npubsToFetch,
          priority: FetchPriority.high);

      bool hasUpdates = false;
      for (var i = 0; i < conversations.length; i++) {
        final conversation = conversations[i];
        final otherUserPubkeyHex =
            conversation['otherUserPubkeyHex'] as String? ?? '';
        final npub =
            _authService.hexToNpub(otherUserPubkeyHex) ?? otherUserPubkeyHex;

        final profileResult = profiles[npub];
        if (profileResult != null) {
          profileResult.fold(
            (user) {
              final currentName =
                  conversation['otherUserName'] as String? ?? '';
              final userName = (user as dynamic)?.name as String? ?? '';
              final userProfileImage =
                  (user as dynamic)?.profileImage as String? ?? '';
              if (userName.isNotEmpty && userName != currentName) {
                conversations[i] = Map<String, dynamic>.from(conversation)
                  ..['otherUserName'] = userName
                  ..['otherUserProfileImage'] = userProfileImage;
                hasUpdates = true;
              }
            },
            (_) {},
          );
        }
      }

      if (hasUpdates) {
        _lastResult = conversations;
      }
    } catch (e) {
      debugPrint('[DmRepository] Error enriching conversations: $e');
    }
  }

  Future<Result<List<Map<String, dynamic>>>> getMessages(
      String otherUserPubkeyHex) async {
    return await _dmService.getMessages(otherUserPubkeyHex);
  }

  Future<Result<void>> sendMessage(
      String recipientPubkeyHex, String content) async {
    return await _dmService.sendMessage(recipientPubkeyHex, content);
  }

  Stream<List<Map<String, dynamic>>> subscribeToMessages(
      String otherUserPubkeyHex) {
    return _dmService.subscribeToMessages(otherUserPubkeyHex);
  }
}
