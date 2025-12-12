import 'dart:async';
import '../../core/base/base_view_model.dart';
import '../../core/base/ui_state.dart';
import '../../core/base/app_error.dart';
import '../../data/repositories/dm_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../models/dm_message_model.dart';

class DmViewModel extends BaseViewModel {
  final DmRepository _dmRepository;

  DmViewModel({
    required DmRepository dmRepository,
    required AuthRepository authRepository,
  }) : _dmRepository = dmRepository;

  UIState<List<DmConversationModel>> _conversationsState = const InitialState();
  UIState<List<DmConversationModel>> get conversationsState => _conversationsState;

  UIState<List<DmMessageModel>> _messagesState = const InitialState();
  UIState<List<DmMessageModel>> get messagesState => _messagesState;

  String? _currentChatPubkeyHex;
  String? get currentChatPubkeyHex => _currentChatPubkeyHex;

  StreamSubscription<List<DmMessageModel>>? _messagesSubscription;
  StreamSubscription<List<DmConversationModel>>? _conversationsSubscription;

  @override
  void initialize() {
    super.initialize();

    _conversationsSubscription = _dmRepository.conversationsStream.listen((conversations) {
      _conversationsState = LoadedState(conversations);
      safeNotifyListeners();
    });
  }

  Future<void> loadConversations() async {
    if (_conversationsState is LoadedState) {
      return;
    }

    if (_conversationsState is! LoadingState) {
      _conversationsState = const LoadingState();
      safeNotifyListeners();
    }

    final result = await _dmRepository.getConversations();

    result.fold(
      (conversations) {
        _conversationsState = LoadedState(conversations);
        safeNotifyListeners();
      },
      (error) {
        _conversationsState = ErrorState(error);
        safeNotifyListeners();
      },
    );
  }

  Future<void> refreshConversations() async {
    _conversationsState = const LoadingState();
    safeNotifyListeners();
    await loadConversations();
  }

  Future<void> loadMessages(String otherUserPubkeyHex) async {
    if (_currentChatPubkeyHex == otherUserPubkeyHex && _messagesState is LoadedState) {
      return;
    }

    _currentChatPubkeyHex = otherUserPubkeyHex;
    _messagesState = const LoadingState();
    safeNotifyListeners();

    _messagesSubscription?.cancel();
    _messagesSubscription = null;

    DateTime? latestTs;

    _messagesSubscription = _dmRepository.subscribeToMessages(otherUserPubkeyHex).listen(
      (messages) {
        if (messages.isNotEmpty) {
          latestTs = messages.last.createdAt;
        }
        _messagesState = LoadedState(messages);
        safeNotifyListeners();
      },
      onError: (error) {
        setError(UnknownError(message: error.toString()));
        safeNotifyListeners();
      },
    );

    final result = await _dmRepository.getMessages(otherUserPubkeyHex);
    result.fold(
      (messages) {
        // Only update if we don't already have newer data from the live stream
        final hasNewerLiveData = latestTs != null &&
            messages.isNotEmpty &&
            messages.last.createdAt.isBefore(latestTs!);
        if (!hasNewerLiveData) {
          _messagesState = LoadedState(messages);
          safeNotifyListeners();
        }
      },
      (error) {
        setError(UnknownError(message: error));
        safeNotifyListeners();
      },
    );
  }

  Future<void> sendMessage(String recipientPubkeyHex, String content) async {
    if (content.trim().isEmpty) {
      return;
    }

    final result = await _dmRepository.sendMessage(recipientPubkeyHex, content.trim());

    result.fold(
      (_) {
      },
      (error) {
        setError(UnknownError(message: error));
      },
    );
  }

  void clearCurrentChat() {
    _currentChatPubkeyHex = null;
    _messagesSubscription?.cancel();
    _messagesSubscription = null;
    _messagesState = const InitialState();
    safeNotifyListeners();
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    _conversationsSubscription?.cancel();
    super.dispose();
  }
}

