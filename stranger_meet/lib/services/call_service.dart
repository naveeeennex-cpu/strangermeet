import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'websocket_service.dart';

enum CallState { idle, calling, ringing, connected, ended }

/// Singleton service that manages a single WebRTC peer connection for voice/video calls.
///
/// Usage:
///   - Caller: `await CallService().startCall(peerId, isVideo: false)`
///   - Callee: `await CallService().answerCall(peerId, offerSdp, isVideo: false)`
///   - Both: listen to [stateStream] and [remoteStream] for UI updates.
class CallService {
  static final CallService _instance = CallService._();
  factory CallService() => _instance;
  CallService._();

  static const List<Map<String, dynamic>> _iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  // Pending ICE candidates that arrived before remote description was set
  final List<RTCIceCandidate> _pendingCandidates = [];

  String? _peerId;
  bool _isVideo = false;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isCameraOff = false;
  bool _remoteDescSet = false;

  // Streams for UI
  final _stateController = StreamController<CallState>.broadcast();
  Stream<CallState> get stateStream => _stateController.stream;

  final _localStreamController = StreamController<MediaStream?>.broadcast();
  Stream<MediaStream?> get localStream => _localStreamController.stream;

  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  Stream<MediaStream?> get remoteStream => _remoteStreamController.stream;

  CallState _state = CallState.idle;
  CallState get state => _state;
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isCameraOff => _isCameraOff;
  bool get isVideo => _isVideo;
  MediaStream? get localMediaStream => _localStream;
  MediaStream? get remoteMediaStream => _remoteStream;

  void _setState(CallState s) {
    _state = s;
    _stateController.add(s);
  }

  // ── Outgoing call ──────────────────────────────────────────────────────────

  Future<void> startCall(String peerId, {bool isVideo = false}) async {
    if (_state != CallState.idle) return;
    _peerId = peerId;
    _isVideo = isVideo;
    _setState(CallState.calling);

    await _initLocalStream();
    await _createPeerConnection();

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    WebSocketService().sendCallOffer(peerId, offer.sdp!, isVideo: isVideo);
  }

  // ── Incoming call — accept ─────────────────────────────────────────────────

  Future<void> answerCall(String peerId, String offerSdp, {bool isVideo = false}) async {
    _peerId = peerId;
    _isVideo = isVideo;
    _setState(CallState.ringing);

    await _initLocalStream();
    await _createPeerConnection();

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(offerSdp, 'offer'),
    );
    _remoteDescSet = true;
    await _flushPendingCandidates();

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    WebSocketService().sendCallAnswer(peerId, answer.sdp!);
    _setState(CallState.connected);
  }

  // ── Called when remote answer arrives (on caller side) ────────────────────

  Future<void> handleAnswer(String sdp) async {
    if (_peerConnection == null) return;
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(sdp, 'answer'),
    );
    _remoteDescSet = true;
    await _flushPendingCandidates();
    _setState(CallState.connected);
  }

  // ── ICE candidate exchange ─────────────────────────────────────────────────

  Future<void> handleIceCandidate(String candidate, String sdpMid, int sdpMLineIndex) async {
    final iceCandidate = RTCIceCandidate(candidate, sdpMid, sdpMLineIndex);
    if (_remoteDescSet && _peerConnection != null) {
      await _peerConnection!.addCandidate(iceCandidate);
    } else {
      _pendingCandidates.add(iceCandidate);
    }
  }

  Future<void> _flushPendingCandidates() async {
    for (final c in _pendingCandidates) {
      try { await _peerConnection!.addCandidate(c); } catch (_) {}
    }
    _pendingCandidates.clear();
  }

  // ── End call ───────────────────────────────────────────────────────────────

  Future<void> endCall() async {
    if (_peerId != null && _state != CallState.idle) {
      WebSocketService().sendCallEnd(_peerId!);
    }
    await _cleanup();
  }

  Future<void> handleRemoteEnd() async {
    await _cleanup();
  }

  // ── Media controls ─────────────────────────────────────────────────────────

  void toggleMute() {
    _isMuted = !_isMuted;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !_isMuted);
    _stateController.add(_state); // trigger UI rebuild
  }

  void toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    // flutter_webrtc handles speaker via MediaStreamTrack settings
    Helper.setSpeakerphoneOn(_isSpeakerOn);
    _stateController.add(_state);
  }

  void toggleCamera() {
    _isCameraOff = !_isCameraOff;
    _localStream?.getVideoTracks().forEach((t) => t.enabled = !_isCameraOff);
    _stateController.add(_state);
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks();
    if (tracks != null && tracks.isNotEmpty) {
      await Helper.switchCamera(tracks.first);
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _initLocalStream() async {
    final constraints = <String, dynamic>{
      'audio': true,
      'video': _isVideo
          ? {'facingMode': 'user', 'width': 640, 'height': 480}
          : false,
    };
    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    _localStreamController.add(_localStream);
  }

  Future<void> _createPeerConnection() async {
    final config = {
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
    };
    _peerConnection = await createPeerConnection(config);

    // Add local tracks
    _localStream?.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    // Remote track — build remote stream
    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        _remoteStreamController.add(_remoteStream);
      }
    };

    // ICE candidate — send to peer
    _peerConnection!.onIceCandidate = (candidate) {
      if (_peerId != null && candidate.candidate != null) {
        WebSocketService().sendIceCandidate(
          _peerId!,
          candidate.candidate!,
          candidate.sdpMid ?? '',
          candidate.sdpMLineIndex ?? 0,
        );
      }
    };

    _peerConnection!.onConnectionState = (state) {
      debugPrint('WebRTC connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _cleanup();
      }
    };
  }

  Future<void> _cleanup() async {
    _setState(CallState.ended);
    _remoteDescSet = false;
    _pendingCandidates.clear();
    _peerId = null;
    _isMuted = false;
    _isSpeakerOn = true;
    _isCameraOff = false;

    await _localStream?.dispose();
    _localStream = null;
    _localStreamController.add(null);

    await _remoteStream?.dispose();
    _remoteStream = null;
    _remoteStreamController.add(null);

    await _peerConnection?.close();
    _peerConnection = null;

    // Small delay then reset to idle
    await Future.delayed(const Duration(milliseconds: 500));
    _setState(CallState.idle);
  }
}
