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
/// Two-phase callbacks:
/// - [onRecordingDone] fires immediately when user releases → add a pending bubble
/// - [onUploadComplete] fires after upload succeeds → replace pending with real message
/// - [onUploadFailed] fires on error → remove the pending bubble
class VoiceRecordButton extends StatefulWidget {
  final Future<void> Function(String tempId, String localPath, int durationSeconds) onRecordingDone;
  final Future<void> Function(String tempId, String audioUrl, int durationSeconds) onUploadComplete;
  final Future<void> Function(String tempId) onUploadFailed;
  final bool isEnabled;

  const VoiceRecordButton({
    super.key,
    required this.onRecordingDone,
    required this.onUploadComplete,
    required this.onUploadFailed,
    this.isEnabled = true,
  });

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton>
    with TickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isCancelled = false;
  Duration _recordDuration = Duration.zero;
  Timer? _durationTimer;
  double _dragOffset = 0;

  // Slow breathing pulse while recording
  late AnimationController _pulseController;
  // Quick pop-scale when recording starts
  late AnimationController _popController;
  late Animation<double> _popAnimation;

  static const double _cancelThreshold = -100.0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    // 1.0 → 1.45 → 1.2  quick spring pop
    _popAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.45), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.45, end: 1.20), weight: 60),
    ]).animate(CurvedAnimation(parent: _popController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _pulseController.dispose();
    _popController.dispose();
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

      // Click sound + strong haptic on record start
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.heavyImpact();

      final path = await _getTempPath();
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
        path: path,
      );

      setState(() {
        _isRecording = true;
        _isCancelled = false;
        _recordDuration = Duration.zero;
        _dragOffset = 0;
      });

      // Quick pop then slow breathing pulse
      _popController.forward(from: 0).then((_) {
        if (_isRecording) _pulseController.repeat(reverse: true);
      });

      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordDuration += const Duration(seconds: 1));
      });
    } catch (e) {
      debugPrint('Voice record start error: $e');
    }
  }

  Future<void> _stopRecording() async {
    _durationTimer?.cancel();
    _pulseController.stop();
    _pulseController.reset();
    _popController.reset();

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
          try { await File(path).delete(); } catch (_) {}
        }
        return;
      }

      // 1. Fire immediately — chat screen adds pending bubble right away
      final tempId = 'temp_voice_${DateTime.now().millisecondsSinceEpoch}';
      await widget.onRecordingDone(tempId, path, duration);

      // 2. Upload in background
      try {
        final bytes = await File(path).readAsBytes();
        final fileName = path.split('/').last;
        final formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: fileName),
          'folder': 'voice_messages',
        });

        final uploadResponse = await ApiService().uploadFile('/upload', formData: formData);
        final audioUrl = uploadResponse.data['url'] ?? uploadResponse.data['image_url'] ?? '';

        if (audioUrl.isNotEmpty) {
          await widget.onUploadComplete(tempId, audioUrl, duration);
        } else {
          await widget.onUploadFailed(tempId);
        }
      } catch (e) {
        await widget.onUploadFailed(tempId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to send voice message: $e')),
          );
        }
      } finally {
        try { await File(path).delete(); } catch (_) {}
      }
    } catch (e) {
      if (mounted) setState(() { _isRecording = false; });
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
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.centerRight,
      children: [
        if (_isRecording)
          Positioned(
            right: 56,
            child: _buildRecordingOverlay(),
          ),

        GestureDetector(
          onLongPressStart: widget.isEnabled ? (_) => _startRecording() : null,
          onLongPressMoveUpdate: _onDragUpdate,
          onLongPressEnd: (_) => _stopRecording(),
          child: AnimatedBuilder(
            animation: Listenable.merge([_pulseController, _popController]),
            builder: (context, child) {
              double scale;
              if (_popController.isAnimating) {
                scale = _popAnimation.value;
              } else if (_isRecording) {
                scale = 1.2 + (_pulseController.value * 0.12);
              } else {
                scale = 1.0;
              }
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
                boxShadow: _isRecording
                    ? [BoxShadow(color: Colors.red.withValues(alpha: 0.45), blurRadius: 12, spreadRadius: 2)]
                    : [],
              ),
              child: Icon(
                _isRecording ? Icons.mic : Icons.mic_none,
                color: _isRecording ? Colors.white : Colors.black,
                size: 26,
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
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) => Opacity(
              opacity: 0.4 + (_pulseController.value * 0.6),
              child: child,
            ),
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 8),
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
          if (!_isCancelled)
            Opacity(
              opacity: (1.0 + (_dragOffset / 150)).clamp(0.3, 1.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left, color: Colors.grey[400], size: 18),
                  Text('Slide to cancel', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                ],
              ),
            )
          else
            Text('Cancelled', style: TextStyle(color: Colors.red[300], fontSize: 13)),
        ],
      ),
    );
  }
}
