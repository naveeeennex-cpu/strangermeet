import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../providers/admin_provider.dart';

class EventEnrollmentsScreen extends ConsumerStatefulWidget {
  final String communityId;
  final String eventId;

  const EventEnrollmentsScreen({
    super.key,
    required this.communityId,
    required this.eventId,
  });

  @override
  ConsumerState<EventEnrollmentsScreen> createState() =>
      _EventEnrollmentsScreenState();
}

class _EventEnrollmentsScreenState
    extends ConsumerState<EventEnrollmentsScreen> {
  Map<String, dynamic>? _eventData;
  List<Map<String, dynamic>> _enrollments = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final result = await ref
          .read(adminCommunitiesProvider.notifier)
          .fetchEventEnrollments(widget.communityId, widget.eventId);
      if (mounted) {
        setState(() {
          _eventData = result['event'] != null
              ? Map<String, dynamic>.from(result['event'])
              : null;
          _enrollments = result['enrollments'] != null
              ? List<Map<String, dynamic>>.from(result['enrollments'])
              : [];
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Event Enrollments'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48, color: Theme.of(context).textTheme.bodySmall?.color),
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Event Header
                        if (_eventData != null) _buildEventHeader(),
                        const Divider(height: 1),
                        // Enrolled Members
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                          child: Text(
                            'Enrolled Members (${_enrollments.length})',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_enrollments.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(Icons.people_outline,
                                      size: 48, color: Theme.of(context).textTheme.bodySmall?.color),
                                  const SizedBox(height: 12),
                                  Text('No enrollments yet',
                                      style:
                                          TextStyle(color: Theme.of(context).textTheme.bodySmall?.color)),
                                ],
                              ),
                            ),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _enrollments.length,
                            itemBuilder: (context, index) {
                              final enrollment = _enrollments[index];
                              return _buildEnrollmentTile(enrollment);
                            },
                          ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildEventHeader() {
    final event = _eventData!;
    final title = event['title']?.toString() ?? 'Untitled';
    final dateStr = event['date']?.toString();
    final eventDate =
        dateStr != null ? DateTime.tryParse(dateStr) : null;
    final price = (event['price'] ?? 0).toDouble();
    final location = event['location']?.toString() ?? '';
    final enrolled = event['enrolled_count'] ?? _enrollments.length;
    final slots = event['slots'] ?? 0;
    final progress =
        slots > 0 ? (enrolled / slots).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (eventDate != null) ...[
                Icon(Icons.calendar_today,
                    size: 15, color: Theme.of(context).textTheme.bodySmall?.color),
                const SizedBox(width: 4),
                Text(
                  DateFormat('MMM d, yyyy').format(eventDate),
                  style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color),
                ),
                const SizedBox(width: 16),
              ],
              Icon(Icons.local_offer_outlined,
                  size: 15, color: Theme.of(context).textTheme.bodySmall?.color),
              const SizedBox(width: 4),
              Text(
                price > 0
                    ? '\u20B9${price.toStringAsFixed(0)}'
                    : 'FREE',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (location.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.location_on_outlined,
                    size: 15, color: Theme.of(context).textTheme.bodySmall?.color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    location,
                    style:
                        TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(
            '$enrolled/$slots enrolled',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Theme.of(context).colorScheme.surface,
              valueColor: const AlwaysStoppedAnimation<Color>(
                  AppTheme.primaryColor),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnrollmentTile(Map<String, dynamic> enrollment) {
    final userName = enrollment['user_name']?.toString() ?? 'Unknown';
    final profileImage = enrollment['user_profile_image']?.toString();
    final paymentStatus =
        enrollment['payment_status']?.toString() ?? 'confirmed';
    final bookedAtStr = enrollment['booked_at']?.toString();
    final bookedAt =
        bookedAtStr != null ? DateTime.tryParse(bookedAtStr) : null;

    final isConfirmed = paymentStatus == 'confirmed' ||
        paymentStatus == 'completed' ||
        paymentStatus == 'free';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
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
        title: Text(
          userName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: bookedAt != null
            ? Text(
                DateFormat('MMM d, yyyy').format(bookedAt),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
                ),
              )
            : null,
        trailing: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isConfirmed ? Colors.green[50] : Colors.orange[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isConfirmed ? Icons.check_circle : Icons.pending,
                size: 14,
                color: isConfirmed
                    ? Colors.green[700]
                    : Colors.orange[700],
              ),
              const SizedBox(width: 4),
              Text(
                isConfirmed ? 'Confirmed' : 'Pending',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isConfirmed
                      ? Colors.green[700]
                      : Colors.orange[700],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
