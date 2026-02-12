import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/services/dm_service.dart';
import '../../../data/repositories/profile_repository.dart';
import 'dm_event.dart';
import 'dm_state.dart';

class DmBloc extends Bloc<DmEvent, DmState> {
  final DmService _dmService;
  final ProfileRepository _profileRepository;

  final List<StreamSubscription> _subscriptions = [];
  String? _currentChatPubkeyHex;
  Timer? _conversationsTimer;
  List<Map<String, dynamic>>? _cachedConversations;

  List<Map<String, dynamic>> _fullMessages = [];
  int _chatDisplayLimit = 20;
  static const int _chatPageSize = 20;

  List<Map<String, dynamic>>? get cachedConversations => _cachedConversations;

  DmBloc({
    required DmService dmService,
    required ProfileRepository profileRepository,
  })  : _dmService = dmService,
        _profileRepository = profileRepository,
        super(const DmInitial()) {
    on<DmConversationsLoadRequested>(_onDmConversationsLoadRequested);
    on<DmConversationOpened>(_onDmConversationOpened);
    on<DmMessageSent>(_onDmMessageSent);
    on<DmEncryptedMediaSent>(_onDmEncryptedMediaSent);
    on<DmMessageDeleted>(_onDmMessageDeleted);
    on<DmConversationRefreshed>(_onDmConversationRefreshed);
    on<DmMessagesUpdated>(_onDmMessagesUpdated);
    on<DmMessagesError>(_onDmMessagesError);
    on<DmConversationsUpdated>(_onDmConversationsUpdated);
    on<DmLoadMoreMessagesRequested>(_onDmLoadMoreMessagesRequested);
  }

  void _emitChatState(String pubkeyHex, Emitter<DmState> emit) {
    final total = _fullMessages.length;
    final displayCount =
        total > _chatDisplayLimit ? _chatDisplayLimit : total;
    final displayMessages = total > _chatDisplayLimit
        ? _fullMessages.sublist(total - displayCount)
        : List<Map<String, dynamic>>.from(_fullMessages);
    emit(DmChatLoaded(
      pubkeyHex: pubkeyHex,
      messages: displayMessages,
      hasMore: total > _chatDisplayLimit,
    ));
  }

  void _onDmMessagesUpdated(
    DmMessagesUpdated event,
    Emitter<DmState> emit,
  ) {
    if (event.pubkeyHex != _currentChatPubkeyHex) return;
    _fullMessages = List<Map<String, dynamic>>.from(event.messages);
    _emitChatState(event.pubkeyHex, emit);
  }

  void _onDmMessagesError(
    DmMessagesError event,
    Emitter<DmState> emit,
  ) {
    emit(DmError(event.error));
  }

  Future<void> _onDmConversationsLoadRequested(
    DmConversationsLoadRequested event,
    Emitter<DmState> emit,
  ) async {
    if (state is DmConversationsLoaded) {
      return;
    }

    if (_cachedConversations != null) {
      emit(DmConversationsLoaded(_cachedConversations!));
      _startConversationsPolling();
      return;
    }

    emit(const DmLoading());

    final result = await _dmService.getConversations();

    if (result.isError) {
      emit(DmError(result.error!));
      return;
    }

    final conversations = result.data!;
    final enriched = await _enrichConversations(conversations);
    _cachedConversations = enriched;
    emit(DmConversationsLoaded(enriched));

    _startConversationsPolling();
  }

  void _startConversationsPolling() {
    _conversationsTimer?.cancel();
    _conversationsTimer =
        Timer.periodic(const Duration(seconds: 15), (_) async {
      try {
        final result = await _dmService.getConversations(forceRefresh: true);
        if (result.isSuccess && result.data != null) {
          final enriched = await _enrichConversations(result.data!);
          add(DmConversationsUpdated(enriched));
        }
      } catch (_) {}
    });
  }

  void _onDmConversationsUpdated(
    DmConversationsUpdated event,
    Emitter<DmState> emit,
  ) {
    _cachedConversations = event.conversations;
    if (state is DmConversationsLoaded) {
      emit(DmConversationsLoaded(event.conversations));
    }
  }

