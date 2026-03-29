import '../utils/date_utils.dart';

class Community {
  final String id;
  final String name;
  final String description;
  final String? imageUrl;
  final String category;
  final bool isPrivate;
  final String createdBy;
  final String? creatorName;
  final int membersCount;
  final bool isMember;
  final String? memberRole; // 'admin', 'member', null
  final DateTime? createdAt;

  Community({
    required this.id,
    required this.name,
    required this.description,
    this.imageUrl,
    this.category = 'General',
    this.isPrivate = false,
    required this.createdBy,
    this.creatorName,
    this.membersCount = 0,
    this.isMember = false,
    this.memberRole,
    this.createdAt,
  });

  factory Community.fromJson(Map<String, dynamic> json) {
    return Community(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      imageUrl: json['image_url'] ?? json['imageUrl'],
      category: json['category'] ?? 'General',
      isPrivate: json['is_private'] ?? json['isPrivate'] ?? false,
      createdBy: json['created_by']?.toString() ?? json['createdBy']?.toString() ?? '',
      creatorName: json['creator_name'] ?? json['creatorName'],
      membersCount: json['members_count'] ?? json['membersCount'] ?? 0,
      isMember: json['is_member'] ?? json['isMember'] ?? false,
      memberRole: json['member_role'] ?? json['memberRole'],
      createdAt: parseUtcToLocal(json['created_at']) ?? parseUtcToLocal(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'image_url': imageUrl,
      'category': category,
      'is_private': isPrivate,
      'created_by': createdBy,
      'creator_name': creatorName,
      'members_count': membersCount,
      'is_member': isMember,
      'member_role': memberRole,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  Community copyWith({
    String? id,
    String? name,
    String? description,
    String? imageUrl,
    String? category,
    bool? isPrivate,
    String? createdBy,
    String? creatorName,
    int? membersCount,
    bool? isMember,
    String? memberRole,
    DateTime? createdAt,
  }) {
    return Community(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      category: category ?? this.category,
      isPrivate: isPrivate ?? this.isPrivate,
      createdBy: createdBy ?? this.createdBy,
      creatorName: creatorName ?? this.creatorName,
      membersCount: membersCount ?? this.membersCount,
      isMember: isMember ?? this.isMember,
      memberRole: memberRole ?? this.memberRole,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class SubGroup {
  final String id;
  final String communityId;
  final String name;
  final String description;
  final String type; // 'gym', 'trip', 'meetup', 'online_meet', 'general'
  final bool isPrivate;
  final int membersCount;
  final bool isMember;
  final String? memberStatus; // 'active', 'pending', null
  final DateTime? createdAt;

  SubGroup({
    required this.id,
    required this.communityId,
    required this.name,
    required this.description,
    this.type = 'general',
    this.isPrivate = false,
    this.membersCount = 0,
    this.isMember = false,
    this.memberStatus,
    this.createdAt,
  });

  bool get isPending => memberStatus == 'pending';

  factory SubGroup.fromJson(Map<String, dynamic> json) {
    return SubGroup(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      communityId: json['community_id']?.toString() ?? json['communityId']?.toString() ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      type: json['type'] ?? 'general',
      isPrivate: json['is_private'] ?? json['isPrivate'] ?? false,
      membersCount: json['members_count'] ?? json['membersCount'] ?? 0,
      isMember: json['is_member'] ?? json['isMember'] ?? false,
      memberStatus: json['member_status'] ?? json['memberStatus'],
      createdAt: parseUtcToLocal(json['created_at']) ?? parseUtcToLocal(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'community_id': communityId,
      'name': name,
      'description': description,
      'type': type,
      'is_private': isPrivate,
      'members_count': membersCount,
      'is_member': isMember,
      'member_status': memberStatus,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  SubGroup copyWith({
    String? id,
    String? communityId,
    String? name,
    String? description,
    String? type,
    bool? isPrivate,
    int? membersCount,
    bool? isMember,
    String? memberStatus,
    DateTime? createdAt,
  }) {
    return SubGroup(
      id: id ?? this.id,
      communityId: communityId ?? this.communityId,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      isPrivate: isPrivate ?? this.isPrivate,
      membersCount: membersCount ?? this.membersCount,
      isMember: isMember ?? this.isMember,
      memberStatus: memberStatus ?? this.memberStatus,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class CommunityMessage {
  final String id;
  final String communityId;
  final String userId;
  final String userName;
  final String? userImage;
  final String message;
  final DateTime? timestamp;
  final String imageUrl;
  final String messageType;

  CommunityMessage({
    required this.id,
    required this.communityId,
    required this.userId,
    required this.userName,
    this.userImage,
    required this.message,
    this.timestamp,
    this.imageUrl = '',
    this.messageType = 'text',
  });

  factory CommunityMessage.fromJson(Map<String, dynamic> json) {
    return CommunityMessage(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      communityId: json['community_id']?.toString() ?? json['sub_group_id']?.toString() ?? json['communityId']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      userName: json['user_name'] ?? json['userName'] ?? '',
      userImage: json['user_profile_image'] ?? json['user_image'] ?? json['userImage'],
      message: json['message'] ?? json['content'] ?? '',
      timestamp: parseUtcToLocal(json['timestamp']) ?? parseUtcToLocal(json['created_at']),
      imageUrl: json['image_url'] ?? json['imageUrl'] ?? '',
      messageType: json['message_type'] ?? json['messageType'] ?? 'text',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'community_id': communityId,
      'user_id': userId,
      'user_name': userName,
      'user_image': userImage,
      'message': message,
      'timestamp': timestamp?.toIso8601String(),
      'image_url': imageUrl,
      'message_type': messageType,
    };
  }

  CommunityMessage copyWith({
    String? id,
    String? communityId,
    String? userId,
    String? userName,
    String? userImage,
    String? message,
    DateTime? timestamp,
    String? imageUrl,
    String? messageType,
  }) {
    return CommunityMessage(
      id: id ?? this.id,
      communityId: communityId ?? this.communityId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userImage: userImage ?? this.userImage,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      imageUrl: imageUrl ?? this.imageUrl,
      messageType: messageType ?? this.messageType,
    );
  }
}

class CommunityEvent {
  final String id;
  final String communityId;
  final String title;
  final String description;
  final String location;
  final DateTime date;
  final double price;
  final int slots;
  final String? imageUrl;
  final int participantsCount;
  final bool isJoined;
  final String eventType;
  final int durationDays;
  final String difficulty;
  final List<String> includes;
  final List<String> excludes;
  final String meetingPoint;
  final DateTime? endDate;
  final double maxAltitude;
  final double totalDistance;
  final String? communityName;
  final String? communityImage;
  final bool isPast;
  final DateTime? createdAt;

  CommunityEvent({
    required this.id,
    required this.communityId,
    required this.title,
    required this.description,
    this.location = '',
    required this.date,
    this.price = 0.0,
    this.slots = 0,
    this.imageUrl,
    this.participantsCount = 0,
    this.isJoined = false,
    this.eventType = 'event',
    this.durationDays = 1,
    this.difficulty = 'easy',
    this.includes = const [],
    this.excludes = const [],
    this.meetingPoint = '',
    this.endDate,
    this.maxAltitude = 0,
    this.totalDistance = 0,
    this.communityName,
    this.communityImage,
    this.isPast = false,
    this.createdAt,
  });

  bool get isTrip => eventType == 'trip';

  String get durationLabel {
    if (durationDays <= 1) return '1 Day';
    return '$durationDays Days / ${durationDays - 1} Nights';
  }

  String get shortDurationLabel {
    if (durationDays <= 1) return '1D';
    return '${durationDays}D/${durationDays - 1}N';
  }

  factory CommunityEvent.fromJson(Map<String, dynamic> json) {
    return CommunityEvent(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      communityId: json['community_id']?.toString() ?? json['communityId']?.toString() ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      location: json['location'] ?? '',
      date: parseUtcToLocal(json['date']) ?? DateTime.now(),
      price: (json['price'] ?? 0).toDouble(),
      slots: json['slots'] ?? 0,
      imageUrl: json['image_url'] ?? json['imageUrl'],
      participantsCount: json['participants_count'] ?? json['participantsCount'] ?? 0,
      isJoined: json['is_joined'] ?? json['isJoined'] ?? false,
      eventType: json['event_type'] ?? json['eventType'] ?? 'event',
      durationDays: json['duration_days'] ?? json['durationDays'] ?? 1,
      difficulty: json['difficulty'] ?? 'easy',
      includes: List<String>.from(json['includes'] ?? []),
      excludes: List<String>.from(json['excludes'] ?? []),
      meetingPoint: json['meeting_point'] ?? json['meetingPoint'] ?? '',
      endDate: parseUtcToLocal(json['end_date']) ?? parseUtcToLocal(json['endDate']),
      maxAltitude: (json['max_altitude_m'] ?? json['maxAltitude'] ?? 0).toDouble(),
      totalDistance: (json['total_distance_km'] ?? json['totalDistance'] ?? 0).toDouble(),
      communityName: json['community_name'] ?? json['communityName'],
      communityImage: json['community_image'] ?? json['communityImage'],
      isPast: json['is_past'] ?? json['isPast'] ?? false,
      createdAt: parseUtcToLocal(json['created_at']) ?? parseUtcToLocal(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'community_id': communityId,
      'title': title,
      'description': description,
      'location': location,
      'date': date.toIso8601String(),
      'price': price,
      'slots': slots,
      'image_url': imageUrl,
      'participants_count': participantsCount,
      'is_joined': isJoined,
      'event_type': eventType,
      'duration_days': durationDays,
      'difficulty': difficulty,
      'includes': includes,
      'excludes': excludes,
      'meeting_point': meetingPoint,
      'end_date': endDate?.toIso8601String(),
      'max_altitude_m': maxAltitude,
      'total_distance_km': totalDistance,
      'is_past': isPast,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  CommunityEvent copyWith({
    String? id,
    String? communityId,
    String? title,
    String? description,
    String? location,
    DateTime? date,
    double? price,
    int? slots,
    String? imageUrl,
    int? participantsCount,
    bool? isJoined,
    String? eventType,
    int? durationDays,
    String? difficulty,
    List<String>? includes,
    List<String>? excludes,
    String? meetingPoint,
    DateTime? endDate,
    double? maxAltitude,
    double? totalDistance,
    bool? isPast,
    DateTime? createdAt,
  }) {
    return CommunityEvent(
      id: id ?? this.id,
      communityId: communityId ?? this.communityId,
      title: title ?? this.title,
      description: description ?? this.description,
      location: location ?? this.location,
      date: date ?? this.date,
      price: price ?? this.price,
      slots: slots ?? this.slots,
      imageUrl: imageUrl ?? this.imageUrl,
      participantsCount: participantsCount ?? this.participantsCount,
      isJoined: isJoined ?? this.isJoined,
      eventType: eventType ?? this.eventType,
      durationDays: durationDays ?? this.durationDays,
      difficulty: difficulty ?? this.difficulty,
      includes: includes ?? this.includes,
      excludes: excludes ?? this.excludes,
      meetingPoint: meetingPoint ?? this.meetingPoint,
      endDate: endDate ?? this.endDate,
      maxAltitude: maxAltitude ?? this.maxAltitude,
      totalDistance: totalDistance ?? this.totalDistance,
      isPast: isPast ?? this.isPast,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class ItineraryDay {
  final String id;
  final String eventId;
  final int dayNumber;
  final String title;
  final String description;
  final List<String> activities;
  final List<String> mealsIncluded;
  final String accommodation;
  final double distanceKm;
  final double elevationM;

  ItineraryDay({
    required this.id,
    required this.eventId,
    required this.dayNumber,
    required this.title,
    this.description = '',
    this.activities = const [],
    this.mealsIncluded = const [],
    this.accommodation = '',
    this.distanceKm = 0,
    this.elevationM = 0,
  });

  factory ItineraryDay.fromJson(Map<String, dynamic> json) {
    return ItineraryDay(
      id: json['id']?.toString() ?? '',
      eventId: json['event_id']?.toString() ?? json['eventId']?.toString() ?? '',
      dayNumber: json['day_number'] ?? json['dayNumber'] ?? 0,
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      activities: List<String>.from(json['activities'] ?? []),
      mealsIncluded: List<String>.from(json['meals_included'] ?? json['mealsIncluded'] ?? []),
      accommodation: json['accommodation'] ?? '',
      distanceKm: (json['distance_km'] ?? json['distanceKm'] ?? 0).toDouble(),
      elevationM: (json['elevation_m'] ?? json['elevationM'] ?? 0).toDouble(),
    );
  }
}

class EventParticipant {
  final String userId;
  final String? userName;
  final String? userProfileImage;
  final DateTime? bookedAt;

  EventParticipant({
    required this.userId,
    this.userName,
    this.userProfileImage,
    this.bookedAt,
  });

  factory EventParticipant.fromJson(Map<String, dynamic> json) {
    return EventParticipant(
      userId: json['user_id']?.toString() ?? '',
      userName: json['user_name'],
      userProfileImage: json['user_profile_image'],
      bookedAt: parseUtcToLocal(json['booked_at']),
    );
  }
}
