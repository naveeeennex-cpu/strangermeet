import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/theme.dart';
import '../../providers/community_provider.dart';
import '../../models/community.dart';

class CommunitiesListScreen extends ConsumerStatefulWidget {
  const CommunitiesListScreen({super.key});

  @override
  ConsumerState<CommunitiesListScreen> createState() =>
      _CommunitiesListScreenState();
}

class _CommunitiesListScreenState extends ConsumerState<CommunitiesListScreen> {
  final _searchController = TextEditingController();
  String _selectedCategory = 'All';

  static const _categories = [
    'All',
    'Travel',
    'Fitness',
    'Food',
    'Tech',
    'Music',
    'Art',
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(communitiesProvider.notifier).fetchCommunities();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    ref.read(communitiesProvider.notifier).fetchCommunities(
          query: query,
          category: _selectedCategory,
        );
  }

  void _onCategorySelected(String category) {
    setState(() => _selectedCategory = category);
    ref.read(communitiesProvider.notifier).fetchCommunities(
          query: _searchController.text,
          category: category,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(communitiesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Communities'),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: 'Search communities...',
                prefixIcon: const Icon(Icons.search, size: 22),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _onSearch('');
                        },
                      )
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),

          // Category filter chips
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = category == _selectedCategory;
                return ChoiceChip(
                  label: Text(category),
                  selected: isSelected,
                  onSelected: (_) => _onCategorySelected(category),
                  selectedColor: AppTheme.primaryColor,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? Colors.black
                        : Theme.of(context).textTheme.bodySmall?.color,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13,
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // Communities list
          Expanded(
            child: _buildBody(state),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(CommunitiesState state) {
    if (state.isLoading && state.communities.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.errorMessage != null && state.communities.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48,
                color: Theme.of(context).textTheme.bodySmall?.color),
            const SizedBox(height: 12),
            Text(
              'Failed to load communities',
              style: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () =>
                  ref.read(communitiesProvider.notifier).fetchCommunities(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (state.communities.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline,
                size: 64,
                color: Theme.of(context).textTheme.bodySmall?.color),
            const SizedBox(height: 12),
            Text(
              'No communities found',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(communitiesProvider.notifier).fetchCommunities(
            query: _searchController.text,
            category: _selectedCategory,
          ),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        itemCount: state.communities.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          return _CommunityCard(
            community: state.communities[index],
            onTap: () =>
                context.push('/community/${state.communities[index].id}'),
          );
        },
      ),
    );
  }
}

class _CommunityCard extends StatelessWidget {
  final Community community;
  final VoidCallback onTap;

  const _CommunityCard({
    required this.community,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ??
              Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
        ),
        child: Row(
          children: [
            // Community image
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: community.imageUrl != null &&
                      community.imageUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: community.imageUrl!,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        width: 60,
                        height: 60,
                        color: Theme.of(context).colorScheme.surface,
                        child: Icon(Icons.people,
                            color: Theme.of(context).textTheme.bodySmall?.color),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        width: 60,
                        height: 60,
                        color: Theme.of(context).colorScheme.surface,
                        child: Icon(Icons.people,
                            color: Theme.of(context).textTheme.bodySmall?.color),
                      ),
                    )
                  : Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.people,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                          size: 28),
                    ),
            ),

            const SizedBox(width: 12),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + category
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          community.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          community.category,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // Member count
                  Row(
                    children: [
                      Icon(Icons.people_outline, size: 14,
                          color: Theme.of(context).textTheme.bodySmall?.color),
                      const SizedBox(width: 4),
                      Text(
                        '${community.membersCount} members',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 2),

                  // Description
                  if (community.description.isNotEmpty)
                    Text(
                      community.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Join / Joined button
            community.isMember
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'Joined',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  )
                : Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Join',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
