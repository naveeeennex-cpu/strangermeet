import '../utils/date_utils.dart';

class Message {
  final String id;
  final String senderId;
  final String receiverId;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final String imageUrl;
  final String messageType;

  Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.message,
    required this.timestamp,
    this.isRead = false,
    this.imageUrl = '',
    this.messageType = 'text',
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      senderId:
          json['sender_id']?.toString() ?? json['senderId']?.toString() ?? '',
      receiverId: json['receiver_id']?.toString() ??
          json['receiverId']?.toString() ??
          '',
      message: json['message'] ?? json['content'] ?? '',
      timestamp: parseUtcToLocal(json['timestamp']) ?? parseUtcToLocal(json['created_at']) ?? DateTime.now(),
      isRead: json['is_read'] ?? json['isRead'] ?? false,
      imageUrl: json['image_url'] ?? json['imageUrl'] ?? '',
      messageType: json['message_type'] ?? json['messageType'] ?? 'text',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'is_read': isRead,
      'image_url': imageUrl,
      'message_type': messageType,
    };
  }
}

class Conversation {
  final String type; // 'dm' or 'community'
  final String userId;
  final String userName;
  final String? userImage;
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;
  final bool isSubgroup;
  final String? communityName;
  final String? communityId;

  Conversation({
    this.type = 'dm',
    required this.userId,
    required this.userName,
    this.userImage,
    required this.lastMessage,
    required this.lastMessageTime,
    this.unreadCount = 0,
    this.isSubgroup = false,
    this.communityName,
    this.communityId,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      type: json['type'] ?? 'dm',
      userId:
          json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      userName: json['user_name'] ?? json['userName'] ?? '',
      userImage: json['user_image'] ?? json['userImage'],
      lastMessage: json['last_message'] ?? json['lastMessage'] ?? json['message'] ?? '',
      lastMessageTime: parseUtcToLocal(json['last_message_time']) ?? parseUtcToLocal(json['lastMessageTime']) ?? parseUtcToLocal(json['timestamp']) ?? DateTime.now(),
      unreadCount: json['unread_count'] ?? json['unreadCount'] ?? 0,
      isSubgroup: json['is_subgroup'] == true,
      communityName: json['community_name'],
      communityId: json['community_id']?.toString(),
    );
  }

  bool get isCommunity => type == 'community';
}
