import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // Call history tracking
  bool _weEndedCall = false;
  bool _wasRejected = false;

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
    if (widget.isVideo) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
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
      } else if (type == 'call_reject') {
        _wasRejected = true;
        _callService.handleRemoteEnd();
      } else if (type == 'call_end') {
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
    _callTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // Save call history log
    final duration = _elapsed.inSeconds;
    if (_weEndedCall) {
      if (duration > 0) {
        // Connected call — we ended it; save log (backend deduplicates)
        WebSocketService().sendCallLog(
          widget.peerId,
          duration: duration,
          isVideo: widget.isVideo,
          status: 'ended',
        );
      } else {
        // We cancelled before it was answered
        WebSocketService().sendCallLog(
          widget.peerId,
          duration: 0,
          isVideo: widget.isVideo,
          status: 'missed',
        );
      }
    } else if (_wasRejected) {
      // They declined our call
      WebSocketService().sendCallLog(
        widget.peerId,
        duration: 0,
        isVideo: widget.isVideo,
        status: 'declined',
      );
    }
    // If remote ended a connected call: they already sent the log; we'll receive it via WS

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
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
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
            onTap: () async { _weEndedCall = true; await _callService.endCall(); },
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
    final size = MediaQuery.of(context).size;
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    return GestureDetector(
      onTap: _onTapScreen,
      behavior: HitTestBehavior.opaque,
      child: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Remote video — true full screen ──────────────────────────
            _remoteRenderer.srcObject != null
                ? RTCVideoView(
                    _remoteRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : Container(
                    color: const Color(0xFF111111),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 72,
                            backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.25),
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
                          const SizedBox(height: 20),
                          Text(widget.peerName,
                              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text('Connecting video...',
                              style: TextStyle(color: Colors.grey[400], fontSize: 14)),
                        ],
                      ),
                    ),
                  ),

            // ── Top gradient ──────────────────────────────────────────────
            Positioned(
              top: 0, left: 0, right: 0,
              height: topPad + 100,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                  ),
                ),
              ),
            ),

            // ── Bottom gradient ───────────────────────────────────────────
            Positioned(
              bottom: 0, left: 0, right: 0,
              height: 240 + botPad,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withOpacity(0.85), Colors.transparent],
                  ),
                ),
              ),
            ),

            // ── Local PiP — bottom-right ──────────────────────────────────
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              bottom: botPad + 180,
              right: 16,
              width: 110,
              height: 160,
              child: GestureDetector(
                onTap: () {}, // prevent closing controls when tapping PiP
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _localRenderer.srcObject != null
                          ? RTCVideoView(
                              _localRenderer,
                              mirror: true,
                              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                            )
                          : Container(color: const Color(0xFF2A2A2A),
                              child: const Icon(Icons.videocam_off, color: Colors.white54, size: 28)),
                      // Border
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white30, width: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Top bar: name + timer ─────────────────────────────────────
            Positioned(
              top: topPad + 12,
              left: 20,
              right: 20,
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Row(
                  children: [
                    // Back/minimise
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.peerName,
                              style: const TextStyle(
                                color: Colors.white, fontSize: 17,
                                fontWeight: FontWeight.w700,
                                shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                              )),
                          Text(
                            _statusText,
                            style: TextStyle(
                              color: _callState == CallState.connected
                                  ? AppTheme.primaryColor
                                  : Colors.white70,
                              fontSize: 13,
                              shadows: const [Shadow(blurRadius: 6, color: Colors.black)],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Bottom controls ───────────────────────────────────────────
            AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, botPad + 36),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Top control row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _ControlButton(
                            icon: _callService.isMuted ? Icons.mic_off : Icons.mic,
                            label: _callService.isMuted ? 'Unmute' : 'Mute',
                            active: _callService.isMuted,
                            onTap: () { _callService.toggleMute(); setState(() {}); },
                          ),
                          _ControlButton(
                            icon: _callService.isCameraOff ? Icons.videocam_off : Icons.videocam,
                            label: _callService.isCameraOff ? 'Cam off' : 'Camera',
                            active: _callService.isCameraOff,
                            onTap: () { _callService.toggleCamera(); setState(() {}); },
                          ),
                          _ControlButton(
                            icon: Icons.flip_camera_ios,
                            label: 'Flip',
                            onTap: () async { await _callService.switchCamera(); },
                          ),
                          _ControlButton(
                            icon: _callService.isSpeakerOn ? Icons.volume_up : Icons.hearing,
                            label: _callService.isSpeakerOn ? 'Speaker' : 'Earpiece',
                            active: _callService.isSpeakerOn,
                            onTap: () { _callService.toggleSpeaker(); setState(() {}); },
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      // End call
                      GestureDetector(
                        onTap: () async { _weEndedCall = true; await _callService.endCall(); },
                        child: Container(
                          width: 72, height: 72,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.4), blurRadius: 16, spreadRadius: 2)],
                          ),
                          child: const Icon(Icons.call_end, color: Colors.white, size: 32),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable control button ────────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: active
                  ? Colors.white.withOpacity(0.9)
                  : Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: active ? Colors.black87 : Colors.white, size: 26),
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
