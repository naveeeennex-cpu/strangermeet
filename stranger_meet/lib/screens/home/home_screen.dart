import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../config/theme.dart';
import '../../providers/post_provider.dart';
import '../../providers/story_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friend_provider.dart';
import '../../providers/chat_provider.dart';
import '../../models/story.dart';
import '../../services/api_service.dart';
import '../../widgets/video_player_widget.dart';
import '../../widgets/auto_play_video_widget.dart';
import '../../widgets/share_bottom_sheet.dart';
import 'story_camera_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scrollController = ScrollController();
  int _selectedSubTab = 0; // 0 = Posts, 1 = Reels
  final Set<String> _sentRequests = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(postsProvider.notifier).fetchPosts(refresh: true);
      ref.read(storiesProvider.notifier).fetchStories();
      ref.read(friendProvider.notifier).fetchFriends();
      ref.read(friendProvider.notifier).fetchPendingRequests();
      ref.read(friendProvider.notifier).fetchSentRequests();
      ref.read(unreadCountProvider.notifier).fetchUnreadCount();
    });
    _scrollController.addListener(_onScroll);
    _loadSentRequests();
  }

  Future<void> _loadSentRequests() async {
    try {
      final response = await ApiService().get('/friends/sent');
      final data = response.data;
      final List<dynamic> results = data is List ? data : (data['results'] ?? []);
      if (mounted) {
        setState(() {
          for (final r in results) {
            final addresseeId = r['addressee_id']?.toString() ?? r['user_id']?.toString() ?? '';
            if (addresseeId.isNotEmpty) {
              _sentRequests.add(addresseeId);
            }
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(postsProvider.notifier).fetchPosts();
    }
  }

  Future<void> _createStoryWithUpload() async {
    if (!mounted) return;

    // Show picker choice: Photo or Video
    final mediaChoice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Add Story',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo'),
              onTap: () => Navigator.pop(ctx, 'image'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video'),
              onTap: () => Navigator.pop(ctx, 'video'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
      ),
    );

    if (mediaChoice == null || !mounted) return;

    final picker = ImagePicker();
    XFile? pickedFile;

    if (mediaChoice == 'video') {
      pickedFile = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 30),
      );
    } else {
      pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        maxHeight: 1920,
        imageQuality: 85,
      );
    }
    if (pickedFile == null) return;

    final bytes = await pickedFile.readAsBytes();

    if (!mounted) return;
    final captionController = TextEditingController();
    bool isUploading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mediaChoice == 'video' ? 'Add Video Story' : 'Add Story',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  if (mediaChoice == 'video')
                    Container(
                      width: double.infinity,
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.videocam, color: Colors.white54, size: 48),
                            SizedBox(height: 8),
                            Text('Video selected',
                                style: TextStyle(color: Colors.white54)),
                          ],
                        ),
                      ),
                    )
                  else
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        bytes,
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: captionController,
                    decoration: const InputDecoration(
                      hintText: 'Caption (optional)',
                      prefixIcon: Icon(Icons.text_fields),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (isUploading)
                    const Center(child: CircularProgressIndicator())
                  else
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          setModalState(() => isUploading = true);
                          try {
                            final formData = FormData.fromMap({
                              if (mediaChoice == 'video')
                                'video': MultipartFile.fromBytes(
                                  bytes,
                                  filename: pickedFile!.name,
                                )
                              else
                                'image': MultipartFile.fromBytes(
                                  bytes,
                                  filename: pickedFile!.name,
                                ),
                              'caption': captionController.text.trim(),
                              'media_type': mediaChoice,
                            });
                            await ApiService().uploadFile(
                              '/upload/story',
                              formData: formData,
                            );
                            ref.read(storiesProvider.notifier).fetchStories();
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Story shared!')),
                              );
                            }
                          } catch (e) {
                            setModalState(() => isUploading = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Failed: $e')),
                              );
                            }
                          }
                        },
                        child: const Text('Share Story'),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final postsState = ref.watch(postsProvider);
    final storiesState = ref.watch(storiesProvider);
    final friendState = ref.watch(friendProvider);
    final unreadMessages = ref.watch(unreadCountProvider);
    final pendingCount = friendState.pendingRequests.length + unreadMessages;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Text(
          'StrangerMeet',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 22,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.search,
                color: Theme.of(context).textTheme.bodyLarge?.color),
            onPressed: () => context.push('/explore'),
          ),
          Stack(
            children: [
              IconButton(
                icon: Icon(Icons.notifications_outlined,
                    color: Theme.of(context).textTheme.bodyLarge?.color),
                onPressed: () => context.push('/notifications'),
              ),
              if (pendingCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      '$pendingCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primaryColor,
        onPressed: () => context.push('/create-post'),
        child: const Icon(Icons.add, color: Colors.black, size: 28),
      ),
      body: RefreshIndicator(
        color: AppTheme.primaryColor,
        onRefresh: () async {
          await Future.wait([
            ref.read(postsProvider.notifier).fetchPosts(refresh: true),
            ref.read(storiesProvider.notifier).fetchStories(),
          ]);
        },
        child: GestureDetector(
          onHorizontalDragEnd: (details) {
            // Left swipe (negative velocity = swipe left)
            if (details.primaryVelocity != null &&
                details.primaryVelocity! < -300) {
              Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const StoryCameraScreen(),
                  transitionsBuilder: (_, animation, __, child) {
                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(1.0, 0.0),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOut,
                      )),
                      child: child,
                    );
                  },
                ),
              );
            }
          },
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // "For you" | "Discover" toggle
              SliverToBoxAdapter(child: _buildForYouDiscoverToggle()),

              // Stories Row
              SliverToBoxAdapter(
                child: _StoriesRow(
                  storiesState: storiesState,
                  onAddStory: _createStoryWithUpload,
                ),
              ),

              // "Posts" | "Reels" sub-tabs
              SliverToBoxAdapter(child: _buildPostsReelsTabs()),

              // Content area
              if (_selectedSubTab == 0) ...[
                // Posts feed
                _buildPostsFeed(postsState),
              ] else ...[
                // Reels grid
                SliverToBoxAdapter(child: _buildReelsGrid()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForYouDiscoverToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              // Already on "For you"
            },
            child: Column(
              children: [
                Text(
                  'For you',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 2.5,
                  width: 50,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          GestureDetector(
            onTap: () {
              context.push('/communities');
            },
            child: Column(
              children: [
                Text(
                  'Discover',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 2.5,
                  width: 50,
                  color: Colors.transparent,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostsReelsTabs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (_selectedSubTab != 0) {
                setState(() => _selectedSubTab = 0);
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Text(
                    'Posts',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: _selectedSubTab == 0
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: _selectedSubTab == 0
                          ? Theme.of(context).textTheme.bodyLarge?.color
                          : Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 2.5,
                    width: 40,
                    decoration: BoxDecoration(
                      color: _selectedSubTab == 0
                          ? AppTheme.primaryColor
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
          GestureDetector(
            onTap: () {
              if (_selectedSubTab != 1) {
                setState(() => _selectedSubTab = 1);
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Text(
                    'Reels',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: _selectedSubTab == 1
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: _selectedSubTab == 1
                          ? Theme.of(context).textTheme.bodyLarge?.color
                          : Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 2.5,
                    width: 40,
                    decoration: BoxDecoration(
                      color: _selectedSubTab == 1
                          ? AppTheme.primaryColor
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
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

  Widget _buildPostsFeed(dynamic postsState) {
    if (postsState.posts.isEmpty && postsState.isLoading) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (postsState.posts.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.photo_library_outlined,
                  size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No posts yet',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Be the first to share something!',
                style: TextStyle(color: Colors.grey[400]),
              ),
            ],
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == postsState.posts.length) {
            if (postsState.hasMore) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return const SizedBox.shrink();
          }
          final post = postsState.posts[index];
          final friendIds = ref.watch(friendProvider).friends
              .map((f) => f.id)
              .toSet();
          return _PostCard(
            post: post,
            sentRequests: _sentRequests,
            friendIds: friendIds,
            onSendRequest: (userId) {
              setState(() => _sentRequests.add(userId));
              ref.read(friendProvider.notifier).sendRequest(userId);
            },
          );
        },
        childCount:
            postsState.posts.length + (postsState.hasMore ? 1 : 0),
      ),
    );
  }

  Widget _buildReelsGrid() {
    final postsState = ref.watch(postsProvider);
    final videoPosts = postsState.posts
        .where((p) => p.mediaType == 'video' && p.videoUrl != null && p.videoUrl!.isNotEmpty)
        .toList();

    if (videoPosts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.videocam_off_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No reels yet',
                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Text(
                'Be the first to share a video!',
                style: TextStyle(color: Colors.grey[400]),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.65,
        ),
        itemCount: videoPosts.length,
        itemBuilder: (context, index) {
          final post = videoPosts[index];
          return GestureDetector(
            onTap: () => context.push('/video-post/${post.id}'),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                children: [
                  // Thumbnail or gradient background
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: post.imageUrl != null && post.imageUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: post.imageUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.grey[300]!, Colors.grey[400]!],
                                  ),
                                ),
                                child: Icon(Icons.videocam_outlined,
                                    size: 48, color: Colors.grey[500]),
                              ),
                            )
                          : Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.grey[300]!, Colors.grey[400]!],
                                ),
                              ),
                              child: Icon(Icons.videocam_outlined,
                                  size: 48, color: Colors.grey[500]),
                            ),
                    ),
                  ),
                  // Play icon overlay
                  Center(
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                  // Caption + likes at bottom
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(12)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.7),
                          ],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (post.caption.isNotEmpty)
                            Text(
                              post.caption,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.favorite,
                                  color: Colors.white, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                '${post.likesCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Stories Row ──────────────────────────────────────────────────────────────

class _StoriesRow extends ConsumerStatefulWidget {
  final StoriesState storiesState;
  final VoidCallback onAddStory;

  const _StoriesRow({
    required this.storiesState,
    required this.onAddStory,
  });

  @override
  ConsumerState<_StoriesRow> createState() => _StoriesRowState();
}

class _StoriesRowState extends ConsumerState<_StoriesRow> {
  List<Map<String, dynamic>> _joinedCommunities = [];
  bool _communitiesLoaded = false;

  @override
  void initState() {
    super.initState();
    _fetchJoinedCommunities();
  }

  Future<void> _fetchJoinedCommunities() async {
    try {
      final response = await ApiService().get('/communities/joined');
      final data = response.data;
      final List<dynamic> results =
          data is List ? data : (data['results'] ?? data['communities'] ?? []);
      if (mounted) {
        setState(() {
          _joinedCommunities = results
              .map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{})
              .toList();
          _communitiesLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _communitiesLoaded = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);

    return Container(
      height: 110,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          // Your Story — check if current user has an active story
          if (currentUser != null &&
              widget.storiesState.userStories
                  .any((s) => s.userId == currentUser.id))
            _StoryCircle(
              imageUrl: currentUser.profileImageUrl,
              label: 'Your Story',
              hasUnviewed: false, // Own story always "viewed"
              hasOwnStory: true,
              onTap: () => context.push('/story/${currentUser.id}'),
              onLongPress: widget.onAddStory,
            )
          else
            _StoryCircle(
              imageUrl: currentUser?.profileImageUrl,
              label: 'Your Story',
              isAddStory: true,
              onTap: widget.onAddStory,
            ),
          // Friend stories (exclude current user's stories since shown above)
          ...widget.storiesState.userStories
              .where((userStory) => userStory.userId != currentUser?.id)
              .map((userStory) {
            return _StoryCircle(
              imageUrl: userStory.userImage,
              label: userStory.userName,
              hasUnviewed: userStory.hasUnviewed,
              onTap: () {
                context.push('/story/${userStory.userId}');
              },
            );
          }),
          // Community stories
          if (_communitiesLoaded)
            ..._joinedCommunities.map((community) {
              final id = community['id']?.toString() ??
                  community['_id']?.toString() ??
                  '';
              final name = community['name'] ?? 'Community';
              final image = community['image_url'] ??
                  community['imageUrl'] ??
                  community['image'];
              return _StoryCircle(
                imageUrl: image,
                label: name,
                isCommunity: true,
                onTap: () {
                  context.push('/community/$id');
                },
              );
            }),
        ],
      ),
    );
  }
}

// ── Story Circle ────────────────────────────────────────────────────────────

class _StoryCircle extends StatelessWidget {
  final String? imageUrl;
  final String label;
  final bool isAddStory;
  final bool hasUnviewed;
  final bool isCommunity;
  final bool hasOwnStory;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _StoryCircle({
    this.imageUrl,
    required this.label,
    this.isAddStory = false,
    this.hasUnviewed = false,
    this.isCommunity = false,
    this.hasOwnStory = false,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 72,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isAddStory
                    ? null
                    : hasOwnStory
                        ? const LinearGradient(
                            colors: [
                              Color(0xFF9E9E9E),
                              Color(0xFF616161),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : hasUnviewed
                            ? const LinearGradient(
                                colors: [
                                  AppTheme.primaryColor,
                                  Color(0xFF8BC34A),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                border: isAddStory
                    ? null
                    : (!hasUnviewed && !hasOwnStory)
                        ? Border.all(color: Theme.of(context).dividerColor, width: 2)
                        : null,
              ),
              padding:
                  isAddStory ? EdgeInsets.zero : const EdgeInsets.all(2.5),
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: isAddStory
                          ? Border.all(color: Theme.of(context).dividerColor, width: 1)
                          : null,
                    ),
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      backgroundImage:
                          imageUrl != null && imageUrl!.isNotEmpty
                              ? CachedNetworkImageProvider(imageUrl!)
                              : null,
                      child: imageUrl == null || imageUrl!.isEmpty
                          ? Icon(
                              isAddStory
                                  ? Icons.camera_alt_outlined
                                  : isCommunity
                                      ? Icons.groups
                                      : Icons.person,
                              color: Colors.grey[500],
                              size: 24,
                            )
                          : null,
                    ),
                  ),
                  if (isAddStory)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 2),
                        ),
                        child: const Icon(
                          Icons.add,
                          size: 14,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  // Own story "+" badge at bottom-left
                  if (hasOwnStory)
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: onLongPress, // tapping "+" adds more stories
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Theme.of(context).scaffoldBackgroundColor,
                                width: 2),
                          ),
                          child: const Icon(
                            Icons.add,
                            size: 12,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  // Community badge
                  if (isCommunity && !isAddStory)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 2),
                        ),
                        child: const Icon(
                          Icons.groups,
                          size: 11,
                          color: Colors.black,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Post Card ───────────────────────────────────────────────────────────────

class _PostCard extends ConsumerStatefulWidget {
  final dynamic post;
  final Set<String> sentRequests;
  final Set<String> friendIds;
  final Function(String) onSendRequest;

  const _PostCard({
    required this.post,
    required this.sentRequests,
    required this.friendIds,
    required this.onSendRequest,
  });

  @override
  ConsumerState<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<_PostCard>
    with SingleTickerProviderStateMixin {
  bool _showHeart = false;
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _checkIfSaved();
  }

  Future<void> _checkIfSaved() async {
    try {
      final res = await ApiService().get('/bookings/saved/check/${widget.post.id}');
      if (mounted) setState(() => _isSaved = res.data['is_saved'] == true);
    } catch (_) {}
  }

  Future<void> _toggleSave() async {
    final postId = widget.post.id;
    final wasSaved = _isSaved;
    setState(() => _isSaved = !wasSaved);
    try {
      if (wasSaved) {
        await ApiService().delete('/bookings/saved/$postId');
      } else {
        await ApiService().post('/bookings/saved', data: {
          'item_id': postId,
          'item_type': 'post',
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSaved = wasSaved);
    }
  }

  void _onDoubleTap() {
    final post = widget.post;
    if (!post.isLiked) {
      ref.read(postsProvider.notifier).toggleLike(post.id);
    }
    setState(() => _showHeart = true);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showHeart = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final currentUser = ref.watch(currentUserProvider);
    final isOwnPost = currentUser?.id == post.userId;
    final isFriend = widget.friendIds.contains(post.userId);
    final hasRequested = widget.sentRequests.contains(post.userId);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 0.5),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: InkWell(
        onTap: () {
          if (post.mediaType == 'video' && post.videoUrl != null) {
            context.push('/video-post/${post.id}');
          } else {
            context.push('/post/${post.id}');
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  // Avatar — own post goes to profile, others go to user profile
                  GestureDetector(
                    onTap: () {
                      if (isOwnPost) {
                        context.go('/profile');
                      } else {
                        context.push('/user/${post.userId}');
                      }
                    },
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      backgroundImage: post.userImage != null
                          ? CachedNetworkImageProvider(post.userImage!)
                          : null,
                      child: post.userImage == null
                          ? Text(
                              post.userName.isNotEmpty
                                  ? post.userName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).textTheme.bodyLarge?.color,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Name + community + time
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (isOwnPost) {
                          context.go('/profile');
                        } else {
                          context.push('/user/${post.userId}');
                        }
                      },
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              post.userName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '  \u00b7  in ',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                          Text(
                            'StrangerMeet',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                          if (post.createdAt != null) ...[
                            Text(
                              '  \u00b7  ',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                            Text(
                              timeago.format(post.createdAt!,
                                  locale: 'en_short'),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Connect/Friends button — only for others' posts
                  if (!isOwnPost)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: isFriend
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: AppTheme.primaryColor.withOpacity(0.15),
                                border: Border.all(color: AppTheme.primaryColor.withOpacity(0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle, size: 12, color: AppTheme.primaryColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Friends',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : hasRequested
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.grey[400]!),
                                  ),
                                  child: Text(
                                    'Requested',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                )
                              : GestureDetector(
                                  onTap: () => widget.onSendRequest(post.userId),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                          color: AppTheme.primaryColor,
                                          width: 1.5),
                                    ),
                                    child: Text(
                                      'Connect',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Theme.of(context).textTheme.bodyLarge?.color,
                                      ),
                                    ),
                                  ),
                                ),
                    ),
                  // More options
                  IconButton(
                    icon: const Icon(Icons.more_horiz, size: 20),
                    onPressed: () {
                      _showOptionsSheet(context, ref);
                    },
                  ),
                ],
              ),
            ),

            // Caption (before image)
            if (post.caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  post.caption,
                  style: const TextStyle(fontSize: 14),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            // Media: Video or Image with double-tap like
            if (post.mediaType == 'video' &&
                post.videoUrl != null &&
                post.videoUrl!.isNotEmpty)
              GestureDetector(
                onDoubleTap: _onDoubleTap,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AutoPlayVideoWidget(
                      videoUrl: post.videoUrl!,
                      onTap: () {
                        context.push('/video-post/${post.id}');
                      },
                    ),
                    // Heart animation overlay
                    AnimatedOpacity(
                      opacity: _showHeart ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: AnimatedScale(
                        scale: _showHeart ? 1.0 : 0.5,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.elasticOut,
                        child: const Icon(
                          Icons.favorite,
                          color: Colors.white,
                          size: 80,
                          shadows: [
                            Shadow(
                              color: Colors.black38,
                              blurRadius: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (post.imageUrl != null && post.imageUrl!.isNotEmpty)
              GestureDetector(
                onDoubleTap: _onDoubleTap,
                onTap: () => context.push('/post/${post.id}'),
                onLongPress: () {
                  // Open full-screen image viewer on long press
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      opaque: false,
                      barrierColor: Colors.black87,
                      pageBuilder: (context, _, __) => _FullScreenImageViewer(
                        imageUrl: post.imageUrl!,
                      ),
                    ),
                  );
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    InteractiveViewer(
                      minScale: 1.0,
                      maxScale: 3.0,
                      child: CachedNetworkImage(
                        imageUrl: post.imageUrl!,
                        width: double.infinity,
                        height: 300,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          height: 300,
                          color: Theme.of(context).colorScheme.surface,
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                        errorWidget: (context, url, error) => Container(
                          height: 300,
                          color: Theme.of(context).colorScheme.surface,
                          child:
                              const Icon(Icons.broken_image_outlined, size: 48),
                        ),
                      ),
                    ),
                    // Heart animation overlay
                    AnimatedOpacity(
                      opacity: _showHeart ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: AnimatedScale(
                        scale: _showHeart ? 1.0 : 0.5,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.elasticOut,
                        child: const Icon(
                          Icons.favorite,
                          color: Colors.white,
                          size: 80,
                          shadows: [
                            Shadow(
                              color: Colors.black38,
                              blurRadius: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Actions row
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: [
                  // Like
                  GestureDetector(
                    onTap: () {
                      ref
                          .read(postsProvider.notifier)
                          .toggleLike(post.id);
                    },
                    child: Row(
                      children: [
                        Icon(
                          post.isLiked
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: post.isLiked ? Colors.red : Colors.grey[600],
                          size: 22,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${post.likesCount}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  // React
                  GestureDetector(
                    onTap: () {
                      // MVP: no functionality
                    },
                    child: Row(
                      children: [
                        Icon(Icons.emoji_emotions_outlined,
                            size: 21, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          'React',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  // Comment
                  GestureDetector(
                    onTap: () {
                      if (post.mediaType == 'video' && post.videoUrl != null) {
                        context.push('/video-post/${post.id}');
                      } else {
                        context.push('/post/${post.id}');
                      }
                    },
                    child: Row(
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 20, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          '${post.commentsCount}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Share
                  GestureDetector(
                    onTap: () {
                      ShareBottomSheet.show(
                        context,
                        postId: post.id,
                        postImageUrl: post.imageUrl,
                        postCaption: post.caption,
                        postUserName: post.userName,
                        mediaType: post.mediaType,
                      );
                    },
                    child: Row(
                      children: [
                        Icon(Icons.share_outlined,
                            size: 20, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          'Share',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Bookmark / Save
                  GestureDetector(
                    onTap: _toggleSave,
                    child: Icon(
                      _isSaved ? Icons.bookmark : Icons.bookmark_border,
                      size: 22,
                      color: _isSaved ? AppTheme.primaryColor : Colors.grey[600],
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

  void _showOptionsSheet(BuildContext context, WidgetRef ref) {
    final post = widget.post;
    final currentUser = ref.read(currentUserProvider);
    final isOwner = currentUser?.id == post.userId;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            if (isOwner) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit Post'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditPostDialog(context, ref, post);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete Post',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showDeleteConfirm(context, ref, post.id);
                },
              ),
            ] else ...[
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Report Post'),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Post reported')),
                  );
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showEditPostDialog(
      BuildContext context, WidgetRef ref, dynamic post) {
    final controller = TextEditingController(text: post.caption);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Post'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Edit caption...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newCaption = controller.text.trim();
              if (newCaption.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await ref.read(postsProvider.notifier).editPost(
                      post.id,
                      caption: newCaption,
                    );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Post updated!')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: $e')),
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

  void _showDeleteConfirm(
      BuildContext context, WidgetRef ref, String postId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Post'),
        content: const Text(
            'Are you sure you want to delete this post? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(postsProvider.notifier)
                    .deletePost(postId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Post deleted')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: $e')),
                  );
                }
              }
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ── Full Screen Image Viewer with Pinch-to-Zoom ──────────────────────────────

class _FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;

  const _FullScreenImageViewer({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null &&
              details.primaryVelocity!.abs() > 300) {
            Navigator.of(context).pop();
          }
        },
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  errorWidget: (context, url, error) => const Center(
                    child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
                  ),
                ),
              ),
            ),
            // Close button
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              right: 16,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
