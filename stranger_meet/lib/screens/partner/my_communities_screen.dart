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
                      Icon(Icons.grid_view_outlined,
                          size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'No communities yet',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[500],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => context.push('/create-community'),
                        child: const Text('Create Community'),
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
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 52,
                              height: 52,
                              child: community.imageUrl != null &&
                                      community.imageUrl!.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: community.imageUrl!,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      color: AppTheme.primaryColor
                                          .withOpacity(0.2),
                                      child: Center(
                                        child: Text(
                                          community.name.isNotEmpty
                                              ? community.name[0]
                                                  .toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          title: Text(
                            community.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${community.membersCount} members',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined,
                                    size: 20),
                                onPressed: () => context.push(
                                    '/partner/community/${community.id}/manage'),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline,
                                    size: 20, color: AppTheme.errorColor),
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title:
                                          const Text('Delete Community'),
                                      content: Text(
                                          'Are you sure you want to delete "${community.name}"?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pop(ctx);
                                            ref
                                                .read(
                                                    adminCommunitiesProvider
                                                        .notifier)
                                                .deleteCommunity(
                                                    community.id);
                                          },
                                          style: TextButton.styleFrom(
                                            foregroundColor:
                                                AppTheme.errorColor,
                                          ),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
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
