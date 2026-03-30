import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../config/theme.dart';
import '../../providers/friend_provider.dart';

class FriendRequestsScreen extends ConsumerStatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  ConsumerState<FriendRequestsScreen> createState() =>
      _FriendRequestsScreenState();
}

class _FriendRequestsScreenState
    extends ConsumerState<FriendRequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    Future.microtask(() {
      ref.read(friendProvider.notifier).fetchPendingRequests();
      ref.read(friendProvider.notifier).fetchSentRequests();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(friendProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friend Requests'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
          unselectedLabelColor: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
          indicatorColor: AppTheme.primaryColor,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'Incoming'),
            Tab(text: 'Sent'),
          ],
        ),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // Incoming
                state.pendingRequests.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_add_disabled,
                                size: 48, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text(
                              'No pending requests',
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: state.pendingRequests.length,
                        itemBuilder: (context, index) {
                          final request = state.pendingRequests[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                radius: 24,
                                backgroundColor: Theme.of(context).colorScheme.surface,
                                backgroundImage:
                                    request.requesterImage != null
                                        ? CachedNetworkImageProvider(
                                            request.requesterImage!)
                                        : null,
                                child: request.requesterImage == null
                                    ? Text(
                                        (request.requesterName ?? '?')
                                            .isNotEmpty
                                            ? (request.requesterName ?? '?')[0]
                                                .toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                      )
                                    : null,
                              ),
                              title: Text(
                                request.requesterName ?? 'Unknown',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    height: 34,
                                    child: ElevatedButton(
                                      onPressed: () => ref
                                          .read(friendProvider.notifier)
                                          .acceptRequest(request.id),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14),
                                        textStyle: const TextStyle(
                                            fontSize: 13),
                                      ),
                                      child: const Text('Accept'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    height: 34,
                                    child: OutlinedButton(
                                      onPressed: () => ref
                                          .read(friendProvider.notifier)
                                          .rejectRequest(request.id),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppTheme.errorColor,
                                        side: const BorderSide(
                                            color: AppTheme.errorColor),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14),
                                        textStyle: const TextStyle(
                                            fontSize: 13),
                                      ),
                                      child: const Text('Reject'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                // Sent
                state.sentRequests.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.send_outlined,
                                size: 48, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text(
                              'No sent requests',
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: state.sentRequests.length,
                        itemBuilder: (context, index) {
                          final request = state.sentRequests[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                radius: 24,
                                backgroundColor: Theme.of(context).colorScheme.surface,
                                backgroundImage:
                                    request.addresseeImage != null
                                        ? CachedNetworkImageProvider(
                                            request.addresseeImage!)
                                        : null,
                                child: request.addresseeImage == null
                                    ? Text(
                                        (request.addresseeName ?? '?')
                                            .isNotEmpty
                                            ? (request.addresseeName ?? '?')[0]
                                                .toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                      )
                                    : null,
                              ),
                              title: Text(
                                request.addresseeName ?? 'Unknown',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  request.status.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ],
            ),
    );
  }
}
