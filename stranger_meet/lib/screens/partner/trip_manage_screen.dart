import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../providers/admin_provider.dart';

class TripManageScreen extends ConsumerStatefulWidget {
  final String communityId;
  final String eventId;

  const TripManageScreen({
    super.key,
    required this.communityId,
    required this.eventId,
  });

  @override
  ConsumerState<TripManageScreen> createState() => _TripManageScreenState();
}

class _TripManageScreenState extends ConsumerState<TripManageScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Event data
  Map<String, dynamic>? _eventData;
  bool _isEventLoading = true;

  // Itinerary
  List<Map<String, dynamic>> _itinerary = [];
  bool _isItineraryLoading = true;

  // Enrollments
  List<Map<String, dynamic>> _enrollments = [];
  bool _isEnrollmentsLoading = true;

  // Settings save
  bool _isSettingsSaving = false;

  // Settings controllers
  late TextEditingController _eventTypeCtrl;
  late TextEditingController _durationCtrl;
  late TextEditingController _maxAltitudeCtrl;
  late TextEditingController _totalDistanceCtrl;
  late TextEditingController _meetingPointCtrl;
  String _difficulty = 'easy';
  List<String> _includes = [];
  List<String> _excludes = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _eventTypeCtrl = TextEditingController();
    _durationCtrl = TextEditingController();
    _maxAltitudeCtrl = TextEditingController();
    _totalDistanceCtrl = TextEditingController();
    _meetingPointCtrl = TextEditingController();
    _loadAll();
  }

  Future<void> _loadAll() async {
    _loadEvent();
    _loadItinerary();
    _loadEnrollments();
  }

  Future<void> _loadEvent() async {
    if (mounted) setState(() => _isEventLoading = true);
    try {
      final events = await ref
          .read(adminCommunitiesProvider.notifier)
          .fetchEvents(widget.communityId);
      final event = events.firstWhere(
        (e) => e['id']?.toString() == widget.eventId,
        orElse: () => <String, dynamic>{},
      );
      if (mounted) {
        setState(() {
          _eventData = event.isNotEmpty ? event : null;
          _isEventLoading = false;
          _populateSettingsFromEvent();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isEventLoading = false);
    }
  }

  void _populateSettingsFromEvent() {
    if (_eventData == null) return;
    _eventTypeCtrl.text = _eventData!['event_type']?.toString() ?? 'trip';
    _durationCtrl.text = (_eventData!['duration_days'] ?? 1).toString();
    _difficulty = _eventData!['difficulty']?.toString() ?? 'easy';
    _maxAltitudeCtrl.text = (_eventData!['max_altitude_m'] ?? 0).toString();
    _totalDistanceCtrl.text =
        (_eventData!['total_distance_km'] ?? 0).toString();
    _meetingPointCtrl.text =
        _eventData!['meeting_point']?.toString() ?? '';

    final incRaw = _eventData!['includes'];
    if (incRaw is List) {
      _includes = incRaw.map((e) => e.toString()).toList();
    }
    final excRaw = _eventData!['excludes'];
    if (excRaw is List) {
      _excludes = excRaw.map((e) => e.toString()).toList();
    }
  }

  Future<void> _loadItinerary() async {
    if (mounted) setState(() => _isItineraryLoading = true);
    try {
      final days = await ref
          .read(adminCommunitiesProvider.notifier)
          .fetchItinerary(widget.communityId, widget.eventId);
      if (mounted) {
        setState(() {
          _itinerary = days;
          _isItineraryLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isItineraryLoading = false);
    }
  }

  Future<void> _loadEnrollments() async {
    if (mounted) setState(() => _isEnrollmentsLoading = true);
    try {
      final result = await ref
          .read(adminCommunitiesProvider.notifier)
          .fetchEventEnrollments(widget.communityId, widget.eventId);
      if (mounted) {
        setState(() {
          _enrollments = result['enrollments'] != null
              ? List<Map<String, dynamic>>.from(result['enrollments'])
              : [];
          _isEnrollmentsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isEnrollmentsLoading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _eventTypeCtrl.dispose();
    _durationCtrl.dispose();
    _maxAltitudeCtrl.dispose();
    _totalDistanceCtrl.dispose();
    _meetingPointCtrl.dispose();
    super.dispose();
  }

  // ─── BUILD ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Trip'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
          unselectedLabelColor: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
          indicatorColor: AppTheme.primaryColor,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'Itinerary'),
            Tab(text: 'Enrollments'),
            Tab(text: 'Settings'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildTripInfoCard(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildItineraryTab(),
                _buildEnrollmentsTab(),
                _buildSettingsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── TRIP INFO CARD ──────────────────────────────────────────

  Widget _buildTripInfoCard() {
    if (_isEventLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
            child: SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (_eventData == null) return const SizedBox.shrink();

    final event = _eventData!;
    final title = event['title']?.toString() ?? 'Untitled Trip';
    final location = event['location']?.toString() ?? '';
    final price = (event['price'] ?? 0).toDouble();
    final slots = event['slots'] ?? 0;
    final enrolled = event['enrolled_count'] ?? _enrollments.length;
    final progress = slots > 0 ? (enrolled / slots).clamp(0.0, 1.0) : 0.0;

    final dateStr = event['date']?.toString();
    final endDateStr = event['end_date']?.toString();
    final startDate = dateStr != null ? DateTime.tryParse(dateStr) : null;
    final endDate = endDateStr != null ? DateTime.tryParse(endDateStr) : null;

    String dateRange = '';
    if (startDate != null) {
      dateRange = DateFormat('MMM d').format(startDate);
      if (endDate != null) {
        dateRange += ' - ${DateFormat('MMM d, yyyy').format(endDate)}';
      } else {
        dateRange = DateFormat('MMM d, yyyy').format(startDate);
      }
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              if (dateRange.isNotEmpty)
                _infoChip(Icons.calendar_today, dateRange),
              if (location.isNotEmpty)
                _infoChip(Icons.location_on_outlined, location),
              _infoChip(
                Icons.currency_rupee,
                price > 0 ? price.toStringAsFixed(0) : 'FREE',
              ),
              _infoChip(Icons.people_outline, '$enrolled / $slots slots'),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Theme.of(context).colorScheme.surface,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ─── ITINERARY TAB ───────────────────────────────────────────

  Widget _buildItineraryTab() {
    if (_isItineraryLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadItinerary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          if (_itinerary.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.hiking, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text(
                      'No itinerary days yet',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => _showDaySheet(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Day 1'),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._itinerary.asMap().entries.map((entry) {
              final day = entry.value;
              return _buildDayCard(day);
            }),
          if (_itinerary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                onPressed: () => _showDaySheet(),
                icon: const Icon(Icons.add, size: 18),
                label: Text('Add Day ${_itinerary.length + 1}'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDayCard(Map<String, dynamic> day) {
    final dayNumber = day['day_number'] ?? 0;
    final title = day['title']?.toString() ?? '';
    final distance = (day['distance_km'] ?? 0).toDouble();
    final elevation = (day['elevation_m'] ?? 0).toDouble();
    final accommodation = day['accommodation']?.toString() ?? '';
    final meals = day['meals_included'] is List
        ? List<String>.from(day['meals_included'])
        : <String>[];
    final activities = day['activities'] is List
        ? List<String>.from(day['activities'])
        : <String>[];
    final dayId = day['id']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.dividerColor, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Day $dayNumber',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _showDaySheet(existing: day),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 20, color: AppTheme.errorColor),
                  onPressed: () => _confirmDeleteDay(dayId, dayNumber),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Distance + Elevation chips
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (distance > 0)
                  _tagChip(Icons.straighten, '${distance.toStringAsFixed(1)} km',
                      Colors.blue[50]!, Colors.blue[700]!),
                if (elevation > 0)
                  _tagChip(Icons.terrain, '${elevation.toStringAsFixed(0)} m',
                      Colors.orange[50]!, Colors.orange[700]!),
                if (accommodation.isNotEmpty)
                  _tagChip(Icons.hotel, accommodation, Colors.purple[50]!,
                      Colors.purple[700]!),
              ],
            ),
            if (meals.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: meals
                    .map((m) => Chip(
                          label: Text(m,
                              style: const TextStyle(fontSize: 11)),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          labelPadding:
                              const EdgeInsets.symmetric(horizontal: 6),
                        ))
                    .toList(),
              ),
            ],
            if (activities.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '${activities.length} activit${activities.length == 1 ? 'y' : 'ies'}',
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
    );
  }

  Widget _tagChip(
      IconData icon, String label, Color bgColor, Color fgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fgColor),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: fgColor)),
        ],
      ),
    );
  }

  void _confirmDeleteDay(String dayId, int dayNumber) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Itinerary Day'),
        content:
            Text('Delete Day $dayNumber? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(adminCommunitiesProvider.notifier)
                    .deleteItineraryDay(
                        widget.communityId, widget.eventId, dayId);
                _loadItinerary();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ─── ADD / EDIT DAY BOTTOM SHEET ─────────────────────────────

  void _showDaySheet({Map<String, dynamic>? existing}) {
    final isEdit = existing != null;
    final dayNumberCtrl = TextEditingController(
      text: isEdit
          ? (existing['day_number'] ?? 1).toString()
          : (_itinerary.length + 1).toString(),
    );
    final titleCtrl =
        TextEditingController(text: existing?['title']?.toString() ?? '');
    final descCtrl =
        TextEditingController(text: existing?['description']?.toString() ?? '');
    final imageCtrl = TextEditingController(
        text: existing?['image_url']?.toString() ?? '');
    final distCtrl = TextEditingController(
        text: (existing?['distance_km'] ?? 0).toString());
    final elevCtrl = TextEditingController(
        text: (existing?['elevation_m'] ?? 0).toString());
    final accomCtrl = TextEditingController(
        text: existing?['accommodation']?.toString() ?? '');

    // Meals
    List<String> meals = [];
    if (existing != null && existing['meals_included'] is List) {
      meals = List<String>.from(existing['meals_included']);
    }
    final mealsCtrl = TextEditingController(text: meals.join(', '));

    // Activities
    List<String> activities = [];
    if (existing != null && existing['activities'] is List) {
      activities = List<String>.from(existing['activities']);
    }

    final dayId = existing?['id']?.toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final activityCtrl = TextEditingController();

            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollController) {
                return Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 16,
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                  ),
                  child: ListView(
                    controller: scrollController,
                    children: [
                      // Title
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isEdit ? 'Edit Day' : 'Add Itinerary Day',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Day Number + Title
                      Row(
                        children: [
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: dayNumberCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Day #',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: titleCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Title',
                                hintText: 'e.g. Dehradun to Sankri',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Description
                      TextField(
                        controller: descCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          hintText: 'Describe the day...',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Image URL
                      TextField(
                        controller: imageCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Image URL (optional)',
                          prefixIcon: Icon(Icons.image_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Distance + Elevation
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: distCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Distance (km)',
                                prefixIcon: Icon(Icons.straighten),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: elevCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Elevation (m)',
                                prefixIcon: Icon(Icons.terrain),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Accommodation
                      TextField(
                        controller: accomCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Accommodation',
                          prefixIcon: Icon(Icons.hotel),
                          hintText: 'e.g. Tents, Guesthouse',
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Meals
                      TextField(
                        controller: mealsCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Meals (comma separated)',
                          prefixIcon: Icon(Icons.restaurant),
                          hintText: 'Breakfast, Lunch, Dinner',
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Activities section
                      Row(
                        children: [
                          const Text(
                            'Activities',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          Text(
                            '${activities.length} added',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...activities.asMap().entries.map((entry) {
                        final i = entry.key;
                        final act = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(act,
                                    style: const TextStyle(fontSize: 13)),
                              ),
                              GestureDetector(
                                onTap: () {
                                  setSheetState(() => activities.removeAt(i));
                                },
                                child: Icon(Icons.close,
                                    size: 18, color: Colors.grey[500]),
                              ),
                            ],
                          ),
                        );
                      }),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: activityCtrl,
                              decoration: const InputDecoration(
                                hintText: 'Add activity...',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                              ),
                              onSubmitted: (val) {
                                if (val.trim().isNotEmpty) {
                                  setSheetState(
                                      () => activities.add(val.trim()));
                                  activityCtrl.clear();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () {
                              if (activityCtrl.text.trim().isNotEmpty) {
                                setSheetState(() =>
                                    activities.add(activityCtrl.text.trim()));
                                activityCtrl.clear();
                              }
                            },
                            icon: const Icon(Icons.add_circle,
                                color: AppTheme.primaryColor),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Save button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            final mealsList = mealsCtrl.text
                                .split(',')
                                .map((e) => e.trim())
                                .where((e) => e.isNotEmpty)
                                .toList();

                            final data = {
                              'day_number':
                                  int.tryParse(dayNumberCtrl.text) ?? 1,
                              'title': titleCtrl.text.trim(),
                              'description': descCtrl.text.trim(),
                              'distance_km':
                                  double.tryParse(distCtrl.text) ?? 0,
                              'elevation_m':
                                  double.tryParse(elevCtrl.text) ?? 0,
                              'accommodation': accomCtrl.text.trim(),
                              'meals_included': mealsList,
                              'activities': activities,
                            };

                            try {
                              if (isEdit && dayId != null) {
                                await ref
                                    .read(adminCommunitiesProvider.notifier)
                                    .updateItineraryDay(widget.communityId,
                                        widget.eventId, dayId, data);
                              } else {
                                await ref
                                    .read(adminCommunitiesProvider.notifier)
                                    .createItineraryDay(widget.communityId,
                                        widget.eventId, data);
                              }
                              if (ctx.mounted) Navigator.pop(ctx);
                              _loadItinerary();
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text(e.toString())),
                                );
                              }
                            }
                          },
                          child: Text(isEdit ? 'Update Day' : 'Add Day'),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ─── ENROLLMENTS TAB ─────────────────────────────────────────

  Widget _buildEnrollmentsTab() {
    if (_isEnrollmentsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_enrollments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('No enrollments yet',
                style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadEnrollments,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // Summary card
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.group, color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black),
                const SizedBox(width: 10),
                Text(
                  '${_enrollments.length} enrolled',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          ..._enrollments.map((e) => _buildEnrollmentTile(e)),
        ],
      ),
    );
  }

  Widget _buildEnrollmentTile(Map<String, dynamic> enrollment) {
    final userName = enrollment['user_name']?.toString() ?? 'Unknown';
    final profileImage = enrollment['user_profile_image']?.toString();
    final paymentStatus =
        enrollment['payment_status']?.toString() ?? 'confirmed';
    final amount = (enrollment['amount'] ?? 0).toDouble();
    final bookedAtStr = enrollment['booked_at']?.toString();
    final bookedAt =
        bookedAtStr != null ? DateTime.tryParse(bookedAtStr) : null;

    final isConfirmed = paymentStatus == 'confirmed' ||
        paymentStatus == 'completed' ||
        paymentStatus == 'free';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
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
                          fontWeight: FontWeight.w700, fontSize: 16),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(userName,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (amount > 0)
                        Text(
                          '\u20B9${amount.toStringAsFixed(0)}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600]),
                        ),
                      if (amount > 0 && bookedAt != null)
                        Text(' | ',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[400])),
                      if (bookedAt != null)
                        Text(
                          DateFormat('MMM d, yyyy').format(bookedAt),
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600]),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
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
                    color:
                        isConfirmed ? Colors.green[700] : Colors.orange[700],
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
          ],
        ),
      ),
    );
  }

  // ─── SETTINGS TAB ────────────────────────────────────────────

  Widget _buildSettingsTab() {
    if (_isEventLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_eventData == null) {
      return Center(
        child: Text('Event not found',
            style: TextStyle(color: Colors.grey[500])),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Event type
          const Text('Event Type',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              _typeToggle('trip', 'Trip'),
              const SizedBox(width: 8),
              _typeToggle('event', 'Event'),
            ],
          ),
          const SizedBox(height: 20),

          // Duration + Difficulty
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _durationCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Duration (days)',
                    prefixIcon: Icon(Icons.schedule),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _difficulty,
                  decoration: const InputDecoration(
                    labelText: 'Difficulty',
                    prefixIcon: Icon(Icons.fitness_center),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'easy', child: Text('Easy')),
                    DropdownMenuItem(
                        value: 'moderate', child: Text('Moderate')),
                    DropdownMenuItem(value: 'hard', child: Text('Hard')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _difficulty = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Difficulty color indicator
          _buildDifficultyBadge(),
          const SizedBox(height: 20),

          // Max altitude + Total distance
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _maxAltitudeCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Max Altitude (m)',
                    prefixIcon: Icon(Icons.terrain),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _totalDistanceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Total Distance (km)',
                    prefixIcon: Icon(Icons.straighten),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Meeting point
          TextField(
            controller: _meetingPointCtrl,
            decoration: const InputDecoration(
              labelText: 'Meeting Point',
              prefixIcon: Icon(Icons.place),
              hintText: 'e.g. Dehradun Railway Station',
            ),
          ),
          const SizedBox(height: 24),

          // Includes
          _buildEditableList(
            label: "What's Included",
            items: _includes,
            onAdd: (val) => setState(() => _includes.add(val)),
            onRemove: (i) => setState(() => _includes.removeAt(i)),
          ),
          const SizedBox(height: 20),

          // Excludes
          _buildEditableList(
            label: "What's Not Included",
            items: _excludes,
            onAdd: (val) => setState(() => _excludes.add(val)),
            onRemove: (i) => setState(() => _excludes.removeAt(i)),
          ),
          const SizedBox(height: 32),

          // Save
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSettingsSaving ? null : _saveSettings,
              child: _isSettingsSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black),
                    )
                  : const Text('Save Settings'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _typeToggle(String value, String label) {
    final selected = _eventTypeCtrl.text == value;
    return GestureDetector(
      onTap: () => setState(() => _eventTypeCtrl.text = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryColor : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.primaryColor : AppTheme.dividerColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected ? Colors.black : Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _buildDifficultyBadge() {
    Color bg;
    Color fg;
    switch (_difficulty) {
      case 'easy':
        bg = Colors.green[50]!;
        fg = Colors.green[700]!;
        break;
      case 'moderate':
        bg = Colors.orange[50]!;
        fg = Colors.orange[700]!;
        break;
      case 'hard':
        bg = Colors.red[50]!;
        fg = Colors.red[700]!;
        break;
      default:
        bg = Colors.grey[100]!;
        fg = Colors.grey[700]!;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Difficulty: ${_difficulty[0].toUpperCase()}${_difficulty.substring(1)}',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildEditableList({
    required String label,
    required List<String> items,
    required void Function(String) onAdd,
    required void Function(int) onRemove,
  }) {
    final ctrl = TextEditingController();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ...items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 16, color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                    child:
                        Text(item, style: const TextStyle(fontSize: 13))),
                GestureDetector(
                  onTap: () => onRemove(i),
                  child:
                      Icon(Icons.close, size: 18, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  hintText: 'Add item...',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty) {
                    onAdd(val.trim());
                    ctrl.clear();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {
                if (ctrl.text.trim().isNotEmpty) {
                  onAdd(ctrl.text.trim());
                  ctrl.clear();
                }
              },
              icon:
                  const Icon(Icons.add_circle, color: AppTheme.primaryColor),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _saveSettings() async {
    if (_eventData == null) return;
    setState(() => _isSettingsSaving = true);

    // We need to send the full event data for the PUT endpoint (CommunityEventCreate).
    // Merge existing event data with the updated settings fields.
    final event = _eventData!;
    final data = {
      'title': event['title'] ?? '',
      'description': event['description'] ?? '',
      'location': event['location'] ?? '',
      'date': event['date']?.toString() ?? DateTime.now().toIso8601String(),
      'price': event['price'] ?? 0,
      'slots': event['slots'] ?? 0,
      'image_url': event['image_url'] ?? '',
      'event_type': _eventTypeCtrl.text.trim(),
      'duration_days': int.tryParse(_durationCtrl.text) ?? 1,
      'difficulty': _difficulty,
      'includes': _includes,
      'excludes': _excludes,
      'meeting_point': _meetingPointCtrl.text.trim(),
      'end_date': event['end_date']?.toString(),
      'max_altitude_m': double.tryParse(_maxAltitudeCtrl.text) ?? 0,
      'total_distance_km': double.tryParse(_totalDistanceCtrl.text) ?? 0,
    };

    try {
      await ref
          .read(adminCommunitiesProvider.notifier)
          .updateEvent(widget.communityId, widget.eventId, data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trip settings saved')),
        );
        _loadEvent();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _isSettingsSaving = false);
    }
  }
}
