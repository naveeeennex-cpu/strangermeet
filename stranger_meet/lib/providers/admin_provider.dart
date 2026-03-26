import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/community.dart';
import '../models/user.dart';
import '../services/api_service.dart';

// ============================================================
// Dashboard Stats
// ============================================================

class DashboardStats {
  final int totalMembers;
  final double totalRevenue;
  final int activeCommunities;
  final int totalEvents;
  final int totalEnrollments;
  final List<Map<String, dynamic>> recentJoiners;
  final List<Map<String, dynamic>> recentEnrollments;
  final List<Map<String, dynamic>> upcomingEvents;

  const DashboardStats({
    this.totalMembers = 0,
    this.totalRevenue = 0.0,
    this.activeCommunities = 0,
    this.totalEvents = 0,
    this.totalEnrollments = 0,
    this.recentJoiners = const [],
    this.recentEnrollments = const [],
    this.upcomingEvents = const [],
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      totalMembers: json['total_members'] ?? json['totalMembers'] ?? 0,
      totalRevenue:
          (json['total_payments'] ?? json['total_revenue'] ?? json['totalRevenue'] ?? 0)
              .toDouble(),
      activeCommunities:
          json['communities_count'] ?? json['active_communities'] ?? json['activeCommunities'] ?? 0,
      totalEvents: json['total_events'] ?? json['totalEvents'] ?? 0,
      totalEnrollments: json['total_enrollments'] ?? json['totalEnrollments'] ?? 0,
      recentJoiners: json['recent_joiners'] != null
          ? List<Map<String, dynamic>>.from(json['recent_joiners'])
          : json['recentJoiners'] != null
              ? List<Map<String, dynamic>>.from(json['recentJoiners'])
              : [],
      recentEnrollments: json['recent_enrollments'] != null
          ? List<Map<String, dynamic>>.from(json['recent_enrollments'])
          : [],
      upcomingEvents: json['upcoming_events'] != null
          ? List<Map<String, dynamic>>.from(json['upcoming_events'])
          : [],
    );
  }
}

class DashboardState {
  final DashboardStats? stats;
  final bool isLoading;
  final String? errorMessage;

  const DashboardState({
    this.stats,
    this.isLoading = false,
    this.errorMessage,
  });

