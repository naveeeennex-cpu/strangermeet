import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(dashboardProvider.notifier).fetchDashboardStats(),
    );
  }

  String _formatCurrency(double amount) {
    if (amount >= 100000) {
      return '${(amount / 100000).toStringAsFixed(1)}L';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}K';
    }
    return amount.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardProvider);
    final authState = ref.watch(authStateProvider);
    final userName = authState.user?.name ?? 'Partner';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(dashboardProvider.notifier).fetchDashboardStats(),
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(dashboardProvider.notifier).fetchDashboardStats(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Greeting
                    Text(
                      'Hello, $userName',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('EEEE, MMM d, yyyy').format(DateTime.now()),
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Stats cards - 2x2 grid
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            title: 'Members',
                            value: '${state.stats?.totalMembers ?? 0}',
                            icon: Icons.people_rounded,
                            color: Colors.blue[600]!,
                            bgColor: Colors.blue[50]!,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            title: 'Enrollments',
                            value: '${state.stats?.totalEnrollments ?? 0}',
                            icon: Icons.confirmation_number_rounded,
                            color: Colors.green[600]!,
                            bgColor: Colors.green[50]!,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            title: 'Revenue',
                            value:
                                '\u20B9${_formatCurrency(state.stats?.totalRevenue ?? 0)}',
                            icon: Icons.currency_rupee_rounded,
                            color: Colors.orange[700]!,
                            bgColor: Colors.orange[50]!,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            title: 'Events',
                            value: '${state.stats?.totalEvents ?? 0}',
                            icon: Icons.event_rounded,
                            color: Colors.purple[600]!,
                            bgColor: Colors.purple[50]!,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // Quick Actions
                    const Text(
                      'Quick Actions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _QuickActionButton(
                            icon: Icons.add_circle_outline,
                            label: 'Create Event',
                            onTap: () => context.push('/partner-communities'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _QuickActionButton(
                            icon: Icons.terrain_outlined,
                            label: 'Create Trip',
                            onTap: () => context.push('/partner-communities'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _QuickActionButton(
                            icon: Icons.people_outline,
                            label: 'Members',
                            onTap: () => context.push('/partner-communities'),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // Recent Enrollments
                    const Text(
                      'Recent Enrollments',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (state.stats == null ||
                        state.stats!.recentEnrollments.isEmpty)
                      _buildEmptyState(
                        icon: Icons.how_to_reg_outlined,
                        label: 'No recent enrollments',
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Theme.of(context).dividerColor),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            ...state.stats!.recentEnrollments
                                .take(5)
                                .toList()
                                .asMap()
                                .entries
                                .map((entry) {
                              final enrollment = entry.value;
                              final isLast = entry.key ==
                                  (state.stats!.recentEnrollments.length > 5
                                      ? 4
                                      : state.stats!.recentEnrollments.length -
                                          1);
                              return _buildEnrollmentTile(enrollment, isLast);
                            }),
                          ],
                        ),
                      ),

                    const SizedBox(height: 28),

                    // Upcoming Events
                    const Text(
                      'Upcoming Events',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (state.stats == null ||
                        state.stats!.upcomingEvents.isEmpty)
                      _buildEmptyState(
                        icon: Icons.event_busy_outlined,
                        label: 'No upcoming events',
                      )
                    else
                      ...state.stats!.upcomingEvents.map((event) {
                        return _buildUpcomingEventCard(event);
                      }),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String label}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: Colors.grey[400]),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildEnrollmentTile(
      Map<String, dynamic> enrollment, bool isLast) {
    final amount = (enrollment['amount'] ?? 0).toDouble();
    final profileImage = enrollment['user_profile_image']?.toString();
    final userName = enrollment['user_name']?.toString() ?? 'Unknown';
    final eventTitle = enrollment['event_title']?.toString() ?? '';
    final status = enrollment['payment_status']?.toString() ?? '';
    final createdAt = enrollment['created_at'] != null
        ? DateTime.tryParse(enrollment['created_at'].toString())
        : null;

    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppTheme.primaryColor.withOpacity(0.2),
              backgroundImage:
                  profileImage != null && profileImage.isNotEmpty
                      ? CachedNetworkImageProvider(profileImage)
                      : null,
              child: profileImage == null || profileImage.isEmpty
                  ? Text(
                      userName.isNotEmpty
                          ? userName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    eventTitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amount > 0
                      ? '\u20B9${amount.toStringAsFixed(0)}'
                      : 'FREE',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color:
                        amount > 0 ? Theme.of(context).textTheme.bodyLarge?.color : Colors.green[600],
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: status == 'confirmed'
                            ? Colors.green
                            : Colors.amber,
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (createdAt != null)
                      Text(
                        DateFormat('MMM d').format(createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingEventCard(Map<String, dynamic> event) {
    final title = event['title']?.toString() ?? 'Untitled';
    final enrolled = (event['enrolled_count'] ?? 0) as int;
    final slots = (event['slots'] ?? 0) as int;
    final progress = slots > 0 ? (enrolled / slots).clamp(0.0, 1.0) : 0.0;
    final dateStr = event['date']?.toString();
    final eventDate = dateStr != null ? DateTime.tryParse(dateStr) : null;
    final price = (event['price'] ?? 0).toDouble();
    final location = event['location']?.toString() ?? '';
    final imageUrl = event['image_url']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: imageUrl,
              width: double.infinity,
              height: 120,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (price > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '\u20B9${price.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Colors.green[700],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (eventDate != null) ...[
                      Icon(Icons.calendar_today,
                          size: 13, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('MMM d, yyyy').format(eventDate),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                    if (location.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.location_on_outlined,
                          size: 13, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          location,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            progress >= 0.8 ? Colors.orange : AppTheme.primaryColor,
                          ),
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$enrolled/$slots',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final Color bgColor;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).textTheme.bodySmall?.color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          children: [
            Icon(icon, size: 24, color: Theme.of(context).textTheme.bodyLarge?.color),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
