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
            _buildHeader(context),
            _buildMedia(context),
            _buildActionRow(context),
            _buildLikesText(context),
            _buildCaption(context),
            if (post.commentsCount > 0) _buildViewComments(context),
            _buildTimeAgo(context),
            const Divider(height: 1),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final textColor = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;
    final secondaryColor = Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
      child: Row(
        children: [
          // User avatar
          CircleAvatar(
            radius: 18,
            backgroundColor: Theme.of(context).colorScheme.surface,
            backgroundImage: post.userImage != null
                ? CachedNetworkImageProvider(post.userImage!)
                : null,
            child: post.userImage == null
                ? Text(
                    post.userName.isNotEmpty
                        ? post.userName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: textColor,
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
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
                if (location != null && location!.isNotEmpty)
                  Text(
                    location!,
                    style: TextStyle(
                      fontSize: 12,
                      color: secondaryColor,
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
                style: TextStyle(
                  fontSize: 12,
                  color: secondaryColor,
                ),
              ),
            ),
          // More menu
          GestureDetector(
            onTap: onMoreMenu,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.more_horiz,
                size: 20,
                color: secondaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedia(BuildContext context) {
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
          color: Theme.of(context).colorScheme.surface,
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
          color: Theme.of(context).colorScheme.surface,
          child: Icon(
            Icons.broken_image_outlined,
            size: 48,
            color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildActionRow(BuildContext context) {
    final textColor = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;

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
                color: post.isLiked ? Colors.red : textColor,
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Comment button
          GestureDetector(
            onTap: onComment,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.chat_bubble_outline,
                size: 24,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Share button
          GestureDetector(
            onTap: onShare,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.send_outlined,
                size: 24,
                color: textColor,
              ),
            ),
          ),
          const Spacer(),
          // Bookmark (optional visual placeholder)
        ],
      ),
    );
  }

  Widget _buildLikesText(BuildContext context) {
    if (post.likesCount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Text(
        post.likesCount == 1
            ? 'Liked by 1 person'
            : 'Liked by ${post.likesCount} others',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
        ),
      ),
    );
  }

  Widget _buildCaption(BuildContext context) {
    if (post.caption.isEmpty) return const SizedBox.shrink();

    const int maxCaptionLength = 120;
    final bool isLong = post.caption.length > maxCaptionLength;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: RichText(
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
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
              TextSpan(
                text: '...more',
                style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey),
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
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _buildTimeAgo(BuildContext context) {
    if (post.createdAt == null) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Text(
        timeago.format(post.createdAt!).toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
