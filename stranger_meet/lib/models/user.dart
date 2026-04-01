import '../utils/date_utils.dart';

class User {
  final String id;
  final String name;
  final String email;
  final String? username;
  final String? bio;
  final String? phone;
  final List<String> interests;
  final String? profileImageUrl;
  final String? coverImageUrl;
  final String role; // 'customer' or 'partner'
  final String? occupation; // "student" or "working"
  final String? collegeName;
  final String? companyName;
  final String? memberRole; // community membership role: 'admin' or 'member'
  final DateTime? createdAt;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.username,
    this.bio,
    this.phone,
    this.interests = const [],
    this.profileImageUrl,
    this.coverImageUrl,
    this.role = 'customer',
    this.occupation,
    this.collegeName,
    this.companyName,
    this.memberRole,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      username: json['username'],
      bio: json['bio'],
      phone: json['phone'],
      interests: json['interests'] != null
          ? List<String>.from(json['interests'])
          : [],
      profileImageUrl: json['profile_image_url'] ?? json['profileImageUrl'],
      coverImageUrl: json['cover_image_url'] ?? json['coverImageUrl'],
      role: json['role'] ?? 'customer',
      occupation: json['occupation'],
      collegeName: json['college_name'] ?? json['collegeName'],
      companyName: json['company_name'] ?? json['companyName'],
      memberRole: json['member_role'] ?? json['memberRole'],
      createdAt: parseUtcToLocal(json['created_at']) ?? parseUtcToLocal(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'username': username,
      'bio': bio,
      'phone': phone,
      'interests': interests,
      'profile_image_url': profileImageUrl,
      'cover_image_url': coverImageUrl,
      'role': role,
      'occupation': occupation,
      'college_name': collegeName,
      'company_name': companyName,
      'member_role': memberRole,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  User copyWith({
    String? id,
    String? name,
    String? email,
    String? username,
    String? bio,
    String? phone,
    List<String>? interests,
    String? profileImageUrl,
    String? coverImageUrl,
    String? role,
    String? occupation,
    String? collegeName,
    String? companyName,
    String? memberRole,
    DateTime? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      username: username ?? this.username,
      bio: bio ?? this.bio,
      phone: phone ?? this.phone,
      interests: interests ?? this.interests,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      role: role ?? this.role,
      occupation: occupation ?? this.occupation,
      collegeName: collegeName ?? this.collegeName,
      companyName: companyName ?? this.companyName,
      memberRole: memberRole ?? this.memberRole,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
