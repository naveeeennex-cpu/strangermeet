import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../config/theme.dart';
import '../../services/call_service.dart';
import '../../services/websocket_service.dart';
import 'call_screen.dart';

/// Full-screen incoming call overlay (like WhatsApp).
/// Shown when a `call_offer` WS message arrives while the app is open.
class IncomingCallScreen extends StatefulWidget {
  final String callerId;
  final String callerName;
  final String callerImage;
  final String offerSdp;
  final bool isVideo;
  final VoidCallback onDismiss;

  const IncomingCallScreen({
    super.key,
    required this.callerId,
    required this.callerName,
    required this.callerImage,
    required this.offerSdp,
    required this.isVideo,
    required this.onDismiss,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  Timer? _autoRejectTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    // Auto-reject after 60 seconds if no answer
    _autoRejectTimer = Timer(const Duration(seconds: 60), _reject);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _autoRejectTimer?.cancel();
    super.dispose();
  }

  void _reject() {
    WebSocketService().sendCallReject(widget.callerId);
    widget.onDismiss();
  }

  void _accept() async {
    _autoRejectTimer?.cancel();
    widget.onDismiss();
    // Open the call screen in "answering" mode
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          peerId: widget.callerId,
          peerName: widget.callerName,
          peerImage: widget.callerImage,
          isVideo: widget.isVideo,
          isIncoming: true,
          incomingOfferSdp: widget.offerSdp,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0A0A0A),
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),

            // Caller info
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final scale = 1.0 + (_pulseController.value * 0.04);
                return Transform.scale(scale: scale, child: child);
              },
              child: CircleAvatar(
                radius: 60,
                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.3),
                backgroundImage: widget.callerImage.isNotEmpty
                    ? CachedNetworkImageProvider(widget.callerImage)
                    : null,
                child: widget.callerImage.isEmpty
                    ? Text(
                        widget.callerName.isNotEmpty
                            ? widget.callerName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.callerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.isVideo ? 'Incoming video call...' : 'Incoming voice call...',
              style: TextStyle(color: Colors.grey[400], fontSize: 16),
            ),

            const Spacer(flex: 3),

            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 60),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Decline
                  _CallActionButton(
                    color: Colors.red,
                    icon: Icons.call_end,
                    label: 'Decline',
                    onTap: _reject,
                  ),
                  // Accept
                  _CallActionButton(
                    color: AppTheme.primaryColor,
                    icon: widget.isVideo ? Icons.videocam : Icons.call,
                    label: 'Accept',
                    iconColor: Colors.black,
                    labelColor: AppTheme.primaryColor,
                    onTap: _accept,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color? labelColor;
  final VoidCallback onTap;

  const _CallActionButton({
    required this.color,
    required this.icon,
    required this.label,
    this.iconColor = Colors.white,
    this.labelColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 32),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(
            color: labelColor ?? Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
