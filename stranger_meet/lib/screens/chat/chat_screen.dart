import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../config/theme.dart';
import '../../models/message.dart';
import '../../providers/chat_provider.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../services/websocket_service.dart';
import '../../widgets/chat_background.dart';
import '../../widgets/date_separator.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String userId;
  final String userName;

  const ChatScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  String? _currentUserId;
  bool _isOnline = false;
  bool _isTyping = false;
  bool _isUploading = false;
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _fetchOnlineStatus();
    Future.microtask(() async {
      await ref.read(messagesProvider(widget.userId).notifier).fetchMessages();
      _scrollToFirstUnreadOrBottom();
    });
    _setupWebSocket();
  }

  void _setupWebSocket() {
    final ws = WebSocketService();
    // Mark messages as read when opening the chat
    ws.markAsRead(widget.userId);

    _wsSubscription = ws.messageStream.listen((data) {
      final type = data['type'];
      if (type == 'message') {
        final senderId = data['sender_id'];
        final receiverId = data['receiver_id'];
        // Check if this message belongs to this conversation
        if (senderId == widget.userId || receiverId == widget.userId) {
          final newMsg = Message.fromJson(data);
          final state = ref.read(messagesProvider(widget.userId));
          final existing = state.messages.any((m) => m.id == newMsg.id);
          if (!existing) {
            ref
                .read(messagesProvider(widget.userId).notifier)
                .addMessage(newMsg);
            _scrollToBottom();
            // Mark as read since we're viewing this conversation
            if (senderId == widget.userId) {
              WebSocketService().markAsRead(widget.userId);
            }
          }
        }
      } else if (type == 'typing' && data['sender_id'] == widget.userId) {
        setState(() => _isTyping = true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _isTyping = false);
        });
      } else if (type == 'read_receipt') {
        // Update all sent messages to show as read
        final currentMessages = ref.read(messagesProvider(widget.userId)).messages;
        final updated = currentMessages.map((m) {
          if (m.senderId == _currentUserId && !m.isRead) {
            return Message(
              id: m.id,
              senderId: m.senderId,
              receiverId: m.receiverId,
              message: m.message,
              timestamp: m.timestamp,
              isRead: true,
              imageUrl: m.imageUrl,
              messageType: m.messageType,
            );
          }
          return m;
        }).toList();
        ref.read(messagesProvider(widget.userId).notifier).setMessages(updated);
      }
    });
  }

  Future<void> _fetchOnlineStatus() async {
    try {
      final api = ApiService();
      final response = await api.get('/messages/online/${widget.userId}');
      if (mounted) {
        setState(() => _isOnline = response.data['online'] ?? false);
      }
    } catch (_) {
      // Fallback: keep offline
    }
  }

  Future<void> _loadCurrentUser() async {
    final userId = await StorageService().getUserId();
    if (mounted) {
      setState(() => _currentUserId = userId);
    }
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    // Refresh unread count when leaving chat (messages got marked as read)
    ref.read(unreadCountProvider.notifier).fetchUnreadCount();
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

  void _scrollToFirstUnreadOrBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final messages = ref.read(messagesProvider(widget.userId)).messages;
      // Find first unread message from the other user
      final firstUnreadIndex = messages.indexWhere(
        (m) => m.senderId != _currentUserId && !m.isRead,
      );
      if (firstUnreadIndex > 0) {
        // Estimate scroll position: each item ~70px, scroll a bit above
        final estimatedOffset = (firstUnreadIndex - 1).clamp(0, messages.length) * 70.0;
        final maxScroll = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(estimatedOffset.clamp(0, maxScroll));
      } else {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Widget _buildMessagesList(MessagesState state) {
    // Find first unread message from the other user
    final firstUnreadIndex = state.messages.indexWhere(
      (m) => m.senderId != _currentUserId && !m.isRead,
    );
    final unreadCount = firstUnreadIndex >= 0
        ? state.messages
            .where((m) => m.senderId != _currentUserId && !m.isRead)
            .length
        : 0;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: state.messages.length,
      itemBuilder: (context, index) {
        final message = state.messages[index];
        final isMe = message.senderId == _currentUserId;
        final showDateSeparator = index == 0 ||
            DateSeparator.isDifferentDay(
              state.messages[index - 1].timestamp,
              message.timestamp,
            );
        // Show unread banner before the first unread message
        final showUnreadBanner = index == firstUnreadIndex && unreadCount > 0;

        return Column(
          children: [
            if (showDateSeparator)
              DateSeparator(date: message.timestamp),
            if (showUnreadBanner)
              _UnreadMessagesBanner(count: unreadCount),
            _MessageBubble(
              message: message.message,
              isMe: isMe,
              isRead: message.isRead,
              time: DateFormat('hh:mm a').format(message.timestamp),
              imageUrl: message.imageUrl,
              messageType: message.messageType,
            ),
          ],
        );
      },
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    // Always use REST API for reliability, then also notify via WS
    try {
      await ref
          .read(messagesProvider(widget.userId).notifier)
          .sendMessage(text);
      _scrollToBottom();

      // Also send via WebSocket for real-time delivery to receiver
      final ws = WebSocketService();
      if (ws.isConnected) {
        ws.sendMessage(widget.userId, text);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (pickedFile == null) return;

    if (mounted) setState(() => _isUploading = true);

    try {
      final bytes = await pickedFile.readAsBytes();
      final fileName = pickedFile.name;

      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: fileName),
        'folder': 'chats',
      });

      final api = ApiService();
      final uploadResponse = await api.uploadFile('/upload', formData: formData);
      final imageUrl = uploadResponse.data['url'] ?? uploadResponse.data['image_url'] ?? '';

      if (imageUrl.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload image')),
          );
        }
        return;
      }

      // Send via WebSocket if connected, otherwise REST
      final ws = WebSocketService();
      if (ws.isConnected) {
        ws.sendMessage(widget.userId, '', imageUrl: imageUrl, messageType: 'image');
      } else {
        await ref
            .read(messagesProvider(widget.userId).notifier)
            .sendMessage('', imageUrl: imageUrl, messageType: 'image');
      }
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send image: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(messagesProvider(widget.userId));

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          onTap: () => context.push('/user/${widget.userId}'),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppTheme.surfaceColor,
                    child: Text(
                      widget.userName.isNotEmpty
                          ? widget.userName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  // Online/offline indicator
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _isOnline ? Colors.green : Colors.grey[400],
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.userName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _isTyping
                          ? 'Typing...'
                          : _isOnline
                              ? 'Active now'
                              : 'Offline',
                      style: TextStyle(
                        fontSize: 12,
                        color: _isTyping
                            ? Colors.blue
                            : _isOnline
                                ? Colors.green
                                : Colors.grey[500],
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: kChatBackgroundColor,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: ChatBackgroundPainter(),
                    ),
                  ),
                  state.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : state.messages.isEmpty
                          ? Center(
                              child: Text(
                                'Say hello!',
                                style: TextStyle(color: Colors.grey[400]),
                              ),
                            )
                          : _buildMessagesList(state),
                ],
              ),
            ),
          ),
          // Typing indicator
          if (_isTyping)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    '${widget.userName} is typing...',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          // Uploading indicator
          if (_isUploading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: LinearProgressIndicator(),
            ),
          // Message input
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey[200]!),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.image, color: Colors.grey[600]),
                    onPressed: _isUploading ? null : _pickAndSendImage,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        filled: true,
                        fillColor: AppTheme.surfaceColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                      ),
                      onChanged: (_) {
                        WebSocketService().sendTyping(widget.userId);
                      },
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
}

