import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';

import '../../config/theme.dart';
import '../../models/community.dart';
import '../../providers/community_provider.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../services/websocket_service.dart';
import '../../widgets/chat_background.dart';
import '../../widgets/message_actions_sheet.dart';

// ── Dark theme constants ─────────────────────────────────────────────────────
const Color _kChatScaffoldBg = Color(0xFF0A0A0A);
const Color _kChatAppBarBg = Color(0xFF1A1A1A);
const Color _kChatAreaBg = Color(0xFF0A0A0A);
const Color _kMyBubbleColor = Color(0xFF1B5E20);
const Color _kOtherBubbleColor = Color(0xFF1E1E1E);
const Color _kInputBarBg = Color(0xFF1A1A1A);
const Color _kInputFieldBg = Color(0xFF2A2A2A);

// ── Model for sub-group member ──────────────────────────────────────────────

class SubGroupMember {
  final String id;
  final String userId;
  final String? userName;
  final String? userProfileImage;
  final DateTime? joinedAt;

  SubGroupMember({
    required this.id,
    required this.userId,
    this.userName,
    this.userProfileImage,
    this.joinedAt,
  });

  factory SubGroupMember.fromJson(Map<String, dynamic> json) {
    return SubGroupMember(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      userName: json['user_name'] ?? json['userName'],
      userProfileImage: json['user_profile_image'] ?? json['userProfileImage'],
      joinedAt: json['joined_at'] != null
          ? DateTime.parse(json['joined_at'])
          : json['joinedAt'] != null
              ? DateTime.parse(json['joinedAt'])
              : null,
    );
  }
}

// ── Provider for sub-group members ──────────────────────────────────────────

class SubGroupMembersState {
  final List<SubGroupMember> members;
  final bool isLoading;
  final String? errorMessage;

  const SubGroupMembersState({
    this.members = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  SubGroupMembersState copyWith({
    List<SubGroupMember>? members,
    bool? isLoading,
    String? errorMessage,
  }) {
    return SubGroupMembersState(
      members: members ?? this.members,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class SubGroupMembersNotifier extends StateNotifier<SubGroupMembersState> {
  final ApiService _api;
  final String communityId;
  final String groupId;

  SubGroupMembersNotifier(this._api, this.communityId, this.groupId)
      : super(const SubGroupMembersState());

  Future<void> fetchMembers() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _api.get(
        '/communities/$communityId/groups/$groupId/members',
      );
      final data = response.data;
      final List<dynamic> results =
          data is List ? data : (data['results'] ?? data['members'] ?? []);
      final members =
          results.map((e) => SubGroupMember.fromJson(e)).toList();
      state = SubGroupMembersState(members: members);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }
}

// Use a family provider keyed by "communityId:groupId"
final subGroupMembersProvider = StateNotifierProvider.family<
    SubGroupMembersNotifier,
    SubGroupMembersState,
    String>((ref, key) {
  final parts = key.split(':');
  final communityId = parts[0];
  final groupId = parts.length > 1 ? parts[1] : '';
  return SubGroupMembersNotifier(ApiService(), communityId, groupId);
});

// ── Screen ──────────────────────────────────────────────────────────────────

class SubGroupChatScreen extends ConsumerStatefulWidget {
  final String communityId;
  final String groupId;

  const SubGroupChatScreen({
    super.key,
    required this.communityId,
    required this.groupId,
  });

  @override
  ConsumerState<SubGroupChatScreen> createState() =>
      _SubGroupChatScreenState();
}

class _SubGroupChatScreenState extends ConsumerState<SubGroupChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _messageFocusNode = FocusNode();
  String? _currentUserId;
  bool _isUploading = false;
  bool _isAdmin = false;
  bool _adminOnlyChat = false;
  List<CommunityMessage> _pinnedMessages = [];
  final Map<String, Map<String, dynamic>> _pollCache = {};
  Timer? _pollTimer;
  StreamSubscription? _wsSubscription;

  // @Mentions state
  bool _showMentionOverlay = false;
  String _mentionQuery = '';

  // Reply-to-message state
  CommunityMessage? _replyingTo;

  String get _providerKey =>
      '${widget.communityId}:${widget.groupId}';

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    Future.microtask(() async {
      await ref
          .read(subGroupMessagesProvider(_providerKey).notifier)
          .fetchMessages();
      ref
          .read(subGroupMembersProvider(_providerKey).notifier)
          .fetchMembers();
      _checkAdminStatus();
      _fetchPinnedMessages();
      _scrollToBottomInstant();
    });

    // Listen for WebSocket group messages (instant delivery)
    _wsSubscription = WebSocketService().messageStream.listen((data) {
      if (!mounted) return;
      if (data['type'] == 'group_message' &&
          data['channel'] == 'subgroup:${widget.groupId}') {
        // New message from another user via WebSocket
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
        final notifier = ref.read(subGroupMessagesProvider(_providerKey).notifier);
        final currentMessages = ref.read(subGroupMessagesProvider(_providerKey)).messages;
        // Dedup by ID
        if (!currentMessages.any((m) => m.id == msg.id)) {
          notifier.addMessageFromWebSocket(msg);
          _scrollToBottom();
        }
      }
    });

    // Backup polling every 10 seconds (in case WebSocket misses)
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        ref.read(subGroupMessagesProvider(_providerKey).notifier).fetchMessages();
      }
    });

