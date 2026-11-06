import '../../../core/bloc/base/base_event.dart';

abstract class DmEvent extends BaseEvent {
  const DmEvent();
}

class DmConversationsLoadRequested extends DmEvent {
  const DmConversationsLoadRequested();
}

class DmConversationsRefreshRequested extends DmEvent {
  const DmConversationsRefreshRequested();
}

class DmConversationOpened extends DmEvent {
  final String pubkeyHex;

  const DmConversationOpened(this.pubkeyHex);

  @override
  List<Object?> get props => [pubkeyHex];
}

class DmMessageSent extends DmEvent {
  final String pubkeyHex;
  final String content;

  const DmMessageSent(this.pubkeyHex, this.content);

  @override
  List<Object?> get props => [pubkeyHex, content];
}

class DmMessageDeleted extends DmEvent {
  final String messageId;

  const DmMessageDeleted(this.messageId);

  @override
  List<Object?> get props => [messageId];
}

class DmEncryptedMediaSent extends DmEvent {
  final String recipientPubkeyHex;
  final String encryptedFileUrl;
  final String mimeType;
  final String encryptionKey;
  final String encryptionNonce;
  final String encryptedHash;
  final String originalHash;
  final int fileSize;

  const DmEncryptedMediaSent({
    required this.recipientPubkeyHex,
    required this.encryptedFileUrl,
    required this.mimeType,
    required this.encryptionKey,
    required this.encryptionNonce,
    required this.encryptedHash,
    required this.originalHash,
    required this.fileSize,
  });

  @override
  List<Object?> get props => [
        recipientPubkeyHex,
        encryptedFileUrl,
        mimeType,
        encryptionKey,
        encryptionNonce,
        encryptedHash,
        originalHash,
        fileSize,
      ];
}

class DmConversationRefreshed extends DmEvent {
  final String pubkeyHex;

  const DmConversationRefreshed(this.pubkeyHex);

  @override
  List<Object?> get props => [pubkeyHex];
}

class DmMessagesUpdated extends DmEvent {
  final String pubkeyHex;
  final List<Map<String, dynamic>> messages;
  final int generation;

  const DmMessagesUpdated({
    required this.pubkeyHex,
    required this.messages,
    required this.generation,
  });

  @override
  List<Object?> get props => [pubkeyHex, messages, generation];
}

class DmMessagesError extends DmEvent {
  final String pubkeyHex;
  final String error;
  final int generation;

  const DmMessagesError({
    required this.pubkeyHex,
    required this.error,
    required this.generation,
  });

  @override
  List<Object?> get props => [pubkeyHex, error, generation];
}

class DmConversationsUpdated extends DmEvent {
  final List<Map<String, dynamic>> conversations;
  final String userHex;
  final int generation;

  const DmConversationsUpdated(
    this.conversations,
    this.userHex,
    this.generation,
  );

  @override
  List<Object?> get props => [conversations, userHex, generation];
}

class DmLoadMoreMessagesRequested extends DmEvent {
  final String pubkeyHex;

  const DmLoadMoreMessagesRequested(this.pubkeyHex);

  @override
  List<Object?> get props => [pubkeyHex];
}
