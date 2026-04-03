import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../config/theme.dart';
import '../../services/api_service.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  final ApiService _api = ApiService();

  List<Map<String, dynamic>> _friendRequests = [];
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _fetchFriendRequests(),
      _fetchNotifications(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchFriendRequests() async {
    try {
      final res = await _api.get('/friends/requests');
      final data = res.data;
      final list = data is List ? data : [];
      if (mounted) {
        setState(() {
          _friendRequests = list.cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchNotifications() async {
    try {
      final res = await _api.get('/notifications');
      final data = res.data;
      final list = data is List ? data : [];
      if (mounted) {
        setState(() {
          _notifications = list.cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {}
  }

  Future<void> _acceptRequest(String requestId, int index) async {
    try {
      await _api.post('/friends/accept/$requestId');
      setState(() => _friendRequests.removeAt(index));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Friend request accepted'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _declineRequest(String requestId, int index) async {
    try {
      await _api.post('/friends/reject/$requestId');
      setState(() => _friendRequests.removeAt(index));
    } catch (_) {}
  }

  Future<void> _markRead(String notifId, int index) async {
    if (_notifications[index]['is_read'] == true) return;
    setState(() => _notifications[index]['is_read'] = true);
    try {
      await _api.post('/notifications/$notifId/read');
    } catch (_) {}
  }

  Future<void> _markAllRead() async {
    setState(() {
      for (final n in _notifications) {
        n['is_read'] = true;
      }
    });
    try {
      await _api.post('/notifications/read-all');
    } catch (_) {}
  }

  int get _unreadCount =>
      _notifications.where((n) => n['is_read'] != true).length;

  @override
  Widget build(BuildContext context) {
    final hasContent = _friendRequests.isNotEmpty || _notifications.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text(
                'Mark all read',
                style: TextStyle(
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !hasContent
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _loadAll,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      // ── Friend Requests ──
                      if (_friendRequests.isNotEmpty) ...[
                        _SectionHeader(
                          label: 'Friend Requests',
                          count: _friendRequests.length,
                        ),
                        ..._friendRequests.asMap().entries.map(
                              (e) => _FriendRequestCard(
                                req: e.value,
                                onAccept: () =>
                                    _acceptRequest(e.value['id']?.toString() ?? '', e.key),
                                onDecline: () =>
                                    _declineRequest(e.value['id']?.toString() ?? '', e.key),
                              ),
                            ),
                      ],

                      // ── Activity Notifications ──
                      if (_notifications.isNotEmpty) ...[
                        _SectionHeader(
                          label: 'Activity',
                          count: _unreadCount > 0 ? _unreadCount : null,
                        ),
                        ..._notifications.asMap().entries.map(
                              (e) => _NotificationCard(
                                notif: e.value,
                                onTap: () {
                                  _markRead(e.value['id']?.toString() ?? '', e.key);
                                  _handleNotifTap(e.value);
                                },
                              ),
                            ),
                      ],
                    ],
                  ),
                ),
    );
  }

  void _handleNotifTap(Map<String, dynamic> notif) {
    final type = notif['type']?.toString() ?? '';
    final data = notif['data'] as Map<String, dynamic>? ?? {};
    if (type == 'event_update') {
      final communityId = data['community_id']?.toString();
      final eventId = data['event_id']?.toString();
      if (communityId != null && eventId != null) {
        context.push('/community/$communityId/event/$eventId');
      }
    }
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_none_outlined,
              size: 64, color: Colors.grey[600]),
          const SizedBox(height: 16),
          const Text(
            'All caught up',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'No notifications right now.',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}

// ── Section Header ────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final int? count;

  const _SectionHeader({required this.label, this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          if (count != null && count! > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Friend Request Card ───────────────────────────────────────────

class _FriendRequestCard extends StatelessWidget {
  final Map<String, dynamic> req;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _FriendRequestCard({
    required this.req,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final name = req['requester_name'] ?? 'Unknown';
    final image = req['requester_image']?.toString();
    final requesterId = req['requester_id']?.toString() ?? '';
    final communities =
        (req['communities'] as List?)?.cast<String>() ?? [];
    final createdAt = req['created_at'] != null
        ? DateTime.tryParse(req['created_at'])
        : null;

    final isDarkReq = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDarkReq ? const Color(0xFF1E1E1E) : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDarkReq ? Colors.white.withOpacity(0.1) : Theme.of(context).dividerColor,
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.push('/user/$requesterId'),
            child: CircleAvatar(
              radius: 26,
              backgroundColor: AppTheme.primaryColor.withOpacity(0.15),
              backgroundImage: (image != null && image.isNotEmpty)
                  ? CachedNetworkImageProvider(image)
                  : null,
              child: (image == null || image.isEmpty)
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 18),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => context.push('/user/$requesterId'),
                  child: Text(
                    name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  createdAt != null
                      ? 'Sent ${timeago.format(createdAt)}'
                      : 'Wants to connect with you',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
                if (communities.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.people_outline,
                          size: 12, color: AppTheme.primaryColor),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          communities.join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 34,
                        child: ElevatedButton(
                          onPressed: onAccept,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Accept',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 34,
                        child: OutlinedButton(
                          onPressed: onDecline,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(context).brightness == Brightness.dark
                                ? Colors.grey[300]
                                : Colors.grey[600],
                            side: BorderSide(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Colors.grey.shade500
                                  : Colors.grey.shade400,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Decline',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Activity Notification Card ────────────────────────────────────

class _NotificationCard extends StatelessWidget {
  final Map<String, dynamic> notif;
  final VoidCallback onTap;

  const _NotificationCard({required this.notif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final type = notif['type']?.toString() ?? 'general';
    final title = notif['title']?.toString() ?? '';
    final body = notif['body']?.toString() ?? '';
    final isRead = notif['is_read'] == true;
    final createdAt = notif['created_at'] != null
        ? DateTime.tryParse(notif['created_at'].toString())
        : null;

    IconData icon;
    Color iconColor;
    switch (type) {
      case 'event_update':
        icon = Icons.event_note_outlined;
        iconColor = AppTheme.primaryColor;
        break;
      case 'friend_request':
        icon = Icons.person_add_outlined;
        iconColor = Colors.blue;
        break;
      default:
        icon = Icons.notifications_outlined;
        iconColor = Colors.grey;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRead
              ? Theme.of(context).colorScheme.surface
              : AppTheme.primaryColor.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isRead
                ? Theme.of(context).dividerColor
                : AppTheme.primaryColor.withOpacity(0.25),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight:
                          isRead ? FontWeight.w500 : FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[500],
                      height: 1.4,
                    ),
                  ),
                  if (createdAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      timeago.format(createdAt),
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ),
            if (!isRead)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(
                  color: AppTheme.primaryColor,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