  DashboardState copyWith({
    DashboardStats? stats,
    bool? isLoading,
    String? errorMessage,
  }) {
    return DashboardState(
      stats: stats ?? this.stats,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class DashboardNotifier extends StateNotifier<DashboardState> {
  final ApiService _api;

  DashboardNotifier(this._api) : super(const DashboardState());

  Future<void> fetchDashboardStats() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _api.get('/partner/dashboard');
      final stats = DashboardStats.fromJson(response.data);
      state = DashboardState(stats: stats);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }
}

final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, DashboardState>((ref) {
  return DashboardNotifier(ApiService());
});

// ============================================================
// Admin Communities
// ============================================================

class AdminCommunitiesState {
  final List<Community> communities;
  final bool isLoading;
  final String? errorMessage;

  const AdminCommunitiesState({
    this.communities = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  AdminCommunitiesState copyWith({
    List<Community>? communities,
    bool? isLoading,
    String? errorMessage,
  }) {
    return AdminCommunitiesState(
      communities: communities ?? this.communities,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class AdminCommunitiesNotifier extends StateNotifier<AdminCommunitiesState> {
  final ApiService _api;

  AdminCommunitiesNotifier(this._api) : super(const AdminCommunitiesState());

  Future<void> fetchMyCommunities() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _api.get('/partner/communities');
      final data = response.data;
      final List<dynamic> results =
          data is List ? data : (data['results'] ?? data['communities'] ?? []);
      final communities = results.map((e) => Community.fromJson(e)).toList();
      state = AdminCommunitiesState(communities: communities);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> editCommunity(String communityId, Map<String, dynamic> data) async {
    try {
      await _api.put('/partner/communities/$communityId', data: data);
      await fetchMyCommunities();
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> deleteCommunity(String communityId) async {
    try {
      await _api.delete('/partner/communities/$communityId');
      await fetchMyCommunities();
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> kickMember(String communityId, String userId) async {
    try {
      await _api.delete('/partner/communities/$communityId/members/$userId');
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }

  Future<List<User>> fetchMembers(String communityId) async {
    final response = await _api.get('/partner/communities/$communityId/members');
    final data = response.data;
    final List<dynamic> results =
        data is List ? data : (data['results'] ?? data['members'] ?? []);
    return results.map((e) {
      final m = e as Map<String, dynamic>;
      return User(
        id: m['user_id']?.toString() ?? m['id']?.toString() ?? '',
        name: m['user_name'] ?? m['name'] ?? '',
        email: m['user_email'] ?? m['email'] ?? '',
        profileImageUrl: m['user_profile_image'] ?? m['profile_image_url'],
      );
    }).toList();
  }

  // --- Events ---

  Future<List<Map<String, dynamic>>> fetchEvents(String communityId) async {
    final response = await _api.get('/partner/communities/$communityId/events');
    final data = response.data;
    final List<dynamic> results =
        data is List ? data : (data['results'] ?? data['events'] ?? []);
    return results.cast<Map<String, dynamic>>();
  }

  Future<void> createEvent(String communityId, Map<String, dynamic> data) async {
    await _api.post('/communities/$communityId/events', data: data);
  }

  Future<void> updateEvent(
      String communityId, String eventId, Map<String, dynamic> data) async {
    await _api.put('/communities/$communityId/events/$eventId', data: data);
  }

  Future<void> deleteEvent(String communityId, String eventId) async {
    await _api.delete('/communities/$communityId/events/$eventId');
  }

  Future<Map<String, dynamic>> fetchEventEnrollments(
      String communityId, String eventId) async {
    final response =
        await _api.get('/partner/communities/$communityId/events/$eventId/enrollments');
    return Map<String, dynamic>.from(response.data);
  }

  // --- Groups ---

  Future<void> createGroup(
      String communityId, String name, String description) async {
    await _api.post('/communities/$communityId/groups', data: {
      'name': name,
      'description': description,
      'type': 'general',
    });
  }

  Future<void> updateGroup(
      String communityId, String groupId, String name, String description) async {
    await _api.put('/partner/communities/$communityId/groups/$groupId', data: {
      'name': name,
      'description': description,
      'type': 'general',
    });
  }

  Future<void> deleteGroup(String communityId, String groupId) async {
    await _api.delete('/partner/communities/$communityId/groups/$groupId');
  }

  // --- Itinerary ---

  Future<List<Map<String, dynamic>>> fetchItinerary(
      String communityId, String eventId) async {
    final response =
        await _api.get('/communities/$communityId/events/$eventId/itinerary');
    final data = response.data;
    final List<dynamic> results = data is List ? data : (data['results'] ?? []);
    return results.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createItineraryDay(
      String communityId, String eventId, Map<String, dynamic> data) async {
    final response = await _api.post(
      '/communities/$communityId/events/$eventId/itinerary',
      data: data,
    );
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> updateItineraryDay(String communityId,
      String eventId, String dayId, Map<String, dynamic> data) async {
    final response = await _api.put(
      '/communities/$communityId/events/$eventId/itinerary/$dayId',
      data: data,
    );
    return Map<String, dynamic>.from(response.data);
  }

  Future<void> deleteItineraryDay(
      String communityId, String eventId, String dayId) async {
    await _api.delete(
        '/communities/$communityId/events/$eventId/itinerary/$dayId');
  }
}

final adminCommunitiesProvider =
    StateNotifierProvider<AdminCommunitiesNotifier, AdminCommunitiesState>((ref) {
  return AdminCommunitiesNotifier(ApiService());
});

// ============================================================
// Payments
// ============================================================

class PaymentRecord {
  final String id;
  final String userName;
  final String eventName;
  final double amount;
  final String status;
  final DateTime? date;

  PaymentRecord({
    required this.id,
    required this.userName,
    required this.eventName,
    required this.amount,
    this.status = 'completed',
    this.date,
  });

  factory PaymentRecord.fromJson(Map<String, dynamic> json) {
    return PaymentRecord(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      userName: json['user_name'] ?? json['userName'] ?? '',
      eventName: json['event_name'] ?? json['eventName'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      status: json['status'] ?? 'completed',
      date: json['date'] != null
          ? DateTime.parse(json['date'])
          : json['created_at'] != null
              ? DateTime.parse(json['created_at'])
              : null,
    );
  }
}

class PaymentsState {
  final List<PaymentRecord> payments;
  final bool isLoading;
  final String? errorMessage;

  const PaymentsState({
    this.payments = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  PaymentsState copyWith({
    List<PaymentRecord>? payments,
    bool? isLoading,
    String? errorMessage,
  }) {
    return PaymentsState(
      payments: payments ?? this.payments,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class PaymentsNotifier extends StateNotifier<PaymentsState> {
  final ApiService _api;

  PaymentsNotifier(this._api) : super(const PaymentsState());

  Future<void> fetchPayments() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _api.get('/partner/payments');
      final data = response.data;
      final List<dynamic> results =
          data is List ? data : (data['results'] ?? data['payments'] ?? []);
      final payments = results.map((e) => PaymentRecord.fromJson(e)).toList();
      state = PaymentsState(payments: payments);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }
}

final paymentsProvider =
    StateNotifierProvider<PaymentsNotifier, PaymentsState>((ref) {
  return PaymentsNotifier(ApiService());
});
