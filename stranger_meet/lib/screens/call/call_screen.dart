import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../config/theme.dart';
import '../../services/call_service.dart';
import '../../services/websocket_service.dart';

/// In-call screen for both voice and video calls.
///
/// Supports:
/// - Outgoing: [isIncoming] = false → starts call immediately
/// - Incoming: [isIncoming] = true + [incomingOfferSdp] → answers call
class CallScreen extends StatefulWidget {
  final String peerId;
  final String peerName;
  final String peerImage;
  final bool isVideo;
  final bool isIncoming;
  final String? incomingOfferSdp;

  const CallScreen({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.peerImage,
    this.isVideo = false,
    this.isIncoming = false,
    this.incomingOfferSdp,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final CallService _callService = CallService();
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  StreamSubscription? _stateSubscription;
  StreamSubscription? _wsSubscription;
  StreamSubscription? _localStreamSub;
  StreamSubscription? _remoteStreamSub;

  CallState _callState = CallState.idle;
  Duration _elapsed = Duration.zero;
  Timer? _callTimer;
  bool _controlsVisible = true;
  Timer? _controlsHideTimer;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _subscribeToCallService();
    _listenWs();
    _startCall();
  }

  void _subscribeToCallService() {
    _stateSubscription = _callService.stateStream.listen((state) {
      if (!mounted) return;
      setState(() => _callState = state);
      if (state == CallState.connected && _callTimer == null) {
        _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
        });
      }
      if (state == CallState.ended || state == CallState.idle) {
        _leaveScreen();
      }
    });

    _localStreamSub = _callService.localStream.listen((stream) {
      if (!mounted) return;
      _localRenderer.srcObject = stream;
      setState(() {});
    });

