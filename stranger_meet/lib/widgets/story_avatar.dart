import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../config/theme.dart';

class StoryAvatar extends StatelessWidget {
  final String? imageUrl;
  final String username;
  final bool isYourStory;
  final bool hasUnseenStory;
  final double size;
  final VoidCallback? onTap;

  const StoryAvatar({
    super.key,
    this.imageUrl,
    required this.username,
    this.isYourStory = false,
    this.hasUnseenStory = true,
    this.size = 68,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final avatarRadius = size / 2;
    final borderWidth = 2.5;
    final gapWidth = 2.0;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size + 8,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avatar with gradient ring
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: hasUnseenStory && !isYourStory
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.primaryColor,
                          Color(0xFFB0CC00),
                          Color(0xFF8FB300),
                        ],
                      )
                    : null,
                border: !hasUnseenStory && !isYourStory
                    ? Border.all(
                        color: AppTheme.dividerColor,
                        width: borderWidth,
                      )
                    : null,
              ),
              child: Padding(
                padding: EdgeInsets.all(
                  hasUnseenStory && !isYourStory
                      ? borderWidth + gapWidth
                      : isYourStory
                          ? 0
                          : borderWidth + gapWidth,
                ),
                child: Stack(
                  children: [
                    // The actual avatar
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: isYourStory
                            ? Border.all(
                                color: AppTheme.dividerColor,
                                width: 1.5,
                              )
                            : null,
                      ),
                      child: CircleAvatar(
                        radius: avatarRadius -
                            borderWidth -
                            gapWidth -
                            (isYourStory ? 1 : 0),
                        backgroundColor: AppTheme.surfaceColor,
                        backgroundImage: imageUrl != null
                            ? CachedNetworkImageProvider(imageUrl!)
                            : null,
                        child: imageUrl == null
                            ? Text(
                                username.isNotEmpty
                                    ? username[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: (size / 3.5).clamp(12, 24),
                                  color: AppTheme.textPrimary,
                                ),
                              )
                            : null,
                      ),
                    ),
                    // "+" icon overlay for "Your story"
                    if (isYourStory)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: size * 0.3,
                          height: size * 0.3,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.add,
                            size: size * 0.18,
                            color: Colors.black,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Username
            Text(
              isYourStory ? 'Your story' : username,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
