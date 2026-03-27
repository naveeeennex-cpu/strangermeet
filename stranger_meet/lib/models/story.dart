import '../utils/date_utils.dart';

class Story {
  final String id;
  final String userId;
  final String userName;
  final String? userImage;
  final String imageUrl;
  final String caption;
  final String mediaType; // 'image' or 'video'
  final String? videoUrl;
  final int viewsCount;
  final bool isViewed;
  final DateTime createdAt;
  final DateTime expiresAt;

  Story({
    required this.id,
    required this.userId,
    required this.userName,
    this.userImage,
    required this.imageUrl,
    this.caption = '',
    this.mediaType = 'image',
    this.videoUrl,
    this.viewsCount = 0,
    this.isViewed = false,
    required this.createdAt,
    required this.expiresAt,
  });

  factory Story.fromJson(Map<String, dynamic> json) {
    return Story(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      userName: json['user_name'] ?? json['userName'] ?? '',
      userImage: json['user_image'] ?? json['userImage'],
      imageUrl: json['image_url'] ?? json['imageUrl'] ?? '',
      caption: json['caption'] ?? '',
      mediaType: json['media_type'] ?? json['mediaType'] ?? 'image',
      videoUrl: json['video_url'] ?? json['videoUrl'],
      viewsCount: json['views_count'] ?? json['viewsCount'] ?? 0,
      isViewed: json['is_viewed'] ?? json['isViewed'] ?? false,
      createdAt: parseUtcToLocal(json['created_at']) ?? parseUtcToLocal(json['createdAt']) ?? DateTime.now(),
      expiresAt: parseUtcToLocal(json['expires_at']) ?? parseUtcToLocal(json['expiresAt']) ?? DateTime.now().add(const Duration(hours: 24)),
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
      'views_count': viewsCount,
      'is_viewed': isViewed,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
    };
  }
}

class UserStories {
  final String userId;
  final String userName;
  final String? userImage;
  final List<Story> stories;
  final bool hasUnviewed;

  UserStories({
    required this.userId,
    required this.userName,
    this.userImage,
    this.stories = const [],
    this.hasUnviewed = true,
  });

  factory UserStories.fromJson(Map<String, dynamic> json) {
    return UserStories(
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      userName: json['user_name'] ?? json['userName'] ?? '',
      userImage: json['user_image'] ?? json['userImage'],
      stories: (json['stories'] as List<dynamic>?)
              ?.map((e) => Story.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      hasUnviewed: json['has_unviewed'] ?? json['hasUnviewed'] ?? true,
    );
  }
}

class StoryReply {
  final String id;
  final String storyId;
  final String userId;
  final String userName;
  final String? userImage;
  final String message;
  final DateTime createdAt;

  StoryReply({
    required this.id,
    required this.storyId,
    required this.userId,
    required this.userName,
    this.userImage,
    required this.message,
    required this.createdAt,
  });

  factory StoryReply.fromJson(Map<String, dynamic> json) {
    return StoryReply(
      id: json['id']?.toString() ?? '',
      storyId:
          json['story_id']?.toString() ?? json['storyId']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      userName: json['user_name'] ?? json['userName'] ?? '',
      userImage: json['user_image'] ?? json['userImage'],
      message: json['message'] ?? '',
      createdAt: parseUtcToLocal(json['created_at']) ?? parseUtcToLocal(json['createdAt']) ?? DateTime.now(),
    );
  }
}
