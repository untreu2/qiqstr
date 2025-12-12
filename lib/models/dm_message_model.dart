import 'package:nostr_nip19/nostr_nip19.dart';

class DmMessageModel {
  final String id;
  final String senderPubkeyHex;
  final String recipientPubkeyHex;
  final String content;
  final DateTime createdAt;
  final bool isFromCurrentUser;

  DmMessageModel({
    required this.id,
    required this.senderPubkeyHex,
    required this.recipientPubkeyHex,
    required this.content,
    required this.createdAt,
    required this.isFromCurrentUser,
  });

  String get senderNpub {
    try {
      if (senderPubkeyHex.startsWith('npub1')) {
        return senderPubkeyHex;
      }
      return encodeBasicBech32(senderPubkeyHex, 'npub');
    } catch (e) {
      return senderPubkeyHex;
    }
  }

  String get recipientNpub {
    try {
      if (recipientPubkeyHex.startsWith('npub1')) {
        return recipientPubkeyHex;
      }
      return encodeBasicBech32(recipientPubkeyHex, 'npub');
    } catch (e) {
      return recipientPubkeyHex;
    }
  }

  factory DmMessageModel.fromJson(Map<String, dynamic> json) {
    return DmMessageModel(
      id: json['id'] as String,
      senderPubkeyHex: json['senderPubkeyHex'] as String,
      recipientPubkeyHex: json['recipientPubkeyHex'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      isFromCurrentUser: json['isFromCurrentUser'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderPubkeyHex': senderPubkeyHex,
        'recipientPubkeyHex': recipientPubkeyHex,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'isFromCurrentUser': isFromCurrentUser,
      };
}

class DmConversationModel {
  final String otherUserPubkeyHex;
  final String? otherUserName;
  final String? otherUserProfileImage;
  final DmMessageModel? lastMessage;
  final int unreadCount;
  final DateTime? lastMessageTime;

  DmConversationModel({
    required this.otherUserPubkeyHex,
    this.otherUserName,
    this.otherUserProfileImage,
    this.lastMessage,
    this.unreadCount = 0,
    this.lastMessageTime,
  });

  String get otherUserNpub {
    try {
      if (otherUserPubkeyHex.startsWith('npub1')) {
        return otherUserPubkeyHex;
      }
      return encodeBasicBech32(otherUserPubkeyHex, 'npub');
    } catch (e) {
      return otherUserPubkeyHex;
    }
  }

  String get displayName => otherUserName ?? 'Anonymous';

  factory DmConversationModel.fromJson(Map<String, dynamic> json) {
    return DmConversationModel(
      otherUserPubkeyHex: json['otherUserPubkeyHex'] as String,
      otherUserName: json['otherUserName'] as String?,
      otherUserProfileImage: json['otherUserProfileImage'] as String?,
      lastMessage: json['lastMessage'] != null
          ? DmMessageModel.fromJson(json['lastMessage'] as Map<String, dynamic>)
          : null,
      unreadCount: json['unreadCount'] as int? ?? 0,
      lastMessageTime: json['lastMessageTime'] != null
          ? DateTime.parse(json['lastMessageTime'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'otherUserPubkeyHex': otherUserPubkeyHex,
        'otherUserName': otherUserName,
        'otherUserProfileImage': otherUserProfileImage,
        'lastMessage': lastMessage?.toJson(),
        'unreadCount': unreadCount,
        'lastMessageTime': lastMessageTime?.toIso8601String(),
      };
}



