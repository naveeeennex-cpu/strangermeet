import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme.dart';
import '../../models/message.dart';
import '../../providers/chat_provider.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../services/websocket_service.dart';
import '../../widgets/chat_background.dart';
import '../../widgets/date_separator.dart';
import '../../widgets/message_actions_sheet.dart';
import '../../widgets/voice_record_button.dart';
import '../../widgets/voice_message_bubble.dart';
import '../call/call_screen.dart';

// ── Dark theme constants for chat screens ────────────────────────────────────
const Color _kChatScaffoldBg = Color(0xFF0A0A0A);
const Color _kChatAppBarBg = Color(0xFF1A1A1A);
const Color _kChatAreaBg = Color(0xFF0A0A0A);
const Color _kMyBubbleColor = Color(0xFF1B5E20);
const Color _kOtherBubbleColor = Color(0xFF1E1E1E);
const Color _kInputBarBg = Color(0xFF1A1A1A);
const Color _kInputFieldBg = Color(0xFF2A2A2A);

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
  bool _hasText = false;
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;
  StreamSubscription<void>? _reconnectSubscription;

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

    // Listen for WebSocket reconnection — re-fetch messages to catch anything missed
    _reconnectSubscription = ws.onReconnected.listen((_) {
      if (mounted) {
        ref.read(messagesProvider(widget.userId).notifier).fetchMessages();
        _fetchOnlineStatus();
      }
    });

    _wsSubscription = ws.messageStream.listen((data) {
      final type = data['type'];

      if (type == 'message') {
        final senderId = data['sender_id']?.toString();
        final receiverId = data['receiver_id']?.toString();
        // Check if this message belongs to this conversation
        // (either from the other user, or sent by us to the other user)
        final belongsToConversation = senderId == widget.userId ||
            receiverId == widget.userId;
        if (belongsToConversation) {
          final newMsg = Message.fromJson(data);
          // Dedup: the provider's addMessage checks by ID
          ref
              .read(messagesProvider(widget.userId).notifier)
              .addMessage(newMsg);
          if (mounted) setState(() {});
          Future.delayed(const Duration(milliseconds: 100), () {
            _scrollToBottom();
          });
          // If the message is FROM the other user, mark as read
          // since we're actively viewing this conversation
          if (senderId == widget.userId) {
            WebSocketService().markAsRead(widget.userId);
          }
        }
      } else if (type == 'typing' && data['sender_id'] == widget.userId) {
        if (mounted) setState(() => _isTyping = true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _isTyping = false);
        });
      } else if (type == 'read_receipt') {
        // The other user (widget.userId) read our messages
        final readerId = data['reader_id']?.toString();
        if (readerId == widget.userId && _currentUserId != null) {
          ref
              .read(messagesProvider(widget.userId).notifier)
              .markSentMessagesAsRead(_currentUserId!);
          if (mounted) setState(() {});
        }
      } else if (type == 'delivered') {
        // Other user came online, our sent messages are now delivered
        final deliveredUserId = data['user_id']?.toString();
        if (deliveredUserId == widget.userId && _currentUserId != null) {
          ref
              .read(messagesProvider(widget.userId).notifier)
              .markSentMessagesAsDelivered(_currentUserId!);
          if (mounted) setState(() {});
        }
      } else if (type == 'online') {
        // A user came online — check if it's the conversation partner
        if (data['user_id']?.toString() == widget.userId) {
          if (mounted) setState(() => _isOnline = true);
        }
      } else if (type == 'offline') {
        // A user went offline — check if it's the conversation partner
        if (data['user_id']?.toString() == widget.userId) {
          if (mounted) setState(() => _isOnline = false);
        }
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
    _reconnectSubscription?.cancel();
    // Refresh unread count when leaving chat (messages got marked as read)
    ref.read(unreadCountProvider.notifier).fetchUnreadCount();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    // Double callback to ensure layout is complete after new message added
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
      // Second scroll after a short delay to catch any layout changes
      Future.delayed(const Duration(milliseconds: 150), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  void _scrollToBottomInstant() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
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
              _DarkDateSeparator(date: message.timestamp),
            if (showUnreadBanner)
              _UnreadMessagesBanner(count: unreadCount),
            GestureDetector(
              onLongPress: () => _handleMessageLongPress(message),
              child: _MessageBubble(
                message: message.message,
                isMe: isMe,
                status: message.status,
                time: DateFormat('hh:mm a').format(message.timestamp),
                imageUrl: message.imageUrl,
                messageType: message.messageType,
              ),
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

    try {
      await ref
          .read(messagesProvider(widget.userId).notifier)
          .sendMessage(text);
      // Force rebuild + scroll after state update
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

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (pickedFile == null) return;

    // 1. Show local preview immediately in the chat
    final tempId = 'temp_img_${DateTime.now().millisecondsSinceEpoch}';
    final localPath = pickedFile.path;
    final pendingMsg = Message(
      id: tempId,
      senderId: _currentUserId ?? '',
      receiverId: widget.userId,
      message: '',
      timestamp: DateTime.now(),
      status: 'pending',
      imageUrl: 'file://$localPath',
      messageType: 'image',
    );
    ref.read(messagesProvider(widget.userId).notifier).addLocalPending(pendingMsg);
    if (mounted) _scrollToBottom();

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
        ref.read(messagesProvider(widget.userId).notifier).removeMessage(tempId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload image')),
          );
        }
        return;
      }

      // 2. Remove local preview, send the real message
      ref.read(messagesProvider(widget.userId).notifier).removeMessage(tempId);
      await ref
          .read(messagesProvider(widget.userId).notifier)
          .sendMessage('', imageUrl: imageUrl, messageType: 'image');
      if (mounted) _scrollToBottom();
    } catch (e) {
      ref.read(messagesProvider(widget.userId).notifier).removeMessage(tempId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send image: $e')),
        );
      }
    }
  }

  Future<void> _shareLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location services are disabled')));
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final lat = pos.latitude;
      final lng = pos.longitude;
      final msgContent = '$lat,$lng';

      ref
          .read(messagesProvider(widget.userId).notifier)
          .sendMessage(msgContent, messageType: 'location');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not get location: $e')));
      }
    }
  }

  Future<void> _handleMessageLongPress(Message message) async {
    final isOwn = message.senderId == _currentUserId;
    final isText = message.messageType == 'text';

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
        final messages = ref.read(messagesProvider(widget.userId)).messages;
        final updated = messages.where((m) => m.id != message.id).toList();
        ref.read(messagesProvider(widget.userId).notifier).setMessages(updated);
        break;
      case 'delete_for_everyone':
        try {
          await ApiService().delete('/messages/${message.id}');
          final messages = ref.read(messagesProvider(widget.userId)).messages;
          final updated = messages.where((m) => m.id != message.id).toList();
          ref.read(messagesProvider(widget.userId).notifier).setMessages(updated);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to delete: $e')),
            );
          }
        }
        break;
      case 'copy':
        break; // Already handled in the sheet
    }
  }

  void _showEditDialog(Message message) {
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
                await ApiService().put('/messages/${message.id}', data: {'message': newText});
                final messages = ref.read(messagesProvider(widget.userId)).messages;
                final updated = messages.map((m) {
                  if (m.id == message.id) {
                    final editedText = newText.endsWith(' (edited)') ? newText : '$newText (edited)';
                    return Message(
                      id: m.id,
                      senderId: m.senderId,
                      receiverId: m.receiverId,
                      message: editedText,
                      timestamp: m.timestamp,
                      status: m.status,
                      imageUrl: m.imageUrl,
                      messageType: m.messageType,
                    );
                  }
                  return m;
                }).toList();
                ref.read(messagesProvider(widget.userId).notifier).setMessages(updated);
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
    final state = ref.watch(messagesProvider(widget.userId));

    return Scaffold(
      backgroundColor: _kChatScaffoldBg,
      appBar: AppBar(
        backgroundColor: _kChatAppBarBg,
        iconTheme: const IconThemeData(color: Colors.white),
        titleSpacing: 0,
        title: GestureDetector(
          onTap: () => context.push('/user/${widget.userId}'),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFF333333),
                    child: Text(
                      widget.userName.isNotEmpty
                          ? widget.userName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Colors.white,
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
                        color: _isOnline ? Colors.green : Colors.grey[600],
                        shape: BoxShape.circle,
                        border: Border.all(color: _kChatAppBarBg, width: 2),
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
                        color: Colors.white,
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
                            ? Colors.blue[300]
                            : _isOnline
                                ? Colors.green[400]
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
        actions: [
          IconButton(
            icon: const Icon(Icons.call, color: Colors.white),
            onPressed: () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(
                builder: (_) => CallScreen(
                  peerId: widget.userId,
                  peerName: widget.userName,
                  peerImage: '',
                  isVideo: false,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.videocam, color: Colors.white),
            onPressed: () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(
                builder: (_) => CallScreen(
                  peerId: widget.userId,
                  peerName: widget.userName,
                  peerImage: '',
                  isVideo: true,
                ),
              ),
            ),
          ),
        ],
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
                      ? const Center(child: CircularProgressIndicator(color: Colors.white))
                      : state.messages.isEmpty
                          ? Center(
                              child: Text(
                                'Say hello!',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            )
                          : _buildMessagesList(state),
                  // Floating typing indicator
                  if (_isTyping)
                    Positioned(
                      bottom: 4,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 24,
                              height: 12,
                              child: _TypingDots(),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${widget.userName} is typing',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[400],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Uploading indicator
          if (_isUploading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: LinearProgressIndicator(color: AppTheme.primaryColor),
            ),
          // Message input
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            decoration: const BoxDecoration(
              color: _kInputBarBg,
              border: Border(
                top: BorderSide(color: Color(0xFF2A2A2A)),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.location_on, color: Colors.grey[500]),
                    onPressed: _shareLocation,
                    tooltip: 'Share location',
                  ),
                  IconButton(
                    icon: Icon(Icons.image, color: Colors.grey[500]),
                    onPressed: _isUploading ? null : _pickAndSendImage,
                  ),
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
                      onChanged: (text) {
                        WebSocketService().sendTyping(widget.userId);
                        final hasText = text.trim().isNotEmpty;
                        if (hasText != _hasText) {
                          setState(() => _hasText = hasText);
                        }
                      },
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _hasText
                      ? Container(
                          decoration: const BoxDecoration(
                            color: AppTheme.primaryColor,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.send, color: Colors.black),
                            onPressed: _sendMessage,
                          ),
                        )
                      : VoiceRecordButton(
                          isEnabled: !_isUploading,
                          onRecordingDone: (tempId, localPath, duration) async {
                            // Instantly show pending voice bubble
                            ref.read(messagesProvider(widget.userId).notifier)
                                .addLocalPending(Message(
                              id: tempId,
                              senderId: _currentUserId ?? '',
                              receiverId: widget.userId,
                              message: duration.toString(),
                              timestamp: DateTime.now(),
                              status: 'pending',
                              imageUrl: localPath,
                              messageType: 'voice',
                            ));
                            if (mounted) _scrollToBottom();
                          },
                          onUploadComplete: (tempId, audioUrl, duration) async {
                            ref.read(messagesProvider(widget.userId).notifier)
                                .removeMessage(tempId);
                            await ref
                                .read(messagesProvider(widget.userId).notifier)
                                .sendMessage(duration.toString(),
                                    imageUrl: audioUrl, messageType: 'voice');
                            if (mounted) _scrollToBottom();
                          },
                          onUploadFailed: (tempId) async {
                            ref.read(messagesProvider(widget.userId).notifier)
                                .removeMessage(tempId);
                          },
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

// ── Unread banner (dark) ─────────────────────────────────────────────────────

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
          color: const Color(0xFF1A3A5C),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$count UNREAD MESSAGE${count == 1 ? '' : 'S'}',
          style: TextStyle(
            fontSize: 11,
            color: Colors.blue[200],
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ── Tick status widget ───────────────────────────────────────────────────────

Widget _buildTicks(String status) {
  switch (status) {
    case 'pending':
      return Icon(Icons.access_time, size: 14, color: Colors.grey[500]);
    case 'sent':
      return Icon(Icons.check, size: 14, color: Colors.grey[500]);
    case 'delivered':
      return Icon(Icons.done_all, size: 14, color: Colors.grey[500]);
    case 'read':
      return const Icon(Icons.done_all, size: 14, color: Colors.blue);
    default:
      return Icon(Icons.check, size: 14, color: Colors.grey[500]);
  }
}

// ── Message bubble (dark theme + shared post support) ────────────────────────

class _MessageBubble extends StatefulWidget {
  final String message;
  final bool isMe;
  final String status;
  final String time;
  final String imageUrl;
  final String messageType;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    this.status = 'sent',
    required this.time,
    this.imageUrl = '',
    this.messageType = 'text',
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<double>(begin: 20.0, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMe = widget.isMe;
    final status = widget.status;
    final message = widget.message;
    final time = widget.time;
    final imageUrl = widget.imageUrl;
    final messageType = widget.messageType;
    final isImage = messageType == 'image' && imageUrl.isNotEmpty;
    final isSharedPost = messageType == 'shared_post';
    final isVoice = messageType == 'voice' && imageUrl.isNotEmpty;
    final isLocation = messageType == 'location';

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(
            isMe ? _slideAnimation.value : -_slideAnimation.value,
            _slideAnimation.value * 0.5,
          ),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: child,
          ),
        );
      },
      child: isVoice
          ? VoiceMessageBubble(
              audioUrl: imageUrl,
              durationSeconds: int.tryParse(message) ?? 0,
              isMe: isMe,
              time: time,
              status: status,
            )
          : isLocation
              ? _buildLocationBubble(context, isMe, status, message, time)
              : isSharedPost
                  ? _buildSharedPostCard(
                      context, isMe, status, message, time, imageUrl)
                  : _buildRegularBubble(
                      context, isMe, status, message, time, imageUrl, isImage),
    );
  }

  Widget _buildLocationBubble(BuildContext context, bool isMe, String status,
      String message, String time) {
    final parts = message.split(',');
    if (parts.length < 2) {
      return _buildRegularBubble(
          context, isMe, status, message, time, '', false);
    }
    final lat = double.tryParse(parts[0].trim()) ?? 0;
    final lng = double.tryParse(parts[1].trim()) ?? 0;
    if (lat == 0 && lng == 0) {
      return _buildRegularBubble(
          context, isMe, status, message, time, '', false);
    }

    final venueLatLng = LatLng(lat, lng);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        width: 260,
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF1B5E20) : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isMe
                ? Colors.green.withOpacity(0.4)
                : const Color(0xFF333333),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Map preview
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
              child: SizedBox(
                height: 150,
                width: double.infinity,
                child: GoogleMap(
                  initialCameraPosition:
                      CameraPosition(target: venueLatLng, zoom: 15),
                  markers: {
                    Marker(
                      markerId: const MarkerId('loc'),
                      position: venueLatLng,
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                          isMe
                              ? BitmapDescriptor.hueGreen
                              : BitmapDescriptor.hueRed),
                    ),
                  },
                  zoomControlsEnabled: false,
                  myLocationButtonEnabled: false,
                  mapToolbarEnabled: false,
                  liteModeEnabled: true,
                  onTap: (_) async {
                    final uri = Uri.parse(
                        'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
                    try {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    } catch (_) {}
                  },
                ),
              ),
            ),
            // Bottom row
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.red, size: 16),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text('Shared Location',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ),
                  GestureDetector(
                    onTap: () async {
                      final uri = Uri.parse(
                          'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
                      try {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      } catch (_) {}
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Directions',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
            // Timestamp
            Padding(
              padding: const EdgeInsets.only(right: 10, bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(time,
                      style: TextStyle(
                          color: Colors.grey[500], fontSize: 10)),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      status == 'read' ? Icons.done_all : Icons.done,
                      size: 12,
                      color: status == 'read'
                          ? Colors.blue[300]
                          : Colors.grey[500],
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

  Widget _buildSharedPostCard(
    BuildContext context,
    bool isMe,
    String status,
    String message,
    String time,
    String imageUrl,
  ) {
    // For shared posts, the message field may contain the post ID
    // and imageUrl contains the thumbnail
    final sharedPostId = message.isNotEmpty ? message : '';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: sharedPostId.isNotEmpty
            ? () => context.push('/post/$sharedPostId')
            : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          width: MediaQuery.of(context).size.width * 0.7,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF333333)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Post image/video thumbnail
              if (imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(15)),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      height: 200,
                      color: const Color(0xFF2A2A2A),
                      child: const Center(
                          child:
                              CircularProgressIndicator(color: Colors.white)),
                    ),
                    errorWidget: (context, url, error) => Container(
                      height: 200,
                      color: const Color(0xFF2A2A2A),
                      child: const Icon(Icons.broken_image,
                          size: 40, color: Colors.grey),
                    ),
                  ),
                ),
              // Post info
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.open_in_new,
                            size: 12, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text('Shared post',
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Tap to view post',
                        style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 13,
                            fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
              // Time + tick status
              Padding(
                padding: const EdgeInsets.only(right: 12, bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      time,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      _buildTicks(status),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRegularBubble(
    BuildContext context,
    bool isMe,
    String status,
    String message,
    String time,
    String imageUrl,
    bool isImage,
  ) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: isImage
            ? const EdgeInsets.all(4)
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: isImage ? 172 : MediaQuery.of(context).size.width * 0.75,
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
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (isImage)
              GestureDetector(
                onTap: status == 'pending'
                    ? null
                    : () => _showFullImage(context, imageUrl),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: imageUrl.startsWith('file://')
                          ? Image.file(
                              File(imageUrl.substring(7)),
                              width: 160,
                              height: 160,
                              fit: BoxFit.cover,
                            )
                          : CachedNetworkImage(
                              imageUrl: imageUrl,
                              width: 160,
                              height: 160,
                              fit: BoxFit.cover,
                              maxWidthDiskCache: 400,
                              placeholder: (context, url) => Container(
                                width: 160,
                                height: 160,
                                color: const Color(0xFF2A2A2A),
                              ),
                              errorWidget: (context, url, error) => Container(
                                width: 160,
                                height: 160,
                                color: const Color(0xFF2A2A2A),
                                child: const Icon(Icons.broken_image,
                                    size: 36, color: Colors.grey),
                              ),
                            ),
                    ),
                    // Uploading overlay
                    if (status == 'pending')
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 160,
                            height: 160,
                            color: Colors.black45,
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (!isImage)
              Text(
                message,
                style: const TextStyle(fontSize: 15, color: Colors.white),
              ),
            if (isImage && message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 14, color: Colors.white),
                ),
              ),
            Padding(
              padding: isImage
                  ? const EdgeInsets.only(right: 8, bottom: 4, top: 4)
                  : EdgeInsets.zero,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[400],
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    _buildTicks(status),
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

// Animated typing dots (3 bouncing dots)
class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with TickerProviderStateMixin {
  late List<AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (i) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 400),
      );
    });
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 150), () {
        if (mounted) _controllers[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _controllers[i],
          builder: (context, child) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 5,
              height: 5 + (_controllers[i].value * 4),
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(3),
              ),
            );
          },
        );
      }),
    );
  }
}
