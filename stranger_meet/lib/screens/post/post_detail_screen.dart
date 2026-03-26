import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../config/theme.dart';
import '../../models/post.dart';
import '../../providers/post_provider.dart';

class PostDetailScreen extends ConsumerStatefulWidget {
  final String postId;

  const PostDetailScreen({super.key, required this.postId});

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _commentController = TextEditingController();
  final _commentFocusNode = FocusNode();
  List<Comment> _comments = [];
  bool _isLoadingComments = true;

  // Reply state
  String? _replyingToCommentId;
  String? _replyingToUserName;

  // Expanded replies per comment
  final Map<String, List<CommentReply>> _repliesMap = {};
  final Set<String> _expandedReplies = {};
  final Set<String> _loadingReplies = {};

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final comments = await ref
          .read(postsProvider.notifier)
          .fetchComments(widget.postId);
      if (mounted) {
        setState(() {
          _comments = comments;
          _isLoadingComments = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingComments = false);
      }
    }
  }

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    try {
      if (_replyingToCommentId != null) {
        // Send reply
        final reply = await ref.read(postsProvider.notifier).replyToComment(
          widget.postId,
          _replyingToCommentId!,
          text,
        );
        setState(() {
          // Update replies count on the comment
          final idx = _comments.indexWhere((c) => c.id == _replyingToCommentId);
          if (idx != -1) {
            _comments[idx] = _comments[idx].copyWith(
              repliesCount: _comments[idx].repliesCount + 1,
            );
          }
          // Add to local replies map if expanded
          if (_repliesMap.containsKey(_replyingToCommentId)) {
            _repliesMap[_replyingToCommentId]!.add(reply);
          }
          _cancelReply();
        });
      } else {
        // Send comment
        final comment = await ref
            .read(postsProvider.notifier)
            .addComment(widget.postId, text);
        setState(() {
          _comments.insert(0, comment);
        });
      }
      _commentController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  void _startReply(String commentId, String userName) {
    setState(() {
      _replyingToCommentId = commentId;
      _replyingToUserName = userName;
    });
    _commentController.text = '@$userName ';
    _commentFocusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyingToCommentId = null;
      _replyingToUserName = null;
    });
    _commentController.clear();
  }

  Future<void> _toggleCommentLike(int index) async {
    final comment = _comments[index];
    // Optimistic update
    setState(() {
      _comments[index] = comment.copyWith(
        isLiked: !comment.isLiked,
        likesCount: comment.isLiked
            ? comment.likesCount - 1
            : comment.likesCount + 1,
      );
    });

    try {
      await ref
          .read(postsProvider.notifier)
          .toggleCommentLike(widget.postId, comment.id);
    } catch (e) {
      // Revert on failure
      if (mounted) {
        setState(() {
          _comments[index] = comment;
        });
      }
    }
  }

  Future<void> _loadReplies(String commentId) async {
    if (_loadingReplies.contains(commentId)) return;

    setState(() {
      _loadingReplies.add(commentId);
      _expandedReplies.add(commentId);
    });

    try {
      final replies = await ref
          .read(postsProvider.notifier)
          .fetchCommentReplies(widget.postId, commentId);
      if (mounted) {
        setState(() {
          _repliesMap[commentId] = replies;
          _loadingReplies.remove(commentId);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingReplies.remove(commentId);
          _expandedReplies.remove(commentId);
        });
      }
    }
  }

  void _collapseReplies(String commentId) {
    setState(() {
      _expandedReplies.remove(commentId);
    });
  }

  Widget _buildAvatar(String? imageUrl, String name, {double radius = 16}) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppTheme.surfaceColor,
      backgroundImage:
          imageUrl != null && imageUrl.isNotEmpty
              ? CachedNetworkImageProvider(imageUrl)
              : null,
      child: imageUrl == null || imageUrl.isEmpty
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: radius * 0.75,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }

  Widget _buildCommentItem(Comment comment, int index) {
    final isExpanded = _expandedReplies.contains(comment.id);
    final isLoadingReply = _loadingReplies.contains(comment.id);
    final replies = _repliesMap[comment.id] ?? [];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAvatar(comment.userProfileImage, comment.userName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Username + comment text inline
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 14,
                          height: 1.4,
                        ),
                        children: [
                          TextSpan(
                            text: comment.userName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const TextSpan(text: '  '),
                          TextSpan(text: comment.text),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Time ago | Like button with count | Reply
                    Row(
                      children: [
                        if (comment.createdAt != null)
                          Text(
                            timeago.format(comment.createdAt!),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () => _toggleCommentLike(index),
                          child: Row(
                            children: [
                              Icon(
                                comment.isLiked
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                size: 14,
                                color:
                                    comment.isLiked ? Colors.red : Colors.grey[500],
                              ),
                              if (comment.likesCount > 0) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '${comment.likesCount}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () =>
                              _startReply(comment.id, comment.userName),
                          child: Text(
                            'Reply',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // View replies expandable
                    if (comment.repliesCount > 0 && !isExpanded)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: GestureDetector(
                          onTap: () => _loadReplies(comment.id),
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 1,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'View ${comment.repliesCount} ${comment.repliesCount == 1 ? 'reply' : 'replies'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // Expanded replies
                    if (isExpanded) ...[
                      if (isLoadingReply)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else ...[
                        const SizedBox(height: 8),
                        ...replies.map((reply) => _buildReplyItem(reply)),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: GestureDetector(
                            onTap: () => _collapseReplies(comment.id),
                            child: Row(
                              children: [
                                Container(
                                  width: 24,
                                  height: 1,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Hide replies',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReplyItem(CommentReply reply) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(reply.userProfileImage, reply.userName, radius: 12),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 13,
                      height: 1.4,
                    ),
                    children: [
                      TextSpan(
                        text: reply.userName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const TextSpan(text: '  '),
                      TextSpan(text: reply.text),
                    ],
                  ),
                ),
                if (reply.createdAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      timeago.format(reply.createdAt!),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final postsState = ref.watch(postsProvider);
    final post = postsState.posts
        .cast<Post?>()
        .firstWhere((p) => p?.id == widget.postId, orElse: () => null);

    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: post == null
          ? const Center(child: Text('Post not found'))
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Post header
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              _buildAvatar(
                                  post.userImage, post.userName,
                                  radius: 20),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    post.userName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
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
                        // Image
                        if (post.imageUrl != null)
                          CachedNetworkImage(
                            imageUrl: post.imageUrl!,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        // Caption
                        if (post.caption.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              post.caption,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                        // Like row
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  post.isLiked
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: post.isLiked ? Colors.red : null,
                                ),
                                onPressed: () => ref
                                    .read(postsProvider.notifier)
                                    .toggleLike(post.id),
                              ),
                              Text(
                                '${post.likesCount} likes',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(),
                        // Comments
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Text(
                            'Comments (${_comments.length})',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_isLoadingComments)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (_comments.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Text(
                                'No comments yet. Be the first!',
                                style:
                                    TextStyle(color: Colors.grey[500]),
                              ),
                            ),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _comments.length,
                            itemBuilder: (context, index) {
                              return _buildCommentItem(
                                  _comments[index], index);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                // Comment input
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Replying indicator
                    if (_replyingToCommentId != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        color: Colors.grey[100],
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Replying to @$_replyingToUserName',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: _cancelReply,
                              child: Icon(
                                Icons.close,
                                size: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          top: BorderSide(color: Colors.grey[200]!),
                        ),
                      ),
                      child: SafeArea(
                        child: Row(
                          children: [
                            _buildAvatar(
                                post.userImage, post.userName,
                                radius: 16),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _commentController,
                                focusNode: _commentFocusNode,
                                decoration: InputDecoration(
                                  hintText: _replyingToCommentId != null
                                      ? 'Reply...'
                                      : 'Add a comment...',
                                  border: InputBorder.none,
                                  filled: false,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 12),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.send),
                              color: AppTheme.primaryColor,
                              onPressed: _addComment,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
