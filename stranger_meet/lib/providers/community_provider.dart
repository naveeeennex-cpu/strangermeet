import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/community.dart';
import '../models/post.dart';
import '../services/api_service.dart';

// ============================================================
// Communities List (explore/browse)
// ============================================================

class CommunitiesState {
  final List<Community> communities;
  final List<Community> myCommunities;
  final bool isLoading;
  final String? errorMessage;

  const CommunitiesState({
    this.communities = const [],
    this.myCommunities = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  CommunitiesState copyWith({
    List<Community>? communities,
    List<Community>? myCommunities,
    bool? isLoading,
    String? errorMessage,
  }) {
    return CommunitiesState(
      communities: communities ?? this.communities,
      myCommunities: myCommunities ?? this.myCommunities,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class CommunitiesNotifier extends StateNotifier<CommunitiesState> {
  final ApiService _api;

  CommunitiesNotifier(this._api) : super(const CommunitiesState());

  Future<void> fetchCommunities({String? query, String? category}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final params = <String, dynamic>{};
      if (query != null && query.isNotEmpty) params['q'] = query;
      if (category != null && category != 'All') params['category'] = category;

      final response = await _api.get('/communities', queryParameters: params);
      final data = response.data;
      final List<dynamic> results =
          data is List ? data : (data['results'] ?? data['communities'] ?? []);
      final communities = results.map((e) => Community.fromJson(e)).toList();
      state = state.copyWith(communities: communities, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> fetchMyCommunities() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _api.get('/communities/my');
      final data = response.data;
      final List<dynamic> results =
          data is List ? data : (data['results'] ?? data['communities'] ?? []);
      final communities = results.map((e) => Community.fromJson(e)).toList();
      state = state.copyWith(myCommunities: communities, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> createCommunity({
    required String name,
    required String description,
    String? imageUrl,
    required String category,
    bool isPrivate = false,
  }) async {
    try {
      await _api.post('/communities', data: {
        'name': name,
        'description': description,
        'image_url': imageUrl,
        'category': category,
        'is_private': isPrivate,
      });
      await fetchCommunities();
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }
}

final communitiesProvider =
    StateNotifierProvider<CommunitiesNotifier, CommunitiesState>((ref) {
  return CommunitiesNotifier(ApiService());
});

// ============================================================
// Community Detail (family by communityId)
// ============================================================

class CommunityDetailState {
  final Community? community;
  final bool isLoading;
  final String? errorMessage;

  const CommunityDetailState({
    this.community,
    this.isLoading = false,
    this.errorMessage,
  });

  CommunityDetailState copyWith({
    Community? community,
    bool? isLoading,
    String? errorMessage,
  }) {
    return CommunityDetailState(
      community: community ?? this.community,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class CommunityDetailNotifier extends StateNotifier<CommunityDetailState> {
  final ApiService _api;
  final String communityId;

  CommunityDetailNotifier(this._api, this.communityId)
      : super(const CommunityDetailState());

  Future<void> fetchCommunity() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _api.get('/communities/$communityId');
      final community = Community.fromJson(response.data);
      state = CommunityDetailState(community: community);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> joinCommunity() async {
    try {
      await _api.post('/communities/$communityId/join');
      if (state.community != null) {
        state = state.copyWith(
          community: state.community!.copyWith(
            isMember: true,
            membersCount: state.community!.membersCount + 1,
            memberRole: 'member',
          ),
        );
      }
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  Future<void> leaveCommunity() async {
    try {
      await _api.post('/communities/$communityId/leave');
      if (state.community != null) {
        state = state.copyWith(
          community: state.community!.copyWith(
            isMember: false,
            membersCount: state.community!.membersCount - 1,
            memberRole: null,
          ),
        );
      }
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }
}

final communityDetailProvider = StateNotifierProvider.family<
    CommunityDetailNotifier, CommunityDetailState, String>((ref, communityId) {
  return CommunityDetailNotifier(ApiService(), communityId);
});

// ============================================================
// Community Posts (family by communityId)
// ============================================================

class CommunityPostsState {
  final List<Post> posts;
  final bool isLoading;
  final String? errorMessage;

  const CommunityPostsState({
    this.posts = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  CommunityPostsState copyWith({
    List<Post>? posts,
    bool? isLoading,
    String? errorMessage,
  }) {
    return CommunityPostsState(
      posts: posts ?? this.posts,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class CommunityPostsNotifier extends StateNotifier<CommunityPostsState> {
  final ApiService _api;
  final String communityId;

  CommunityPostsNotifier(this._api, this.communityId)
      : super(const CommunityPostsState());

  Future<void> fetchPosts() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _api.get('/communities/$communityId/posts');
      final data = response.data;
      final List<dynamic> results =
          data is List ? data : (data['results'] ?? data['posts'] ?? []);
      final posts = results.map((e) => Post.fromJson(e)).toList();
      state = CommunityPostsState(posts: posts);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> createPost(String caption) async {
    try {
      await _api.post('/communities/$communityId/posts', data: {
        'caption': caption,
      });
      await fetchPosts();
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> toggleLike(String postId) async {
    final postIndex = state.posts.indexWhere((p) => p.id == postId);
    if (postIndex == -1) return;

    final post = state.posts[postIndex];
    final updatedPost = post.copyWith(
      isLiked: !post.isLiked,
      likesCount: post.isLiked ? post.likesCount - 1 : post.likesCount + 1,
    );

    final updatedPosts = List<Post>.from(state.posts);
    updatedPosts[postIndex] = updatedPost;
    state = state.copyWith(posts: updatedPosts);

    try {
      await _api.post('/posts/$postId/like');
    } catch (e) {
      final revertedPosts = List<Post>.from(state.posts);
      revertedPosts[postIndex] = post;
      state = state.copyWith(posts: revertedPosts);
    }
  }
}

final communityPostsProvider = StateNotifierProvider.family<
    CommunityPostsNotifier, CommunityPostsState, String>((ref, communityId) {
  return CommunityPostsNotifier(ApiService(), communityId);
});

// ============================================================
// Community Messages (family by communityId)
// ============================================================

class CommunityMessagesState {
  final List<CommunityMessage> messages;
  final bool isLoading;
  final String? errorMessage;

  const CommunityMessagesState({
    this.messages = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  CommunityMessagesState copyWith({
    List<CommunityMessage>? messages,
    bool? isLoading,
    String? errorMessage,
  }) {
    return CommunityMessagesState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class CommunityMessagesNotifier
    extends StateNotifier<CommunityMessagesState> {
  final ApiService _api;
  final String communityId;

  CommunityMessagesNotifier(this._api, this.communityId)
      : super(const CommunityMessagesState());

  Future<void> fetchMessages() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _api.get('/communities/$communityId/messages');
      final data = response.data;
      final List<dynamic> results =
          data is List ? data : (data['results'] ?? data['messages'] ?? []);
      final messages =
          results.map((e) => CommunityMessage.fromJson(e)).toList();
      state = CommunityMessagesState(messages: messages);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  void setMessages(List<CommunityMessage> messages) {
    state = state.copyWith(messages: messages);
  }

  Future<void> sendMessage(String text, {String imageUrl = '', String messageType = 'text'}) async {
    try {
      final response = await _api.post(
        '/communities/$communityId/messages',
        data: {
          'message': text,
          'image_url': imageUrl,
          'message_type': messageType,
        },
      );
      final newMessage = CommunityMessage.fromJson(response.data);
      state = state.copyWith(
        messages: [...state.messages, newMessage],
      );
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }
}

final communityMessagesProvider = StateNotifierProvider.family<
    CommunityMessagesNotifier,
    CommunityMessagesState,
    String>((ref, communityId) {
  return CommunityMessagesNotifier(ApiService(), communityId);
});

// ============================================================
// Sub Groups (family by communityId)
// ============================================================

class SubGroupsState {
  final List<SubGroup> groups;
  final bool isLoading;
  final String? errorMessage;

  const SubGroupsState({
    this.groups = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  SubGroupsState copyWith({
    List<SubGroup>? groups,
    bool? isLoading,
    String? errorMessage,
  }) {
    return SubGroupsState(
      groups: groups ?? this.groups,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class SubGroupsNotifier extends StateNotifier<SubGroupsState> {
  final ApiService _api;
  final String communityId;

  SubGroupsNotifier(this._api, this.communityId)
      : super(const SubGroupsState());

  Future<void> fetchGroups() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _api.get('/communities/$communityId/groups');
      final data = response.data;
      final List<dynamic> results =
          data is List ? data : (data['results'] ?? data['groups'] ?? []);
      final groups = results.map((e) => SubGroup.fromJson(e)).toList();
      state = SubGroupsState(groups: groups);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> createGroup({
    required String name,
    required String description,
    required String type,
  }) async {
    try {
      await _api.post('/communities/$communityId/groups', data: {
        'name': name,
        'description': description,
        'type': type,
      });
      await fetchGroups();
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }
}

final subGroupsProvider = StateNotifierProvider.family<SubGroupsNotifier,
    SubGroupsState, String>((ref, communityId) {
  return SubGroupsNotifier(ApiService(), communityId);
});

// ============================================================
// Sub Group Messages (family by groupId)
// ============================================================

class SubGroupMessagesState {
  final List<CommunityMessage> messages;
  final bool isLoading;
  final String? errorMessage;

  const SubGroupMessagesState({
    this.messages = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  SubGroupMessagesState copyWith({
    List<CommunityMessage>? messages,
    bool? isLoading,
    String? errorMessage,
  }) {
    return SubGroupMessagesState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class SubGroupMessagesNotifier extends StateNotifier<SubGroupMessagesState> {
  final ApiService _api;
  final String communityId;
  final String groupId;

  SubGroupMessagesNotifier(this._api, this.communityId, this.groupId)
      : super(const SubGroupMessagesState());

  String get _basePath => '/communities/$communityId/groups/$groupId/messages';

  Future<void> fetchMessages() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _api.get(_basePath);
      final data = response.data;
      final List<dynamic> results =
          data is List ? data : (data['results'] ?? data['messages'] ?? []);
      final messages =
          results.map((e) => CommunityMessage.fromJson(e)).toList();
      state = SubGroupMessagesState(messages: messages);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  void setMessages(List<CommunityMessage> messages) {
    state = state.copyWith(messages: messages);
  }

  Future<void> sendMessage(String text, {String imageUrl = '', String messageType = 'text'}) async {
    try {
      final response = await _api.post(
        _basePath,
        data: {
          'message': text,
          'image_url': imageUrl,
          'message_type': messageType,
        },
      );
      final newMessage = CommunityMessage.fromJson(response.data);
      state = state.copyWith(
        messages: [...state.messages, newMessage],
      );
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }
}

// Key format: "communityId:groupId"
final subGroupMessagesProvider = StateNotifierProvider.family<
    SubGroupMessagesNotifier,
    SubGroupMessagesState,
    String>((ref, key) {
  final parts = key.split(':');
  final communityId = parts[0];
  final groupId = parts.length > 1 ? parts[1] : '';
  return SubGroupMessagesNotifier(ApiService(), communityId, groupId);
});

// ============================================================
// Community Events (family by communityId)
// ============================================================

class CommunityEventsState {
  final List<CommunityEvent> events;
  final bool isLoading;
  final String? errorMessage;

  const CommunityEventsState({
    this.events = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  CommunityEventsState copyWith({
    List<CommunityEvent>? events,
    bool? isLoading,
    String? errorMessage,
  }) {
    return CommunityEventsState(
      events: events ?? this.events,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class CommunityEventsNotifier extends StateNotifier<CommunityEventsState> {
  final ApiService _api;
  final String communityId;

  CommunityEventsNotifier(this._api, this.communityId)
      : super(const CommunityEventsState());

  Future<void> fetchEvents() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _api.get('/communities/$communityId/events');
      final data = response.data;
      final List<dynamic> results =
          data is List ? data : (data['results'] ?? data['events'] ?? []);
      final events =
          results.map((e) => CommunityEvent.fromJson(e)).toList();
      state = CommunityEventsState(events: events);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> createEvent({
    required String title,
    required String description,
    required String location,
    required DateTime date,
    double price = 0.0,
    int slots = 0,
    String? imageUrl,
  }) async {
    try {
      await _api.post('/communities/$communityId/events', data: {
        'title': title,
        'description': description,
        'location': location,
        'date': date.toIso8601String(),
        'price': price,
        'slots': slots,
        'image_url': imageUrl,
      });
      await fetchEvents();
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> joinEvent(String eventId) async {
    try {
      await _api.post('/communities/$communityId/events/$eventId/book');
      final eventIndex = state.events.indexWhere((e) => e.id == eventId);
      if (eventIndex != -1) {
        final event = state.events[eventIndex];
        final updatedEvents = List<CommunityEvent>.from(state.events);
        updatedEvents[eventIndex] = event.copyWith(
          isJoined: true,
          participantsCount: event.participantsCount + 1,
        );
        state = state.copyWith(events: updatedEvents);
      }
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }
}

final communityEventsProvider = StateNotifierProvider.family<
    CommunityEventsNotifier,
    CommunityEventsState,
    String>((ref, communityId) {
  return CommunityEventsNotifier(ApiService(), communityId);
});

// ============================================================
// Event Itinerary (family by "communityId:eventId")
// ============================================================

class EventItineraryState {
  final List<ItineraryDay> days;
  final bool isLoading;
  final String? errorMessage;

  const EventItineraryState({
    this.days = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  EventItineraryState copyWith({
    List<ItineraryDay>? days,
    bool? isLoading,
    String? errorMessage,
  }) {
    return EventItineraryState(
      days: days ?? this.days,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class EventItineraryNotifier extends StateNotifier<EventItineraryState> {
  final ApiService _api;
  final String communityId;
  final String eventId;

  EventItineraryNotifier(this._api, this.communityId, this.eventId)
      : super(const EventItineraryState());

  Future<void> fetchItinerary() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _api.get(
        '/communities/$communityId/events/$eventId/itinerary',
      );
      final data = response.data;
      final List<dynamic> results = data is List ? data : [];
      final days = results.map((e) => ItineraryDay.fromJson(e)).toList();
      state = EventItineraryState(days: days);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }
}

// Key format: "communityId:eventId"
final eventItineraryProvider = StateNotifierProvider.family<
    EventItineraryNotifier,
    EventItineraryState,
    String>((ref, key) {
  final parts = key.split(':');
  final communityId = parts[0];
  final eventId = parts.length > 1 ? parts[1] : '';
  return EventItineraryNotifier(ApiService(), communityId, eventId);
});
