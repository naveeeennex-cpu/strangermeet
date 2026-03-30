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

class _NotificationsScreenState extends ConsumerState<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ApiService _api = ApiService();

  List<Map<String, dynamic>> _friendRequests = [];
  List<Map<String, dynamic>> _chatNotifications = [];
  bool _isLoadingRequests = true;
  bool _isLoadingChats = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchFriendRequests();
    _fetchChatNotifications();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchFriendRequests() async {
    try {
      final response = await _api.get('/friends/requests');
      final data = response.data;
      final List<dynamic> results = data is List ? data : [];
      setState(() {
        _friendRequests = results.cast<Map<String, dynamic>>();
        _isLoadingRequests = false;
      });
    } catch (e) {
      setState(() => _isLoadingRequests = false);
    }
  }

  Future<void> _fetchChatNotifications() async {
    try {
      final response = await _api.get('/messages');
      final data = response.data;
      final List<dynamic> results = data is List ? data : [];
      // Filter to show only unread or recent messages
      setState(() {
        _chatNotifications = results.cast<Map<String, dynamic>>();
        _isLoadingChats = false;
      });
    } catch (e) {
      setState(() => _isLoadingChats = false);
    }
  }

  Future<void> _acceptRequest(String requestId, int index) async {
    try {
      await _api.post('/friends/accept/$requestId');
      setState(() {
        _friendRequests.removeAt(index);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Friend request accepted!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  Future<void> _rejectRequest(String requestId, int index) async {
    try {
      await _api.post('/friends/reject/$requestId');
      setState(() {
        _friendRequests.removeAt(index);
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryColor,
          indicatorWeight: 3,
          labelColor: Theme.of(context).textTheme.bodyLarge?.color,
          unselectedLabelColor: Theme.of(context).textTheme.bodySmall?.color,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_add, size: 18),
                  const SizedBox(width: 6),
                  const Text('Requests'),
                  if (_friendRequests.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_friendRequests.length}',
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
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.chat_bubble_outline, size: 18),
                  const SizedBox(width: 6),
                  const Text('Messages'),
                  if (_chatNotifications.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_chatNotifications.length}',
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
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildRequestsTab(),
          _buildChatsTab(),
        ],
      ),
    );
  }

  Widget _buildRequestsTab() {
    if (_isLoadingRequests) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_friendRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_add_outlined, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No friend requests',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'When someone sends you a request, it will appear here',
              style: TextStyle(fontSize: 13, color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _friendRequests.length,
      itemBuilder: (context, index) {
        final req = _friendRequests[index];
        final name = req['requester_name'] ?? 'Unknown';
        final image = req['requester_image'];
        final requestId = req['id']?.toString() ?? '';
        final createdAt = req['created_at'] != null
            ? DateTime.tryParse(req['created_at'])
            : null;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color ?? Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Theme.of(context).colorScheme.surface,
                backgroundImage: image != null && image.toString().isNotEmpty
                    ? CachedNetworkImageProvider(image.toString())
                    : null,
                child: image == null || image.toString().isEmpty
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      createdAt != null
                          ? 'Sent ${timeago.format(createdAt)}'
                          : 'Wants to be your friend',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              // Accept button
              SizedBox(
                height: 34,
                child: ElevatedButton(
                  onPressed: () => _acceptRequest(requestId, index),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Accept',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Reject button
              SizedBox(
                height: 34,
                child: OutlinedButton(
                  onPressed: () => _rejectRequest(requestId, index),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    side: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  child: Icon(Icons.close, size: 18, color: Colors.grey[600]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChatsTab() {
    if (_isLoadingChats) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_chatNotifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Start chatting with your friends!',
              style: TextStyle(fontSize: 13, color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _chatNotifications.length,
      itemBuilder: (context, index) {
        final chat = _chatNotifications[index];
        final senderName = chat['sender_name'] ?? 'Unknown';
        final message = chat['message'] ?? '';
        final senderId = chat['sender_id']?.toString() ?? '';
        final receiverId = chat['receiver_id']?.toString() ?? '';
        final timestamp = chat['timestamp'] != null
            ? DateTime.tryParse(chat['timestamp'])
            : null;
        final isRead = chat['is_read'] ?? true;

        return ListTile(
          leading: CircleAvatar(
            radius: 22,
            backgroundColor:
                isRead ? Theme.of(context).colorScheme.surface : AppTheme.primaryColor.withOpacity(0.2),
            child: Text(
              senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isRead ? Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey : Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
              ),
            ),
          ),
          title: Text(
            senderName,
            style: TextStyle(
              fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            message,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: isRead ? Colors.grey[500] : Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
            ),
          ),
          trailing: timestamp != null
              ? Text(
                  timeago.format(timestamp),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[400],
                  ),
                )
              : null,
          onTap: () {
            // Navigate to chat with the other user
            final chatUserId = senderId;
            context.push('/chat/$chatUserId?name=${Uri.encodeComponent(senderName)}');
          },
        );
      },
    );
  }
}
