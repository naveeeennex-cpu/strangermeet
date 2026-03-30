import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../models/community.dart';
import '../../services/api_service.dart';

class CommunityGroupsScreen extends ConsumerStatefulWidget {
  final String communityId;

  const CommunityGroupsScreen({super.key, required this.communityId});

  @override
  ConsumerState<CommunityGroupsScreen> createState() =>
      _CommunityGroupsScreenState();
}

class _CommunityGroupsScreenState
    extends ConsumerState<CommunityGroupsScreen> {
  final ApiService _api = ApiService();

  Community? _community;
  List<SubGroup> _joinedGroups = [];
  List<SubGroup> _availableGroups = [];
  CommunityMessage? _lastCommunityMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _fetchCommunity(),
      _fetchGroups(),
      _fetchLastMessage(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchCommunity() async {
    try {
      final response = await _api.get('/communities/${widget.communityId}');
      if (mounted) {
        setState(() {
          _community = Community.fromJson(response.data);
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchGroups() async {
    try {
      final response =
          await _api.get('/communities/${widget.communityId}/groups');
      final data = response.data;
      final List<dynamic> results =
          data is List ? data : (data['results'] ?? data['groups'] ?? []);
      final groups = results.map((e) => SubGroup.fromJson(e)).toList();
      if (mounted) {
        setState(() {
          _joinedGroups = groups.where((g) => g.isMember).toList();
          _availableGroups = groups.where((g) => !g.isMember && !g.isPending).toList();
          // Add pending groups to a separate area or show in available with badge
          final pendingGroups = groups.where((g) => g.isPending).toList();
          _availableGroups = [...pendingGroups, ..._availableGroups];
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchLastMessage() async {
    try {
      final response = await _api.get(
        '/communities/${widget.communityId}/messages',
        queryParameters: {'limit': 1},
      );
      final data = response.data;
      final List<dynamic> results =
          data is List ? data : (data['results'] ?? data['messages'] ?? []);
      if (results.isNotEmpty && mounted) {
        setState(() {
          _lastCommunityMessage = CommunityMessage.fromJson(results.last);
        });
      }
    } catch (_) {}
  }

  Future<void> _joinAndOpenGroup(SubGroup group) async {
    try {
      await _api.post(
        '/communities/${widget.communityId}/groups/${group.id}/join',
      );
      if (mounted) {
        context.push(
            '/community/${widget.communityId}/group/${group.id}');
        // Refresh groups in background
        _fetchGroups();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to join group: $e')),
        );
      }
    }
  }

  void _leaveCommunity() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Community'),
        content:
            const Text('Are you sure you want to leave this community?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Leave',
                style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _api.post('/communities/${widget.communityId}/leave');
        if (mounted) context.pop();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to leave: $e')),
          );
        }
      }
    }
  }

  String _timeAgo(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}';
  }

  IconData _groupTypeIcon(String type) {
    switch (type) {
      case 'trip':
        return Icons.hiking;
      case 'meetup':
        return Icons.people;
      case 'gym':
        return Icons.fitness_center;
      case 'online_meet':
        return Icons.videocam;
      default:
        return Icons.group;
    }
  }

  Color _groupTypeColor(String type) {
    switch (type) {
      case 'trip':
        return const Color(0xFF4CAF50);
      case 'meetup':
        return const Color(0xFF2196F3);
      case 'gym':
        return const Color(0xFFFF5722);
      case 'online_meet':
        return const Color(0xFF9C27B0);
      default:
        return AppTheme.primaryColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            // Community image
            if (_community != null)
              _community!.imageUrl != null &&
                      _community!.imageUrl!.isNotEmpty
                  ? ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: _community!.imageUrl!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _communityInitialAvatar(),
                      ),
                    )
                  : _communityInitialAvatar()
            else
              SizedBox(
                width: 40,
                height: 40,
                child: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  child: const Icon(Icons.groups, size: 20, color: Colors.grey),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _community?.name ?? 'Community',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Community',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black),
            onSelected: (value) {
              if (value == 'info') {
                context.push('/community/${widget.communityId}');
              } else if (value == 'leave') {
                _leaveCommunity();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'info',
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 20),
                    SizedBox(width: 12),
                    Text('View info'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'leave',
                child: Row(
                  children: [
                    Icon(Icons.exit_to_app,
                        size: 20, color: AppTheme.errorColor),
                    const SizedBox(width: 12),
                    Text('Leave community',
                        style: TextStyle(color: AppTheme.errorColor)),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 0.5,
            color: AppTheme.dividerColor,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              color: AppTheme.primaryColor,
              onRefresh: _loadData,
              child: ListView(
                children: [
                  // ── Announcements tile ──
                  _buildAnnouncementTile(),
                  Container(
                    height: 8,
                    color: const Color(0xFFF5F5F5),
                  ),

                  // ── Groups you're in ──
                  if (_joinedGroups.isNotEmpty) ...[
                    _buildSectionHeader('Groups you\'re in'),
                    ..._joinedGroups.map((g) => _buildGroupTile(g, isJoined: true)),
                    Container(
                      height: 8,
                      color: const Color(0xFFF5F5F5),
                    ),
                  ],

                  // ── Groups you can join ──
                  if (_availableGroups.isNotEmpty) ...[
                    _buildSectionHeader('Groups you can join'),
                    ..._availableGroups
                        .map((g) => _buildGroupTile(g, isJoined: false)),
                  ],

                  // ── Empty state ──
                  if (_joinedGroups.isEmpty && _availableGroups.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.group_outlined,
                                size: 48, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text(
                              'No groups yet',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _communityInitialAvatar() {
    final name = _community?.name ?? '?';
    return CircleAvatar(
      radius: 20,
      backgroundColor: AppTheme.primaryColor.withOpacity(0.2),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 16,
          color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
        ),
      ),
    );
  }

  // ── Announcement Tile ──
  Widget _buildAnnouncementTile() {
    final lastMsg = _lastCommunityMessage;
    final preview = lastMsg != null
        ? '${lastMsg.userName}: ${lastMsg.message}'
        : 'Welcome to the community!';
    final time = _timeAgo(lastMsg?.timestamp);

    return InkWell(
      onTap: () => context.push('/community/${widget.communityId}/chat'),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Green megaphone circle
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: Color(0xFF25D366),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.campaign,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            // Title + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Announcements',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Time + pin
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Transform.rotate(
                  angle: 0.5,
                  child: Icon(
                    Icons.push_pin,
                    size: 16,
                    color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Section Header ──
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
        ),
      ),
    );
  }

  // ── Group Tile ──
  Widget _buildGroupTile(SubGroup group, {required bool isJoined}) {
    final typeColor = _groupTypeColor(group.type);
    final typeIcon = _groupTypeIcon(group.type);
    final isPending = group.isPending;

    return Column(
      children: [
        InkWell(
          onTap: () {
            if (isJoined) {
              context.push(
                  '/community/${widget.communityId}/group/${group.id}');
            } else if (isPending) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Your join request is pending approval')),
              );
            } else {
              if (group.isPrivate) {
                // Request to join
                _requestToJoinGroup(group);
              } else {
                _joinAndOpenGroup(group);
              }
            }
          },
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                // Group icon
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: isJoined
                        ? typeColor.withOpacity(0.15)
                        : Colors.grey[200],
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    typeIcon,
                    color: isJoined ? typeColor : Colors.grey[500],
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                // Group name + member count
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              group.name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (group.isPrivate) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.lock, size: 14, color: Colors.grey[500]),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '${group.membersCount} member${group.membersCount == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
                            ),
                          ),
                          if (isPending) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Pending',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.amber,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Trailing
                if (!isJoined && !isPending)
                  group.isPrivate
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Request',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : Icon(
                          Icons.chevron_right,
                          color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
                        ),
                if (isPending)
                  Icon(Icons.hourglass_top, size: 20, color: Colors.amber[700]),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 80),
          child: Divider(
            height: 0.5,
            thickness: 0.5,
            color: Colors.grey[200],
          ),
        ),
      ],
    );
  }

  Future<void> _requestToJoinGroup(SubGroup group) async {
    try {
      await _api.post(
        '/communities/${widget.communityId}/groups/${group.id}/join',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Join request sent! Waiting for admin approval.')),
        );
        _fetchGroups();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send request: $e')),
        );
      }
    }
  }
}
