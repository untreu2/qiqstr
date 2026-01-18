import 'dart:async';
import 'package:bloc/bloc.dart';
import '../../../data/repositories/dm_repository.dart';
import '../../../data/repositories/auth_repository.dart';
import 'dm_event.dart';
import 'dm_state.dart';

class DmBloc extends Bloc<DmEvent, DmState> {
  final DmRepository _dmRepository;

  final List<StreamSubscription> _subscriptions = [];
  String? _currentChatPubkeyHex;

  DmBloc({
    required DmRepository dmRepository,
    required AuthRepository authRepository,
  })  : _dmRepository = dmRepository,
        super(const DmInitial()) {
    on<DmConversationsLoadRequested>(_onDmConversationsLoadRequested);
    on<DmConversationOpened>(_onDmConversationOpened);
    on<DmMessageSent>(_onDmMessageSent);
    on<DmMessageDeleted>(_onDmMessageDeleted);
    on<DmConversationRefreshed>(_onDmConversationRefreshed);
    on<DmConversationsUpdated>(_onDmConversationsUpdated);
    on<DmMessagesUpdated>(_onDmMessagesUpdated);
    on<DmMessagesError>(_onDmMessagesError);

    _subscribeToConversations();
  }

  void _subscribeToConversations() {
    _subscriptions.add(
      _dmRepository.conversationsStream.listen((conversations) {
        if (state is! DmChatLoaded) {
          add(DmConversationsUpdated(conversations));
        }
      }),
    );
  }

  void _onDmConversationsUpdated(
    DmConversationsUpdated event,
    Emitter<DmState> emit,
  ) {
    emit(DmConversationsLoaded(event.conversations));
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

    final result = await _dmRepository.getConversations();

    result.fold(
      (conversations) => emit(DmConversationsLoaded(conversations)),
      (error) => emit(DmError(error)),
    );
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
      _dmRepository.subscribeToMessages(event.pubkeyHex).listen(
        (messages) {
          add(DmMessagesUpdated(pubkeyHex: event.pubkeyHex, messages: messages));
        },
        onError: (error) {
          add(DmMessagesError(error.toString()));
        },
      ),
    );

    final result = await _dmRepository.getMessages(event.pubkeyHex);
    result.fold(
      (messages) {
        if (state is! DmChatLoaded || (state as DmChatLoaded).messages.isEmpty) {
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
    final result = await _dmRepository.sendMessage(event.pubkeyHex, event.content);

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
      emit(DmChatLoaded(pubkeyHex: currentState.pubkeyHex, messages: updatedMessages));
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
