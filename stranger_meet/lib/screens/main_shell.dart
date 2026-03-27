import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../config/theme.dart';
import '../providers/chat_provider.dart';
import '../services/websocket_service.dart';
import '../services/storage_service.dart';

class MainShell extends ConsumerStatefulWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _currentIndex = 2; // Default to Explore (center)
  StreamSubscription? _wsSubscription;
  String? _currentUserId;

  // In-app notification state
  OverlayEntry? _notificationOverlay;
  Timer? _notificationTimer;

  static const _routes = [
    '/main',          // 0 - Home
    '/communities',   // 1 - Communities
    '/explore',       // 2 - Explore (CENTER)
    '/conversations', // 3 - Chat
    '/profile',       // 4 - Profile
  ];

  @override
  void initState() {
    super.initState();
    _loadUserId();
    _setupNotificationListener();
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _notificationTimer?.cancel();
    _dismissNotification();
    super.dispose();
  }

  Future<void> _loadUserId() async {
    final userId = await StorageService().getUserId();
    if (mounted) setState(() => _currentUserId = userId);
  }

  void _setupNotificationListener() {
    final ws = WebSocketService();
    _wsSubscription = ws.messageStream.listen((data) {
      final type = data['type'];
      if (type == 'message') {
        final senderId = data['sender_id']?.toString() ?? '';
        final senderName = data['sender_name']?.toString() ?? 'Someone';
        final senderImage = data['sender_image']?.toString();
        final messageText = data['message']?.toString() ?? '';
        final messageType = data['message_type']?.toString() ?? 'text';

        // Don't show notification for own messages
        if (senderId == _currentUserId) return;

        // Don't show if user is already on that chat screen
        final location = GoRouterState.of(context).uri.toString();
        if (location.contains('/chat/$senderId')) return;

        // Update unread count
        ref.read(unreadCountProvider.notifier).fetchUnreadCount();

        // Show in-app notification popup
        final displayText = messageType == 'image' ? '📷 Photo' : messageText;
        _showNotificationPopup(
          senderId: senderId,
          senderName: senderName,
          senderImage: senderImage,
          message: displayText,
        );
      } else if (type == 'friend_request') {
        final senderName = data['sender_name']?.toString() ?? 'Someone';
        _showNotificationPopup(
          senderId: '',
          senderName: senderName,
          message: 'sent you a friend request',
          isFriendRequest: true,
        );
      }
    });
  }

  void _showNotificationPopup({
    required String senderId,
    required String senderName,
    String? senderImage,
    required String message,
    bool isFriendRequest = false,
  }) {
    _dismissNotification();

    _notificationOverlay = OverlayEntry(
      builder: (context) => _NotificationBanner(
        senderName: senderName,
        senderImage: senderImage,
        message: message,
        isFriendRequest: isFriendRequest,
        onTap: () {
          _dismissNotification();
          if (isFriendRequest) {
            context.push('/notifications');
          } else {
            context.push('/chat/$senderId');
          }
        },
        onDismiss: _dismissNotification,
      ),
    );

    Overlay.of(context).insert(_notificationOverlay!);

    // Auto-dismiss after 4 seconds
    _notificationTimer?.cancel();
    _notificationTimer = Timer(const Duration(seconds: 4), _dismissNotification);
  }

  void _dismissNotification() {
    _notificationOverlay?.remove();
    _notificationOverlay = null;
    _notificationTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    // Sync the bottom nav index with the current route
    final location = GoRouterState.of(context).uri.toString();
    for (int i = 0; i < _routes.length; i++) {
      if (location.startsWith(_routes[i])) {
        _currentIndex = i;
        break;
      }
    }

    return Scaffold(
      body: widget.child,
      extendBody: true,
      bottomNavigationBar: _buildBottomNavBar(context),
    );
  }

  Widget _buildBottomNavBar(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home,
                label: 'Home',
                isActive: _currentIndex == 0,
                onTap: () => _onTabTapped(0, context),
              ),
              _NavItem(
                icon: Icons.people_outlined,
                activeIcon: Icons.people,
                label: 'Groups',
                isActive: _currentIndex == 1,
                onTap: () => _onTabTapped(1, context),
              ),
              // ── Center Explore FAB ──
              _ExploreFab(
                isActive: _currentIndex == 2,
                onTap: () => _onTabTapped(2, context),
              ),
              _NavItemWithBadge(
                icon: Icons.chat_bubble_outline,
                activeIcon: Icons.chat_bubble,
                label: 'Chat',
                isActive: _currentIndex == 3,
                badgeCount: ref.watch(unreadCountProvider),
                onTap: () {
                  ref.read(unreadCountProvider.notifier).fetchUnreadCount();
                  _onTabTapped(3, context);
                },
              ),
              _NavItem(
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: 'Profile',
                isActive: _currentIndex == 4,
                onTap: () => _onTabTapped(4, context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onTabTapped(int index, BuildContext context) {
    if (index != _currentIndex) {
      setState(() => _currentIndex = index);
      context.go(_routes[index]);
    }
  }
}

// ── In-App Notification Banner ─────────────────────────────────────────────

class _NotificationBanner extends StatefulWidget {
  final String senderName;
  final String? senderImage;
  final String message;
  final bool isFriendRequest;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _NotificationBanner({
    required this.senderName,
    this.senderImage,
    required this.message,
    this.isFriendRequest = false,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_NotificationBanner> createState() => _NotificationBannerState();
}

class _NotificationBannerState extends State<_NotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: GestureDetector(
            onTap: widget.onTap,
            onVerticalDragEnd: (details) {
              if (details.velocity.pixelsPerSecond.dy < 0) {
                widget.onDismiss();
              }
            },
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(16),
              shadowColor: Colors.black.withOpacity(0.2),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    // Avatar
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: widget.isFriendRequest
                          ? AppTheme.primaryColor.withOpacity(0.2)
                          : AppTheme.surfaceColor,
                      backgroundImage: widget.senderImage != null &&
                              widget.senderImage!.isNotEmpty
                          ? CachedNetworkImageProvider(widget.senderImage!)
                          : null,
                      child: (widget.senderImage == null || widget.senderImage!.isEmpty)
                          ? Icon(
                              widget.isFriendRequest
                                  ? Icons.person_add
                                  : Icons.person,
                              size: 20,
                              color: widget.isFriendRequest
                                  ? AppTheme.primaryColor
                                  : Colors.grey[500],
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.senderName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.message,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // App icon / timestamp
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'now',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[400],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppTheme.primaryColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Center Explore FAB Button ──────────────────────────────────────────────

class _ExploreFab extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;

  const _ExploreFab({required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFC8E600),
                  Color(0xFFAAC800),
                ],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              Icons.explore,
              size: 28,
              color: isActive ? Colors.black : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              size: 26,
              color: isActive
                  ? AppTheme.textPrimary
                  : AppTheme.textSecondary,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight:
                    isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive
                    ? AppTheme.textPrimary
                    : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItemWithBadge extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final int badgeCount;
  final VoidCallback onTap;

  const _NavItemWithBadge({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.badgeCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isActive ? activeIcon : icon,
                  size: 26,
                  color: isActive
                      ? AppTheme.textPrimary
                      : AppTheme.textSecondary,
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        badgeCount > 9 ? '9+' : '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight:
                    isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive
                    ? AppTheme.textPrimary
                    : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
