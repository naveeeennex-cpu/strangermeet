import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../config/theme.dart';
import '../../providers/admin_provider.dart';

class MyCommunitiesScreen extends ConsumerStatefulWidget {
  const MyCommunitiesScreen({super.key});

  @override
  ConsumerState<MyCommunitiesScreen> createState() =>
      _MyCommunitiesScreenState();
}

class _MyCommunitiesScreenState
    extends ConsumerState<MyCommunitiesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(adminCommunitiesProvider.notifier).fetchMyCommunities(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminCommunitiesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Communities'),
        automaticallyImplyLeading: false,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.communities.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.grid_view_outlined,
                            size: 48, color: Theme.of(context).textTheme.bodySmall?.color),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'No communities yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create your first community to get started',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => context.push('/create-community'),
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text('Create Community'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => ref
                      .read(adminCommunitiesProvider.notifier)
                      .fetchMyCommunities(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.communities.length,
                    itemBuilder: (context, index) {
                      final community = state.communities[index];
                      return GestureDetector(
                        onTap: () => context.push(
                            '/partner/community/${community.id}/manage'),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Theme.of(context).dividerColor),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Community Image
                              SizedBox(
                                height: 140,
                                width: double.infinity,
                                child: community.imageUrl != null &&
                                        community.imageUrl!.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: community.imageUrl!,
                                        fit: BoxFit.cover,
                                      )
                                    : Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              AppTheme.primaryColor
                                                  .withOpacity(0.3),
                                              AppTheme.primaryColor
                                                  .withOpacity(0.1),
                                            ],
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            community.name.isNotEmpty
                                                ? community.name[0]
                                                    .toUpperCase()
                                                : '?',
                                            style: const TextStyle(
                                              fontSize: 48,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white54,
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                              // Info section
                              Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            community.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 18,
                                            ),
                                          ),
                                        ),
                                        if (community.isPrivate)
                                          Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3),
                                            decoration: BoxDecoration(
                                              color:
                                                  Theme.of(context).colorScheme.surface,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Row(
                                              mainAxisSize:
                                                  MainAxisSize.min,
                                              children: [
                                                Icon(Icons.lock,
                                                    size: 12,
                                                    color: Theme.of(context).textTheme.bodySmall?.color),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Private',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.w600,
                                                    color:
                                                        Theme.of(context).textTheme.bodySmall?.color,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    // Stats row
                                    Row(
                                      children: [
                                        _MiniStat(
                                          icon: Icons.people_outline,
                                          value:
                                              '${community.membersCount}',
                                          label: 'Members',
                                        ),
                                        const SizedBox(width: 20),
                                        _MiniStat(
                                          icon: Icons.category_outlined,
                                          value: community.category,
                                          label: 'Category',
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    // Action buttons
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () => context.push(
                                                '/partner/community/${community.id}/manage'),
                                            icon: const Icon(
                                                Icons.settings_outlined,
                                                size: 18),
                                            label:
                                                const Text('Manage'),
                                            style:
                                                OutlinedButton.styleFrom(
                                              padding: const EdgeInsets
                                                  .symmetric(
                                                  vertical: 10),
                                              textStyle:
                                                  const TextStyle(
                                                fontSize: 13,
                                                fontWeight:
                                                    FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        SizedBox(
                                          width: 44,
                                          height: 44,
                                          child: OutlinedButton(
                                            onPressed: () {
                                              showDialog(
                                                context: context,
                                                builder: (ctx) =>
                                                    AlertDialog(
                                                  title: const Text(
                                                      'Delete Community'),
                                                  content: Text(
                                                      'Are you sure you want to delete "${community.name}"?'),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              ctx),
                                                      child: const Text(
                                                          'Cancel'),
                                                    ),
                                                    TextButton(
                                                      onPressed: () {
                                                        Navigator.pop(
                                                            ctx);
                                                        ref
                                                            .read(adminCommunitiesProvider
                                                                .notifier)
                                                            .deleteCommunity(
                                                                community
                                                                    .id);
                                                      },
                                                      style: TextButton
                                                          .styleFrom(
                                                        foregroundColor:
                                                            AppTheme
                                                                .errorColor,
                                                      ),
                                                      child: const Text(
                                                          'Delete'),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                            style:
                                                OutlinedButton.styleFrom(
                                              padding: EdgeInsets.zero,
                                              side: BorderSide(
                                                  color: Colors
                                                      .red.shade200),
                                            ),
                                            child: Icon(
                                                Icons.delete_outline,
                                                size: 18,
                                                color: AppTheme
                                                    .errorColor),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/create-community'),
        backgroundColor: AppTheme.primaryColor,
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).textTheme.bodySmall?.color),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
      ],
    );
  }
}
