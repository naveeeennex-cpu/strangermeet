import '../utils/date_utils.dart';

class FriendRequest {
  final String id;
  final String requesterId;
  final String addresseeId;
  final String status;
  final String? requesterName;
  final String? requesterImage;
  final String? addresseeName;
  final String? addresseeImage;
  final DateTime? createdAt;

  FriendRequest({
    required this.id,
    required this.requesterId,
    required this.addresseeId,
    this.status = 'pending',
    this.requesterName,
    this.requesterImage,
    this.addresseeName,
    this.addresseeImage,
    this.createdAt,
  });

  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    return FriendRequest(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      requesterId: json['requester_id']?.toString() ?? json['requesterId']?.toString() ?? '',
      addresseeId: json['addressee_id']?.toString() ?? json['addresseeId']?.toString() ?? '',
      status: json['status'] ?? 'pending',
      requesterName: json['requester_name'] ?? json['requesterName'],
      requesterImage: json['requester_image'] ?? json['requesterImage'],
      addresseeName: json['addressee_name'] ?? json['addresseeName'],
      addresseeImage: json['addressee_image'] ?? json['addresseeImage'],
      createdAt: parseUtcToLocal(json['created_at']) ?? parseUtcToLocal(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'requester_id': requesterId,
      'addressee_id': addresseeId,
      'status': status,
      'requester_name': requesterName,
      'requester_image': requesterImage,
      'addressee_name': addresseeName,
      'addressee_image': addresseeImage,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
