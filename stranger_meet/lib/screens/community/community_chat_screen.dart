import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../models/community.dart';
import '../../providers/community_provider.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/chat_background.dart';
import '../../widgets/message_actions_sheet.dart';

// ── Dark theme constants (shared with chat_screen.dart) ──────────────────────
const Color _kChatScaffoldBg = Color(0xFF0A0A0A);
const Color _kChatAppBarBg = Color(0xFF1A1A1A);
const Color _kChatAreaBg = Color(0xFF0A0A0A);
const Color _kMyBubbleColor = Color(0xFF1B5E20);
const Color _kOtherBubbleColor = Color(0xFF1E1E1E);
const Color _kInputBarBg = Color(0xFF1A1A1A);
const Color _kInputFieldBg = Color(0xFF2A2A2A);

class CommunityChatScreen extends ConsumerStatefulWidget {
  final String communityId;

  const CommunityChatScreen({super.key, required this.communityId});

  @override
  ConsumerState<CommunityChatScreen> createState() =>
      _CommunityChatScreenState();
}

class _CommunityChatScreenState extends ConsumerState<CommunityChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    Future.microtask(() async {
      await ref
          .read(communityMessagesProvider(widget.communityId).notifier)
          .fetchMessages();
      _scrollToBottomInstant();
    });
  }

  Future<void> _loadCurrentUser() async {
    final userId = await StorageService().getUserId();
    if (mounted) {
      setState(() => _currentUserId = userId);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _scrollToBottomInstant() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    try {
      await ref
          .read(communityMessagesProvider(widget.communityId).notifier)
          .sendMessage(text);
      if (mounted) {
        setState(() {});
        await Future.delayed(const Duration(milliseconds: 100));
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _handleMessageLongPress(CommunityMessage message) async {
    final isOwn = message.userId == _currentUserId;
    // Community chat screen only has text messages (no image support)
    final isText = true;

    final action = await MessageActionsSheet.show(
      context,
      isOwnMessage: isOwn,
      isTextMessage: isText,
      messageText: message.message,
    );

    if (action == null || !mounted) return;

    switch (action) {
      case 'edit':
        _showEditDialog(message);
        break;
      case 'delete_for_me':
        final messages = ref.read(communityMessagesProvider(widget.communityId)).messages;
        final updated = messages.where((m) => m.id != message.id).toList();
        ref.read(communityMessagesProvider(widget.communityId).notifier).setMessages(updated);
        break;
      case 'delete_for_everyone':
        try {
          await ApiService().delete(
            '/communities/${widget.communityId}/messages/${message.id}',
          );
          final messages = ref.read(communityMessagesProvider(widget.communityId)).messages;
          final updated = messages.where((m) => m.id != message.id).toList();
          ref.read(communityMessagesProvider(widget.communityId).notifier).setMessages(updated);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to delete: $e')),
            );
          }
        }
        break;
      case 'copy':
        break;
    }
  }

  void _showEditDialog(CommunityMessage message) {
    final controller = TextEditingController(text: message.message);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Edit message', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Edit your message...',
            hintStyle: TextStyle(color: Colors.grey),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newText = controller.text.trim();
              if (newText.isEmpty) return;
              try {
                await ApiService().put(
                  '/communities/${widget.communityId}/messages/${message.id}',
                  data: {'message': newText},
                );
                final messages = ref.read(communityMessagesProvider(widget.communityId)).messages;
                final updated = messages.map((m) {
                  if (m.id == message.id) {
                    final editedText = newText.endsWith(' (edited)') ? newText : '$newText (edited)';
                    return m.copyWith(message: editedText);
                  }
                  return m;
                }).toList();
                ref.read(communityMessagesProvider(widget.communityId).notifier).setMessages(updated);
                if (mounted) Navigator.pop(ctx);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to edit: $e')),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(communityMessagesProvider(widget.communityId));

    return Scaffold(
      backgroundColor: _kChatScaffoldBg,
      appBar: AppBar(
        backgroundColor: _kChatAppBarBg,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Community Chat',
            style: TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: _kChatAreaBg,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: ChatBackgroundPainter(isDark: true),
                    ),
                  ),
                  state.isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white))
                      : state.messages.isEmpty
                          ? Center(
                              child: Text(
                                'Start the conversation!',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(16),
                              itemCount: state.messages.length,
                              itemBuilder: (context, index) {
                                final message = state.messages[index];
                                final isMe = message.userId == _currentUserId;
                                final showDateSeparator = index == 0 ||
                                    _isDifferentDay(
                                      state.messages[index - 1].timestamp,
                                      message.timestamp,
                                    );
                                return Column(
                                  children: [
                                    if (showDateSeparator &&
                                        message.timestamp != null)
                                      _DarkDateSeparator(
                                          date: message.timestamp!),
                                    GestureDetector(
                                      onLongPress: () => _handleMessageLongPress(message),
                                      child: _GroupMessageBubble(
                                        senderName: message.userName,
                                        message: message.message,
                                        isMe: isMe,
                                        time: message.timestamp != null
                                            ? DateFormat('hh:mm a')
                                                .format(message.timestamp!)
                                            : '',
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                ],
              ),
            ),
          ),
          // Message input
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            decoration: const BoxDecoration(
              color: _kInputBarBg,
              border: Border(
                top: BorderSide(color: Color(0xFF2A2A2A)),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        filled: true,
                        fillColor: _kInputFieldBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.black),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isDifferentDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return true;
    return a.year != b.year || a.month != b.month || a.day != b.day;
  }
}

// ── Dark date separator ──────────────────────────────────────────────────────

class _DarkDateSeparator extends StatelessWidget {
  final DateTime date;
  const _DarkDateSeparator({required this.date});

  String _getLabel() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(date.year, date.month, date.day);
    final diff = today.difference(messageDate).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (date.year == now.year) return DateFormat('EEE, MMM d').format(date);
    return DateFormat('MMM d, yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _getLabel(),
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[500],
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ── Group message bubble (dark) ──────────────────────────────────────────────

class _GroupMessageBubble extends StatelessWidget {
  final String senderName;
  final String message;
  final bool isMe;
  final String time;

  const _GroupMessageBubble({
    required this.senderName,
    required this.message,
    required this.isMe,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe ? _kMyBubbleColor : _kOtherBubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  senderName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _getSenderColor(senderName),
                  ),
                ),
              ),
            Text(
              message,
              style: const TextStyle(fontSize: 15, color: Colors.white),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                time,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[400],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Generate a consistent color for each sender name
  Color _getSenderColor(String name) {
    final colors = [
      Colors.tealAccent[400]!,
      Colors.orangeAccent[200]!,
      Colors.lightBlueAccent[200]!,
      Colors.pinkAccent[100]!,
      Colors.amberAccent[200]!,
      Colors.purpleAccent[100]!,
      Colors.cyanAccent[400]!,
      Colors.lightGreenAccent[200]!,
    ];
    final hash = name.codeUnits.fold<int>(0, (prev, c) => prev + c);
    return colors[hash % colors.length];
  }
}
