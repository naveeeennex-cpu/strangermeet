import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../config/theme.dart';
import '../models/post.dart';
import 'video_player_widget.dart';

class PostCard extends StatelessWidget {
  final Post post;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onTap;
  final VoidCallback? onShare;
  final VoidCallback? onMoreMenu;
  final String? location;

  const PostCard({
    super.key,
    required this.post,
    this.onLike,
    this.onComment,
    this.onTap,
    this.onShare,
    this.onMoreMenu,
    this.location,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildMedia(),
            _buildActionRow(),
            _buildLikesText(),
            _buildCaption(),
            if (post.commentsCount > 0) _buildViewComments(context),
            _buildTimeAgo(),
            const Divider(height: 1),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
      child: Row(
        children: [
          // User avatar
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.surfaceColor,
            backgroundImage: post.userImage != null
                ? CachedNetworkImageProvider(post.userImage!)
                : null,
            child: post.userImage == null
                ? Text(
                    post.userName.isNotEmpty
                        ? post.userName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppTheme.textPrimary,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          // Username + location + time
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      post.userName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
                if (location != null && location!.isNotEmpty)
                  Text(
                    location!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          // Time ago (small, on the right)
          if (post.createdAt != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                timeago.format(post.createdAt!, locale: 'en_short'),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          // More menu
          GestureDetector(
            onTap: onMoreMenu,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.more_horiz,
                size: 20,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedia() {
    if (post.mediaType == 'video' &&
        post.videoUrl != null &&
        post.videoUrl!.isNotEmpty) {
      return Stack(
        children: [
          VideoPlayerWidget(
            videoUrl: post.videoUrl!,
            autoPlay: false,
            showControls: true,
            aspectRatio: 16 / 9,
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.videocam,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ],
      );
    }

    if (post.imageUrl != null && post.imageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: post.imageUrl!,
        width: double.infinity,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 250),
          color: AppTheme.surfaceColor,
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          width: double.infinity,
          height: 250,
          color: AppTheme.surfaceColor,
          child: const Icon(
            Icons.broken_image_outlined,
            size: 48,
            color: AppTheme.textSecondary,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildActionRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          // Like button
          GestureDetector(
            onTap: onLike,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                post.isLiked ? Icons.favorite : Icons.favorite_border,
                size: 26,
                color: post.isLiked ? Colors.red : AppTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Comment button
          GestureDetector(
            onTap: onComment,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.chat_bubble_outline,
                size: 24,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Share button
          GestureDetector(
            onTap: onShare,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.send_outlined,
                size: 24,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          const Spacer(),
          // Bookmark (optional visual placeholder)
        ],
      ),
    );
  }

  Widget _buildLikesText() {
    if (post.likesCount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Text(
        post.likesCount == 1
            ? 'Liked by 1 person'
            : 'Liked by ${post.likesCount} others',
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildCaption() {
    if (post.caption.isEmpty) return const SizedBox.shrink();

    const int maxCaptionLength = 120;
    final bool isLong = post.caption.length > maxCaptionLength;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: RichText(
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: const TextStyle(
            fontSize: 13,
            color: AppTheme.textPrimary,
            height: 1.4,
          ),
          children: [
            TextSpan(
              text: '${post.userName} ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: isLong
                  ? post.caption.substring(0, maxCaptionLength)
                  : post.caption,
            ),
            if (isLong)
              const TextSpan(
                text: '...more',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewComments(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: GestureDetector(
        onTap: onComment,
        child: Text(
          'View all ${post.commentsCount} comments',
          style: const TextStyle(
            fontSize: 13,
            color: AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildTimeAgo() {
    if (post.createdAt == null) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Text(
        timeago.format(post.createdAt!).toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          color: AppTheme.textSecondary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
