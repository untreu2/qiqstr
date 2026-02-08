import '../../../core/bloc/base/base_event.dart';

abstract class DmEvent extends BaseEvent {
  const DmEvent();
}

class DmConversationsLoadRequested extends DmEvent {
  const DmConversationsLoadRequested();
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

  const DmMessagesUpdated({required this.pubkeyHex, required this.messages});

  @override
  List<Object?> get props => [pubkeyHex, messages];
}

class DmMessagesError extends DmEvent {
  final String error;

  const DmMessagesError(this.error);

  @override
  List<Object?> get props => [error];
}

class DmConversationsUpdated extends DmEvent {
  final List<Map<String, dynamic>> conversations;

  const DmConversationsUpdated(this.conversations);

  @override
  List<Object?> get props => [conversations];
}
