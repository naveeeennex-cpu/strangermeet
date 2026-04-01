import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../config/theme.dart';
import '../../models/story.dart';
import '../../providers/story_provider.dart';
import '../../widgets/video_player_widget.dart';

class StoryViewerScreen extends ConsumerStatefulWidget {
  final String userId;

  const StoryViewerScreen({super.key, required this.userId});

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late AnimationController _progressController;
  final _replyController = TextEditingController();
  final _replyFocusNode = FocusNode();
  bool _isPaused = false;

  List<Story> _stories = [];
  String _userName = '';
  String? _userImage;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _nextStory();
      }
    });

    _replyFocusNode.addListener(() {
      if (_replyFocusNode.hasFocus) {
        _pauseTimer();
      } else {
        _resumeTimer();
      }
    });

    Future.microtask(_loadStories);
  }

  void _loadStories() {
    final storiesState = ref.read(storiesProvider);
    final userStoriesGroup = storiesState.userStories.where(
      (us) => us.userId == widget.userId,
    );

    if (userStoriesGroup.isNotEmpty) {
      final group = userStoriesGroup.first;
      setState(() {
        _stories = group.stories;
        _userName = group.userName;
        _userImage = group.userImage;
        _isLoaded = true;
      });

      if (_stories.isNotEmpty) {
        final firstUnviewed = _stories.indexWhere((s) => !s.isViewed);
        if (firstUnviewed != -1) {
          _currentIndex = firstUnviewed;
        }
        _markCurrentAsViewed();
        _startProgress();
      }
    } else {
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _startProgress() {
    _progressController.reset();
    _progressController.forward();
  }

  void _pauseTimer() {
    _isPaused = true;
    _progressController.stop();
  }

  void _resumeTimer() {
    if (_isPaused) {
      _isPaused = false;
      _progressController.forward();
    }
  }

  void _nextStory() {
    if (_currentIndex < _stories.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _markCurrentAsViewed();
      _startProgress();
    } else {
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _prevStory() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      _startProgress();
    } else {
      _startProgress();
    }
  }

  void _markCurrentAsViewed() {
    if (_stories.isNotEmpty && _currentIndex < _stories.length) {
      ref
          .read(storiesProvider.notifier)
          .viewStory(_stories[_currentIndex].id);
    }
  }

  void _sendReply() {
    final message = _replyController.text.trim();
    if (message.isEmpty || _stories.isEmpty) return;

    ref
        .read(storiesProvider.notifier)
        .replyToStory(_stories[_currentIndex].id, message);

    _replyController.clear();
    _replyFocusNode.unfocus();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reply sent!'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _progressController.dispose();
    _replyController.dispose();
    _replyFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _stories.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final story = _stories[_currentIndex];
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null &&
              details.primaryVelocity! > 300) {
            Navigator.of(context).pop();
          }
        },
        onTapDown: (details) {
          _pauseTimer();
        },
        onTapUp: (details) {
          final x = details.globalPosition.dx;
          if (x < screenSize.width / 3) {
            _prevStory();
          } else if (x > screenSize.width * 2 / 3) {
            _nextStory();
          } else {
            _resumeTimer();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Story media: video or image
            if (story.mediaType == 'video' &&
                story.videoUrl != null &&
                story.videoUrl!.isNotEmpty)
              VideoPlayerWidget(
                videoUrl: story.videoUrl!,
                autoPlay: true,
                looping: true,
                showControls: false,
              )
            else
              CachedNetworkImage(
                imageUrl: story.imageUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                errorWidget: (context, url, error) => const Center(
                  child: Icon(Icons.broken_image, color: Colors.white, size: 64),
                ),
              ),

            // Gradient overlays
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 180,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 200,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
              ),
            ),

            // Progress bars at top
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              right: 12,
              child: Row(
                children: List.generate(_stories.length, (index) {
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: 2.5,
                      child: _buildProgressSegment(index),
                    ),
                  );
                }),
              ),
            ),

            // User info header
            Positioned(
              top: MediaQuery.of(context).padding.top + 20,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.grey[800],
                    backgroundImage: _userImage != null &&
                            _userImage!.isNotEmpty
                        ? CachedNetworkImageProvider(_userImage!)
                        : null,
                    child: _userImage == null || _userImage!.isEmpty
                        ? Text(
                            _userName.isNotEmpty
                                ? _userName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _userName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    timeago.format(story.createdAt),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Caption at bottom
            if (story.caption.isNotEmpty)
              Positioned(
                bottom: 90,
                left: 16,
                right: 16,
                child: Text(
                  story.caption,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    shadows: [
                      Shadow(
                        blurRadius: 8,
                        color: Colors.black54,
                      ),
                    ],
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            // Reply field at bottom
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 12,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.5),
                          width: 1,
                        ),
                      ),
                      child: TextField(
                        controller: _replyController,
                        focusNode: _replyFocusNode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Send a reply...',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          filled: false,
                        ),
                        onSubmitted: (_) => _sendReply(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sendReply,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.send,
                        size: 18,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressSegment(int index) {
    if (index < _currentIndex) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    } else if (index == _currentIndex) {
      return AnimatedBuilder(
        animation: _progressController,
        builder: (context, child) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: _progressController.value,
              backgroundColor: Colors.white.withOpacity(0.3),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 2.5,
            ),
          );
        },
      );
    } else {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }
  }
}
