import '../utils/date_utils.dart';

class Post {
  final String id;
  final String userId;
  final String userName;
  final String? userImage;
  final String? imageUrl;
  final String caption;
  final String mediaType; // 'image', 'video', 'text'
  final String? videoUrl;
  final int likesCount;
  final bool isLiked;
  final int commentsCount;
  final DateTime? createdAt;
  final String? communityId;
  final String? communityName;

  Post({
    required this.id,
    required this.userId,
    required this.userName,
    this.userImage,
    this.imageUrl,
    required this.caption,
    this.mediaType = 'image',
    this.videoUrl,
    this.likesCount = 0,
    this.isLiked = false,
    this.commentsCount = 0,
    this.createdAt,
    this.communityId,
    this.communityName,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      userName: json['user_name'] ?? json['userName'] ?? '',
      userImage: json['user_profile_image'] ?? json['user_image'] ?? json['userImage'],
      imageUrl: json['image_url'] ?? json['imageUrl'],
      caption: json['caption'] ?? '',
      mediaType: json['media_type'] ?? json['mediaType'] ?? 'image',
      videoUrl: json['video_url'] ?? json['videoUrl'],
      likesCount: json['likes_count'] ?? json['likesCount'] ?? 0,
      isLiked: json['is_liked'] ?? json['isLiked'] ?? false,
      commentsCount: json['comments_count'] ?? json['commentsCount'] ?? 0,
      createdAt: parseUtcToLocal(json['created_at']) ?? parseUtcToLocal(json['createdAt']),
      communityId: json['community_id']?.toString(),
      communityName: json['community_name']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'user_name': userName,
      'user_image': userImage,
      'image_url': imageUrl,
      'caption': caption,
      'media_type': mediaType,
      'video_url': videoUrl,
      'likes_count': likesCount,
      'is_liked': isLiked,
      'comments_count': commentsCount,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  Post copyWith({
    String? id,
    String? userId,
    String? userName,
    String? userImage,
    String? imageUrl,
    String? caption,
    String? mediaType,
    String? videoUrl,
    int? likesCount,
    bool? isLiked,
    int? commentsCount,
    DateTime? createdAt,
    String? communityId,
    String? communityName,
  }) {
    return Post(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userImage: userImage ?? this.userImage,
      imageUrl: imageUrl ?? this.imageUrl,
      caption: caption ?? this.caption,
      mediaType: mediaType ?? this.mediaType,
      videoUrl: videoUrl ?? this.videoUrl,
      likesCount: likesCount ?? this.likesCount,
      isLiked: isLiked ?? this.isLiked,
      commentsCount: commentsCount ?? this.commentsCount,
      createdAt: createdAt ?? this.createdAt,
      communityId: communityId ?? this.communityId,
      communityName: communityName ?? this.communityName,
    );
  }
}

class Comment {
  final String id;
  final String postId;
  final String userId;
  final String userName;
  final String? userProfileImage;
  final String text;
  final int likesCount;
  final bool isLiked;
  final int repliesCount;
  final DateTime? createdAt;

  Comment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.userName,
    this.userProfileImage,
    required this.text,
    this.likesCount = 0,
    this.isLiked = false,
    this.repliesCount = 0,
    this.createdAt,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      postId: json['post_id']?.toString() ?? json['postId']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      userName: json['user_name'] ?? json['userName'] ?? '',
      userProfileImage: json['user_profile_image'] ?? json['userProfileImage'],
      text: json['text'] ?? json['content'] ?? '',
      likesCount: json['likes_count'] ?? json['likesCount'] ?? 0,
      isLiked: json['is_liked'] ?? json['isLiked'] ?? false,
      repliesCount: json['replies_count'] ?? json['repliesCount'] ?? 0,
      createdAt: parseUtcToLocal(json['created_at']) ?? parseUtcToLocal(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'post_id': postId,
      'user_id': userId,
      'user_name': userName,
      'user_profile_image': userProfileImage,
      'text': text,
      'likes_count': likesCount,
      'is_liked': isLiked,
      'replies_count': repliesCount,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  Comment copyWith({
    String? id,
    String? postId,
    String? userId,
    String? userName,
    String? userProfileImage,
    String? text,
    int? likesCount,
    bool? isLiked,
    int? repliesCount,
    DateTime? createdAt,
  }) {
    return Comment(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userProfileImage: userProfileImage ?? this.userProfileImage,
      text: text ?? this.text,
      likesCount: likesCount ?? this.likesCount,
      isLiked: isLiked ?? this.isLiked,
      repliesCount: repliesCount ?? this.repliesCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class CommentReply {
  final String id;
  final String commentId;
  final String userId;
  final String userName;
  final String? userProfileImage;
  final String text;
  final DateTime? createdAt;

  CommentReply({
    required this.id,
    required this.commentId,
    required this.userId,
    required this.userName,
    this.userProfileImage,
    required this.text,
    this.createdAt,
  });

  factory CommentReply.fromJson(Map<String, dynamic> json) {
    return CommentReply(
      id: json['id']?.toString() ?? '',
      commentId: json['comment_id']?.toString() ?? json['commentId']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      userName: json['user_name'] ?? json['userName'] ?? '',
      userProfileImage: json['user_profile_image'] ?? json['userProfileImage'],
      text: json['text'] ?? '',
      createdAt: parseUtcToLocal(json['created_at']) ?? parseUtcToLocal(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'comment_id': commentId,
      'user_id': userId,
      'user_name': userName,
      'user_profile_image': userProfileImage,
      'text': text,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
