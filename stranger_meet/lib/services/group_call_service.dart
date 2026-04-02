import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'websocket_service.dart';

/// Manages a mesh of WebRTC peer connections for group voice/video calls.
/// Each participant connects to every other participant directly.
class GroupCallService {
  static final GroupCallService _instance = GroupCallService._();
  factory GroupCallService() => _instance;
  GroupCallService._();

  static const List<Map<String, dynamic>> _iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];

  // Peer connections: peerId -> RTCPeerConnection
  final Map<String, RTCPeerConnection> _peerConnections = {};
  // Remote streams: peerId -> MediaStream
  final Map<String, MediaStream> _remoteStreams = {};
  // Pending ICE candidates per peer (before remote desc is set)
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};
  // Track which peers have remote description set
  final Set<String> _remoteDescSet = {};

  MediaStream? _localStream;
  String? _subGroupId;
  bool _isVideo = false;
  bool _isAdmin = false;
  bool _isMuted = false;
  bool _isSpeakerOn = true;

  // Streams for UI
  final _remoteStreamAdded = StreamController<MapEntry<String, MediaStream>>.broadcast();
  Stream<MapEntry<String, MediaStream>> get onRemoteStreamAdded => _remoteStreamAdded.stream;

  final _remoteStreamRemoved = StreamController<String>.broadcast();
  Stream<String> get onRemoteStreamRemoved => _remoteStreamRemoved.stream;

  final _callEndedController = StreamController<void>.broadcast();
  Stream<void> get onCallEnded => _callEndedController.stream;

  final _stateController = StreamController<void>.broadcast();
  Stream<void> get onStateChanged => _stateController.stream;

  bool get isActive => _subGroupId != null;
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isVideo => _isVideo;
  bool get isAdmin => _isAdmin;
  MediaStream? get localStream => _localStream;
  Map<String, MediaStream> get remoteStreams => Map.unmodifiable(_remoteStreams);

  /// Admin starts a new group call
  Future<void> startCall(String subGroupId, String communityId, {bool isVideo = false}) async {
    _subGroupId = subGroupId;
    _isVideo = isVideo;
    _isAdmin = true;

    await _initLocalStream();
    WebSocketService().sendGroupCallStart(subGroupId, communityId, isVideo: isVideo);
  }

  /// Non-admin joins an existing call
  Future<void> joinCall(String subGroupId, List<String> existingParticipants, {bool isVideo = false}) async {
    _subGroupId = subGroupId;
    _isVideo = isVideo;
    _isAdmin = false;

    await _initLocalStream();
    WebSocketService().sendGroupCallJoin(subGroupId);

    // Send offers to all existing participants
    for (final peerId in existingParticipants) {
      await _createPeerAndOffer(peerId);
    }
  }

  /// Called when a new participant joins (we receive group_call_participant_joined)
  /// We wait for them to send us an offer (since the joiner initiates)
  void onParticipantJoined(String userId) {
    // The new joiner will send us an offer — we just wait
    debugPrint('GroupCall: participant joined: $userId');
  }

  /// Handle incoming offer from a peer
  Future<void> handleOffer(String senderId, String sdp) async {
    final pc = await _createPeerConnection(senderId);
    await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    _remoteDescSet.add(senderId);
    await _flushPendingCandidates(senderId);

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    WebSocketService().sendGroupCallAnswer(senderId, _subGroupId!, answer.sdp!);
  }

  /// Handle incoming answer from a peer
  Future<void> handleAnswer(String senderId, String sdp) async {
    final pc = _peerConnections[senderId];
    if (pc == null) return;
    await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
    _remoteDescSet.add(senderId);
    await _flushPendingCandidates(senderId);
  }

  /// Handle ICE candidate from a peer
  Future<void> handleIce(String senderId, String candidate, String sdpMid, int sdpMLineIndex) async {
    final ice = RTCIceCandidate(candidate, sdpMid, sdpMLineIndex);
    if (_remoteDescSet.contains(senderId) && _peerConnections.containsKey(senderId)) {
      await _peerConnections[senderId]!.addCandidate(ice);
    } else {
      _pendingCandidates.putIfAbsent(senderId, () => []).add(ice);
    }
  }

  /// Remove a peer who left the call
  void removePeer(String userId) {
    _peerConnections[userId]?.close();
    _peerConnections.remove(userId);
    _remoteStreams[userId]?.dispose();
    _remoteStreams.remove(userId);
    _pendingCandidates.remove(userId);
    _remoteDescSet.remove(userId);
    _remoteStreamRemoved.add(userId);
    _stateController.add(null);
  }

  /// Leave/end the call
  Future<void> endCall() async {
    if (_subGroupId != null) {
      if (_isAdmin) {
        WebSocketService().sendGroupCallEnd(_subGroupId!);
      } else {
        WebSocketService().sendGroupCallLeave(_subGroupId!);
      }
    }
    await _cleanup();
  }

  /// Called when admin ends the call (remote event)
  Future<void> handleCallEnded() async {
    _callEndedController.add(null);
    await _cleanup();
  }

  // Media controls
  void toggleMute() {
    _isMuted = !_isMuted;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !_isMuted);
    _stateController.add(null);
  }

  void toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    Helper.setSpeakerphoneOn(_isSpeakerOn);
    _stateController.add(null);
  }

  // Private helpers

  Future<void> _initLocalStream() async {
    final constraints = <String, dynamic>{
      'audio': true,
      'video': _isVideo ? {'facingMode': 'user', 'width': 640, 'height': 480} : false,
    };
    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
  }

  Future<void> _createPeerAndOffer(String peerId) async {
    final pc = await _createPeerConnection(peerId);
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    WebSocketService().sendGroupCallOffer(peerId, _subGroupId!, offer.sdp!, isVideo: _isVideo);
  }

  Future<RTCPeerConnection> _createPeerConnection(String peerId) async {
    final config = {
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
    };
    final pc = await createPeerConnection(config);

    // Add local tracks
    _localStream?.getTracks().forEach((track) {
      pc.addTrack(track, _localStream!);
    });

    // Remote track
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStreams[peerId] = event.streams.first;
        _remoteStreamAdded.add(MapEntry(peerId, event.streams.first));
        _stateController.add(null);
      }
    };

    // ICE candidate
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null && _subGroupId != null) {
        WebSocketService().sendGroupCallIce(
          peerId,
          _subGroupId!,
          candidate.candidate!,
          candidate.sdpMid ?? '',
          candidate.sdpMLineIndex ?? 0,
        );
      }
    };

    pc.onConnectionState = (state) {
      debugPrint('GroupCall peer $peerId state: $state');
    };

    _peerConnections[peerId] = pc;
    return pc;
  }

  Future<void> _flushPendingCandidates(String peerId) async {
    final pending = _pendingCandidates.remove(peerId);
    if (pending != null) {
      for (final c in pending) {
        try {
          await _peerConnections[peerId]?.addCandidate(c);
        } catch (_) {}
      }
    }
  }

  Future<void> _cleanup() async {
    for (final pc in _peerConnections.values) {
      await pc.close();
    }
    _peerConnections.clear();

    for (final stream in _remoteStreams.values) {
      await stream.dispose();
    }
    _remoteStreams.clear();
    _pendingCandidates.clear();
    _remoteDescSet.clear();

    await _localStream?.dispose();
    _localStream = null;
    _subGroupId = null;
    _isAdmin = false;
    _isMuted = false;
    _isSpeakerOn = true;
    _stateController.add(null);
  }
}
