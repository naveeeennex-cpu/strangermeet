import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../config/theme.dart';
import '../../models/post.dart';
import '../../services/api_service.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;

  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late TabController _tabController;

  Map<String, dynamic>? _user;
  List<Post> _posts = [];
  bool _isLoadingUser = true;
  bool _isLoadingPosts = true;
  String? _errorMessage;

  // Friend system
  String _friendshipStatus = 'none'; // none, pending_sent, pending_received, friends
  String? _friendRequestId;
  int _friendCount = 0;
  int _communityCount = 0;
  bool _isSendingRequest = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchUserData();
    _fetchUserPosts();
    _fetchFriendshipStatus();
    _fetchCounts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserData() async {
    try {
      final response = await _api.get('/users/${widget.userId}');
      setState(() {
        _user = response.data;
        _isLoadingUser = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoadingUser = false;
      });
    }
  }

  Future<void> _fetchUserPosts() async {
    try {
      final response = await _api.get('/users/${widget.userId}/posts');
      final data = response.data;
      final List<dynamic> results =
          data is List ? data : (data['results'] ?? data['posts'] ?? []);
      setState(() {
        _posts = results.map((e) => Post.fromJson(e)).toList();
        _isLoadingPosts = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingPosts = false;
      });
    }
  }

  Future<void> _fetchFriendshipStatus() async {
    try {
      final response = await _api.get('/friends/status/${widget.userId}');
      setState(() {
        _friendshipStatus = response.data['status'] ?? 'none';
        _friendRequestId = response.data['request_id'];
      });
    } catch (e) {
      // Silently fail — defaults to 'none'
    }
  }

  Future<void> _fetchCounts() async {
    try {
      // Fetch friend count
      final friendsRes = await _api.get('/friends');
      final friendsData = friendsRes.data;
      final friendsList = friendsData is List ? friendsData : [];

      // Fetch community count
      int commCount = 0;
      try {
        final commRes = await _api.get('/communities/count/${widget.userId}');
        commCount = commRes.data['count'] ?? 0;
      } catch (_) {}

      setState(() {
        _friendCount = friendsList.length;
        _communityCount = commCount;
      });
    } catch (_) {}
  }

  Future<void> _sendFriendRequest() async {
    setState(() => _isSendingRequest = true);
    try {
      await _api.post('/friends/request', data: {
        'addressee_id': widget.userId,
      });
      setState(() {
        _friendshipStatus = 'pending_sent';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send request: $e')),
        );
      }
    }
    setState(() => _isSendingRequest = false);
  }

  Future<void> _acceptFriendRequest() async {
    if (_friendRequestId == null) return;
    try {
      await _api.post('/friends/accept/$_friendRequestId');
      setState(() {
        _friendshipStatus = 'friends';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  Future<void> _rejectFriendRequest() async {
    if (_friendRequestId == null) return;
    try {
      await _api.post('/friends/reject/$_friendRequestId');
      setState(() {
        _friendshipStatus = 'none';
        _friendRequestId = null;
      });
    } catch (_) {}
  }

  Future<void> _refresh() async {
    await Future.wait([
      _fetchUserData(),
      _fetchUserPosts(),
      _fetchFriendshipStatus(),
      _fetchCounts(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final userName = _user?['name'] ?? 'User';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(
          userName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _isLoadingUser
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load profile',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _refresh,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppTheme.primaryColor,
                  onRefresh: _refresh,
                  child: NestedScrollView(
                    headerSliverBuilder: (context, innerBoxIsScrolled) {
                      return [
                        SliverToBoxAdapter(
                          child: _buildProfileHeader(),
                        ),
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _TabBarDelegate(
                            tabBar: TabBar(
                              controller: _tabController,
                              indicatorColor: AppTheme.textPrimary,
                              labelColor: AppTheme.textPrimary,
                              unselectedLabelColor: AppTheme.textSecondary,
                              tabs: const [
                                Tab(icon: Icon(Icons.grid_on)),
                                Tab(icon: Icon(Icons.view_list)),
                              ],
                            ),
                          ),
                        ),
                      ];
                    },
                    body: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildGridTab(),
                        _buildListTab(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildProfileHeader() {
    final profileImageUrl =
        _user?['profile_image_url'] ?? _user?['profileImageUrl'];
    final name = _user?['name'] ?? '';
    final bio = _user?['bio'] ?? '';
    final interests = _user?['interests'] as List<dynamic>? ?? [];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar + Stats row
          Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 40,
                backgroundColor: AppTheme.surfaceColor,
                backgroundImage: profileImageUrl != null &&
                        profileImageUrl.toString().isNotEmpty
                    ? CachedNetworkImageProvider(profileImageUrl.toString())
                    : null,
                child: profileImageUrl == null ||
                        profileImageUrl.toString().isEmpty
                    ? Icon(Icons.person, size: 40, color: Colors.grey[500])
                    : null,
              ),
              const SizedBox(width: 24),
              // Stats — Posts, Friends, Communities
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatColumn('${_posts.length}', 'Posts'),
                    _buildStatColumn('$_friendCount', 'Friends'),
                    _buildStatColumn('$_communityCount', 'Communities'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Name
          if (name.isNotEmpty)
            Text(
              name,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          // Username
          if (_user?['username'] != null &&
              _user!['username'].toString().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '@${_user!['username']}',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
          // Bio
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              bio,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
          ],
          // Interests
          if (interests.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: interests.map<Widget>((interest) {
                return Chip(
                  label: Text(
                    interest.toString(),
                    style: const TextStyle(fontSize: 12),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 12),
          // Action buttons based on friendship status
          _buildActionButtons(name),
        ],
      ),
    );
  }

  Widget _buildActionButtons(String name) {
    switch (_friendshipStatus) {
      case 'friends':
        // Already friends — show Message button + Friends badge
        return Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  context.push(
                    '/chat/${widget.userId}?name=${Uri.encodeComponent(name)}',
                  );
                },
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('Message'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.check_circle, size: 18, color: Colors.green),
                label: const Text(
                  'Friends',
                  style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  side: const BorderSide(color: Colors.green),
                ),
              ),
            ),
          ],
        );

      case 'pending_sent':
        // Request sent — show "Request Sent" disabled
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.hourglass_top, size: 18),
            label: const Text('Request Sent'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              side: BorderSide(color: Colors.grey[400]!),
            ),
          ),
        );

      case 'pending_received':
        // They sent us a request — Accept / Reject
        return Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _acceptFriendRequest,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Accept'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _rejectFriendRequest,
                icon: const Icon(Icons.close, size: 18, color: Colors.red),
                label: const Text(
                  'Reject',
                  style: TextStyle(color: Colors.red),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  side: const BorderSide(color: Colors.red),
                ),
              ),
            ),
          ],
        );

      default:
        // Not friends — show "Send Friend Request"
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSendingRequest ? null : _sendFriendRequest,
            icon: _isSendingRequest
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Icon(Icons.person_add_outlined, size: 18),
            label: Text(_isSendingRequest ? 'Sending...' : 'Send Friend Request'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
          ),
        );
    }
  }

  Widget _buildStatColumn(String count, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          count,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildGridTab() {
    if (_isLoadingPosts) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No posts yet',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(1),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _posts.length,
      itemBuilder: (context, index) {
        final post = _posts[index];
        return GestureDetector(
          onTap: () => context.push('/post/${post.id}'),
          child: post.imageUrl != null && post.imageUrl!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: post.imageUrl!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: AppTheme.surfaceColor,
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: AppTheme.surfaceColor,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                )
              : Container(
                  color: AppTheme.surfaceColor,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        post.caption,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildListTab() {
    if (_isLoadingPosts) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No posts yet',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: _posts.length,
      itemBuilder: (context, index) {
        final post = _posts[index];
        return _UserPostCard(post: post);
      },
    );
  }
}

class _UserPostCard extends StatelessWidget {
  final Post post;

  const _UserPostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 0.5),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: InkWell(
        onTap: () => context.push('/post/${post.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppTheme.surfaceColor,
                    backgroundImage: post.userImage != null
                        ? CachedNetworkImageProvider(post.userImage!)
                        : null,
                    child: post.userImage == null
                        ? Text(
                            post.userName.isNotEmpty
                                ? post.userName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                              fontSize: 14,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.userName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        if (post.createdAt != null)
                          Text(
                            timeago.format(post.createdAt!),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Image
            if (post.imageUrl != null && post.imageUrl!.isNotEmpty)
              CachedNetworkImage(
                imageUrl: post.imageUrl!,
                width: double.infinity,
                height: 300,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  height: 300,
                  color: AppTheme.surfaceColor,
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, url, error) => Container(
                  height: 300,
                  color: AppTheme.surfaceColor,
                  child: const Icon(Icons.broken_image_outlined, size: 48),
                ),
              ),
            // Caption
            if (post.caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  post.caption,
                  style: const TextStyle(fontSize: 14),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            // Stats
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Icon(
                    post.isLiked ? Icons.favorite : Icons.favorite_border,
                    size: 18,
                    color: post.isLiked ? Colors.red : Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${post.likesCount}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.chat_bubble_outline,
                      size: 18, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${post.commentsCount}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _TabBarDelegate({required this.tabBar});

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppTheme.backgroundColor,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) => false;
}
