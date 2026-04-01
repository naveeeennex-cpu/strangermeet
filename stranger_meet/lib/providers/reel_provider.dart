import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/reel.dart';
import '../services/api_service.dart';
import '../config/constants.dart';

class ReelsState {
  final List<Reel> reels;
  final bool isLoading;
  final bool hasMore;
  final int page;
  final String? errorMessage;

  const ReelsState({
    this.reels = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.page = 1,
    this.errorMessage,
  });

  ReelsState copyWith({
    List<Reel>? reels,
    bool? isLoading,
    bool? hasMore,
    int? page,
    String? errorMessage,
  }) {
    return ReelsState(
      reels: reels ?? this.reels,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      errorMessage: errorMessage,
    );
  }
}

class ReelsNotifier extends StateNotifier<ReelsState> {
  final ApiService _api;

  ReelsNotifier(this._api) : super(const ReelsState());

  Future<void> fetchReels({bool refresh = false}) async {
    if (state.isLoading) return;
    if (!refresh && !state.hasMore) return;

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final skip = refresh ? 0 : (state.page - 1) * AppConstants.pageSize;
      final response = await _api.get('/reels', queryParameters: {
        'skip': skip,
        'limit': AppConstants.pageSize,
      });

      final data = response.data;
      final List<dynamic> results =
          data is List ? data : (data['results'] ?? data['reels'] ?? []);
      final newReels = results.map((e) => Reel.fromJson(e)).toList();

      final hasMore = newReels.length >= AppConstants.pageSize;

      if (refresh) {
        state = ReelsState(
          reels: newReels,
          page: 2,
          hasMore: hasMore,
        );
      } else {
        state = state.copyWith(
          reels: [...state.reels, ...newReels],
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

  Future<void> createReel({
    required String mediaUrl,
    required String caption,
    String mediaType = 'image',
  }) async {
    try {
      await _api.post('/reels', data: {
        'media_url': mediaUrl,
        'caption': caption,
        'media_type': mediaType,
      });
      await fetchReels(refresh: true);
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> toggleLike(String reelId) async {
    final reelIndex = state.reels.indexWhere((r) => r.id == reelId);
    if (reelIndex == -1) return;

    final reel = state.reels[reelIndex];
    final updatedReel = reel.copyWith(
      isLiked: !reel.isLiked,
      likesCount: reel.isLiked ? reel.likesCount - 1 : reel.likesCount + 1,
    );

    final updatedReels = List<Reel>.from(state.reels);
    updatedReels[reelIndex] = updatedReel;
    state = state.copyWith(reels: updatedReels);

    try {
      await _api.post('/reels/$reelId/like');
    } catch (e) {
      final revertedReels = List<Reel>.from(state.reels);
      revertedReels[reelIndex] = reel;
      state = state.copyWith(reels: revertedReels);
    }
  }
}

final reelsProvider =
    StateNotifierProvider<ReelsNotifier, ReelsState>((ref) {
  return ReelsNotifier(ApiService());
});
