import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';

class ShareBottomSheet extends StatefulWidget {
  final String postId;
  final String? postImageUrl;
  final String? postCaption;
  final String postUserName;
  final String mediaType; // 'image', 'video', 'reel'

  const ShareBottomSheet({
    super.key,
    required this.postId,
    this.postImageUrl,
    this.postCaption,
    required this.postUserName,
    this.mediaType = 'image',
  });

  static void show(
    BuildContext context, {
    required String postId,
    String? postImageUrl,
    String? postCaption,
    required String postUserName,
    String mediaType = 'image',
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ShareBottomSheet(
        postId: postId,
        postImageUrl: postImageUrl,
        postCaption: postCaption,
        postUserName: postUserName,
        mediaType: mediaType,
      ),
    );
  }

  @override
  State<ShareBottomSheet> createState() => _ShareBottomSheetState();
}

class _ShareBottomSheetState extends State<ShareBottomSheet> {
  final _api = ApiService();
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _communities = [];
  Set<String> _sentTo = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadShareTargets();
  }

  Future<void> _loadShareTargets() async {
    try {
      // Fetch friends
      final friendsRes = await _api.get('/friends');
      final friendsData = friendsRes.data;
      _friends =
          (friendsData is List ? friendsData : []).cast<Map<String, dynamic>>();

      // Fetch joined communities
      final commRes = await _api.get('/communities/joined');
      final commData = commRes.data;
      _communities =
          (commData is List ? commData : []).cast<Map<String, dynamic>>();
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _shareToFriend(String friendId, String friendName) async {
    try {
      await _api.post('/messages', data: {
        'receiver_id': friendId,
        'message': '',
        'message_type': 'shared_post',
        'shared_post_id': widget.postId,
        'image_url': widget.postImageUrl ?? '',
      });
      setState(() => _sentTo.add('friend_$friendId'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Sent to $friendName'),
              duration: const Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    }
  }

  Future<void> _shareToCommunity(
      String communityId, String communityName) async {
    try {
      await _api.post('/communities/$communityId/messages', data: {
        'message': '',
        'message_type': 'shared_post',
        'shared_post_id': widget.postId,
        'image_url': widget.postImageUrl ?? '',
      });
      setState(() => _sentTo.add('comm_$communityId'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Sent to $communityName'),
              duration: const Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.toLowerCase();
    final filteredFriends = query.isEmpty
        ? _friends
        : _friends
            .where((f) =>
                (f['name'] ?? '').toString().toLowerCase().contains(query))
            .toList();
    final filteredComms = query.isEmpty
        ? _communities
        : _communities
            .where((c) =>
                (c['name'] ?? '').toString().toLowerCase().contains(query))
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
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
                  borderRadius: BorderRadius.circular(2)),
            ),
            // Title
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text('Share with',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
            ),
            // Search
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search...',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            // Quick share row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  _QuickShareButton(
                    icon: Icons.link,
                    label: 'Copy Link',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Link copied!'),
                            duration: Duration(seconds: 1)),
                      );
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(width: 12),
                  _QuickShareButton(
                    icon: Icons.share_outlined,
                    label: 'More',
                    onTap: () {
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF333333), height: 1),
            // Content
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white))
                  : ListView(
                      controller: scrollController,
                      children: [
                        // Friends section
                        if (filteredFriends.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                            child: Text('Friends',
                                style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ),
                          ...filteredFriends.map((friend) {
                            final id = friend['id']?.toString() ??
                                friend['friend_id']?.toString() ??
                                '';
                            final name = friend['name']?.toString() ?? '';
                            final image =
                                friend['profile_image_url']?.toString() ?? '';
                            final sent = _sentTo.contains('friend_$id');
                            return _ShareTargetTile(
                              name: name,
                              imageUrl: image,
                              isSent: sent,
                              onSend: () => _shareToFriend(id, name),
                            );
                          }),
                        ],
                        // Communities section
                        if (filteredComms.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                            child: Text('Communities',
                                style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ),
                          ...filteredComms.map((comm) {
                            final id = comm['id']?.toString() ?? '';
                            final name = comm['name']?.toString() ?? '';
                            final image = comm['image_url']?.toString() ?? '';
                            final sent = _sentTo.contains('comm_$id');
                            return _ShareTargetTile(
                              name: name,
                              imageUrl: image,
                              isSent: sent,
                              isCommunity: true,
                              onSend: () => _shareToCommunity(id, name),
                            );
                          }),
                        ],
                        if (filteredFriends.isEmpty && filteredComms.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(
                              child: Text('No one to share with yet',
                                  style: TextStyle(color: Colors.grey[500])),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _QuickShareButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickShareButton(
      {required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareTargetTile extends StatelessWidget {
  final String name;
  final String imageUrl;
  final bool isSent;
  final bool isCommunity;
  final VoidCallback onSend;
  const _ShareTargetTile(
      {required this.name,
      required this.imageUrl,
      required this.isSent,
      this.isCommunity = false,
      required this.onSend});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: const Color(0xFF333333),
        backgroundImage:
            imageUrl.isNotEmpty ? CachedNetworkImageProvider(imageUrl) : null,
        child: imageUrl.isEmpty
            ? Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700))
            : null,
      ),
      title: Row(
        children: [
          Flexible(
              child: Text(name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15),
                  overflow: TextOverflow.ellipsis)),
          if (isCommunity) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(8)),
              child: const Text('Group',
                  style: TextStyle(color: Colors.grey, fontSize: 10)),
            ),
          ],
        ],
      ),
      trailing: GestureDetector(
        onTap: isSent ? null : onSend,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSent ? Colors.grey[700] : const Color(0xFFCDDC39),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            isSent ? 'Sent' : 'Send',
            style: TextStyle(
                color: isSent ? Colors.grey[400] : Colors.black,
                fontWeight: FontWeight.w600,
                fontSize: 13),
          ),
        ),
      ),
    );
  }
}
