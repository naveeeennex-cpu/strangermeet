import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../config/theme.dart';
import '../services/api_service.dart';

/// WhatsApp-style hold-to-record voice button.
///
/// Replaces the send button when the text field is empty.
/// Hold to record, release to send, slide left to cancel.
class VoiceRecordButton extends StatefulWidget {
  /// Called after the recording is uploaded. Returns the public URL and duration.
  final Future<void> Function(String audioUrl, int durationSeconds) onVoiceSent;
  final bool isEnabled;

  const VoiceRecordButton({
    super.key,
    required this.onVoiceSent,
    this.isEnabled = true,
  });

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton>
    with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isUploading = false;
  bool _isCancelled = false;
  Duration _recordDuration = Duration.zero;
  Timer? _durationTimer;
  double _dragOffset = 0;
  late AnimationController _pulseController;

  static const double _cancelThreshold = -100.0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _pulseController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<String> _getTempPath() async {
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${dir.path}/voice_$timestamp.m4a';
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) return;

      final path = await _getTempPath();
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
        path: path,
      );

      HapticFeedback.mediumImpact();

      setState(() {
        _isRecording = true;
        _isCancelled = false;
        _recordDuration = Duration.zero;
        _dragOffset = 0;
      });

      _pulseController.repeat(reverse: true);

      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _recordDuration += const Duration(seconds: 1);
          });
        }
      });
    } catch (e) {
      debugPrint('Voice record start error: $e');
    }
  }

  Future<void> _stopRecording() async {
    _durationTimer?.cancel();
    _pulseController.stop();
    _pulseController.reset();

    if (!_isRecording) return;

    try {
      final path = await _recorder.stop();
      final wasCancelled = _isCancelled;
      final duration = _recordDuration.inSeconds;

      setState(() {
        _isRecording = false;
        _dragOffset = 0;
      });

      // Discard if cancelled or too short
      if (wasCancelled || duration < 1 || path == null) {
        if (path != null) {
          try {
            await File(path).delete();
          } catch (_) {}
        }
        return;
      }

      // Upload
      setState(() => _isUploading = true);
      try {
        final bytes = await File(path).readAsBytes();
        final fileName = path.split('/').last;

        final formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: fileName),
          'folder': 'voice_messages',
        });

        final api = ApiService();
        final uploadResponse =
            await api.uploadFile('/upload', formData: formData);
        final audioUrl =
            uploadResponse.data['url'] ?? uploadResponse.data['image_url'] ?? '';

        if (audioUrl.isNotEmpty) {
          await widget.onVoiceSent(audioUrl, duration);
        }

        // Clean up temp file
        try {
          await File(path).delete();
        } catch (_) {}
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to send voice message: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isUploading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _isUploading = false;
        });
      }
      debugPrint('Voice record stop error: $e');
    }
  }

  void _onDragUpdate(LongPressMoveUpdateDetails details) {
    if (!_isRecording) return;
    setState(() {
      _dragOffset = details.offsetFromOrigin.dx.clamp(-200.0, 0.0);
      if (_dragOffset <= _cancelThreshold && !_isCancelled) {
        _isCancelled = true;
        HapticFeedback.heavyImpact();
      }
    });
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (_isUploading) {
      return Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          color: AppTheme.primaryColor,
          shape: BoxShape.circle,
        ),
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.black,
          ),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.centerRight,
      children: [
        // Recording overlay — shown to the left of the mic button
        if (_isRecording)
          Positioned(
            right: 56,
            child: _buildRecordingOverlay(),
          ),

        // Mic button
        GestureDetector(
          onLongPressStart: widget.isEnabled ? (_) => _startRecording() : null,
          onLongPressMoveUpdate: _onDragUpdate,
          onLongPressEnd: (_) => _stopRecording(),
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final scale = _isRecording
                  ? 1.0 + (_pulseController.value * 0.15)
                  : 1.0;
              return Transform.scale(scale: scale, child: child);
            },
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _isRecording
                    ? (_isCancelled ? Colors.grey[700] : Colors.red)
                    : AppTheme.primaryColor,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isRecording ? Icons.mic : Icons.mic_none,
                color: _isRecording ? Colors.white : Colors.black,
                size: 24,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingOverlay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Red recording dot
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Opacity(
                opacity: 0.4 + (_pulseController.value * 0.6),
                child: child,
              );
            },
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Duration
          Text(
            _formatDuration(_recordDuration),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 16),

          // Slide to cancel
          if (!_isCancelled)
            Opacity(
              opacity: (1.0 + (_dragOffset / 150)).clamp(0.3, 1.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left,
                      color: Colors.grey[400], size: 18),
                  Text(
                    'Slide to cancel',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              'Cancelled',
              style: TextStyle(color: Colors.red[300], fontSize: 13),
            ),
        ],
      ),
    );
  }
}
