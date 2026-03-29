import 'package:flutter/material.dart';
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
  String? _currentUserId;
  bool _isUploading = false;

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
          .read(subGroupMessagesProvider(_providerKey).notifier)
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
                                return _MemberListTile(member: member);
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
    final isOwn = message.userId == _currentUserId;
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
        final messages = ref.read(subGroupMessagesProvider(_providerKey)).messages;
        final updated = messages.where((m) => m.id != message.id).toList();
        ref.read(subGroupMessagesProvider(_providerKey).notifier).setMessages(updated);
        break;
      case 'delete_for_everyone':
        try {
          await ApiService().delete(
            '/communities/${widget.communityId}/groups/${widget.groupId}/messages/${message.id}',
          );
          final messages = ref.read(subGroupMessagesProvider(_providerKey)).messages;
          final updated = messages.where((m) => m.id != message.id).toList();
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

    return Scaffold(
      backgroundColor: _kChatScaffoldBg,
      appBar: AppBar(
        backgroundColor: _kChatAppBarBg,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Group Chat',
            style: TextStyle(color: Colors.white)),
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
                                return Column(
                                  children: [
                                    if (showDateSeparator && message.timestamp != null)
                                      _DarkDateSeparator(date: message.timestamp!),
                                    GestureDetector(
                                      onLongPress: () => _handleMessageLongPress(message),
                                      child: _GroupMessageBubble(
                                        senderName: message.userName,
                                        senderImage: message.userImage,
                                        message: message.message,
                                        isMe: isMe,
                                        time: message.timestamp != null
                                            ? DateFormat('hh:mm a')
                                                .format(message.timestamp!)
                                            : '',
                                        imageUrl: message.imageUrl,
                                        messageType: message.messageType,
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

  const _MemberListTile({required this.member});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: _MemberAvatar(
        imageUrl: member.userProfileImage,
        size: 40,
      ),
      title: Text(
        member.userName ?? 'Unknown User',
        style: const TextStyle(
            fontWeight: FontWeight.w500, fontSize: 15, color: Colors.white),
      ),
      subtitle: member.joinedAt != null
          ? Text(
              'Joined ${DateFormat('MMM d, yyyy').format(member.joinedAt!)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            )
          : null,
      trailing: Icon(Icons.chevron_right, color: Colors.grey[600]),
      onTap: () {
        Navigator.of(context).pop(); // close bottom sheet
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

  const _GroupMessageBubble({
    required this.senderName,
    this.senderImage,
    required this.message,
    required this.isMe,
    required this.time,
    this.imageUrl = '',
    this.messageType = 'text',
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
        padding: isImage
            ? const EdgeInsets.all(4)
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * (isMe ? 0.75 : 0.65),
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
