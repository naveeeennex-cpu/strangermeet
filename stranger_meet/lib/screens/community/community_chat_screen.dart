import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../models/community.dart';
import '../../providers/community_provider.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../services/websocket_service.dart';
import '../../widgets/chat_background.dart';
import '../../widgets/message_actions_sheet.dart';
import '../../widgets/voice_record_button.dart';
import '../../widgets/voice_message_bubble.dart';

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
  final _messageFocusNode = FocusNode();
  String? _currentUserId;
  Timer? _pollTimer;
  StreamSubscription? _wsSubscription;

  // @Mentions state
  bool _showMentionOverlay = false;
  String _mentionQuery = '';
  List<Map<String, String>> _communityMembers = [];

  // Reply-to-message state
  CommunityMessage? _replyingTo;
  bool _hasText = false;

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

    // Listen for WebSocket community messages (instant delivery)
    _wsSubscription = WebSocketService().messageStream.listen((data) {
      if (!mounted) return;
      if (data['type'] == 'group_message' &&
          data['channel'] == 'community:${widget.communityId}') {
        final msg = CommunityMessage(
          id: data['id']?.toString() ?? '',
          communityId: data['community_id']?.toString() ?? '',
          userId: data['user_id']?.toString() ?? '',
          userName: data['user_name'] ?? '',
          userImage: data['user_profile_image'],
          message: data['message'] ?? '',
          timestamp: DateTime.tryParse(data['timestamp'] ?? '') ?? DateTime.now(),
          imageUrl: data['image_url'] ?? '',
          messageType: data['message_type'] ?? 'text',
        );
        final currentMessages = ref.read(communityMessagesProvider(widget.communityId)).messages;
        if (!currentMessages.any((m) => m.id == msg.id)) {
          ref.read(communityMessagesProvider(widget.communityId).notifier).addMessageFromWebSocket(msg);
          _scrollToBottom();
        }
      }
    });

    // Backup polling every 10 seconds
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        ref.read(communityMessagesProvider(widget.communityId).notifier).fetchMessages();
      }
    });

    // Load community members for @mentions
    _fetchCommunityMembers();

    // Listen for @ mentions in text input
    _messageController.addListener(_onMessageTextChanged);
  }

  Future<void> _loadCurrentUser() async {
    final userId = await StorageService().getUserId();
    if (mounted) {
      setState(() => _currentUserId = userId);
    }
  }

  Future<void> _fetchCommunityMembers() async {
    try {
      final response =
          await ApiService().get('/communities/${widget.communityId}/members');
      final data = response.data;
      final List<dynamic> results =
          data is List ? data : (data['results'] ?? data['members'] ?? []);
      if (mounted) {
        setState(() {
          _communityMembers = results
              .map((e) => {
                    'id': (e['user_id'] ?? e['userId'] ?? '').toString(),
                    'name': (e['user_name'] ?? e['userName'] ?? 'User').toString(),
                    'image': (e['user_profile_image'] ?? e['userProfileImage'] ?? '').toString(),
                  })
              .toList();
        });
      }
    } catch (_) {}
  }

  void _onMessageTextChanged() {
    final text = _messageController.text;
    final hasText = text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
    final cursorPos = _messageController.selection.baseOffset;
    if (cursorPos < 0) return;

    final beforeCursor = text.substring(0, cursorPos);
    final lastAt = beforeCursor.lastIndexOf('@');

    if (lastAt >= 0) {
      final queryPart = beforeCursor.substring(lastAt + 1);
      if (!queryPart.contains(' ')) {
        setState(() {
          _showMentionOverlay = true;
          _mentionQuery = queryPart.toLowerCase();
        });
        return;
      }
    }
    setState(() => _showMentionOverlay = false);
  }

  void _insertMention(String userName) {
    final text = _messageController.text;
    final cursorPos = _messageController.selection.baseOffset;
    final beforeCursor = text.substring(0, cursorPos);
    final lastAt = beforeCursor.lastIndexOf('@');

    if (lastAt >= 0) {
      final newText =
          '${text.substring(0, lastAt)}@$userName ${text.substring(cursorPos)}';
      _messageController.text = newText;
      _messageController.selection =
          TextSelection.collapsed(offset: lastAt + userName.length + 2);
    }
    setState(() => _showMentionOverlay = false);
  }

  Widget _buildMentionOverlay() {
    if (!_showMentionOverlay) return const SizedBox.shrink();

    final filtered = _communityMembers
        .where((m) => (m['name'] ?? '').toLowerCase().contains(_mentionQuery))
        .take(5)
        .toList();

    if (filtered.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[700]!),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final member = filtered[index];
          final name = member['name'] ?? 'User';
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF333333),
              child: Text(
                name[0].toUpperCase(),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
            ),
            title: Text(name,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            onTap: () => _insertMention(name),
          );
        },
      ),
    );
  }

  Widget _buildMessageText(String text, {bool isMe = true}) {
    final spans = <TextSpan>[];
    final mentionRegex = RegExp(r'@(\w+[\w.]*)');
    int lastEnd = 0;

    for (final match in mentionRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: TextStyle(
            color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.white, fontSize: 15),
        children: spans,
      ),
    );
  }

  Widget _buildReplyPreview() {
    if (_replyingTo == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border(
            top: BorderSide(color: AppTheme.primaryColor, width: 2)),
      ),
      child: Row(
        children: [
          Container(width: 3, height: 36, color: AppTheme.primaryColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _replyingTo!.userName,
                  style: TextStyle(
                      color: AppTheme.primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  _replyingTo!.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _replyingTo = null),
            child: Icon(Icons.close, size: 18, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyQuote(CommunityMessage message) {
    try {
      final replyData = jsonDecode(message.imageUrl);
      final replyUser = replyData['reply_to_user'] ?? '';
      final replyText = replyData['reply_to_text'] ?? '';

      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border(
              left: BorderSide(color: AppTheme.primaryColor, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(replyUser,
                style: TextStyle(
                    color: AppTheme.primaryColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(replyText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey[400], fontSize: 12)),
          ],
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _wsSubscription?.cancel();
    _messageController.removeListener(_onMessageTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
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
      String imageUrl = '';
      String messageType = 'text';

      if (_replyingTo != null) {
        messageType = 'reply';
        imageUrl = jsonEncode({
          'reply_to_id': _replyingTo!.id,
          'reply_to_user': _replyingTo!.userName,
          'reply_to_text': _replyingTo!.message.length > 100
              ? '${_replyingTo!.message.substring(0, 100)}...'
              : _replyingTo!.message,
        });
      }

      await ref
          .read(communityMessagesProvider(widget.communityId).notifier)
          .sendMessage(text, imageUrl: imageUrl, messageType: messageType);
      if (mounted) {
        setState(() => _replyingTo = null);
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
      case 'reply':
        setState(() => _replyingTo = message);
        _messageFocusNode.requestFocus();
        break;
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

    // Auto-scroll to bottom when new messages arrive via polling
    ref.listen(communityMessagesProvider(widget.communityId), (prev, next) {
      if (prev != null && next.messages.length > prev.messages.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            final maxScroll = _scrollController.position.maxScrollExtent;
            final currentScroll = _scrollController.position.pixels;
            // Only auto-scroll if user was within 100px of bottom
            if (maxScroll - currentScroll < 100) {
              _scrollController.animateTo(
                maxScroll + 100,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            }
          }
        });
      }
    });

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
                                final isReplyMessage = message.messageType == 'reply' &&
                                    message.imageUrl.isNotEmpty &&
                                    message.imageUrl.startsWith('{');

                                return Column(
                                  children: [
                                    if (showDateSeparator &&
                                        message.timestamp != null)
                                      _DarkDateSeparator(
                                          date: message.timestamp!),
                                    Dismissible(
                                      key: Key('swipe_${message.id}'),
                                      direction: DismissDirection.startToEnd,
                                      confirmDismiss: (direction) async {
                                        setState(() => _replyingTo = message);
                                        _messageFocusNode.requestFocus();
                                        return false;
                                      },
                                      background: Container(
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.only(left: 20),
                                        child: Icon(Icons.reply, color: AppTheme.primaryColor),
                                      ),
                                      child: GestureDetector(
                                        onLongPress: () => _handleMessageLongPress(message),
                                        child: message.messageType == 'voice' &&
                                                message.imageUrl.isNotEmpty
                                            ? Column(
                                                crossAxisAlignment: isMe
                                                    ? CrossAxisAlignment.end
                                                    : CrossAxisAlignment.start,
                                                children: [
                                                  if (!isMe)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              left: 4,
                                                              bottom: 2),
                                                      child: Text(
                                                        message.userName,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: Colors
                                                              .tealAccent[400],
                                                        ),
                                                      ),
                                                    ),
                                                  VoiceMessageBubble(
                                                    audioUrl: message.imageUrl,
                                                    durationSeconds:
                                                        int.tryParse(message
                                                                .message) ??
                                                            0,
                                                    isMe: isMe,
                                                    time: message.timestamp !=
                                                            null
                                                        ? DateFormat('hh:mm a')
                                                            .format(message
                                                                .timestamp!)
                                                        : '',
                                                  ),
                                                ],
                                              )
                                            : _GroupMessageBubble(
                                                senderName: message.userName,
                                                message: message.message,
                                                isMe: isMe,
                                                time: message.timestamp != null
                                                    ? DateFormat('hh:mm a')
                                                        .format(
                                                            message.timestamp!)
                                                    : '',
                                                replyWidget: isReplyMessage
                                                    ? _buildReplyQuote(message)
                                                    : null,
                                                buildMessageText:
                                                    _buildMessageText,
                                              ),
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
          // Mention overlay
          _buildMentionOverlay(),
          // Reply preview
          _buildReplyPreview(),
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
                      focusNode: _messageFocusNode,
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
                          onRecordingDone: (tempId, localPath, duration) async {
                            ref.read(communityMessagesProvider(widget.communityId).notifier)
                                .addLocalPending(CommunityMessage(
                              id: tempId,
                              communityId: widget.communityId,
                              userId: _currentUserId ?? '',
                              userName: '',
                              message: duration.toString(),
                              imageUrl: localPath,
                              messageType: 'voice',
                            ));
                            if (mounted) _scrollToBottom();
                          },
                          onUploadComplete: (tempId, audioUrl, duration) async {
                            ref.read(communityMessagesProvider(widget.communityId).notifier)
                                .removeMessage(tempId);
                            await ref
                                .read(communityMessagesProvider(widget.communityId).notifier)
                                .sendMessage(duration.toString(),
                                    imageUrl: audioUrl, messageType: 'voice');
                            if (mounted) _scrollToBottom();
                          },
                          onUploadFailed: (tempId) async {
                            ref.read(communityMessagesProvider(widget.communityId).notifier)
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
  final Widget? replyWidget;
  final Widget Function(String text, {bool isMe})? buildMessageText;

  const _GroupMessageBubble({
    required this.senderName,
    required this.message,
    required this.isMe,
    required this.time,
    this.replyWidget,
    this.buildMessageText,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    senderName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _getSenderColor(senderName),
                    ),
                  ),
                ),
              ),
            // Reply quote (if this is a reply message)
            if (replyWidget != null) replyWidget!,
            buildMessageText != null
                ? buildMessageText!(message, isMe: isMe)
                : Text(
                    message,
                    style: const TextStyle(fontSize: 15, color: Colors.white),
                  ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time,
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
              ],
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