    _remoteStreamSub = _callService.remoteStream.listen((stream) {
      if (!mounted) return;
      _remoteRenderer.srcObject = stream;
      setState(() {});
    });
  }

  void _listenWs() {
    _wsSubscription = WebSocketService().messageStream.listen((data) {
      final type = data['type'];
      if (type == 'call_answer') {
        final sdp = data['sdp']?.toString();
        if (sdp != null) _callService.handleAnswer(sdp);
      } else if (type == 'call_end' || type == 'call_reject') {
        _callService.handleRemoteEnd();
      } else if (type == 'ice_candidate') {
        final candidate = data['candidate']?.toString();
        final sdpMid = data['sdp_mid']?.toString() ?? '';
        final sdpMLineIndex = (data['sdp_m_line_index'] as num?)?.toInt() ?? 0;
        if (candidate != null) {
          _callService.handleIceCandidate(candidate, sdpMid, sdpMLineIndex);
        }
      }
    });
  }

  Future<void> _startCall() async {
    if (widget.isIncoming && widget.incomingOfferSdp != null) {
      await _callService.answerCall(
        widget.peerId,
        widget.incomingOfferSdp!,
        isVideo: widget.isVideo,
      );
    } else {
      await _callService.startCall(widget.peerId, isVideo: widget.isVideo);
    }

    // Assign streams if already available (after startCall)
    if (mounted) {
      _localRenderer.srcObject = _callService.localMediaStream;
      _remoteRenderer.srcObject = _callService.remoteMediaStream;
      setState(() {});
    }
  }

  void _leaveScreen() {
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _controlsHideTimer?.cancel();
    _stateSubscription?.cancel();
    _wsSubscription?.cancel();
    _localStreamSub?.cancel();
    _remoteStreamSub?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  String _formatElapsed(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _statusText {
    switch (_callState) {
      case CallState.calling:
        return 'Calling...';
      case CallState.ringing:
        return 'Connecting...';
      case CallState.connected:
        return _formatElapsed(_elapsed);
      case CallState.ended:
        return 'Call ended';
      default:
        return '';
    }
  }

  void _onTapScreen() {
    if (!widget.isVideo) return;
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _controlsHideTimer?.cancel();
      _controlsHideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _controlsVisible = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: widget.isVideo ? _buildVideoCall() : _buildVoiceCall(),
    );
  }

  // ── Voice call UI ──────────────────────────────────────────────────────────

  Widget _buildVoiceCall() {
    return SafeArea(
      child: Column(
        children: [
          const Spacer(flex: 2),

          // Peer avatar
          CircleAvatar(
            radius: 70,
            backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.3),
            backgroundImage: widget.peerImage.isNotEmpty
                ? CachedNetworkImageProvider(widget.peerImage)
                : null,
            child: widget.peerImage.isEmpty
                ? Text(
                    widget.peerName.isNotEmpty
                        ? widget.peerName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 24),
          Text(
            widget.peerName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _statusText,
            style: TextStyle(
              color: _callState == CallState.connected
                  ? AppTheme.primaryColor
                  : Colors.grey[400],
              fontSize: 16,
            ),
          ),

          const Spacer(flex: 3),

          // Controls
          _buildVoiceControls(),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildVoiceControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          // Top row: mute + speaker
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ControlButton(
                icon: _callService.isMuted ? Icons.mic_off : Icons.mic,
                label: _callService.isMuted ? 'Unmute' : 'Mute',
                onTap: () { _callService.toggleMute(); setState(() {}); },
              ),
              _ControlButton(
                icon: _callService.isSpeakerOn ? Icons.volume_up : Icons.hearing,
                label: _callService.isSpeakerOn ? 'Speaker' : 'Earpiece',
                onTap: () { _callService.toggleSpeaker(); setState(() {}); },
              ),
            ],
          ),
          const SizedBox(height: 32),

          // End call button
          GestureDetector(
            onTap: () async { await _callService.endCall(); },
            child: Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.call_end, color: Colors.white, size: 36),
            ),
          ),
        ],
      ),
    );
  }

  // ── Video call UI ──────────────────────────────────────────────────────────

  Widget _buildVideoCall() {
    return GestureDetector(
      onTap: _onTapScreen,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          // Remote (full screen)
          Positioned.fill(
            child: _remoteRenderer.srcObject != null
                ? RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                : Container(
                    color: const Color(0xFF1A1A1A),
                    child: Center(
                      child: CircleAvatar(
                        radius: 70,
                        backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.3),
                        backgroundImage: widget.peerImage.isNotEmpty
                            ? CachedNetworkImageProvider(widget.peerImage)
                            : null,
                        child: widget.peerImage.isEmpty
                            ? Text(
                                widget.peerName.isNotEmpty ? widget.peerName[0].toUpperCase() : '?',
                                style: const TextStyle(fontSize: 52, color: Colors.white, fontWeight: FontWeight.w700),
                              )
                            : null,
                      ),
                    ),
                  ),
          ),

          // Local preview (small, top-right)
          if (_localRenderer.srcObject != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              width: 100,
              height: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: RTCVideoView(
                  _localRenderer,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),

          // Status bar (top)
          SafeArea(
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Text(
                      widget.peerName,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 8)]),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _statusText,
                      style: TextStyle(
                        color: _callState == CallState.connected ? AppTheme.primaryColor : Colors.grey[300],
                        fontSize: 14,
                        shadows: const [Shadow(blurRadius: 8)],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Controls (bottom)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: _buildVideoControls(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoControls() {
    return Container(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 20,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ControlButton(
                icon: _callService.isMuted ? Icons.mic_off : Icons.mic,
                label: _callService.isMuted ? 'Unmute' : 'Mute',
                onTap: () { _callService.toggleMute(); setState(() {}); },
              ),
              _ControlButton(
                icon: _callService.isCameraOff ? Icons.videocam_off : Icons.videocam,
                label: _callService.isCameraOff ? 'Camera off' : 'Camera',
                onTap: () { _callService.toggleCamera(); setState(() {}); },
              ),
              _ControlButton(
                icon: Icons.flip_camera_ios,
                label: 'Flip',
                onTap: () async { await _callService.switchCamera(); },
              ),
              _ControlButton(
                icon: _callService.isSpeakerOn ? Icons.volume_up : Icons.hearing,
                label: 'Speaker',
                onTap: () { _callService.toggleSpeaker(); setState(() {}); },
              ),
            ],
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () async { await _callService.endCall(); },
            child: Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              child: const Icon(Icons.call_end, color: Colors.white, size: 32),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable control button ────────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ControlButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
