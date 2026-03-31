import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../services/api_service.dart';

class MySavedScreen extends ConsumerStatefulWidget {
  const MySavedScreen({super.key});

  @override
  ConsumerState<MySavedScreen> createState() => _MySavedScreenState();
}

class _MySavedScreenState extends ConsumerState<MySavedScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _savedItems = [];
  bool _isLoading = true;
  String _currentFilter = 'all';

  static const _tabs = ['All', 'Posts', 'Trips', 'Events'];
  static const _tabTypes = ['all', 'post', 'trip', 'event'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _currentFilter = _tabTypes[_tabController.index];
        _fetchSavedItems();
      }
    });
    _fetchSavedItems();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchSavedItems() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final response = await ApiService().get(
        '/bookings/saved',
        queryParameters:
            _currentFilter != 'all' ? {'item_type': _currentFilter} : null,
      );
      final data = response.data;
      final List<dynamic> items = data is List ? data : [];
      if (mounted) {
        setState(() {
          _savedItems = items.cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _unsaveItem(String itemId, int index) async {
    final removed = _savedItems[index];
    setState(() => _savedItems.removeAt(index));
    try {
      await ApiService().delete('/bookings/saved/$itemId');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Removed from saved'),
            action: SnackBarAction(
              label: 'Undo',
              textColor: AppTheme.primaryColor,
              onPressed: () async {
                try {
                  await ApiService().post('/bookings/saved', data: {
                    'item_id': removed['item_id'],
                    'item_type': removed['item_type'],
                  });
                  _fetchSavedItems();
                } catch (_) {}
              },
            ),
          ),
        );
      }
    } catch (_) {
      // Re-add on failure
      if (mounted) {
        setState(() => _savedItems.insert(index, removed));
      }
    }
  }

  void _navigateToDetail(Map<String, dynamic> item) {
    final type = item['item_type'] as String;
    final details = item['details'] as Map<String, dynamic>?;
    if (details == null) return;

    if (type == 'post') {
      context.push('/post/${details['id']}');
    } else if (type == 'trip' || type == 'event') {
      final communityId = details['community_id'] ?? '';
      final eventId = details['id'] ?? '';
      if (communityId.isNotEmpty && eventId.isNotEmpty) {
        context.push('/community/$communityId/event/$eventId');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: Theme.of(context).textTheme.bodyLarge?.color),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'My Saved',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: isDark ? Colors.black : Colors.white,
          unselectedLabelColor: Theme.of(context).textTheme.bodySmall?.color,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            color: AppTheme.primaryColor,
          ),
          dividerColor: Colors.transparent,
          splashBorderRadius: BorderRadius.circular(25),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          tabs: _tabs
              .map((t) => Tab(
                    child: Text(t,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                  ))
              .toList(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _savedItems.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  color: AppTheme.primaryColor,
                  onRefresh: _fetchSavedItems,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: _savedItems.length,
                    itemBuilder: (context, index) {
                      final item = _savedItems[index];
                      final type = item['item_type'] as String;
                      if (type == 'post') {
                        return _buildPostCard(item, index);
                      } else {
                        return _buildEventCard(item, index);
                      }
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    String message;
    IconData icon;
    switch (_currentFilter) {
      case 'post':
        message = 'No saved posts yet';
        icon = Icons.photo_library_outlined;
        break;
      case 'trip':
        message = 'No saved trips yet';
        icon = Icons.hiking;
        break;
      case 'event':
        message = 'No saved events yet';
        icon = Icons.event_outlined;
        break;
      default:
        message = 'Nothing saved yet';
        icon = Icons.bookmark_border;
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64,
              color: Theme.of(context).textTheme.bodySmall?.color),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Items you save will appear here',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> item, int index) {
    final details = item['details'] as Map<String, dynamic>?;
    if (details == null) return const SizedBox.shrink();

    final imageUrl = details['image_url'] as String? ?? '';
    final caption = details['caption'] as String? ?? '';
    final userName = details['user_name'] as String? ?? '';
    final userImage = details['user_profile_image'] as String? ?? '';
    final likesCount = details['likes_count'] ?? 0;

    return GestureDetector(
      onTap: () => _navigateToDetail(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ??
              Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).dividerColor.withOpacity(0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    backgroundImage: userImage.isNotEmpty
                        ? CachedNetworkImageProvider(userImage)
                        : null,
                    child: userImage.isEmpty
                        ? Text(
                            userName.isNotEmpty
                                ? userName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color:
                                Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                        Text(
                          'Post',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.bookmark,
                        color: AppTheme.primaryColor, size: 22),
                    onPressed: () => _unsaveItem(item['item_id'], index),
                    tooltip: 'Remove from saved',
                  ),
                ],
              ),
            ),
            // Image
            if (imageUrl.isNotEmpty)
              ClipRRect(
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    height: 200,
                    color: Theme.of(context).colorScheme.surface,
                    child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    height: 200,
                    color: Theme.of(context).colorScheme.surface,
                    child: const Icon(Icons.broken_image_outlined, size: 40),
                  ),
                ),
              ),
            // Caption + likes
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (caption.isNotEmpty)
                    Text(
                      caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                        height: 1.4,
                      ),
                    ),
                  if (likesCount > 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.favorite, size: 14, color: Colors.red[400]),
                        const SizedBox(width: 4),
                        Text(
                          '$likesCount likes',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventCard(Map<String, dynamic> item, int index) {
    final details = item['details'] as Map<String, dynamic>?;
    if (details == null) return const SizedBox.shrink();

    final imageUrl = details['image_url'] as String? ?? '';
    final title = details['title'] as String? ?? '';
    final location = details['location'] as String? ?? '';
    final dateStr = details['date'] as String? ?? '';
    final price = (details['price'] ?? 0).toDouble();
    final eventType = details['event_type'] as String? ?? 'event';
    final communityName = details['community_name'] as String? ?? '';
    final durationDays = details['duration_days'] ?? 1;
    final difficulty = details['difficulty'] as String? ?? 'easy';
    final isTrip = item['item_type'] == 'trip' || eventType == 'trip';

    String formattedDate = '';
    if (dateStr.isNotEmpty) {
      try {
        final date = DateTime.parse(dateStr);
        formattedDate = DateFormat('MMM d, yyyy').format(date);
      } catch (_) {
        formattedDate = dateStr;
      }
    }

    final priceText =
        price <= 0 ? 'Free' : '\u20B9${price.toStringAsFixed(0)}';

    return GestureDetector(
      onTap: () => _navigateToDetail(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ??
              Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).dividerColor.withOpacity(0.5),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image with overlays
            Stack(
              children: [
                CachedNetworkImage(
                  imageUrl: imageUrl,
                  width: double.infinity,
                  height: 180,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    height: 180,
                    color: Theme.of(context).colorScheme.surface,
                    child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    height: 180,
                    color: Theme.of(context).colorScheme.surface,
                    child: const Icon(Icons.landscape, size: 48),
                  ),
                ),
                // Gradient overlay
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.5),
                        ],
                      ),
                    ),
                  ),
                ),
                // Type badge
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isTrip
                          ? Colors.orange.withOpacity(0.9)
                          : AppTheme.primaryColor.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isTrip ? 'Trip' : 'Event',
                      style: TextStyle(
                        color: isTrip ? Colors.white : Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                // Bookmark button
                Positioned(
                  top: 12,
                  right: 12,
                  child: GestureDetector(
                    onTap: () => _unsaveItem(item['item_id'], index),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.bookmark,
                          color: AppTheme.primaryColor, size: 20),
                    ),
                  ),
                ),
                // Duration badge for trips
                if (isTrip && durationDays > 1)
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.schedule,
                              size: 14, color: Colors.black87),
                          const SizedBox(width: 4),
                          Text(
                            '$durationDays days',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Price badge
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: price <= 0 ? Colors.green : AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      priceText,
                      style: TextStyle(
                        color: price <= 0 ? Colors.white : Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Details section
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (location.isNotEmpty)
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined,
                            size: 15,
                            color:
                                Theme.of(context).textTheme.bodySmall?.color),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (formattedDate.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 14,
                            color:
                                Theme.of(context).textTheme.bodySmall?.color),
                        const SizedBox(width: 4),
                        Text(
                          formattedDate,
                          style: TextStyle(
                            fontSize: 13,
                            color:
                                Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (communityName.isNotEmpty) ...[
                        Icon(Icons.groups_outlined,
                            size: 14,
                            color:
                                Theme.of(context).textTheme.bodySmall?.color),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            communityName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color,
                            ),
                          ),
                        ),
                      ],
                      if (isTrip && difficulty.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _difficultyColor(difficulty)
                                .withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            difficulty[0].toUpperCase() +
                                difficulty.substring(1),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _difficultyColor(difficulty),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _difficultyColor(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'easy':
        return Colors.green;
      case 'moderate':
        return Colors.orange;
      case 'hard':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
