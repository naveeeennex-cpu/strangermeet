import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart';
import '../models/friend_request.dart';
import '../services/api_service.dart';

class FriendState {
  final List<User> friends;
  final List<FriendRequest> pendingRequests;
  final List<FriendRequest> sentRequests;
  final bool isLoading;
  final String? errorMessage;

  const FriendState({
    this.friends = const [],
    this.pendingRequests = const [],
    this.sentRequests = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  FriendState copyWith({
    List<User>? friends,
    List<FriendRequest>? pendingRequests,
    List<FriendRequest>? sentRequests,
    bool? isLoading,
    String? errorMessage,
  }) {
    return FriendState(
      friends: friends ?? this.friends,
      pendingRequests: pendingRequests ?? this.pendingRequests,
      sentRequests: sentRequests ?? this.sentRequests,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class FriendNotifier extends StateNotifier<FriendState> {
  final ApiService _api;

  FriendNotifier(this._api) : super(const FriendState());

  Future<void> fetchFriends() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _api.get('/friends');
      final data = response.data;
      final List<dynamic> results =
          data is List ? data : (data['results'] ?? data['friends'] ?? []);
      final friends = results.map((e) => User.fromJson(e)).toList();
      state = state.copyWith(friends: friends, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> fetchPendingRequests() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _api.get('/friends/requests');
      final data = response.data;
      final List<dynamic> results =
          data is List ? data : (data['results'] ?? data['requests'] ?? []);
      final requests = results.map((e) => FriendRequest.fromJson(e)).toList();
      state = state.copyWith(pendingRequests: requests, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> fetchSentRequests() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _api.get('/friends/sent');
      final data = response.data;
      final List<dynamic> results =
          data is List ? data : (data['results'] ?? data['requests'] ?? []);
      final requests = results.map((e) => FriendRequest.fromJson(e)).toList();
      state = state.copyWith(sentRequests: requests, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> sendRequest(String userId) async {
    try {
      await _api.post('/friends/request', data: {'addressee_id': userId});
      await fetchSentRequests();
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  Future<void> acceptRequest(String requestId) async {
    try {
      await _api.post('/friends/accept/$requestId');
      await fetchPendingRequests();
      await fetchFriends();
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  Future<void> rejectRequest(String requestId) async {
    try {
      await _api.post('/friends/reject/$requestId');
      await fetchPendingRequests();
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  Future<void> unfriend(String userId) async {
    try {
      await _api.delete('/friends/$userId');
      await fetchFriends();
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  Future<String> getFriendshipStatus(String userId) async {
    try {
      final response = await _api.get('/friends/status/$userId');
      return response.data['status'] ?? 'none';
    } catch (e) {
      return 'none';
    }
  }
}

final friendProvider =
    StateNotifierProvider<FriendNotifier, FriendState>((ref) {
  return FriendNotifier(ApiService());
});