  Future<List<Map<String, dynamic>>> _enrichConversations(
      List<Map<String, dynamic>> conversations) async {
    if (conversations.isEmpty) return conversations;

    final pubkeys = conversations
        .map((c) => c['otherUserPubkeyHex'] as String? ?? '')
        .where((p) => p.isNotEmpty)
        .toList();

    if (pubkeys.isEmpty) return conversations;

    final profiles = await _profileRepository.getProfiles(pubkeys);

    return conversations.map((conversation) {
      final otherUserPubkeyHex =
          conversation['otherUserPubkeyHex'] as String? ?? '';
      final profile = profiles[otherUserPubkeyHex];

      if (profile != null) {
        final userName = profile.name ?? '';
        final userProfileImage = profile.picture ?? '';
        final displayName = userName.isNotEmpty
            ? userName
            : (otherUserPubkeyHex.length > 12
                ? otherUserPubkeyHex.substring(0, 12)
                : otherUserPubkeyHex);

        return Map<String, dynamic>.from(conversation)
          ..['otherUserName'] = displayName
          ..['otherUserProfileImage'] = userProfileImage;
      }

      return conversation;
    }).toList();
  }

  Future<void> _onDmConversationOpened(
    DmConversationOpened event,
    Emitter<DmState> emit,
  ) async {
    if (_currentChatPubkeyHex == event.pubkeyHex && state is DmChatLoaded) {
      return;
    }

    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();

    _currentChatPubkeyHex = event.pubkeyHex;
    _chatDisplayLimit = _chatPageSize;
    _fullMessages = [];
    emit(const DmLoading());

    _subscriptions.add(
      _dmService.subscribeToMessages(event.pubkeyHex).listen(
        (messages) {
          add(DmMessagesUpdated(
              pubkeyHex: event.pubkeyHex, messages: messages));
        },
        onError: (error) {
          add(DmMessagesError(error.toString()));
        },
      ),
    );

    final result = await _dmService.getMessages(event.pubkeyHex);
    result.fold(
      (messages) {
        _fullMessages = List<Map<String, dynamic>>.from(messages);
        if (state is! DmChatLoaded ||
            (state as DmChatLoaded).messages.isEmpty) {
          _emitChatState(event.pubkeyHex, emit);
        }
      },
      (error) => emit(DmError(error)),
    );
  }

  void _onDmLoadMoreMessagesRequested(
    DmLoadMoreMessagesRequested event,
    Emitter<DmState> emit,
  ) {
    if (event.pubkeyHex != _currentChatPubkeyHex) return;
    if (_fullMessages.length <= _chatDisplayLimit) return;
    _chatDisplayLimit += _chatPageSize;
    _emitChatState(event.pubkeyHex, emit);
  }

  Future<void> _onDmMessageSent(
    DmMessageSent event,
    Emitter<DmState> emit,
  ) async {
    final result = await _dmService.sendMessage(event.pubkeyHex, event.content);

    result.fold(
      (_) {},
      (error) => emit(DmError(error)),
    );
  }

  Future<void> _onDmEncryptedMediaSent(
    DmEncryptedMediaSent event,
    Emitter<DmState> emit,
  ) async {
    final result = await _dmService.sendEncryptedMediaMessage(
      recipientPubkeyHex: event.recipientPubkeyHex,
      encryptedFileUrl: event.encryptedFileUrl,
      mimeType: event.mimeType,
      encryptionKey: event.encryptionKey,
      encryptionNonce: event.encryptionNonce,
      encryptedHash: event.encryptedHash,
      originalHash: event.originalHash,
      fileSize: event.fileSize,
    );

    result.fold(
      (_) {},
      (error) => emit(DmError(error)),
    );
  }

  void _onDmMessageDeleted(
    DmMessageDeleted event,
    Emitter<DmState> emit,
  ) {
    if (state is DmChatLoaded) {
      final currentState = state as DmChatLoaded;
      _fullMessages.removeWhere((m) {
        final messageId = m['id'] as String? ?? '';
        return messageId.isNotEmpty && messageId == event.messageId;
      });
      final updatedMessages = currentState.messages.where((m) {
        final messageId = m['id'] as String? ?? '';
        return messageId.isNotEmpty && messageId != event.messageId;
      }).toList();
      emit(currentState.copyWith(
        messages: updatedMessages,
        hasMore: _fullMessages.length > _chatDisplayLimit,
      ));
    }
  }

  Future<void> _onDmConversationRefreshed(
    DmConversationRefreshed event,
    Emitter<DmState> emit,
  ) async {
    _currentChatPubkeyHex = null;
    emit(const DmLoading());
    await _onDmConversationOpened(DmConversationOpened(event.pubkeyHex), emit);
  }

  @override
  Future<void> close() {
    _conversationsTimer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    return super.close();
  }
}
