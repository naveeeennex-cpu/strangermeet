import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../services/api_service.dart';

class MyBookingsScreen extends ConsumerStatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends ConsumerState<MyBookingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _upcomingBookings = [];
  List<Map<String, dynamic>> _pastBookings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchBookings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchBookings() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get('/bookings/my');
      final data = response.data;
      final List<dynamic> results =
          data is List ? data : (data['results'] ?? data['bookings'] ?? []);

      final now = DateTime.now();
      final upcoming = <Map<String, dynamic>>[];
      final past = <Map<String, dynamic>>[];

      for (final item in results) {
        final booking = Map<String, dynamic>.from(item);
        final dateStr = booking['event_date'] ?? booking['date'] ?? '';
        final eventDate = DateTime.tryParse(dateStr.toString());
        if (eventDate != null && eventDate.isAfter(now)) {
          upcoming.add(booking);
        } else {
          past.add(booking);
        }
      }

      if (mounted) {
        setState(() {
          _upcomingBookings = upcoming;
          _pastBookings = past;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bookings'),
        automaticallyImplyLeading: false,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryColor,
          labelColor: theme.textTheme.bodyLarge?.color,
          unselectedLabelColor: theme.textTheme.bodySmall?.color,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.upcoming, size: 18),
                  const SizedBox(width: 6),
                  const Text('Upcoming'),
                  if (_upcomingBookings.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_upcomingBookings.length}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.black),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.history, size: 18),
                  const SizedBox(width: 6),
                  const Text('Past'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchBookings,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildBookingsList(_upcomingBookings, isPast: false),
                  _buildBookingsList(_pastBookings, isPast: true),
                ],
              ),
            ),
    );
  }

  Widget _buildBookingsList(List<Map<String, dynamic>> bookings,
      {required bool isPast}) {
    if (bookings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPast ? Icons.history_outlined : Icons.event_available_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              isPast ? 'No past bookings' : 'No upcoming bookings',
              style: TextStyle(fontSize: 16, color: Colors.grey[500]),
            ),
            const SizedBox(height: 8),
            if (!isPast)
              TextButton.icon(
                onPressed: () => context.go('/explore'),
                icon: const Icon(Icons.explore),
                label: const Text('Explore trips & events'),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: bookings.length,
      itemBuilder: (context, index) {
        final booking = bookings[index];
        return _BookingCard(booking: booking, isPast: isPast);
      },
    );
  }
}

void _showReviewDialog(BuildContext context, String eventId) {
  int selectedRating = 0;
  final reviewController = TextEditingController();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
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
                  'Rate your experience',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                // Star rating
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return GestureDetector(
                      onTap: () => setSheetState(() => selectedRating = index + 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          index < selectedRating ? Icons.star : Icons.star_outline,
                          size: 40,
                          color: index < selectedRating ? Colors.amber : Colors.grey[400],
                        ),
                      ),
                    );
                  }),
                ),
                if (selectedRating > 0) ...[
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      ['', 'Poor', 'Fair', 'Good', 'Great', 'Amazing!'][selectedRating],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber[700],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                // Review text
                TextField(
                  controller: reviewController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Share your experience...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                // Submit button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: selectedRating == 0
                        ? null
                        : () async {
                            try {
                              await ApiService().post(
                                '/bookings/events/$eventId/review',
                                data: {
                                  'rating': selectedRating,
                                  'review': reviewController.text.trim(),
                                },
                              );
                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Review submitted! Thank you!')),
                                );
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text(e.toString())),
                                );
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Submit Review'),
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

class _BookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final bool isPast;

  const _BookingCard({required this.booking, required this.isPast});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final title = booking['event_title'] ?? booking['title'] ?? 'Unknown Event';
    final imageUrl = booking['event_image'] ?? booking['image_url'] ?? '';
    final location = booking['location'] ?? '';
    final dateStr = booking['event_date'] ?? booking['date'] ?? '';
    final eventDate = DateTime.tryParse(dateStr.toString());
    final price = (booking['amount'] ?? booking['price'] ?? 0).toDouble();
    final eventType = booking['event_type'] ?? 'event';
    final communityName = booking['community_name'] ?? '';
    final communityId = booking['community_id']?.toString() ?? '';
    final eventId = booking['event_id']?.toString() ?? '';
    final status = booking['payment_status'] ?? 'confirmed';
    final isTrip = eventType == 'trip';

    return GestureDetector(
      onTap: communityId.isNotEmpty && eventId.isNotEmpty
          ? () => context.push('/community/$communityId/event/$eventId')
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.12) : theme.dividerColor,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.4 : 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            if (imageUrl.isNotEmpty)
              Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: double.infinity,
                    height: 140,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      height: 140,
                      color: theme.colorScheme.surface,
                      child: const Center(
                          child: Icon(Icons.landscape, size: 40)),
                    ),
                  ),
                  // Overlay for past events
                  if (isPast)
                    Container(
                      width: double.infinity,
                      height: 140,
                      color: Colors.black.withOpacity(0.4),
                      child: const Center(
                        child: Text(
                          'COMPLETED',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                  // Type badge
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isTrip ? Colors.deepOrange : Colors.blue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isTrip ? 'Trip' : 'Event',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  // Price badge
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: price <= 0
                            ? Colors.green
                            : AppTheme.primaryColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        price <= 0
                            ? 'FREE'
                            : '\u20B9${price.toStringAsFixed(0)}',
                        style: TextStyle(
                          color: price <= 0 ? Colors.white : Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

            // Details
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // Community name
                  if (communityName.isNotEmpty)
                    Text(
                      communityName,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  const SizedBox(height: 8),
                  // Date + Location row
                  Row(
                    children: [
                      if (eventDate != null) ...[
                        Icon(Icons.calendar_today,
                            size: 14,
                            color: theme.textTheme.bodySmall?.color),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('MMM d, yyyy').format(eventDate),
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                      if (location.isNotEmpty) ...[
                        const SizedBox(width: 16),
                        Icon(Icons.location_on_outlined,
                            size: 14,
                            color: theme.textTheme.bodySmall?.color),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            location,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.textTheme.bodySmall?.color,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Status badge
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: status == 'confirmed'
                              ? Colors.green.withOpacity(0.15)
                              : Colors.amber.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              status == 'confirmed'
                                  ? Icons.check_circle
                                  : Icons.hourglass_top,
                              size: 14,
                              color: status == 'confirmed'
                                  ? Colors.green
                                  : Colors.amber,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              status == 'confirmed'
                                  ? 'Confirmed'
                                  : 'Pending',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: status == 'confirmed'
                                    ? Colors.green
                                    : Colors.amber,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (!isPast)
                        Text(
                          eventDate != null
                              ? '${eventDate.difference(DateTime.now()).inDays} days to go'
                              : '',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textTheme.bodySmall?.color,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  // Rate & Review + Memories buttons for past events
                  if (isPast) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _showReviewDialog(context, eventId),
                            icon: const Icon(Icons.star_outline, size: 18),
                            label: const Text('Review'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.amber[700],
                              side: BorderSide(color: Colors.amber[300]!),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              final encodedTitle = Uri.encodeComponent(title);
                              context.push('/event/$eventId/memories?title=$encodedTitle&canUpload=true');
                            },
                            icon: const Icon(Icons.photo_library_outlined, size: 18),
                            label: const Text('Memories'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primaryColor,
                              side: const BorderSide(color: AppTheme.primaryColor),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
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
}
