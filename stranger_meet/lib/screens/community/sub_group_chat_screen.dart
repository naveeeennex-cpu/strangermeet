import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';

import '../../config/theme.dart';
import '../../providers/community_provider.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/chat_background.dart';
import '../../widgets/date_separator.dart';

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
      _scrollToBottom();
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

  void _showMembersBottomSheet() {
    final membersState =
        ref.read(subGroupMembersProvider(_providerKey));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.group, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Members (${membersState.members.length})',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                // Members list
                Expanded(
                  child: membersState.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : membersState.members.isEmpty
                          ? Center(
                              child: Text(
                                'No members yet',
                                style: TextStyle(color: Colors.grey[400]),
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(subGroupMessagesProvider(_providerKey));
    final membersState =
        ref.watch(subGroupMembersProvider(_providerKey));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Chat'),
        actions: [
          InkWell(
            onTap: _showMembersBottomSheet,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.group, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    '${membersState.members.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
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
          // Members preview strip
          if (!membersState.isLoading && membersState.members.isNotEmpty)
            _MembersPreviewStrip(
              members: membersState.members,
              onViewAll: _showMembersBottomSheet,
            ),
          // Chat messages
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
                                'Start the conversation!',
                                style: TextStyle(color: Colors.grey[400]),
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
                                    DateSeparator.isDifferentDay(
                                      state.messages[index - 1].timestamp,
                                      message.timestamp,
                                    );
                                return Column(
                                  children: [
                                    if (showDateSeparator && message.timestamp != null)
                                      DateSeparator(date: message.timestamp!),
                                    _GroupMessageBubble(
                                      senderName: message.userName,
                                      message: message.message,
                                      isMe: isMe,
                                      time: message.timestamp != null
                                          ? DateFormat('hh:mm a')
                                              .format(message.timestamp!)
                                          : '',
                                      imageUrl: message.imageUrl,
                                      messageType: message.messageType,
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
              child: LinearProgressIndicator(),
            ),
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

// ── Members preview strip (horizontal avatars above chat) ───────────────────

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
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!),
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
                  color: Colors.black87,
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
                    color: AppTheme.primaryDark,
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
                            style: const TextStyle(fontSize: 10),
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

// ── Member list tile (for bottom sheet) ─────────────────────────────────────

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
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
      ),
      subtitle: member.joinedAt != null
          ? Text(
              'Joined ${DateFormat('MMM d, yyyy').format(member.joinedAt!)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            )
          : null,
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
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
                color: Colors.grey[200],
                child: Icon(Icons.person, size: size * 0.6, color: Colors.grey),
              ),
              errorWidget: (context, url, error) => Container(
                width: size,
                height: size,
                color: Colors.grey[200],
                child: Icon(Icons.person, size: size * 0.6, color: Colors.grey),
              ),
            )
          : Container(
              width: size,
              height: size,
              color: Colors.grey[200],
              child: Icon(Icons.person, size: size * 0.6, color: Colors.grey),
            ),
    );
  }
}

// ── Chat message bubble ─────────────────────────────────────────────────────

class _GroupMessageBubble extends StatelessWidget {
  final String senderName;
  final String message;
  final bool isMe;
  final String time;
  final String imageUrl;
  final String messageType;

  const _GroupMessageBubble({
    required this.senderName,
    required this.message,
    required this.isMe,
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: EdgeInsets.only(bottom: 4, left: isImage ? 8 : 0, top: isImage ? 4 : 0),
                child: Text(
                  senderName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryDark,
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
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: isImage ? const EdgeInsets.only(right: 8, bottom: 4) : EdgeInsets.zero,
                child: Text(
                  time,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
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
