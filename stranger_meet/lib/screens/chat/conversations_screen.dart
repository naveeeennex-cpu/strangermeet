import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../config/theme.dart';
import '../../providers/chat_provider.dart';

class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  @override
  ConsumerState<ConversationsScreen> createState() =>
      _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(conversationsProvider.notifier).fetchConversations(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(conversationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
      ),
      body: RefreshIndicator(
        color: AppTheme.primaryColor,
        onRefresh: () =>
            ref.read(conversationsProvider.notifier).fetchConversations(),
        child: state.isLoading && state.conversations.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : state.conversations.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start a conversation!',
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: state.conversations.length,
                    separatorBuilder: (context, index) => const Divider(
                      indent: 76,
                    ),
                    itemBuilder: (context, index) {
                      final conversation = state.conversations[index];
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
                                  : AppTheme.surfaceColor,
                              backgroundImage:
                                  conversation.userImage != null &&
                                          conversation.userImage!.isNotEmpty
                                      ? CachedNetworkImageProvider(
                                          conversation.userImage!)
                                      : null,
                              child: (conversation.userImage == null ||
                                      conversation.userImage!.isEmpty)
                                  ? Icon(
                                      isCommunity
                                          ? Icons.groups
                                          : Icons.person,
                                      size: 24,
                                      color: isCommunity
                                          ? AppTheme.primaryDark
                                          : AppTheme.textSecondary,
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
                                    border: Border.all(
                                        color: Colors.white, width: 2),
                                  ),
                                  child: const Icon(Icons.groups,
                                      size: 10, color: Colors.black),
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
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: conversation.isSubgroup
                                      ? Colors.blue.withOpacity(0.2)
                                      : AppTheme.primaryColor.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  conversation.isSubgroup ? 'Group' : 'Community',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600),
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
                                ? AppTheme.textPrimary
                                : AppTheme.textSecondary,
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
                                    : AppTheme.textSecondary,
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
                            // Route to sub-group chat using existing route
                            context.push(
                              '/community/${conversation.communityId}/group/${conversation.userId}',
                            );
                          } else if (isCommunity) {
                            context.push(
                                '/community/${conversation.userId}/chat');
                          } else {
                            context.push(
                              '/chat/${conversation.userId}?name=${Uri.encodeComponent(conversation.userName)}',
                            );
                          }
                        },
                      );
                    },
                  ),
      ),
    );
  }
}
