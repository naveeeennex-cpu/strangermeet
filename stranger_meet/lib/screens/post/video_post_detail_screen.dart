import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:go_router/go_router.dart';

import '../../models/post.dart';
import '../../providers/post_provider.dart';
import '../../config/theme.dart';
import '../../services/storage_service.dart';

class VideoPostDetailScreen extends ConsumerStatefulWidget {
  final String postId;
  const VideoPostDetailScreen({super.key, required this.postId});

  @override
  ConsumerState<VideoPostDetailScreen> createState() =>
      _VideoPostDetailScreenState();
}

class _VideoPostDetailScreenState extends ConsumerState<VideoPostDetailScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isMuted = false;
  bool _isPlaying = true;
  bool _showPlayPauseOverlay = false;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _initVideo();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final userId = await StorageService().getUserId();
    if (mounted) setState(() => _currentUserId = userId);
  }

  Future<void> _deletePost(Post post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Post'),
        content: const Text('Are you sure you want to delete this post? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(postsProvider.notifier).deletePost(post.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post deleted')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  void _showPostMenu(Post post) {
    final isOwner = _currentUserId != null && _currentUserId == post.userId;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOwner || post.communityId != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete Post', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deletePost(post);
                },
              ),
            ListTile(
              leading: const Icon(Icons.cancel_outlined),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  void _initVideo() {
    final postsState = ref.read(postsProvider);
    final post = postsState.posts
        .cast<Post?>()
        .firstWhere((p) => p?.id == widget.postId, orElse: () => null);

    if (post != null &&
        post.mediaType == 'video' &&
        post.videoUrl != null &&
        post.videoUrl!.isNotEmpty) {
      _controller =
          VideoPlayerController.networkUrl(Uri.parse(post.videoUrl!))
            ..initialize().then((_) {
              if (mounted) {
                setState(() => _isInitialized = true);
                _controller!.setLooping(true);
                _controller!.play();
                _controller!.addListener(_onVideoUpdate);
              }
            });
    }
  }

  void _onVideoUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoUpdate);
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        _isPlaying = false;
      } else {
        _controller!.play();
        _isPlaying = true;
      }
      _showPlayPauseOverlay = true;
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showPlayPauseOverlay = false);
    });
  }

  void _toggleMute() {
    if (_controller == null) return;
    setState(() {
      _isMuted = !_isMuted;
      _controller!.setVolume(_isMuted ? 0 : 1);
    });
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  Widget _engagementButton(IconData icon, String label,
      {Color? color, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: color ?? Colors.grey[400], size: 20),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          ],
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Icon(icon, color: Colors.white70, size: 20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final postsState = ref.watch(postsProvider);
    final post = postsState.posts
        .cast<Post?>()
        .firstWhere((p) => p?.id == widget.postId, orElse: () => null);

    if (post == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(
          child: Text('Post not found',
              style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () => _showPostMenu(post),
          ),
        ],
      ),
      body: Column(
        children: [
          // Video section
          Expanded(
            child: Center(
              child: _isInitialized && _controller != null
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: GestureDetector(
                            onTap: _togglePlayPause,
                            child: VideoPlayer(_controller!),
                          ),
                        ),
                        // Play/pause overlay
                        if (_showPlayPauseOverlay)
                          AnimatedOpacity(
                            opacity: _showPlayPauseOverlay ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isPlaying
                                    ? Icons.play_arrow
                                    : Icons.pause,
                                color: Colors.white,
                                size: 40,
                              ),
                            ),
                          ),
                        // Bottom controls
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Column(
                            children: [
                              // Control icons row
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    _iconButton(
                                      _isMuted
                                          ? Icons.volume_off
                                          : Icons.volume_up,
                                      _toggleMute,
                                    ),
                                    _iconButton(
                                        Icons.fullscreen, () {}),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${_formatDuration(_controller!.value.position)} / ${_formatDuration(_controller!.value.duration)}',
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              // Progress bar
                              VideoProgressIndicator(
                                _controller!,
                                allowScrubbing: true,
                                colors: VideoProgressColors(
                                  playedColor: Colors.white,
                                  bufferedColor: Colors.white24,
                                  backgroundColor: Colors.grey[800]!,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : const CircularProgressIndicator(color: Colors.white),
            ),
          ),
          // User info + engagement
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User row
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => context.push('/user/${post.userId}'),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.grey[800],
                            backgroundImage: post.userImage != null &&
                                    post.userImage!.isNotEmpty
                                ? CachedNetworkImageProvider(post.userImage!)
                                : null,
                            child: post.userImage == null ||
                                    post.userImage!.isEmpty
                                ? Text(
                                    post.userName.isNotEmpty
                                        ? post.userName[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                post.userName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              if (post.createdAt != null)
                                Text(
                                  timeago.format(post.createdAt!),
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 13),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon:
                          const Icon(Icons.more_vert, color: Colors.white),
                      onPressed: () => _showPostMenu(post),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Caption
                if (post.caption.isNotEmpty)
                  Text(
                    post.caption,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                const SizedBox(height: 16),
                // Engagement row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _engagementButton(
                      Icons.chat_bubble_outline,
                      '${post.commentsCount}',
                    ),
                    _engagementButton(
                      post.isLiked
                          ? Icons.favorite
                          : Icons.favorite_border,
                      '${post.likesCount}',
                      color: post.isLiked ? Colors.red : null,
                      onTap: () => ref
                          .read(postsProvider.notifier)
                          .toggleLike(post.id),
                    ),
                    _engagementButton(
                      Icons.bar_chart,
                      '${post.likesCount * 10}',
                    ),
                    _engagementButton(Icons.bookmark_border, ''),
                    _engagementButton(Icons.share_outlined, ''),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
