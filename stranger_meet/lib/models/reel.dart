import '../utils/date_utils.dart';

class Reel {
  final String id;
  final String userId;
  final String userName;
  final String? userImage;
  final String mediaUrl;
  final String mediaType; // 'image' or 'video'
  final String caption;
  final int likesCount;
  final bool isLiked;
  final int commentsCount;
  final DateTime? createdAt;

  Reel({
    required this.id,
    required this.userId,
    required this.userName,
    this.userImage,
    required this.mediaUrl,
    this.mediaType = 'image',
    required this.caption,
    this.likesCount = 0,
    this.isLiked = false,
    this.commentsCount = 0,
    this.createdAt,
  });

  factory Reel.fromJson(Map<String, dynamic> json) {
    return Reel(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      userName: json['user_name'] ?? json['userName'] ?? '',
      userImage: json['user_image'] ?? json['userImage'],
      mediaUrl: json['media_url'] ?? json['mediaUrl'] ?? '',
      mediaType: json['media_type'] ?? json['mediaType'] ?? 'image',
      caption: json['caption'] ?? '',
      likesCount: json['likes_count'] ?? json['likesCount'] ?? 0,
      isLiked: json['is_liked'] ?? json['isLiked'] ?? false,
      commentsCount: json['comments_count'] ?? json['commentsCount'] ?? 0,
      createdAt: parseUtcToLocal(json['created_at']) ?? parseUtcToLocal(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'user_name': userName,
      'user_image': userImage,
      'media_url': mediaUrl,
      'media_type': mediaType,
      'caption': caption,
      'likes_count': likesCount,
      'is_liked': isLiked,
      'comments_count': commentsCount,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  Reel copyWith({
    String? id,
    String? userId,
    String? userName,
    String? userImage,
    String? mediaUrl,
    String? mediaType,
    String? caption,
    int? likesCount,
    bool? isLiked,
    int? commentsCount,
    DateTime? createdAt,
  }) {
    return Reel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userImage: userImage ?? this.userImage,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaType: mediaType ?? this.mediaType,
      caption: caption ?? this.caption,
      likesCount: likesCount ?? this.likesCount,
      isLiked: isLiked ?? this.isLiked,
      commentsCount: commentsCount ?? this.commentsCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