    // Listen for @ mentions in text input
    _messageController.addListener(_onMessageTextChanged);
  }

  Future<void> _loadCurrentUser() async {
    final userId = await StorageService().getUserId();
    if (mounted) {
      setState(() => _currentUserId = userId);
    }
  }

  void _onMessageTextChanged() {
    final text = _messageController.text;
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

    final members =
        ref.read(subGroupMembersProvider(_providerKey)).members;
    final filtered = members
        .where(
            (m) => (m.userName ?? '').toLowerCase().contains(_mentionQuery))
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
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF333333),
              backgroundImage: member.userProfileImage != null &&
                      member.userProfileImage!.isNotEmpty
                  ? CachedNetworkImageProvider(member.userProfileImage!)
                  : null,
              child: member.userProfileImage == null ||
                      member.userProfileImage!.isEmpty
                  ? Text(
                      (member.userName ?? '?')[0].toUpperCase(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    )
                  : null,
            ),
            title: Text(member.userName ?? 'User',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            onTap: () => _insertMention(member.userName ?? 'User'),
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

  Future<void> _checkAdminStatus() async {
    try {
      final response = await ApiService().get('/communities/${widget.communityId}');
      final data = response.data;
      if (data['member_role'] == 'admin') {
        if (mounted) setState(() => _isAdmin = true);
      }
    } catch (_) {}

    // Fetch admin_only_chat status for this sub-group
    try {
      final groupsResp = await ApiService().get(
        '/communities/${widget.communityId}/groups',
      );
      final groups = groupsResp.data is List ? groupsResp.data : [];
      for (final g in groups) {
        if (g['id']?.toString() == widget.groupId) {
          if (mounted) {
            setState(() => _adminOnlyChat = g['admin_only_chat'] == true);
          }
          break;
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleAdminOnlyChat() async {
    try {
      final response = await ApiService().put(
        '/partner/communities/${widget.communityId}/groups/${widget.groupId}/toggle-admin-chat',
      );
      final data = response.data;
      if (mounted) {
        setState(() => _adminOnlyChat = data['admin_only_chat'] == true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_adminOnlyChat
                ? 'Admin-only chat enabled'
                : 'Admin-only chat disabled'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to toggle: $e')),
        );
      }
    }
  }

  Future<void> _fetchPinnedMessages() async {
    try {
      final response = await ApiService().get(
        '/communities/${widget.communityId}/groups/${widget.groupId}/messages/pinned',
      );
      final data = response.data;
      final List<dynamic> results = data is List ? data : [];
      if (mounted) {
        setState(() {
          _pinnedMessages = results.map((e) => CommunityMessage.fromJson(e)).toList();
        });
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _fetchPollData(String pollId) async {
    if (_pollCache.containsKey(pollId)) return _pollCache[pollId]!;
    try {
      final response = await ApiService().get(
        '/communities/${widget.communityId}/groups/${widget.groupId}/polls/$pollId',
      );
      final data = Map<String, dynamic>.from(response.data);
      _pollCache[pollId] = data;
      return data;
    } catch (_) {
      return {};
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
          .read(subGroupMessagesProvider(_providerKey).notifier)
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

      await ref
          .read(subGroupMessagesProvider(_providerKey).notifier)
          .sendMessage('', imageUrl: imageUrl, messageType: 'image');
      if (mounted) {
        setState(() {});
        await Future.delayed(const Duration(milliseconds: 100));
        _scrollToBottom();
      }
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

  void _showMembersBottomSheet() {
    final membersState =
        ref.read(subGroupMembersProvider(_providerKey));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.group, size: 22, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        'Members (${membersState.members.length})',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Color(0xFF333333)),
                // Members list
                Expanded(
                  child: membersState.isLoading
                      ? const Center(child: CircularProgressIndicator(color: Colors.white))
                      : membersState.members.isEmpty
                          ? Center(
                              child: Text(
                                'No members yet',
                                style: TextStyle(color: Colors.grey[500]),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              itemCount: membersState.members.length,
                              itemBuilder: (context, index) {
                                final member = membersState.members[index];
                                return _MemberListTile(
                                  member: member,
                                  isCurrentUserAdmin: _isAdmin,
                                  communityId: widget.communityId,
                                  onRefresh: () {
                                    ref.read(subGroupMembersProvider(_providerKey).notifier).fetchMembers();
                                    Navigator.of(context).pop();
                                  },
                                );
                              },
                            ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleMessageLongPress(CommunityMessage message) async {
    if (message.isDeleted) return; // No actions on deleted messages

    final isOwn = message.userId == _currentUserId;
    final isText = message.messageType == 'text';

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Reply
              ListTile(
                leading: const Icon(Icons.reply, color: Colors.white70),
                title: const Text('Reply', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 'reply'),
              ),
              // Copy text (for text messages)
              if (isText)
                ListTile(
                  leading: const Icon(Icons.copy_outlined, color: Colors.white70),
                  title: const Text('Copy text', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.message));
                    Navigator.pop(ctx, 'copy');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
              // Pin/Unpin (admin only)
              if (_isAdmin)
                ListTile(
                  leading: Icon(
                    message.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                    color: AppTheme.primaryColor,
                  ),
                  title: Text(
                    message.isPinned ? 'Unpin message' : 'Pin message',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.pop(ctx, 'pin'),
                ),
              // Edit (own text messages only)
              if (isOwn && isText)
                ListTile(
                  leading: const Icon(Icons.edit_outlined, color: Colors.white70),
                  title: const Text('Edit message', style: TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(ctx, 'edit'),
                ),
              // Delete for me
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.white70),
                title: const Text('Delete for me', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 'delete_for_me'),
              ),
              // Delete for everyone (admin or own message)
              if (isOwn || _isAdmin)
                ListTile(
                  leading: const Icon(Icons.delete_forever_outlined, color: Colors.redAccent),
                  title: const Text('Delete for everyone', style: TextStyle(color: Colors.redAccent)),
                  onTap: () => Navigator.pop(ctx, 'delete_for_everyone'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
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
      case 'pin':
        await _togglePinMessage(message);
        break;
      case 'delete_for_me':
        final messages = ref.read(subGroupMessagesProvider(_providerKey)).messages;
        final updated = messages.where((m) => m.id != message.id).toList();
        ref.read(subGroupMessagesProvider(_providerKey).notifier).setMessages(updated);
        break;
      case 'delete_for_everyone':
        try {
          await ApiService().delete(
            '/communities/${widget.communityId}/groups/${widget.groupId}/messages/${message.id}',
          );
          // Update to show as deleted instead of removing
          final messages = ref.read(subGroupMessagesProvider(_providerKey)).messages;
          final updated = messages.map((m) {
            if (m.id == message.id) {
              return m.copyWith(
                isDeleted: true,
                message: 'This message was deleted',
              );
            }
            return m;
          }).toList();
          ref.read(subGroupMessagesProvider(_providerKey).notifier).setMessages(updated);
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

  Future<void> _togglePinMessage(CommunityMessage message) async {
    try {
      await ApiService().post(
        '/communities/${widget.communityId}/groups/${widget.groupId}/messages/${message.id}/pin',
      );
      // Update local state
      final messages = ref.read(subGroupMessagesProvider(_providerKey)).messages;
      final updated = messages.map((m) {
        if (m.id == message.id) {
          return m.copyWith(isPinned: !m.isPinned);
        }
        return m;
      }).toList();
      ref.read(subGroupMessagesProvider(_providerKey).notifier).setMessages(updated);
      _fetchPinnedMessages();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message.isPinned ? 'Message unpinned' : 'Message pinned'),
            duration: const Duration(seconds: 1),
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

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _AttachmentOption(
                      icon: Icons.photo_camera,
                      label: 'Photo',
                      color: Colors.purple,
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendImage();
                      },
                    ),
                    _AttachmentOption(
                      icon: Icons.videocam,
                      label: 'Video',
                      color: Colors.pink,
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendVideo();
                      },
                    ),
                    _AttachmentOption(
                      icon: Icons.poll,
                      label: 'Poll',
                      color: Colors.amber,
                      onTap: () {
                        Navigator.pop(ctx);
                        _showCreatePollDialog();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _AttachmentOption(
                      icon: Icons.location_on,
                      label: 'Location',
                      color: Colors.green,
                      onTap: () {
                        Navigator.pop(ctx);
                        _shareLocation();
                      },
                    ),
                    _AttachmentOption(
                      icon: Icons.insert_drive_file,
                      label: 'Document',
                      color: Colors.blue,
                      onTap: () {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Document sharing coming soon')),
                        );
                      },
                    ),
                    // Spacer to keep grid alignment
                    const SizedBox(width: 72),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAndSendVideo() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickVideo(source: ImageSource.gallery);
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
      final videoUrl = uploadResponse.data['url'] ?? uploadResponse.data['image_url'] ?? '';

      if (videoUrl.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload video')),
          );
        }
        return;
      }

      await ref
          .read(subGroupMessagesProvider(_providerKey).notifier)
          .sendMessage('', imageUrl: videoUrl, messageType: 'video');
      if (mounted) {
        setState(() {});
        await Future.delayed(const Duration(milliseconds: 100));
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send video: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showCreatePollDialog() {
    final questionController = TextEditingController();
    final optionControllers = [TextEditingController(), TextEditingController()];
    bool isMultipleChoice = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[600],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Row(
                      children: [
                        Icon(Icons.poll, color: AppTheme.primaryColor, size: 22),
                        const SizedBox(width: 8),
                        const Text(
                          'Create Poll',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: questionController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Ask a question...',
                        hintStyle: TextStyle(color: Colors.grey[500]),
                        filled: true,
                        fillColor: const Color(0xFF2A2A2A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...List.generate(optionControllers.length, (index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: optionControllers[index],
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Option ${index + 1}',
                                  hintStyle: TextStyle(color: Colors.grey[600]),
                                  filled: true,
                                  fillColor: const Color(0xFF2A2A2A),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            if (optionControllers.length > 2)
                              IconButton(
                                icon: Icon(Icons.close, color: Colors.grey[500], size: 20),
                                onPressed: () {
                                  setSheetState(() {
                                    optionControllers[index].dispose();
                                    optionControllers.removeAt(index);
                                  });
                                },
                              ),
                          ],
                        ),
                      );
                    }),
                    if (optionControllers.length < 6)
                      TextButton.icon(
                        onPressed: () {
                          setSheetState(() {
                            optionControllers.add(TextEditingController());
                          });
                        },
                        icon: Icon(Icons.add, color: AppTheme.primaryColor, size: 18),
                        label: Text(
                          'Add option',
                          style: TextStyle(color: AppTheme.primaryColor),
                        ),
                      ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Allow multiple answers', style: TextStyle(color: Colors.white, fontSize: 14)),
                      value: isMultipleChoice,
                      activeColor: AppTheme.primaryColor,
                      onChanged: (val) => setSheetState(() => isMultipleChoice = val),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () async {
                          final question = questionController.text.trim();
                          final options = optionControllers
                              .map((c) => c.text.trim())
                              .where((t) => t.isNotEmpty)
                              .toList();
                          if (question.isEmpty || options.length < 2) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Enter a question and at least 2 options')),
                            );
                            return;
                          }
                          Navigator.pop(ctx);
                          try {
                            await ApiService().post(
                              '/communities/${widget.communityId}/groups/${widget.groupId}/polls',
                              data: {
                                'question': question,
                                'options': options,
                                'is_multiple_choice': isMultipleChoice,
                              },
                            );
                            await ref
                                .read(subGroupMessagesProvider(_providerKey).notifier)
                                .fetchMessages();
                            _scrollToBottom();
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to create poll: $e')),
                              );
                            }
                          }
                        },
                        child: const Text('Create Poll', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _shareLocation() async {
    // Show a simple dialog to enter coordinates manually since we don't have geolocator
    final latController = TextEditingController();
    final lngController = TextEditingController();
    final addressController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Share Location', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: latController,
              style: const TextStyle(color: Colors.white),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(
                hintText: 'Latitude (e.g. 13.0827)',
                hintStyle: TextStyle(color: Colors.grey[600]),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: lngController,
              style: const TextStyle(color: Colors.white),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(
                hintText: 'Longitude (e.g. 80.2707)',
                hintStyle: TextStyle(color: Colors.grey[600]),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: addressController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Address (optional)',
                hintStyle: TextStyle(color: Colors.grey[600]),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Share', style: TextStyle(color: AppTheme.primaryColor)),
          ),
        ],
      ),
    );

    if (result != true) return;

    final lat = double.tryParse(latController.text.trim());
    final lng = double.tryParse(lngController.text.trim());
    if (lat == null || lng == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid coordinates')),
        );
      }
      return;
    }

    try {
      await ApiService().post(
        '/communities/${widget.communityId}/groups/${widget.groupId}/messages/location',
        data: {
          'latitude': lat,
          'longitude': lng,
          'address': addressController.text.trim(),
        },
      );
      await ref
          .read(subGroupMessagesProvider(_providerKey).notifier)
          .fetchMessages();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share location: $e')),
        );
      }
    }
  }

  Future<void> _voteOnPoll(String pollId, int optionIndex) async {
    try {
      final response = await ApiService().post(
        '/communities/${widget.communityId}/groups/${widget.groupId}/polls/$pollId/vote',
        data: {'option_index': optionIndex},
      );
      // Update poll cache
      _pollCache[pollId] = Map<String, dynamic>.from(response.data);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to vote: $e')),
        );
      }
    }
  }

  void _showPinnedMessages() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.push_pin, size: 20, color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    Text(
                      'Pinned Messages (${_pinnedMessages.length})',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF333333)),
              if (_pinnedMessages.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('No pinned messages', style: TextStyle(color: Colors.grey[500])),
                )
              else
                ...(_pinnedMessages.take(10).map((msg) => ListTile(
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: const Color(0xFF333333),
                        child: Text(
                          msg.userName.isNotEmpty ? msg.userName[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                      title: Text(msg.userName, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      subtitle: Text(
                        msg.message,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _openInMaps(double lat, double lng) {
    // url_launcher not available, show coordinates in snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Location: $lat, $lng\nOpen https://www.google.com/maps?q=$lat,$lng'),
        duration: const Duration(seconds: 4),
      ),
    );
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
                  '/communities/${widget.communityId}/groups/${widget.groupId}/messages/${message.id}',
                  data: {'message': newText},
                );
                final messages = ref.read(subGroupMessagesProvider(_providerKey)).messages;
                final updated = messages.map((m) {
                  if (m.id == message.id) {
                    final editedText = newText.endsWith(' (edited)') ? newText : '$newText (edited)';
                    return m.copyWith(message: editedText);
                  }
                  return m;
                }).toList();
                ref.read(subGroupMessagesProvider(_providerKey).notifier).setMessages(updated);
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
    final state = ref.watch(subGroupMessagesProvider(_providerKey));
    final membersState =
        ref.watch(subGroupMembersProvider(_providerKey));

    // Auto-scroll to bottom when new messages arrive via polling
    ref.listen(subGroupMessagesProvider(_providerKey), (prev, next) {
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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_adminOnlyChat)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(Icons.lock, size: 16, color: Colors.amber[400]),
              ),
            const Text('Group Chat',
                style: TextStyle(color: Colors.white)),
          ],
        ),
        actions: [
          InkWell(
            onTap: _showMembersBottomSheet,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.group, size: 20, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    '${membersState.members.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isAdmin)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              color: const Color(0xFF1E1E1E),
              onSelected: (value) {
                if (value == 'toggle_admin_chat') {
                  _toggleAdminOnlyChat();
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'toggle_admin_chat',
                  child: Row(
                    children: [
                      Icon(
                        _adminOnlyChat ? Icons.lock_open : Icons.lock,
                        color: Colors.white70,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _adminOnlyChat
                            ? 'Disable Admin-only Chat'
                            : 'Enable Admin-only Chat',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Members preview strip (dark)
          if (!membersState.isLoading && membersState.members.isNotEmpty)
            _MembersPreviewStrip(
              members: membersState.members,
              onViewAll: _showMembersBottomSheet,
            ),
          // Pinned messages banner
          if (_pinnedMessages.isNotEmpty)
            GestureDetector(
              onTap: _showPinnedMessages,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: AppTheme.primaryColor.withOpacity(0.1),
                child: Row(
                  children: [
                    Icon(Icons.push_pin, size: 16, color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _pinnedMessages.first.message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: Colors.white),
                      ),
                    ),
                    Text(
                      '${_pinnedMessages.length}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                  ],
                ),
              ),
            ),
          // Chat messages
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
                                // Determine the actual imageUrl and messageType for display
                                // For 'reply' type, imageUrl contains reply JSON, not an actual image
                                final displayImageUrl = message.messageType == 'reply' ? '' : message.imageUrl;
                                final displayMessageType = message.messageType == 'reply' ? 'text' : message.messageType;
                                final isReplyMessage = message.messageType == 'reply' &&
                                    message.imageUrl.isNotEmpty &&
                                    message.imageUrl.startsWith('{');

                                Widget messageBubbleWidget = message.isDeleted
                                    ? _buildDeletedMessage(isMe)
                                    : message.messageType == 'poll'
                                        ? _buildPollMessageWrapper(message, isMe)
                                        : message.messageType == 'location'
                                            ? _buildLocationMessage(message, isMe)
                                            : Stack(
                                                children: [
                                                  _GroupMessageBubble(
                                                    senderName: message.userName,
                                                    senderImage: message.userImage,
                                                    message: message.message,
                                                    isMe: isMe,
                                                    time: message.timestamp != null
                                                        ? DateFormat('hh:mm a')
                                                            .format(message.timestamp!)
                                                        : '',
                                                    imageUrl: displayImageUrl,
                                                    messageType: displayMessageType,
                                                    replyWidget: isReplyMessage
                                                        ? _buildReplyQuote(message)
                                                        : null,
                                                    buildMessageText: _buildMessageText,
                                                  ),
                                                  if (message.isPinned)
                                                    Positioned(
                                                      top: 2,
                                                      right: isMe ? 4 : null,
                                                      left: isMe ? null : 36,
                                                      child: Icon(Icons.push_pin, size: 12, color: AppTheme.primaryColor),
                                                    ),
                                                ],
                                              );

                                return Column(
                                  children: [
                                    if (showDateSeparator && message.timestamp != null)
                                      _DarkDateSeparator(date: message.timestamp!),
                                    Dismissible(
                                      key: Key('swipe_${message.id}'),
                                      direction: DismissDirection.startToEnd,
                                      confirmDismiss: (direction) async {
                                        if (!message.isDeleted) {
                                          setState(() => _replyingTo = message);
                                          _messageFocusNode.requestFocus();
                                        }
                                        return false;
                                      },
                                      background: Container(
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.only(left: 20),
                                        child: Icon(Icons.reply, color: AppTheme.primaryColor),
                                      ),
                                      child: GestureDetector(
                                        onLongPress: () => _handleMessageLongPress(message),
                                        child: messageBubbleWidget,
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
          // Uploading indicator
          if (_isUploading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: LinearProgressIndicator(color: AppTheme.primaryColor),
            ),
          // Mention overlay
          _buildMentionOverlay(),
          // Reply preview
          _buildReplyPreview(),
          // Input bar or admin-only notice
          if (_adminOnlyChat && !_isAdmin)
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF1A1A1A),
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline, size: 16, color: Colors.grey[500]),
                    const SizedBox(width: 8),
                    Text(
                      'Only admins can send messages',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else
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
                      icon: Icon(Icons.add_circle_outline, color: AppTheme.primaryColor),
                      onPressed: _isUploading ? null : _showAttachmentMenu,
                    ),
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

  Widget _buildDeletedMessage(bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey[800]!.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block, size: 14, color: Colors.grey[500]),
            const SizedBox(width: 6),
            Text(
              'This message was deleted',
              style: TextStyle(
                color: Colors.grey[500],
                fontStyle: FontStyle.italic,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPollMessageWrapper(CommunityMessage message, bool isMe) {
    // message.imageUrl contains poll_id
    final pollId = message.imageUrl;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _fetchPollData(pollId),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[700]!),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.poll, color: AppTheme.primaryColor, size: 18),
                    const SizedBox(width: 8),
                    const Text('Loading poll...', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              );
            }

            final pollData = snapshot.data!;
            final question = pollData['question'] ?? message.message;
            final List options = pollData['options'] ?? [];
            final int totalVotes = pollData['total_votes'] ?? 0;
            final List userVotes = pollData['user_votes'] ?? [];
            final Set<int> userVotedSet = userVotes.map((e) => e as int).toSet();

            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[700]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        message.userName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _getSenderColor(message.userName),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Icon(Icons.poll, color: AppTheme.primaryColor, size: 18),
                      const SizedBox(width: 8),
                      Text('Poll', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    question,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(options.length, (index) {
                    final option = options[index];
                    final text = option['text'] ?? '';
                    final votes = option['votes'] ?? 0;
                    final isVoted = userVotedSet.contains(index);
                    final percentage = totalVotes > 0 ? votes / totalVotes : 0.0;

                    return GestureDetector(
                      onTap: () => _voteOnPoll(pollId, index),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: Stack(
                          children: [
                            Container(
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.grey[800],
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: percentage.clamp(0.0, 1.0),
                              child: Container(
                                height: 40,
                                decoration: BoxDecoration(
                                  color: isVoted
                                      ? AppTheme.primaryColor.withOpacity(0.3)
                                      : Colors.grey[700],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                            Container(
                              height: 40,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                children: [
                                  if (isVoted)
                                    Icon(Icons.check_circle, size: 16, color: AppTheme.primaryColor),
                                  if (isVoted) const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(text, style: const TextStyle(color: Colors.white)),
                                  ),
                                  Text(
                                    '${(percentage * 100).toStringAsFixed(0)}%',
                                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Text(
                    '$totalVotes vote${totalVotes == 1 ? '' : 's'}',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLocationMessage(CommunityMessage message, bool isMe) {
    Map<String, dynamic> data = {};
    try {
      data = jsonDecode(message.imageUrl);
    } catch (_) {}
    final lat = (data['lat'] ?? 0).toDouble();
    final lng = (data['lng'] ?? 0).toDouble();
    final address = data['address'] ?? message.message;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 36),
                child: Text(
                  message.userName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _getSenderColor(message.userName),
                  ),
                ),
              ),
            GestureDetector(
              onTap: () => _openInMaps(lat, lng),
              child: Container(
                width: 220,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[700]!),
                ),
                child: Column(
                  children: [
                    Container(
                      height: 120,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on, color: Colors.red, size: 32),
                            const SizedBox(height: 4),
                            Text(
                              '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                              style: TextStyle(color: Colors.grey[400], fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on, size: 16, color: Colors.red),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              address,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(Icons.open_in_new, size: 14, color: Colors.grey[500]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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

// ── Members preview strip (dark) ────────────────────────────────────────────

class _MembersPreviewStrip extends StatelessWidget {
  final List<SubGroupMember> members;
  final VoidCallback onViewAll;

  const _MembersPreviewStrip({
    required this.members,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: _kChatAppBarBg,
        border: Border(
          bottom: BorderSide(color: Color(0xFF2A2A2A)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Members (${members.length})',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onViewAll,
                child: Text(
                  'View all',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 56,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: members.length,
              itemBuilder: (context, index) {
                final member = members[index];
                return GestureDetector(
                  onTap: () => context.push('/user/${member.userId}'),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Column(
                      children: [
                        _MemberAvatar(
                          imageUrl: member.userProfileImage,
                          size: 36,
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 50,
                          child: Text(
                            member.userName ?? 'User',
                            style: const TextStyle(
                                fontSize: 10, color: Colors.white70),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Member list tile (dark) ─────────────────────────────────────────────────

class _MemberListTile extends StatelessWidget {
  final SubGroupMember member;
  final bool isCurrentUserAdmin;
  final String communityId;
  final VoidCallback? onRefresh;

  const _MemberListTile({
    required this.member,
    this.isCurrentUserAdmin = false,
    this.communityId = '',
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: _MemberAvatar(
        imageUrl: member.userProfileImage,
        size: 40,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              member.userName ?? 'Unknown User',
              style: const TextStyle(
                  fontWeight: FontWeight.w500, fontSize: 15, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Show admin badge if member is admin (check via role field if available)
        ],
      ),
      subtitle: member.joinedAt != null
          ? Text(
              'Joined ${DateFormat('MMM d, yyyy').format(member.joinedAt!)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            )
          : null,
      trailing: isCurrentUserAdmin
          ? PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 20, color: Colors.grey[500]),
              color: const Color(0xFF1E1E1E),
              onSelected: (value) async {
                if (value == 'view') {
                  Navigator.of(context).pop();
                  context.push('/user/${member.userId}');
                } else if (value == 'chat') {
                  Navigator.of(context).pop();
                  context.push('/chat/${member.userId}?name=${Uri.encodeComponent(member.userName ?? '')}');
                } else if (value == 'make_admin') {
                  try {
                    await ApiService().put(
                      '/partner/communities/$communityId/members/${member.userId}/role',
                      data: {'role': 'admin'},
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${member.userName} promoted to Admin')),
                    );
                    onRefresh?.call();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed: $e')),
                    );
                  }
                } else if (value == 'remove_admin') {
                  try {
                    await ApiService().put(
                      '/partner/communities/$communityId/members/${member.userId}/role',
                      data: {'role': 'member'},
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${member.userName} demoted to Member')),
                    );
                    onRefresh?.call();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed: $e')),
                    );
                  }
                } else if (value == 'kick') {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      backgroundColor: const Color(0xFF1E1E1E),
                      title: const Text('Kick Member', style: TextStyle(color: Colors.white)),
                      content: Text('Remove ${member.userName} from this community?', style: const TextStyle(color: Colors.white70)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(d, true), child: Text('Kick', style: TextStyle(color: Colors.red[400]))),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    try {
                      await ApiService().delete('/partner/communities/$communityId/members/${member.userId}');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${member.userName} removed')),
                      );
                      onRefresh?.call();
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed: $e')),
                      );
                    }
                  }
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'view', child: Row(children: [Icon(Icons.person_outline, size: 18, color: Colors.white70), SizedBox(width: 8), Text('View Profile', style: TextStyle(color: Colors.white))])),
                const PopupMenuItem(value: 'chat', child: Row(children: [Icon(Icons.chat_bubble_outline, size: 18, color: Colors.white70), SizedBox(width: 8), Text('Message', style: TextStyle(color: Colors.white))])),
                PopupMenuItem(value: 'make_admin', child: Row(children: [Icon(Icons.admin_panel_settings, size: 18, color: AppTheme.primaryColor), SizedBox(width: 8), Text('Make Admin', style: TextStyle(color: AppTheme.primaryColor))])),
                PopupMenuItem(value: 'remove_admin', child: Row(children: [Icon(Icons.person, size: 18, color: Colors.orange[300]), SizedBox(width: 8), Text('Remove Admin', style: TextStyle(color: Colors.orange[300]))])),
                PopupMenuItem(value: 'kick', child: Row(children: [Icon(Icons.remove_circle_outline, size: 18, color: Colors.red[400]), SizedBox(width: 8), Text('Kick', style: TextStyle(color: Colors.red[400]))])),
              ],
            )
          : Icon(Icons.chevron_right, color: Colors.grey[600]),
      onTap: isCurrentUserAdmin
          ? null
          : () {
              Navigator.of(context).pop();
              context.push('/user/${member.userId}');
            },
    );
  }
}

// ── Member avatar widget ────────────────────────────────────────────────────

class _MemberAvatar extends StatelessWidget {
  final String? imageUrl;
  final double size;

  const _MemberAvatar({this.imageUrl, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    return ClipOval(
      child: hasImage
          ? CachedNetworkImage(
              imageUrl: imageUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                width: size,
                height: size,
                color: const Color(0xFF333333),
                child: Icon(Icons.person,
                    size: size * 0.6, color: Colors.grey[600]),
              ),
              errorWidget: (context, url, error) => Container(
                width: size,
                height: size,
                color: const Color(0xFF333333),
                child: Icon(Icons.person,
                    size: size * 0.6, color: Colors.grey[600]),
              ),
            )
          : Container(
              width: size,
              height: size,
              color: const Color(0xFF333333),
              child: Icon(Icons.person,
                  size: size * 0.6, color: Colors.grey[600]),
            ),
    );
  }
}

// ── Chat message bubble (dark, with sender colors + image support) ──────────

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

class _GroupMessageBubble extends StatelessWidget {
  final String senderName;
  final String? senderImage;
  final String message;
  final bool isMe;
  final String time;
  final String imageUrl;
  final String messageType;
  final Widget? replyWidget;
  final Widget Function(String text, {bool isMe})? buildMessageText;

  const _GroupMessageBubble({
    required this.senderName,
    this.senderImage,
    required this.message,
    required this.isMe,
    required this.time,
    this.imageUrl = '',
    this.messageType = 'text',
    this.replyWidget,
    this.buildMessageText,
  });

  @override
  Widget build(BuildContext context) {
    final isImage = messageType == 'image' && imageUrl.isNotEmpty;

    if (isMe) {
      return _buildBubbleOnly(context, isImage);
    }

    // For other users: show avatar + bubble
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar
          CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFF333333),
            backgroundImage: senderImage != null && senderImage!.isNotEmpty
                ? CachedNetworkImageProvider(senderImage!)
                : null,
            child: senderImage == null || senderImage!.isEmpty
                ? Text(
                    senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          // Bubble
          Flexible(child: _buildBubbleOnly(context, isImage, addMargin: false)),
        ],
      ),
    );
  }

  Widget _buildBubbleOnly(BuildContext context, bool isImage, {bool addMargin = true}) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: addMargin ? 8 : 0),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * (isMe ? 0.75 : 0.65),
          ),
          child: Container(
            padding: isImage
                ? const EdgeInsets.all(4)
                : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                padding: EdgeInsets.only(
                    bottom: 4, left: isImage ? 8 : 0, top: isImage ? 4 : 0),
                child: Text(
                  senderName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _getSenderColor(senderName),
                  ),
                ),
              ),
            // Reply quote (if this is a reply message)
            if (replyWidget != null) replyWidget!,
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
                    fit: BoxFit.cover,
                    width: double.infinity,
                  ),
                ),
              ),
            if (!isImage)
              buildMessageText != null
                  ? buildMessageText!(message, isMe: isMe)
                  : Text(
                      message,
                      style: const TextStyle(fontSize: 15, color: Colors.white),
                    ),
            if (isImage && message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: buildMessageText != null
                    ? buildMessageText!(message, isMe: isMe)
                    : Text(
                        message,
                        style: const TextStyle(fontSize: 14, color: Colors.white),
                      ),
              ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: isImage
                    ? const EdgeInsets.only(right: 8, bottom: 4)
                    : EdgeInsets.zero,
                child: Text(
                  time,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[400],
                  ),
                ),
              ),
            ),
              ],
            ),
          ),
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

// ── Attachment menu option (WhatsApp-style) ─────────────────────────────────

class _AttachmentOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
