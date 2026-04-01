import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/constants.dart';
import '../models/post.dart';
import '../services/api_service.dart';

class PostsState {
  final List<Post> posts;
  final bool isLoading;
  final bool hasMore;
  final int page;
  final String? errorMessage;

  const PostsState({
    this.posts = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.page = 1,
    this.errorMessage,
  });

  PostsState copyWith({
    List<Post>? posts,
    bool? isLoading,
    bool? hasMore,
    int? page,
    String? errorMessage,
  }) {
    return PostsState(
      posts: posts ?? this.posts,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      errorMessage: errorMessage,
    );
  }
}

class PostsNotifier extends StateNotifier<PostsState> {
  final ApiService _api;

  PostsNotifier(this._api) : super(const PostsState());

  Future<void> fetchPosts({bool refresh = false}) async {
    if (state.isLoading) return;
    if (!refresh && !state.hasMore) return;

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final skip = refresh ? 0 : (state.page - 1) * AppConstants.pageSize;
      final response = await _api.get('/posts', queryParameters: {
        'skip': skip,
        'limit': AppConstants.pageSize,
      });

      final data = response.data;
      final List<dynamic> results =
          data is List ? data : (data['results'] ?? data['posts'] ?? []);
      final newPosts = results.map((e) => Post.fromJson(e)).toList();

      final hasMore = newPosts.length >= AppConstants.pageSize;

      if (refresh) {
        state = PostsState(
          posts: newPosts,
          page: 2,
          hasMore: hasMore,
        );
      } else {
        state = state.copyWith(
          posts: [...state.posts, ...newPosts],
          page: state.page + 1,
          hasMore: hasMore,
          isLoading: false,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> createPost({
    required String caption,
    String? imagePath,
  }) async {
    try {
      dynamic data;
      if (imagePath != null) {
        data = FormData.fromMap({
          'caption': caption,
          'image': await MultipartFile.fromFile(imagePath),
        });
        await _api.uploadFile('/posts', formData: data);
      } else {
        await _api.post('/posts', data: {'caption': caption});
      }
      await fetchPosts(refresh: true);
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> toggleLike(String postId) async {
    // Optimistic update
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
      // Revert on failure
      final revertedPosts = List<Post>.from(state.posts);
      revertedPosts[postIndex] = post;
      state = state.copyWith(posts: revertedPosts);
    }
  }

  Future<List<Comment>> fetchComments(String postId) async {
    final response = await _api.get('/posts/$postId/comments');
    final data = response.data;
    final List<dynamic> results =
        data is List ? data : (data['results'] ?? data['comments'] ?? []);
    return results.map((e) => Comment.fromJson(e)).toList();
  }

  Future<Comment> addComment(String postId, String text) async {
    final response = await _api.post('/posts/$postId/comment', data: {
      'text': text,
    });

    // Update comment count
    final postIndex = state.posts.indexWhere((p) => p.id == postId);
    if (postIndex != -1) {
      final post = state.posts[postIndex];
      final updatedPosts = List<Post>.from(state.posts);
      updatedPosts[postIndex] = post.copyWith(
        commentsCount: post.commentsCount + 1,
      );
      state = state.copyWith(posts: updatedPosts);
    }

    return Comment.fromJson(response.data);
  }

  Future<Map<String, dynamic>> toggleCommentLike(String postId, String commentId) async {
    final response = await _api.post('/posts/$postId/comments/$commentId/like');
    return Map<String, dynamic>.from(response.data);
  }

  Future<CommentReply> replyToComment(String postId, String commentId, String text) async {
    final response = await _api.post('/posts/$postId/comments/$commentId/reply', data: {
      'text': text,
    });
    return CommentReply.fromJson(response.data);
  }

  Future<List<CommentReply>> fetchCommentReplies(String postId, String commentId) async {
    final response = await _api.get('/posts/$postId/comments/$commentId/replies');
    final data = response.data;
    final List<dynamic> results = data is List ? data : (data['results'] ?? []);
    return results.map((e) => CommentReply.fromJson(e)).toList();
  }

  Future<void> deletePost(String postId) async {
    try {
      await _api.delete('/posts/$postId');
      // Remove from local state
      final updatedPosts = state.posts.where((p) => p.id != postId).toList();
      state = state.copyWith(posts: updatedPosts);
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> editPost(String postId, {required String caption}) async {
    try {
      final response = await _api.put('/posts/$postId', data: {
        'caption': caption,
      });
      // Update local state
      final updatedPost = Post.fromJson(response.data);
      final postIndex = state.posts.indexWhere((p) => p.id == postId);
      if (postIndex != -1) {
        final updatedPosts = List<Post>.from(state.posts);
        updatedPosts[postIndex] = state.posts[postIndex].copyWith(
          caption: updatedPost.caption,
        );
        state = state.copyWith(posts: updatedPosts);
      }
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }
}

final postsProvider =
    StateNotifierProvider<PostsNotifier, PostsState>((ref) {
  return PostsNotifier(ApiService());
});
