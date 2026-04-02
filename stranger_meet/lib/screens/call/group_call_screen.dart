import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../config/theme.dart';
import '../../services/group_call_service.dart';
import '../../services/websocket_service.dart';

class GroupCallScreen extends StatefulWidget {
  final String subGroupId;
  final String communityId;
  final String groupName;
  final bool isVideo;
  final bool isAdmin;
  final List<String> existingParticipants;
  final Map<String, String> participantNames;
  final Map<String, String> participantImages;

  const GroupCallScreen({
    super.key,
    required this.subGroupId,
    required this.communityId,
    required this.groupName,
    this.isVideo = false,
    this.isAdmin = false,
    this.existingParticipants = const [],
    this.participantNames = const {},
    this.participantImages = const {},
  });

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  final GroupCallService _service = GroupCallService();
  StreamSubscription? _wsSubscription;
  StreamSubscription? _stateSubscription;
  StreamSubscription? _endedSubscription;
  StreamSubscription? _remoteAddedSub;
  StreamSubscription? _remoteRemovedSub;

  Duration _elapsed = Duration.zero;
  Timer? _callTimer;

  // Track participants and their names/images
  List<String> _participants = [];
  final Map<String, String> _participantNames = {};
  final Map<String, String> _participantImages = {};

  @override
  void initState() {
    super.initState();
    _participantNames.addAll(widget.participantNames);
    _participantImages.addAll(widget.participantImages);
    _participants = List.from(widget.existingParticipants);
    _init();
  }

  Future<void> _init() async {
    _listenWs();
    _stateSubscription = _service.onStateChanged.listen((_) {
      if (mounted) setState(() {});
    });
    _endedSubscription = _service.onCallEnded.listen((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Call ended by admin')),
        );
        Navigator.of(context).pop();
      }
    });
    _remoteAddedSub = _service.onRemoteStreamAdded.listen((_) {
      if (mounted) setState(() {});
    });
    _remoteRemovedSub = _service.onRemoteStreamRemoved.listen((_) {
      if (mounted) setState(() {});
    });

    if (widget.isAdmin) {
      await _service.startCall(widget.subGroupId, widget.communityId, isVideo: widget.isVideo);
    } else {
      await _service.joinCall(widget.subGroupId, widget.existingParticipants, isVideo: widget.isVideo);
    }

    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  void _listenWs() {
    _wsSubscription = WebSocketService().messageStream.listen((data) {
      if (!mounted) return;
      final type = data['type'];
      final sgId = data['sub_group_id'];
      if (sgId != widget.subGroupId) return;

      switch (type) {
        case 'group_call_offer':
          _service.handleOffer(data['sender_id'], data['sdp']);
          break;
        case 'group_call_answer':
          _service.handleAnswer(data['sender_id'], data['sdp']);
          break;
        case 'group_call_ice':
          _service.handleIce(
            data['sender_id'],
            data['candidate'],
            data['sdp_mid'] ?? '',
            data['sdp_m_line_index'] ?? 0,
          );
          break;
        case 'group_call_participant_joined':
          final userId = data['user_id'];
          final userName = data['user_name'] ?? 'User';
          final userImage = data['user_image'] ?? '';
          final participants = List<String>.from(data['participants'] ?? []);
          setState(() {
            _participants = participants;
            _participantNames[userId] = userName;
            _participantImages[userId] = userImage;
          });
          _service.onParticipantJoined(userId);
          break;
        case 'group_call_participant_left':
          final userId = data['user_id'];
          final participants = List<String>.from(data['participants'] ?? []);
          setState(() => _participants = participants);
          _service.removePeer(userId);
          break;
        case 'group_call_ended':
          _service.handleCallEnded();
          break;
      }
    });
  }

  Future<void> _endCall() async {
    await _service.endCall();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _wsSubscription?.cancel();
    _stateSubscription?.cancel();
    _endedSubscription?.cancel();
    _remoteAddedSub?.cancel();
    _remoteRemovedSub?.cancel();
    // Cleanup if still active (user pressed back)
    if (_service.isActive) {
      _service.endCall();
    }
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                children: [
                  Text(
                    widget.groupName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDuration(_elapsed),
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_participants.length} participant${_participants.length != 1 ? 's' : ''}',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Participants grid
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _buildParticipantsGrid(),
              ),
            ),

            // Controls
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 16, 32, 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ControlButton(
                    icon: _service.isMuted ? Icons.mic_off : Icons.mic,
                    label: _service.isMuted ? 'Unmute' : 'Mute',
                    isActive: _service.isMuted,
                    onTap: () {
                      _service.toggleMute();
                      setState(() {});
                    },
                  ),
                  _ControlButton(
                    icon: _service.isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                    label: 'Speaker',
                    isActive: _service.isSpeakerOn,
                    onTap: () {
                      _service.toggleSpeaker();
                      setState(() {});
                    },
                  ),
                  // End call button
                  GestureDetector(
                    onTap: _endCall,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.call_end, color: Colors.white, size: 30),
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

  Widget _buildParticipantsGrid() {
    // Show circular avatars for voice call participants
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _participants.length <= 2 ? 1 : 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: _participants.length <= 2 ? 1.2 : 1.0,
      ),
      itemCount: _participants.length,
      itemBuilder: (context, index) {
        final pid = _participants[index];
        final name = _participantNames[pid] ?? 'User';
        final image = _participantImages[pid] ?? '';
        final hasRemoteStream = _service.remoteStreams.containsKey(pid);
        final isLocalUser = !hasRemoteStream && index == 0 && widget.isAdmin ||
            !hasRemoteStream && _participants.indexOf(pid) == _participants.length - 1 && !widget.isAdmin;

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2A2A2A),
                border: Border.all(
                  color: hasRemoteStream || isLocalUser
                      ? AppTheme.primaryColor
                      : Colors.grey[700]!,
                  width: 2,
                ),
                image: image.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(image),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: image.isEmpty
                  ? Center(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (hasRemoteStream)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.graphic_eq, size: 14, color: AppTheme.primaryColor),
                  const SizedBox(width: 4),
                  Text('Connected', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    this.isActive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isActive ? Colors.white.withOpacity(0.2) : const Color(0xFF2A2A2A),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 11)),
        ],
      ),
    );
  }
}