class _UnreadMessagesBanner extends StatelessWidget {
  final int count;
  const _UnreadMessagesBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFD4EDFF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$count UNREAD MESSAGE${count == 1 ? '' : 'S'}',
          style: TextStyle(
            fontSize: 11,
            color: Colors.blue[700],
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String message;
  final bool isMe;
  final bool isRead;
  final String time;
  final String imageUrl;
  final String messageType;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    this.isRead = false,
    required this.time,
    this.imageUrl = '',
    this.messageType = 'text',
  });

  @override
  Widget build(BuildContext context) {
    final isImage = messageType == 'image' && imageUrl.isNotEmpty;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: isImage
            ? const EdgeInsets.all(4)
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe ? AppTheme.primaryColor : AppTheme.surfaceColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (isImage)
              GestureDetector(
                onTap: () => _showFullImage(context, imageUrl),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    maxWidthDiskCache: 600,
                    placeholder: (context, url) => Container(
                      height: 200,
                      color: Colors.grey[200],
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (context, url, error) => Container(
                      height: 200,
                      color: Colors.grey[200],
                      child: const Icon(Icons.broken_image, size: 40, color: Colors.grey),
                    ),
                    fit: BoxFit.cover,
                    width: double.infinity,
                  ),
                ),
              ),
            if (!isImage)
              Text(
                message,
                style: const TextStyle(fontSize: 15),
              ),
            if (isImage && message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            Padding(
              padding: isImage ? const EdgeInsets.only(right: 8, bottom: 4, top: 4) : EdgeInsets.zero,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      isRead ? Icons.done_all : Icons.done,
                      size: 14,
                      color: isRead ? Colors.blue : Colors.grey[500],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: url,
                placeholder: (context, url) =>
                    const Center(child: CircularProgressIndicator()),
                errorWidget: (context, url, error) =>
                    const Icon(Icons.broken_image, color: Colors.white, size: 50),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
