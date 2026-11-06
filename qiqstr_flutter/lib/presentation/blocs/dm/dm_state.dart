import '../../../core/bloc/base/base_state.dart';

abstract class DmState extends BaseState {
  const DmState();
}

class DmInitial extends DmState {
  const DmInitial();
}

class DmLoading extends DmState {
  const DmLoading();
}

class DmConversationsLoaded extends DmState {
  final List<Map<String, dynamic>> conversations;

  const DmConversationsLoaded(this.conversations);

  @override
  List<Object?> get props => [conversations];
}

class DmChatLoaded extends DmState {
  final String pubkeyHex;
  final List<Map<String, dynamic>> messages;
  final bool hasMore;
  final bool isLoadingMore;

  const DmChatLoaded({
    required this.pubkeyHex,
    required this.messages,
    this.hasMore = false,
    this.isLoadingMore = false,
  });

  DmChatLoaded copyWith({
    List<Map<String, dynamic>>? messages,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return DmChatLoaded(
      pubkeyHex: pubkeyHex,
      messages: messages ?? this.messages,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }

  @override
  List<Object?> get props => [pubkeyHex, messages, hasMore, isLoadingMore];
}

class DmError extends DmState {
  final String message;

  const DmError(this.message);

  @override
  List<Object?> get props => [message];
}
