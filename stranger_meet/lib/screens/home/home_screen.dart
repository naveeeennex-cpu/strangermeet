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

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(postsProvider.notifier).fetchPosts(refresh: true);
      ref.read(storiesProvider.notifier).fetchStories();
      ref.read(friendProvider.notifier).fetchPendingRequests();
      ref.read(unreadCountProvider.notifier).fetchUnreadCount();
    });
    _scrollController.addListener(_onScroll);
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
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (pickedFile == null) return;

    final bytes = await pickedFile.readAsBytes();

    // Show caption dialog after picking image
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
                  const Text(
                    'Add Story',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  // Preview
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
                              'image': MultipartFile.fromBytes(
                                bytes,
                                filename: pickedFile.name,
                              ),
                              'caption': captionController.text.trim(),
                            });
                            await ApiService().uploadFile(
                              '/upload/story',
                              formData: formData,
                            );
                            // Refresh stories
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
        title: const Text(
          'StrangerMeet',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
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
      body: RefreshIndicator(
        color: AppTheme.primaryColor,
        onRefresh: () async {
          await Future.wait([
            ref.read(postsProvider.notifier).fetchPosts(refresh: true),
            ref.read(storiesProvider.notifier).fetchStories(),
          ]);
        },
        child: postsState.posts.isEmpty && postsState.isLoading
            ? const Center(child: CircularProgressIndicator())
            : postsState.posts.isEmpty
                ? ListView(
                    children: [
                      _StoriesRow(
                        storiesState: storiesState,
                        onAddStory: _createStoryWithUpload,
                      ),
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
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
                      ),
                    ],
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: postsState.posts.length +
                        1 +
                        (postsState.hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _StoriesRow(
                          storiesState: storiesState,
                          onAddStory: _createStoryWithUpload,
                        );
                      }
                      final postIndex = index - 1;
                      if (postIndex == postsState.posts.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final post = postsState.posts[postIndex];
                      return _PostCard(post: post);
                    },
                  ),
      ),
    );
  }
}

class _StoriesRow extends ConsumerWidget {
  final StoriesState storiesState;
  final VoidCallback onAddStory;

  const _StoriesRow({
    required this.storiesState,
    required this.onAddStory,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);

    return Container(
      height: 110,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!, width: 0.5),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          // Your Story
          _StoryCircle(
            imageUrl: currentUser?.profileImageUrl,
            label: 'Your Story',
            isAddStory: true,
            onTap: onAddStory,
          ),
          // Other users' stories
          ...storiesState.userStories.map((userStory) {
            return _StoryCircle(
              imageUrl: userStory.userImage,
              label: userStory.userName,
              hasUnviewed: userStory.hasUnviewed,
              onTap: () {
                context.push('/story/${userStory.userId}');
              },
            );
          }),
        ],
      ),
    );
  }
}

class _StoryCircle extends StatelessWidget {
  final String? imageUrl;
  final String label;
  final bool isAddStory;
  final bool hasUnviewed;
  final VoidCallback onTap;

  const _StoryCircle({
    this.imageUrl,
    required this.label,
    this.isAddStory = false,
    this.hasUnviewed = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
                    : !hasUnviewed
                        ? Border.all(color: Colors.grey[300]!, width: 2)
                        : null,
              ),
              padding: isAddStory
                  ? EdgeInsets.zero
                  : const EdgeInsets.all(2.5),
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: isAddStory
                          ? Border.all(color: Colors.grey[300]!, width: 1)
                          : null,
                    ),
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: AppTheme.surfaceColor,
                      backgroundImage: imageUrl != null &&
                              imageUrl!.isNotEmpty
                          ? CachedNetworkImageProvider(imageUrl!)
                          : null,
                      child: imageUrl == null || imageUrl!.isEmpty
                          ? Icon(
                              isAddStory
                                  ? Icons.camera_alt_outlined
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
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.add,
                          size: 14,
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

class _PostCard extends ConsumerWidget {
  final dynamic post;

  const _PostCard({required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  GestureDetector(
                    onTap: () => context.push('/user/${post.userId}'),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
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
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Column(
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
                      ],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.more_horiz, size: 20),
                    onPressed: () {
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
                                width: 40, height: 4,
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
                                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                                  title: const Text('Delete Post', style: TextStyle(color: Colors.red)),
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
                    },
                  ),
                ],
              ),
            ),
            // Image
            if (post.imageUrl != null)
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
            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      post.isLiked ? Icons.favorite : Icons.favorite_border,
                      color: post.isLiked ? Colors.red : null,
                    ),
                    onPressed: () {
                      ref.read(postsProvider.notifier).toggleLike(post.id);
                    },
                  ),
                  Text(
                    '${post.likesCount}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_outline),
                    onPressed: () => context.push('/post/${post.id}'),
                  ),
                  Text(
                    '${post.commentsCount}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.share_outlined),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditPostDialog(BuildContext context, WidgetRef ref, dynamic post) {
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

  void _showDeleteConfirm(BuildContext context, WidgetRef ref, String postId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Post'),
        content: const Text('Are you sure you want to delete this post? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(postsProvider.notifier).deletePost(postId);
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
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
