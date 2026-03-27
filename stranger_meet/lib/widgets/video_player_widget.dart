import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final bool autoPlay;
  final bool looping;
  final double? aspectRatio;
  final bool showControls;

  const VideoPlayerWidget({
    super.key,
    required this.videoUrl,
    this.autoPlay = false,
    this.looping = false,
    this.aspectRatio,
    this.showControls = true,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _videoController;
  ChewieController? _chewieController;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    _videoController =
        VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    try {
      await _videoController.initialize();
      _chewieController = ChewieController(
        videoPlayerController: _videoController,
        autoPlay: widget.autoPlay,
        looping: widget.looping,
        aspectRatio: widget.aspectRatio ?? _videoController.value.aspectRatio,
        showControls: widget.showControls,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    color: Colors.white54, size: 42),
                const SizedBox(height: 8),
                Text('Video error',
                    style: TextStyle(color: Colors.white54)),
              ],
            ),
          );
        },
      );
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        height: 300,
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off, color: Colors.white38, size: 48),
              SizedBox(height: 8),
              Text('Failed to load video',
                  style: TextStyle(color: Colors.white38)),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Container(
        height: 300,
        color: Colors.black,
        child: const Center(
            child: CircularProgressIndicator(color: Colors.white54)),
      );
    }

    return AspectRatio(
      aspectRatio: widget.aspectRatio ?? _videoController.value.aspectRatio,
      child: Chewie(controller: _chewieController!),
    );
  }
}
