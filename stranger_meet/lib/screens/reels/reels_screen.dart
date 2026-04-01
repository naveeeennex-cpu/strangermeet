import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../config/theme.dart';
import '../../providers/reel_provider.dart';
import '../../models/reel.dart';

class ReelsScreen extends ConsumerStatefulWidget {
  const ReelsScreen({super.key});

  @override
  ConsumerState<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends ConsumerState<ReelsScreen> {
  final _pageController = PageController();

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(reelsProvider.notifier).fetchReels(refresh: true),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reelsProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Reels',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box_outlined, color: Colors.white),
            onPressed: () => context.push('/create-reel'),
          ),
        ],
      ),
      body: state.isLoading && state.reels.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : state.reels.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.movie_outlined,
                          size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'No reels yet',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[500],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => context.push('/create-reel'),
                        child: const Text('Create First Reel'),
                      ),
                    ],
                  ),
                )
              : PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  itemCount: state.reels.length,
                  onPageChanged: (index) {
                    // Load more when near the end
                    if (index >= state.reels.length - 3) {
                      ref.read(reelsProvider.notifier).fetchReels();
                    }
                  },
                  itemBuilder: (context, index) {
                    return _ReelPage(
                      reel: state.reels[index],
                      onLike: () => ref
                          .read(reelsProvider.notifier)
                          .toggleLike(state.reels[index].id),
                    );
                  },
                ),
    );
  }
}

class _ReelPage extends StatelessWidget {
  final Reel reel;
  final VoidCallback onLike;

  const _ReelPage({required this.reel, required this.onLike});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background image
        CachedNetworkImage(
          imageUrl: reel.mediaUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            color: Colors.black,
            child: const Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (context, url, error) => Container(
            color: Colors.black,
            child: const Center(
              child: Icon(Icons.broken_image, size: 64, color: Colors.grey),
            ),
          ),
        ),
        // Bottom gradient
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 300,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black87,
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        // Bottom info
        Positioned(
          bottom: 80,
          left: 16,
          right: 72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppTheme.primaryColor,
                    backgroundImage: reel.userImage != null
                        ? CachedNetworkImageProvider(reel.userImage!)
                        : null,
                    child: reel.userImage == null
                        ? Text(
                            reel.userName.isNotEmpty
                                ? reel.userName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Colors.black,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    reel.userName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                reel.caption,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        // Right side actions
        Positioned(
          right: 12,
          bottom: 100,
          child: Column(
            children: [
              // User avatar
              CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.primaryColor,
                backgroundImage: reel.userImage != null
                    ? CachedNetworkImageProvider(reel.userImage!)
                    : null,
                child: reel.userImage == null
                    ? Text(
                        reel.userName.isNotEmpty
                            ? reel.userName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Colors.black,
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 20),
              // Like
              GestureDetector(
                onTap: onLike,
                child: Column(
                  children: [
                    Icon(
                      reel.isLiked ? Icons.favorite : Icons.favorite_border,
                      color: reel.isLiked ? Colors.red : Colors.white,
                      size: 32,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${reel.likesCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Comments
              Column(
                children: [
                  const Icon(
                    Icons.comment_outlined,
                    color: Colors.white,
                    size: 30,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${reel.commentsCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Share
              const Icon(
                Icons.share_outlined,
                color: Colors.white,
                size: 28,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
