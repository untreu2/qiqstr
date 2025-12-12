import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/base/result.dart';
import '../../models/dm_message_model.dart';
import '../services/dm_service.dart';
import '../services/user_batch_fetcher.dart';
import '../services/auth_service.dart';
import 'user_repository.dart';

class DmRepository {
  final DmService _dmService;
  final UserRepository _userRepository;
  final AuthService _authService;

  List<DmConversationModel>? _lastResult;

  final StreamController<List<DmConversationModel>> _conversationsController = StreamController<List<DmConversationModel>>.broadcast();

  Stream<List<DmConversationModel>> get conversationsStream => _conversationsController.stream;

  DmRepository({
    required DmService dmService,
    required UserRepository userRepository,
    required AuthService authService,
  })  : _dmService = dmService,
        _userRepository = userRepository,
        _authService = authService;

  List<DmConversationModel>? get cachedConversations => _lastResult;

  void dispose() {
    _conversationsController.close();
  }

  Future<Result<List<DmConversationModel>>> getConversations({bool forceRefresh = false}) async {
    if (!forceRefresh && _lastResult != null) {
      _enrichConversationsInBackground(_lastResult!);
      return Result.success(_lastResult!);
    }

    final result = await _dmService.getConversations(forceRefresh: forceRefresh);

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
      final npub = _authService.hexToNpub(conversation.otherUserPubkeyHex) ?? conversation.otherUserPubkeyHex;

      final cachedUser = _userRepository.getCachedUserSync(npub);

      if (cachedUser != null) {
        conversations[i] = conversation.copyWith(
          otherUserName: cachedUser.name.isNotEmpty ? cachedUser.name : npub.substring(0, 12),
          otherUserProfileImage: cachedUser.profileImage,
        );
      } else {
        conversations[i] = conversation.copyWith(
          otherUserName: npub.substring(0, 12),
        );
      }
    }

    _lastResult = conversations;

    _enrichConversationsInBackground(conversations);

    return Result.success(conversations);
  }

  Future<void> _enrichConversationsInBackground(List<DmConversationModel> conversations) async {
    try {
      final npubsToFetch = <String>[];

      for (final conversation in conversations) {
        final npub = _authService.hexToNpub(conversation.otherUserPubkeyHex) ?? conversation.otherUserPubkeyHex;

        final cachedUser = _userRepository.getCachedUserSync(npub);
        if (cachedUser == null || cachedUser.name.isEmpty || cachedUser.name.length <= 12) {
          npubsToFetch.add(npub);
        }
      }

      if (npubsToFetch.isEmpty) return;

      final profiles = await _userRepository.getUserProfiles(npubsToFetch, priority: FetchPriority.high);

      bool hasUpdates = false;
      for (var i = 0; i < conversations.length; i++) {
        final conversation = conversations[i];
        final npub = _authService.hexToNpub(conversation.otherUserPubkeyHex) ?? conversation.otherUserPubkeyHex;

        final profileResult = profiles[npub];
        if (profileResult != null) {
          profileResult.fold(
            (user) {
              if (user.name.isNotEmpty && user.name != conversation.otherUserName) {
                conversations[i] = conversation.copyWith(
                  otherUserName: user.name,
                  otherUserProfileImage: user.profileImage,
                );
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

  Future<Result<List<DmMessageModel>>> getMessages(String otherUserPubkeyHex) async {
    return await _dmService.getMessages(otherUserPubkeyHex);
  }

  Future<Result<void>> sendMessage(String recipientPubkeyHex, String content) async {
    return await _dmService.sendMessage(recipientPubkeyHex, content);
  }

  Stream<List<DmMessageModel>> subscribeToMessages(String otherUserPubkeyHex) {
    return _dmService.subscribeToMessages(otherUserPubkeyHex);
  }
}

