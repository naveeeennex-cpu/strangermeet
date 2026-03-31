import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../config/theme.dart';
import '../../providers/chat_provider.dart';
import '../../models/message.dart';
import '../../services/websocket_service.dart';

class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  @override
  ConsumerState<ConversationsScreen> createState() =>
      _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  final _searchController = TextEditingController();
  int _selectedTab = 0; // 0 = Communities, 1 = People
  StreamSubscription? _wsSubscription;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshConversations();

    // Listen for new messages via WebSocket → refresh list
    _wsSubscription = WebSocketService().messageStream.listen((data) {
      if (!mounted) return;
      final type = data['type']?.toString() ?? '';
      if (type == 'message' || type == 'group_message') {
        _refreshConversations();
      }
    });

    // Periodic refresh every 5 seconds (catches any missed updates)
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _refreshConversations();
    });
  }

  void _refreshConversations() {
    ref.read(conversationsProvider.notifier).fetchConversations();
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  List<Conversation> _filterConversations(List<Conversation> conversations) {
    final query = _searchController.text.trim().toLowerCase();

    // Filter by tab
    List<Conversation> filtered;
    if (_selectedTab == 0) {
      // Communities tab: community + subgroup chats
      filtered = conversations
          .where((c) => c.isCommunity || c.isSubgroup)
          .toList();
    } else {
      // People tab: DM conversations
      filtered = conversations
          .where((c) => !c.isCommunity && !c.isSubgroup)
          .toList();
    }

    // Filter by search query
    if (query.isNotEmpty) {
      filtered = filtered
          .where((c) => c.userName.toLowerCase().contains(query))
          .toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(conversationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search chats...',
                prefixIcon: Icon(
                  Icons.search,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          // Tabs
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                _buildTab('Communities', 0),
                const SizedBox(width: 8),
                _buildTab('People', 1),
              ],
            ),
          ),
          // Content
          Expanded(
            child: RefreshIndicator(
              color: AppTheme.primaryColor,
              onRefresh: () => ref
                  .read(conversationsProvider.notifier)
                  .fetchConversations(),
              child: state.isLoading && state.conversations.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _buildConversationList(state),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryColor
                : Theme.of(context).dividerColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? Colors.black
                : Theme.of(context).textTheme.bodySmall?.color,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildConversationList(ConversationsState state) {
    final filtered = _filterConversations(state.conversations);

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _selectedTab == 0
                  ? Icons.groups_outlined
                  : Icons.chat_bubble_outline,
              size: 64,
              color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.4),
            ),
            const SizedBox(height: 16),
            Text(
              _selectedTab == 0
                  ? 'No community chats yet'
                  : 'No conversations yet',
              style: TextStyle(
                fontSize: 18,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedTab == 0
                  ? 'Join a community to start chatting!'
                  : 'Start a conversation!',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: filtered.length,
      separatorBuilder: (context, index) => const Divider(indent: 76),
      itemBuilder: (context, index) {
        final conversation = filtered[index];
        final isCommunity = conversation.isCommunity;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: Stack(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: isCommunity
                    ? AppTheme.primaryColor.withOpacity(0.2)
                    : Theme.of(context).colorScheme.surface,
                backgroundImage: conversation.userImage != null &&
                        conversation.userImage!.isNotEmpty
                    ? CachedNetworkImageProvider(conversation.userImage!)
                    : null,
                child: (conversation.userImage == null ||
                        conversation.userImage!.isEmpty)
                    ? Icon(
                        isCommunity ? Icons.groups : Icons.person,
                        size: 24,
                        color: isCommunity
                            ? AppTheme.primaryDark
                            : Theme.of(context).textTheme.bodySmall?.color ??
                                Colors.grey,
                      )
                    : null,
              ),
              if (isCommunity)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.groups, size: 10, color: Colors.black),
                  ),
                ),
            ],
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  conversation.userName,
                  style: TextStyle(
                    fontWeight: conversation.unreadCount > 0
                        ? FontWeight.w700
                        : FontWeight.w500,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isCommunity)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: conversation.isSubgroup
                        ? Colors.blue.withOpacity(0.2)
                        : AppTheme.primaryColor.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    conversation.isSubgroup ? 'Group' : 'Community',
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          subtitle: Text(
            conversation.lastMessage,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: conversation.unreadCount > 0
                  ? Theme.of(context).textTheme.bodyLarge?.color ??
                      Colors.black
                  : Theme.of(context).textTheme.bodySmall?.color ??
                      Colors.grey,
              fontWeight: conversation.unreadCount > 0
                  ? FontWeight.w500
                  : FontWeight.w400,
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                timeago.format(conversation.lastMessageTime),
                style: TextStyle(
                  fontSize: 12,
                  color: conversation.unreadCount > 0
                      ? AppTheme.primaryDark
                      : Theme.of(context).textTheme.bodySmall?.color ??
                          Colors.grey,
                ),
              ),
              if (conversation.unreadCount > 0) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${conversation.unreadCount}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ],
          ),
          onTap: () {
            if (conversation.isSubgroup && conversation.communityId != null) {
              context.push(
                '/community/${conversation.communityId}/group/${conversation.userId}',
              );
            } else if (isCommunity) {
              context.push('/community/${conversation.userId}/chat');
            } else {
              context.push(
                '/chat/${conversation.userId}?name=${Uri.encodeComponent(conversation.userName)}',
              );
            }
          },
        );
      },
    );
  }
}
