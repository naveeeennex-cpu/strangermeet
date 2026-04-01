import 'dart:math';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

/// Professional voice message bubble with waveform-style progress bar.
///
/// Shared across DM, community, and sub-group chat screens.
class VoiceMessageBubble extends StatefulWidget {
  final String audioUrl;
  final int durationSeconds;
  final bool isMe;
  final String time;
  final String status; // 'sent', 'delivered', 'read' — empty for group chats

  const VoiceMessageBubble({
    super.key,
    required this.audioUrl,
    required this.durationSeconds,
    required this.isMe,
    required this.time,
    this.status = '',
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  late final AudioPlayer _player;
  late final List<double> _waveformBars;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;

  static const Color _meBubbleColor = Color(0xFF1B5E20);
  static const Color _otherBubbleColor = Color(0xFF1E1E1E);
  static const int _barCount = 36;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _waveformBars = _generateWaveform(widget.audioUrl.hashCode);
    _totalDuration = Duration(seconds: widget.durationSeconds);
    _initPlayer();
  }

  /// Generate deterministic pseudo-random waveform bars from a seed.
  List<double> _generateWaveform(int seed) {
    final rng = Random(seed);
    return List.generate(_barCount, (_) => 0.15 + rng.nextDouble() * 0.85);
  }

  Future<void> _initPlayer() async {
    try {
      final dur = await _player.setUrl(widget.audioUrl);
      if (dur != null && mounted) {
        setState(() => _totalDuration = dur);
      }
    } catch (e) {
      debugPrint('Voice playback init error: $e');
    }

    _player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });

    _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state.playing);
        if (state.processingState == ProcessingState.completed) {
          _player.seek(Duration.zero);
          _player.pause();
        }
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _togglePlayback() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget? _buildStatusTick() {
    if (widget.status.isEmpty) return null;
    switch (widget.status) {
      case 'pending':
        return Icon(Icons.access_time, size: 14, color: Colors.grey[500]);
      case 'sent':
        return Icon(Icons.check, size: 14, color: Colors.grey[400]);
      case 'delivered':
        return Icon(Icons.done_all, size: 14, color: Colors.grey[400]);
      case 'read':
        return const Icon(Icons.done_all, size: 14, color: Colors.blue);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bubbleColor = widget.isMe ? _meBubbleColor : _otherBubbleColor;
    final progress = _totalDuration.inMilliseconds > 0
        ? (_position.inMilliseconds / _totalDuration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
          minWidth: 220,
        ),
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 6),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(widget.isMe ? 16 : 4),
            bottomRight: Radius.circular(widget.isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Play button + waveform + duration
            Row(
              children: [
                // Play / Pause button (spinner when pending)
                widget.status == 'pending'
                    ? Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : GestureDetector(
                        onTap: _togglePlayback,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                const SizedBox(width: 8),

                // Waveform bars
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: CustomPaint(
                      painter: _WaveformPainter(
                        bars: _waveformBars,
                        progress: progress,
                        playedColor: Colors.white,
                        unplayedColor: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Duration label
                Text(
                  _isPlaying || _position.inMilliseconds > 0
                      ? _formatDuration(_position)
                      : _formatDuration(_totalDuration),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),

            // Timestamp + status tick
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.time,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
                if (widget.isMe && widget.status.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  _buildStatusTick() ?? const SizedBox.shrink(),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Waveform CustomPainter ──────────────────────────────────────────────────

class _WaveformPainter extends CustomPainter {
  final List<double> bars;
  final double progress; // 0.0 – 1.0
  final Color playedColor;
  final Color unplayedColor;

  _WaveformPainter({
    required this.bars,
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;

    final barWidth = size.width / (bars.length * 1.6);
    final gap = barWidth * 0.6;
    final totalBarWidth = barWidth + gap;
    final startX = (size.width - (totalBarWidth * bars.length - gap)) / 2;
    final midY = size.height / 2;
    final maxBarHeight = size.height * 0.9;
    final progressIndex = (progress * bars.length).floor();

    final playedPaint = Paint()
      ..color = playedColor
      ..strokeCap = StrokeCap.round;

    final unplayedPaint = Paint()
      ..color = unplayedColor
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < bars.length; i++) {
      final barHeight = bars[i] * maxBarHeight;
      final halfBar = barHeight / 2;
      final x = startX + (i * totalBarWidth) + barWidth / 2;
      final paint = i <= progressIndex ? playedPaint : unplayedPaint;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x, midY),
            width: barWidth,
            height: barHeight.clamp(3.0, maxBarHeight),
          ),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
