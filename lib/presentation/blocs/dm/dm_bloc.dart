import 'dart:async';
import 'package:bloc/bloc.dart';
import '../../../data/services/dm_service.dart';
import '../../../data/repositories/profile_repository.dart';
import 'dm_event.dart';
import 'dm_state.dart';

class DmBloc extends Bloc<DmEvent, DmState> {
  final DmService _dmService;
  final ProfileRepository _profileRepository;

  final List<StreamSubscription> _subscriptions = [];
  String? _currentChatPubkeyHex;

  DmBloc({
    required DmService dmService,
    required ProfileRepository profileRepository,
  })  : _dmService = dmService,
        _profileRepository = profileRepository,
        super(const DmInitial()) {
    on<DmConversationsLoadRequested>(_onDmConversationsLoadRequested);
    on<DmConversationOpened>(_onDmConversationOpened);
    on<DmMessageSent>(_onDmMessageSent);
    on<DmMessageDeleted>(_onDmMessageDeleted);
    on<DmConversationRefreshed>(_onDmConversationRefreshed);
    on<DmMessagesUpdated>(_onDmMessagesUpdated);
    on<DmMessagesError>(_onDmMessagesError);
  }

  void _onDmMessagesUpdated(
    DmMessagesUpdated event,
    Emitter<DmState> emit,
  ) {
    emit(DmChatLoaded(pubkeyHex: event.pubkeyHex, messages: event.messages));
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

    emit(const DmLoading());

    final result = await _dmService.getConversations();

    if (result.isError) {
      emit(DmError(result.error!));
      return;
    }

    final conversations = result.data!;
    final enriched = await _enrichConversations(conversations);
    emit(DmConversationsLoaded(enriched));
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

    _currentChatPubkeyHex = event.pubkeyHex;
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
        if (state is! DmChatLoaded ||
            (state as DmChatLoaded).messages.isEmpty) {
          emit(DmChatLoaded(pubkeyHex: event.pubkeyHex, messages: messages));
        }
      },
      (error) => emit(DmError(error)),
    );
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

  void _onDmMessageDeleted(
    DmMessageDeleted event,
    Emitter<DmState> emit,
  ) {
    if (state is DmChatLoaded) {
      final currentState = state as DmChatLoaded;
      final updatedMessages = currentState.messages.where((m) {
        final messageId = m['id'] as String? ?? '';
        return messageId.isNotEmpty && messageId != event.messageId;
      }).toList();
      emit(DmChatLoaded(
          pubkeyHex: currentState.pubkeyHex, messages: updatedMessages));
    }
  }

  Future<void> _onDmConversationRefreshed(
    DmConversationRefreshed event,
    Emitter<DmState> emit,
  ) async {
    emit(const DmLoading());
    await _onDmConversationOpened(DmConversationOpened(event.pubkeyHex), emit);
  }

  @override
  Future<void> close() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    return super.close();
  }
}
