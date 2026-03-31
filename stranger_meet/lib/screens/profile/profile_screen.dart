import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../models/post.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friend_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with SingleTickerProviderStateMixin {
  int _communityCount = 0;
  int _postCount = 0;
  List<Post> _posts = [];
  List<dynamic> _communities = [];
  bool _isLoadingPosts = true;
  bool _isLoadingCommunities = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    Future.microtask(() {
      ref.read(friendProvider.notifier).fetchFriends();
      ref.read(friendProvider.notifier).fetchPendingRequests();
      _fetchCounts();
      _fetchPosts();
      _fetchCommunities();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchCounts() async {
    final api = ApiService();
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    try {
      final commRes = await api.get('/communities/count/${user.id}');
      if (mounted) {
        setState(() {
          _communityCount = commRes.data['count'] ?? 0;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchPosts() async {
    final api = ApiService();
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    try {
      final postsRes = await api.get('/users/${user.id}/posts');
      final postsData = postsRes.data;
      final List<dynamic> results = postsData is List ? postsData : [];
      if (mounted) {
        setState(() {
          _posts = results.map((e) => Post.fromJson(e)).toList();
          _postCount = _posts.length;
          _isLoadingPosts = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingPosts = false);
    }
  }

  Future<void> _fetchCommunities() async {
    try {
      final response = await ApiService().get('/communities/my');
      final data = response.data;
      if (mounted) {
        setState(() {
          _communities = data is List ? data : [];
          _isLoadingCommunities = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingCommunities = false);
    }
  }

  Future<void> _refresh() async {
    await Future.wait([
      _fetchCounts(),
      _fetchPosts(),
      _fetchCommunities(),
    ]);
    ref.read(friendProvider.notifier).fetchFriends();
  }

  Future<void> _handleLogout() async {
    await ref.read(authStateProvider.notifier).logout();
    if (mounted) context.go('/welcome');
  }

  void _showLogoutConfirm() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _handleLogout();
            },
            child: const Text('Log Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final friendState = ref.watch(friendProvider);

    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Profile',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert,
                color: Theme.of(context).textTheme.bodyLarge?.color),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            offset: const Offset(0, 48),
            onSelected: (value) {
              if (value == 'settings') {
                context.push('/edit-profile');
              } else if (value == 'saved') {
                context.push('/saved');
              } else if (value == 'dark_mode') {
                ref.read(themeProvider.notifier).toggleTheme();
              } else if (value == 'logout') {
                _showLogoutConfirm();
              }
            },
            itemBuilder: (context) {
              final isDark = ref.read(themeProvider) == ThemeMode.dark;
              return [
                const PopupMenuItem(
                  value: 'settings',
                  child: Row(
                    children: [
                      Icon(Icons.settings_outlined, size: 20),
                      SizedBox(width: 12),
                      Text('Settings'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'saved',
                  child: Row(
                    children: [
                      Icon(Icons.bookmark_outline, size: 20),
                      SizedBox(width: 12),
                      Text('Saved'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'dark_mode',
                  child: Row(
                    children: [
                      Icon(
                        isDark ? Icons.dark_mode : Icons.light_mode,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      const Text('Dark Mode'),
                      const Spacer(),
                      Switch(
                        value: isDark,
                        activeColor: AppTheme.primaryColor,
                        onChanged: (value) {
                          ref.read(themeProvider.notifier).toggleTheme();
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 20, color: Colors.red),
                      SizedBox(width: 12),
                      Text('Log Out', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.primaryColor,
        onRefresh: _refresh,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              // -- Cover Image + Avatar --
              SliverToBoxAdapter(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Cover image
                    Container(
                      height: 180,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primaryColor.withOpacity(0.7),
                            Colors.black87,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: (user.coverImageUrl != null &&
                              user.coverImageUrl!.isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: user.coverImageUrl!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => const SizedBox(),
                              errorWidget: (_, __, ___) => const SizedBox(),
                            )
                          : null,
                    ),
                    // Avatar overlapping bottom of cover
                    Positioned(
                      bottom: -40,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Theme.of(context).scaffoldBackgroundColor,
                                width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 45,
                            backgroundColor: Theme.of(context).colorScheme.surface,
                            backgroundImage: user.profileImageUrl != null &&
                                    user.profileImageUrl!.isNotEmpty
                                ? CachedNetworkImageProvider(
                                    user.profileImageUrl!)
                                : null,
                            child: user.profileImageUrl == null ||
                                    user.profileImageUrl!.isEmpty
                                ? Text(
                                    user.name.isNotEmpty
                                        ? user.name[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w700,
                                      color: Theme.of(context).textTheme.bodyLarge?.color,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Spacer for overlapping avatar
              const SliverToBoxAdapter(child: SizedBox(height: 48)),

              // -- User Info --
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      Text(
                        user.name,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                      if (user.username != null && user.username!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '@${user.username}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        user.email,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                      if (user.bio != null && user.bio!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          user.bio!,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),

              // -- Action Buttons Row --
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => context.push('/create-post'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Create Post',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => context.push('/edit-profile'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(
                                color: Theme.of(context).dividerColor, width: 1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Edit Profile',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // -- Stats Card --
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color ??
                        Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).dividerColor.withOpacity(0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => _showFriendsList(context, friendState.friends),
                        child: _buildStat(
                          friendState.friends.length,
                          'Friends',
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 36,
                        color: Theme.of(context).dividerColor,
                      ),
                      _buildStat(_communityCount, 'Communities'),
                      Container(
                        width: 1,
                        height: 36,
                        color: Theme.of(context).dividerColor,
                      ),
                      _buildStat(_postCount, 'Posts'),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // -- Tab Bar --
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverTabBarDelegate(
                  TabBar(
                    controller: _tabController,
                    indicatorColor: Theme.of(context).textTheme.bodyLarge?.color,
                    indicatorWeight: 2,
                    labelColor: Theme.of(context).textTheme.bodyLarge?.color,
                    unselectedLabelColor: Theme.of(context).textTheme.bodySmall?.color,
                    tabs: const [
                      Tab(icon: Icon(Icons.grid_on)),
                      Tab(icon: Icon(Icons.people_outline)),
                    ],
                  ),
                ),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              // -- Posts Grid Tab --
              _buildPostsGrid(),
              // -- Communities Tab --
              _buildCommunitiesTab(),
            ],
          ),
        ),
      ),
    );
  }

  void _showFriendsList(BuildContext context, List<dynamic> friends) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (ctx, scrollController) {
            return Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Friends (${friends.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: friends.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 8),
                              Text('No friends yet', style: TextStyle(color: Colors.grey[500])),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: friends.length,
                          itemBuilder: (ctx, index) {
                            final friend = friends[index];
                            final name = friend.name ?? friend.toString();
                            final image = friend.profileImageUrl;
                            final userId = friend.id;

                            return ListTile(
                              leading: CircleAvatar(
                                radius: 22,
                                backgroundColor: Theme.of(context).colorScheme.surface,
                                backgroundImage: image != null && image.isNotEmpty
                                    ? CachedNetworkImageProvider(image)
                                    : null,
                                child: image == null || image.isEmpty
                                    ? Text(
                                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      )
                                    : null,
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: friend.username != null
                                  ? Text('@${friend.username}',
                                      style: TextStyle(fontSize: 13, color: Colors.grey[500]))
                                  : null,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.chat_bubble_outline, size: 20),
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      context.push('/chat/$userId?name=${Uri.encodeComponent(name)}');
                                    },
                                  ),
                                  const Icon(Icons.chevron_right, size: 20),
                                ],
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                context.push('/user/$userId');
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

  Widget _buildStat(int count, String label) {
    String formatted;
    if (count >= 1000000) {
      formatted = '${(count / 1000000).toStringAsFixed(1)}m';
    } else if (count >= 1000) {
      formatted = '${(count / 1000).toStringAsFixed(1)}k';
    } else {
      formatted = '$count';
    }

    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            formatted,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostsGrid() {
    if (_isLoadingPosts) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.camera_alt_outlined, size: 56,
                color: Theme.of(context).textTheme.bodySmall?.color),
            const SizedBox(height: 12),
            Text(
              'No posts yet',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.push('/create-post'),
              child: const Text('Create your first post'),
            ),
          ],
        ),
      );
    }

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(2),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final post = _posts[index];
                return GestureDetector(
                  onTap: () => context.push('/post/${post.id}'),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      post.imageUrl != null && post.imageUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: post.imageUrl!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: Colors.grey[200],
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: Colors.grey[200],
                                child: const Icon(Icons.broken_image_outlined),
                              ),
                            )
                          : Container(
                              color: Colors.grey[200],
                              padding: const EdgeInsets.all(8),
                              child: Center(
                                child: Text(
                                  post.caption,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ),
                      // Likes overlay
                      if (post.likesCount > 0)
                        Positioned(
                          bottom: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.favorite,
                                    size: 12, color: Colors.white),
                                const SizedBox(width: 3),
                                Text(
                                  '${post.likesCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
              childCount: _posts.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    ),
    );
  }

  Widget _buildCommunitiesTab() {
    if (_isLoadingCommunities) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_communities.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_outlined, size: 56,
                color: Theme.of(context).textTheme.bodySmall?.color),
            const SizedBox(height: 12),
            Text(
              'No communities joined yet',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.go('/explore'),
              child: const Text('Explore Communities'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _communities.length + 1, // +1 for logout button
      itemBuilder: (context, index) {
        if (index == _communities.length) {
          return const SizedBox(height: 80);
        }

        final c = _communities[index];
        final name = c['name'] ?? 'Unknown';
        final imageUrl = c['image_url'] ?? '';
        final category = c['category'] ?? '';
        final membersCount = c['members_count'] ?? 0;
        final communityId = c['id']?.toString() ?? '';

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color ??
                Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        width: 50,
                        height: 50,
                        color: Colors.grey[200],
                        child: const Icon(Icons.groups, color: Colors.grey),
                      ),
                    )
                  : Container(
                      width: 50,
                      height: 50,
                      color: AppTheme.primaryColor.withOpacity(0.2),
                      child: Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
            ),
            title: Text(
              name,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            subtitle: Row(
              children: [
                if (category.isNotEmpty) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      category,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  '$membersCount members',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
            trailing:
                const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () =>
                context.push('/community/$communityId/groups'),
          ),
        );
      },
    );
  }
}

// -- Sliver persistent header delegate for pinned TabBar --
class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;

  _SliverTabBarDelegate(this._tabBar);

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) => false;
}
