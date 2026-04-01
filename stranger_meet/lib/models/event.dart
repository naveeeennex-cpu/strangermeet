import '../utils/date_utils.dart';

class Event {
  final String id;
  final String title;
  final String description;
  final String location;
  final DateTime date;
  final double price;
  final int slots;
  final String? imageUrl;
  final String creatorName;
  final int participantsCount;
  final DateTime? createdAt;

  Event({
    required this.id,
    required this.title,
    required this.description,
    required this.location,
    required this.date,
    this.price = 0,
    this.slots = 0,
    this.imageUrl,
    required this.creatorName,
    this.participantsCount = 0,
    this.createdAt,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      location: json['location'] ?? '',
      date: parseUtcToLocal(json['date']) ?? DateTime.now(),
      price: (json['price'] ?? 0).toDouble(),
      slots: json['slots'] ?? 0,
      imageUrl: json['image_url'] ?? json['imageUrl'],
      creatorName: json['creator_name'] ?? json['creatorName'] ?? '',
      participantsCount:
          json['participants_count'] ?? json['participantsCount'] ?? 0,
      createdAt: parseUtcToLocal(json['created_at']) ?? parseUtcToLocal(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'location': location,
      'date': date.toIso8601String(),
      'price': price,
      'slots': slots,
      'image_url': imageUrl,
      'creator_name': creatorName,
      'participants_count': participantsCount,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  Event copyWith({
    String? id,
    String? title,
    String? description,
    String? location,
    DateTime? date,
    double? price,
    int? slots,
    String? imageUrl,
    String? creatorName,
    int? participantsCount,
    DateTime? createdAt,
  }) {
    return Event(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      location: location ?? this.location,
      date: date ?? this.date,
      price: price ?? this.price,
      slots: slots ?? this.slots,
      imageUrl: imageUrl ?? this.imageUrl,
      creatorName: creatorName ?? this.creatorName,
      participantsCount: participantsCount ?? this.participantsCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
