import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/story.dart';
import '../services/api_service.dart';

class StoriesState {
  final List<UserStories> userStories;
  final bool isLoading;
  final String? errorMessage;

  const StoriesState({
    this.userStories = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  StoriesState copyWith({
    List<UserStories>? userStories,
    bool? isLoading,
    String? errorMessage,
  }) {
    return StoriesState(
      userStories: userStories ?? this.userStories,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class StoriesNotifier extends StateNotifier<StoriesState> {
  final ApiService _api;

  StoriesNotifier(this._api) : super(const StoriesState());

  Future<void> fetchStories() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final response = await _api.get('/stories/');
      final data = response.data;
      final List<dynamic> results = data is List ? data : [];
      final stories =
          results.map((e) => UserStories.fromJson(e as Map<String, dynamic>)).toList();

      state = StoriesState(userStories: stories);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> createStory(String imageUrl, String caption) async {
    try {
      await _api.post('/stories/', data: {
        'image_url': imageUrl,
        'caption': caption,
      });
      await fetchStories();
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }

  Future<Story> viewStory(String storyId) async {
    try {
      final response = await _api.get('/stories/$storyId');
      return Story.fromJson(response.data);
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> replyToStory(String storyId, String message) async {
    try {
      await _api.post('/stories/$storyId/reply', data: {
        'message': message,
      });
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> deleteStory(String storyId) async {
    try {
      await _api.delete('/stories/$storyId');
      await fetchStories();
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }
}

final storiesProvider =
    StateNotifierProvider<StoriesNotifier, StoriesState>((ref) {
  return StoriesNotifier(ApiService());
});
