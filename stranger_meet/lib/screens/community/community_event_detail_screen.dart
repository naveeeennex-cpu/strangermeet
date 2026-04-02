import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../config/theme.dart';
import '../../models/community.dart';
import '../../providers/community_provider.dart';
import '../../services/api_service.dart';
import 'event_rides_screen.dart';

class CommunityEventDetailScreen extends ConsumerStatefulWidget {
  final String communityId;
  final String eventId;

  const CommunityEventDetailScreen({
    super.key,
    required this.communityId,
    required this.eventId,
  });

  @override
  ConsumerState<CommunityEventDetailScreen> createState() =>
      _CommunityEventDetailScreenState();
}

class _CommunityEventDetailScreenState
    extends ConsumerState<CommunityEventDetailScreen>
    with TickerProviderStateMixin {
  bool _isJoining = false;
  List<EventParticipant> _participants = [];
  bool _isLoadingParticipants = true;
  TabController? _tabController;
  int _lastTabCount = 0;
  CommunityEvent? _fetchedEvent;
  bool _isFetchingEvent = false;
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _fetchParticipants();
    _ensureEventLoaded();
    _checkIfSaved();
    Future.microtask(() {
      ref
          .read(eventItineraryProvider(
                  '${widget.communityId}:${widget.eventId}')
              .notifier)
          .fetchItinerary();
    });
  }

  Future<void> _ensureEventLoaded() async {
    setState(() => _isFetchingEvent = true);

    // Always fetch the single event directly for reliability
    try {
      final response = await ApiService().get(
        '/communities/${widget.communityId}/events/${widget.eventId}',
      );
      if (mounted) {
        setState(() {
          _fetchedEvent = CommunityEvent.fromJson(response.data);
          _isFetchingEvent = false;
        });
      }
    } catch (_) {
      // Fallback: try fetching all community events
      try {
        await ref.read(communityEventsProvider(widget.communityId).notifier).fetchEvents();
      } catch (_) {}
      if (mounted) setState(() => _isFetchingEvent = false);
    }
  }

  Future<void> _checkIfSaved() async {
    try {
      final res = await ApiService().get('/bookings/saved/check/${widget.eventId}');
      if (mounted) setState(() => _isSaved = res.data['is_saved'] == true);
    } catch (_) {}
  }

  Future<void> _toggleSave() async {
    final wasSaved = _isSaved;
    setState(() => _isSaved = !wasSaved);
    final event = _getEvent();
    final itemType = (event != null && event.isTrip) ? 'trip' : 'event';
    try {
      if (wasSaved) {
        await ApiService().delete('/bookings/saved/${widget.eventId}');
      } else {
        await ApiService().post('/bookings/saved', data: {
          'item_id': widget.eventId,
          'item_type': itemType,
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSaved = wasSaved);
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  TabController _getTabController(int tabCount) {
    if (_tabController == null || _lastTabCount != tabCount) {
      _tabController?.dispose();
      _tabController = TabController(length: tabCount, vsync: this);
      _lastTabCount = tabCount;
    }
    return _tabController!;
  }

  CommunityEvent? _getEvent() {
    final state = ref.watch(communityEventsProvider(widget.communityId));
    try {
      return state.events.firstWhere((e) => e.id == widget.eventId);
    } catch (_) {
      return _fetchedEvent;
    }
  }

  Future<void> _fetchParticipants() async {
    try {
      final response = await ApiService().get(
        '/communities/${widget.communityId}/events/${widget.eventId}/participants',
      );
      if (mounted) {
        final List data = response.data is List ? response.data : [];
        setState(() {
          _participants =
              data.map((json) => EventParticipant.fromJson(json)).toList();
          _isLoadingParticipants = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingParticipants = false);
    }
  }

  Future<void> _joinEvent() async {
    setState(() => _isJoining = true);
    try {
      await ApiService().post(
        '/communities/${widget.communityId}/events/${widget.eventId}/book',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully enrolled! See you there!'),
            backgroundColor: Colors.green,
          ),
        );
        // Re-fetch event to get updated isJoined status
        await _ensureEventLoaded();
        _fetchParticipants();
      }
    } catch (e) {
      if (mounted) {
        String msg = e.toString();
        if (msg.contains('Already booked')) {
          msg = 'You are already enrolled!';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _isJoining = false);
  }

  @override
  Widget build(BuildContext context) {
    final event = _getEvent();

    if (event == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _isFetchingEvent
            ? const Center(child: CircularProgressIndicator())
            : const Center(child: Text('Event not found')),
      );
    }

    final isTrip = event.isTrip;
    final tabs = isTrip
        ? ['Tour schedule', 'Accommodation', 'Booking details']
        : ['Overview', 'Members'];

    final tabController = _getTabController(tabs.length);

    final slotsLeft = event.slots - event.participantsCount;
    final isFull = event.slots > 0 && slotsLeft <= 0;
    final isPast = event.date.isBefore(DateTime.now());

    final dateStr = event.endDate != null
        ? '${DateFormat('EEE, MMM d').format(event.date)} \u2014 ${DateFormat('EEE, MMM d').format(event.endDate!)}'
        : DateFormat('EEE, MMM d, yyyy').format(event.date);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        leading: GestureDetector(
          onTap: () => context.pop(),
          child: Icon(Icons.arrow_back, color: Theme.of(context).iconTheme.color),
        ),
        title: Column(
          children: [
            Text(
              event.title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              dateStr,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          GestureDetector(
            onTap: _toggleSave,
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isSaved ? Icons.bookmark : Icons.bookmark_border,
                color: _isSaved ? AppTheme.primaryColor : Theme.of(context).textTheme.bodySmall?.color,
                size: 20,
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: tabController,
          labelColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.black
              : Colors.white,
          unselectedLabelColor: Theme.of(context).textTheme.bodySmall?.color,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: AppTheme.primaryColor,
            borderRadius: BorderRadius.circular(10),
          ),
          indicatorPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          dividerColor: Colors.transparent,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
          tabs: tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: Column(
        children: [
          _MeetingTimeBanner(event: event),
          Expanded(
            child: TabBarView(
              controller: tabController,
              children: isTrip
                  ? [
                      _TourScheduleTab(
                        event: event,
                        communityId: widget.communityId,
                        eventId: widget.eventId,
                      ),
                      _AccommodationTab(
                        communityId: widget.communityId,
                        eventId: widget.eventId,
                      ),
                      _BookingDetailsTab(event: event),
                    ]
                  : [
                      _OverviewTab(event: event),
                      _MembersTab(
                        event: event,
                        participants: _participants,
                        isLoadingParticipants: _isLoadingParticipants,
                      ),
                    ],
            ),
          ),
        ],
      ),

      // Ride sharing FAB — only visible to enrolled users
      floatingActionButton: event.isJoined
          ? FloatingActionButton(
              onPressed: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => EventRidesScreen(
                    communityId: widget.communityId,
                    eventId: widget.eventId,
                    eventTitle: event.title,
                    meetingPoint: event.meetingPoint,
                    venueLat: event.venueLat,
                    venueLng: event.venueLng,
                  ),
                ),
              ),
              backgroundColor: AppTheme.primaryColor,
              tooltip: 'Ride sharing',
              child: const Icon(Icons.directions_car, color: Colors.black),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,

      // Bottom bar
      bottomNavigationBar: _BottomBar(
        event: event,
        isFull: isFull,
        isPast: isPast,
        isJoining: _isJoining,
        onJoin: _joinEvent,
        participants: _participants,
        communityId: widget.communityId,
      ),
    );
  }
}

// ── Meeting Time Banner ───────────────────────────────────────────

class _MeetingTimeBanner extends StatelessWidget {
  final CommunityEvent event;

  const _MeetingTimeBanner({required this.event});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(event.date.year, event.date.month, event.date.day);
    final diff = eventDay.difference(today).inDays;

    String dayLabel;
    Color labelColor;
    IconData labelIcon;

    if (diff == 0) {
      dayLabel = 'Today';
      labelColor = Colors.orange;
      labelIcon = Icons.today;
    } else if (diff == 1) {
      dayLabel = 'Tomorrow';
      labelColor = AppTheme.primaryColor;
      labelIcon = Icons.event;
    } else if (diff > 1) {
      dayLabel = 'in $diff days';
      labelColor = AppTheme.primaryColor;
      labelIcon = Icons.event_available;
    } else {
      dayLabel = 'Ended';
      labelColor = Colors.grey;
      labelIcon = Icons.event_busy;
    }

    final timeStr = DateFormat('h:mm a').format(event.date);
    final dateStr = DateFormat('EEE, MMM d').format(event.date);

    // For trips with an end date, also show end
    final endStr = (event.isTrip && event.endDate != null)
        ? ' — ${DateFormat('MMM d').format(event.endDate!)}'
        : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          // Time pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).dividerColor.withOpacity(0.6),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.access_time_rounded, size: 14, color: Colors.grey[400]),
                const SizedBox(width: 5),
                Text(
                  timeStr,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Date
          Expanded(
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 13, color: Colors.grey[500]),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    '$dateStr$endStr',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[400],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Countdown chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: labelColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(labelIcon, size: 13, color: labelColor),
                const SizedBox(width: 4),
                Text(
                  dayLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: labelColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tour Schedule Tab ─────────────────────────────────────────────

class _TourScheduleTab extends ConsumerStatefulWidget {
  final CommunityEvent event;
  final String communityId;
  final String eventId;

  const _TourScheduleTab({
    required this.event,
    required this.communityId,
    required this.eventId,
  });

  @override
  ConsumerState<_TourScheduleTab> createState() => _TourScheduleTabState();
}

class _TourScheduleTabState extends ConsumerState<_TourScheduleTab> {
  // Track which day is expanded (first day open by default)
  int _expandedDay = 0;

  // Placeholder images for day thumbnails
  static const _dayImages = [
    'https://images.unsplash.com/photo-1544735716-392fe2489ffa?w=300&h=200&fit=crop',
    'https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=300&h=200&fit=crop',
    'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=300&h=200&fit=crop',
    'https://images.unsplash.com/photo-1486911278844-a81c5267e227?w=300&h=200&fit=crop',
    'https://images.unsplash.com/photo-1501785888041-af3ef285b470?w=300&h=200&fit=crop',
    'https://images.unsplash.com/photo-1551632811-561732d1e306?w=300&h=200&fit=crop',
    'https://images.unsplash.com/photo-1490750967868-88aa4f44baee?w=300&h=200&fit=crop',
  ];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
        eventItineraryProvider('${widget.communityId}:${widget.eventId}'));

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.days.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route_outlined, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('No itinerary available',
                style: TextStyle(color: Colors.grey[500], fontSize: 15)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        // Clickable community name
        if (widget.event.communityName != null)
          GestureDetector(
            onTap: () => context.push('/community/${widget.communityId}'),
            child: Row(
              children: [
                Icon(Icons.group_outlined, size: 14, color: AppTheme.primaryColor),
                const SizedBox(width: 6),
                Text(
                  widget.event.communityName!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 16, color: AppTheme.primaryColor),
              ],
            ),
          ),
        if (widget.event.communityName != null) const SizedBox(height: 8),
        // Trip title header
        Text(
          '${widget.event.durationDays}-Days ${widget.event.title}',
          style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w800, color: Theme.of(context).textTheme.bodyLarge?.color),
        ),
        const SizedBox(height: 24),

        // Day-wise collapsible cards
        ...List.generate(state.days.length, (index) {
          final day = state.days[index];
          final isExpanded = _expandedDay == index;
          final imageUrl = _dayImages[index % _dayImages.length];

          return _CollapsibleDayCard(
            day: day,
            imageUrl: imageUrl,
            isExpanded: isExpanded,
            onToggle: () {
              setState(() {
                _expandedDay = isExpanded ? -1 : index;
              });
            },
          );
        }),
      ],
    );
  }
}

class _CollapsibleDayCard extends StatelessWidget {
  final ItineraryDay day;
  final String imageUrl;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _CollapsibleDayCard({
    required this.day,
    required this.imageUrl,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    // Map activities to Morning/Afternoon/Evening
    final timeSections = <String, String>{};
    if (day.activities.isNotEmpty) {
      for (int i = 0; i < day.activities.length && i < 3; i++) {
        final label = i == 0 ? 'Morning' : (i == 1 ? 'Afternoon' : 'Evening');
        // Strip "Morning: " prefix if present
        String text = day.activities[i];
        if (text.startsWith('Morning: ')) text = text.substring(9);
        if (text.startsWith('Afternoon: ')) text = text.substring(11);
        if (text.startsWith('Evening: ')) text = text.substring(9);
        timeSections[label] = text;
      }
    } else if (day.description.isNotEmpty) {
      final sentences = day.description
          .split('.')
          .where((s) => s.trim().isNotEmpty)
          .map((s) => s.trim())
          .toList();
      final labels = ['Morning', 'Afternoon', 'Evening'];
      for (int i = 0; i < sentences.length && i < 3; i++) {
        timeSections[labels[i]] = '${sentences[i]}.';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ?? Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isExpanded ? Theme.of(context).dividerColor : Theme.of(context).dividerColor,
          ),
          boxShadow: isExpanded
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        child: Column(
          children: [
            // ── Collapsed header (always visible) ──
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Day image thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          width: 56,
                          height: 56,
                          color: Theme.of(context).dividerColor,
                        ),
                        errorWidget: (_, __, ___) => Container(
                          width: 56,
                          height: 56,
                          color: Theme.of(context).dividerColor,
                          child: const Icon(Icons.landscape, size: 24, color: Colors.grey),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Day badge + title
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Day ${day.dayNumber}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            day.title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).textTheme.bodyLarge?.color,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Expand/collapse arrow
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          size: 20,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Expanded content ──
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Description
                    if (day.description.isNotEmpty) ...[
                      Text(
                        day.description,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: Colors.grey[600],
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Time sections
                    ...timeSections.entries.map((entry) {
                      IconData icon;
                      Color iconColor;
                      switch (entry.key) {
                        case 'Morning':
                          icon = Icons.wb_sunny_outlined;
                          iconColor = Colors.orange;
                          break;
                        case 'Afternoon':
                          icon = Icons.wb_cloudy_outlined;
                          iconColor = Colors.blue;
                          break;
                        default:
                          icon = Icons.nightlight_outlined;
                          iconColor = Colors.indigo;
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: iconColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(icon, size: 16, color: iconColor),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.key,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[500],
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    entry.value,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Theme.of(context).textTheme.bodyLarge?.color,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    // Info chips row
                    if (day.distanceKm > 0 || day.elevationM > 0 || day.mealsIncluded.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (day.distanceKm > 0)
                              _DayInfoChip(
                                icon: Icons.directions_walk,
                                label: '${day.distanceKm.toStringAsFixed(0)} km',
                                color: Colors.green,
                              ),
                            if (day.elevationM > 0)
                              _DayInfoChip(
                                icon: Icons.terrain,
                                label: '${day.elevationM.toStringAsFixed(0)}m',
                                color: Colors.orange,
                              ),
                            if (day.accommodation.isNotEmpty)
                              _DayInfoChip(
                                icon: Icons.night_shelter,
                                label: day.accommodation.length > 25
                                    ? '${day.accommodation.substring(0, 25)}...'
                                    : day.accommodation,
                                color: Colors.purple,
                              ),
                            ...day.mealsIncluded.map((meal) => _DayInfoChip(
                                  icon: Icons.restaurant,
                                  label: meal,
                                  color: Colors.teal,
                                )),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              crossFadeState:
                  isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _DayInfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color.withOpacity(0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Accommodation Tab ─────────────────────────────────────────────

class _AccommodationTab extends ConsumerWidget {
  final String communityId;
  final String eventId;

  const _AccommodationTab({required this.communityId, required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state =
        ref.watch(eventItineraryProvider('$communityId:$eventId'));

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.days.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.night_shelter_outlined, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              'No accommodation details available',
              style: TextStyle(color: Colors.grey[500], fontSize: 15),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      itemCount: state.days.length,
      itemBuilder: (context, index) {
        final day = state.days[index];
        final hasAccommodation = day.accommodation.isNotEmpty;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    'D${day.dayNumber}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Day ${day.dayNumber}: ${day.title}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          hasAccommodation
                              ? Icons.night_shelter
                              : Icons.home_outlined,
                          size: 15,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            hasAccommodation
                                ? day.accommodation
                                : 'No accommodation needed',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (day.elevationM > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Elevation: ${day.elevationM.toStringAsFixed(0)}m',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                    if (day.mealsIncluded.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: day.mealsIncluded
                            .map((meal) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    meal,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.green[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Booking Details Tab ───────────────────────────────────────────

class _BookingDetailsTab extends StatelessWidget {
  final CommunityEvent event;

  const _BookingDetailsTab({required this.event});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        // Price breakdown
        const Text(
          'Price breakdown',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            children: [
              _PriceRow(
                label: 'Trip cost per person',
                value: event.price > 0
                    ? '\u20B9${event.price.toStringAsFixed(0)}'
                    : 'FREE',
                isBold: true,
              ),
              if (event.price > 0) ...[
                const SizedBox(height: 8),
                Divider(color: Colors.grey.shade300),
                const SizedBox(height: 8),
                _PriceRow(
                  label: 'Booking amount',
                  value: '\u20B9${(event.price * 0.2).toStringAsFixed(0)}',
                ),
                const SizedBox(height: 4),
                _PriceRow(
                  label: 'Balance due on arrival',
                  value: '\u20B9${(event.price * 0.8).toStringAsFixed(0)}',
                ),
              ],
            ],
          ),
        ),

        // What's included
        if (event.includes.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text(
            "What's included",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ...event.includes.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 14, color: Colors.green),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],

        // What's not included
        if (event.excludes.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text(
            "What's not included",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ...event.excludes.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 14, color: Colors.red),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],

        // Meeting point
        if (event.meetingPoint.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text(
            'Meeting point',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Builder(builder: (context) {
            final mp = event.meetingPoint;
            final hasUrl = mp.contains('|');
            final mpTitle = hasUrl ? mp.split('|')[0].trim() : mp;
            final mpUrl = hasUrl && mp.split('|').length > 1 ? mp.split('|')[1].trim() : '';
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return GestureDetector(
              onTap: mpUrl.isNotEmpty
                  ? () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Opening: $mpUrl'),
                          action: SnackBarAction(
                            label: 'COPY',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: mpUrl));
                            },
                          ),
                        ),
                      );
                      // Try to open URL
                      try {
                        launchUrl(Uri.parse(mpUrl), mode: LaunchMode.externalApplication);
                      } catch (_) {}
                    }
                  : null,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? Colors.blue.withOpacity(0.12) : Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? Colors.blue.withOpacity(0.3) : Colors.blue.shade100),
                ),
                child: Row(
                  children: [
                    Icon(Icons.pin_drop, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            mpTitle,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).textTheme.bodyLarge?.color),
                          ),
                          if (mpUrl.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.open_in_new, size: 13, color: Colors.blue[400]),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Open in Google Maps',
                                    style: TextStyle(fontSize: 12, color: Colors.blue[400], fontWeight: FontWeight.w500),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (mpUrl.isNotEmpty)
                      Icon(Icons.navigation_outlined, color: Colors.blue[400], size: 22),
                  ],
                ),
              ),
            );
          }),
        ],

        // Venue map
        const SizedBox(height: 24),
        const Text(
          'Venue on Map',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        _VenueMapSection(
          venueLat: event.venueLat,
          venueLng: event.venueLng,
          locationName: event.location,
        ),

        // Trip details grid
        const SizedBox(height: 24),
        const Text(
          'Trip details',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _DetailGridCard(
                icon: Icons.signal_cellular_alt,
                label: 'Difficulty',
                value: event.difficulty[0].toUpperCase() +
                    event.difficulty.substring(1),
                color: _difficultyColor(event.difficulty),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DetailGridCard(
                icon: Icons.calendar_today,
                label: 'Duration',
                value: event.durationLabel,
                color: Colors.blue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (event.maxAltitude > 0)
              Expanded(
                child: _DetailGridCard(
                  icon: Icons.terrain,
                  label: 'Max altitude',
                  value: '${event.maxAltitude.toStringAsFixed(0)}m',
                  color: Colors.orange,
                ),
              ),
            if (event.maxAltitude > 0 && event.totalDistance > 0)
              const SizedBox(width: 12),
            if (event.totalDistance > 0)
              Expanded(
                child: _DetailGridCard(
                  icon: Icons.directions_walk,
                  label: 'Total distance',
                  value: '${event.totalDistance.toStringAsFixed(0)} km',
                  color: Colors.green,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _DetailGridCard(
                icon: Icons.people,
                label: 'Enrolled',
                value: '${event.participantsCount}/${event.slots}',
                color: Colors.purple,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DetailGridCard(
                icon: Icons.location_on,
                label: 'Location',
                value: event.location.isNotEmpty ? event.location : 'TBD',
                color: Colors.red,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Color _difficultyColor(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'easy':
        return Colors.green;
      case 'moderate':
        return Colors.orange;
      case 'hard':
      case 'difficult':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;

  const _PriceRow({
    required this.label,
    required this.value,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: isBold ? Theme.of(context).textTheme.bodyLarge?.color : Theme.of(context).textTheme.bodySmall?.color,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 18 : 14,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
      ],
    );
  }
}

class _DetailGridCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DetailGridCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Overview Tab (non-trip events) ────────────────────────────────

class _OverviewTab extends StatefulWidget {
  final CommunityEvent event;

  const _OverviewTab({required this.event});

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  int _memoriesCount = 0;
  List<Map<String, dynamic>> _memoryPreviews = [];
  bool _loadedMemories = false;

  CommunityEvent get event => widget.event;

  @override
  void initState() {
    super.initState();
    if (event.date.isBefore(DateTime.now())) {
      _fetchMemoriesPreview();
    }
  }

  Future<void> _fetchMemoriesPreview() async {
    try {
      final response = await ApiService()
          .get('/bookings/events/${event.id}/memories');
      final data = response.data;
      if (mounted) {
        final list = (data is List ? data : []).cast<Map<String, dynamic>>();
        setState(() {
          _memoriesCount = list.length;
          _memoryPreviews = list.take(4).toList();
          _loadedMemories = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadedMemories = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Clickable community name
        if (event.communityName != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GestureDetector(
              onTap: () => context.push('/community/${event.communityId}'),
              child: Row(
                children: [
                  Icon(Icons.group_outlined, size: 14, color: AppTheme.primaryColor),
                  const SizedBox(width: 6),
                  Text(
                    event.communityName!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 16, color: AppTheme.primaryColor),
                ],
              ),
            ),
          ),
        // Hero image
        if (event.imageUrl != null && event.imageUrl!.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CachedNetworkImage(
              imageUrl: event.imageUrl!,
              width: double.infinity,
              height: 200,
              fit: BoxFit.cover,
            ),
          ),
        if (event.imageUrl != null && event.imageUrl!.isNotEmpty)
          const SizedBox(height: 20),

        // Description
        const Text(
          'About this event',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          event.description,
          style: TextStyle(fontSize: 14.5, color: Theme.of(context).textTheme.bodyLarge?.color, height: 1.6),
        ),

        // Meeting point (with Google Maps link)
        if (event.meetingPoint.isNotEmpty) ...[
          const SizedBox(height: 20),
          Builder(builder: (context) {
            final mp = event.meetingPoint;
            final hasUrl = mp.contains('|');
            final mpTitle = hasUrl ? mp.split('|')[0].trim() : mp;
            final mpUrl = hasUrl && mp.split('|').length > 1 ? mp.split('|')[1].trim() : '';
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return GestureDetector(
              onTap: mpUrl.isNotEmpty
                  ? () {
                      try {
                        launchUrl(Uri.parse(mpUrl), mode: LaunchMode.externalApplication);
                      } catch (_) {
                        Clipboard.setData(ClipboardData(text: mpUrl));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Link copied!')),
                        );
                      }
                    }
                  : null,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? Colors.blue.withOpacity(0.12) : Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? Colors.blue.withOpacity(0.3) : Colors.blue.shade100),
                ),
                child: Row(
                  children: [
                    Icon(Icons.pin_drop, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Meeting Point',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.blue[isDark ? 400 : 800]),
                          ),
                          const SizedBox(height: 2),
                          Text(mpTitle, style: TextStyle(fontSize: 13.5, color: Theme.of(context).textTheme.bodyLarge?.color)),
                          if (mpUrl.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.open_in_new, size: 12, color: Colors.blue[400]),
                                const SizedBox(width: 4),
                                Text('Open in Google Maps', style: TextStyle(fontSize: 12, color: Colors.blue[400])),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (mpUrl.isNotEmpty)
                      Icon(Icons.navigation_outlined, color: Colors.blue[400], size: 20),
                  ],
                ),
              ),
            );
          }),
        ],

        // Info cards
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _InfoCard(
                icon: Icons.calendar_today,
                iconColor: Colors.orange,
                title: DateFormat('MMM d, yyyy').format(event.date),
                subtitle: event.endDate != null
                    ? 'to ${DateFormat('MMM d').format(event.endDate!)}'
                    : DateFormat('hh:mm a').format(event.date),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _InfoCard(
                icon: Icons.currency_rupee,
                iconColor: Colors.green,
                title: event.price > 0
                    ? '\u20B9${event.price.toStringAsFixed(0)}'
                    : 'FREE',
                subtitle: 'Per person',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _InfoCard(
          icon: Icons.location_on,
          iconColor: Colors.red,
          title: event.location.isNotEmpty ? event.location : 'Location TBD',
          subtitle: 'Event location',
        ),

        // Venue map
        const SizedBox(height: 16),
        _VenueMapSection(
          venueLat: event.venueLat,
          venueLng: event.venueLng,
          locationName: event.location,
        ),

        // Enrollment progress
        if (event.slots > 0) ...[
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Enrollment',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              Text(
                '${event.participantsCount}/${event.slots} enrolled',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: event.participantsCount / event.slots,
              minHeight: 10,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(
                event.participantsCount / event.slots > 0.8
                    ? Colors.orange
                    : Colors.black,
              ),
            ),
          ),
        ],

        // Enrolled badge
        if (event.isJoined) ...[
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 22),
                SizedBox(width: 8),
                Text(
                  'You are enrolled!',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],

        // Event Memories section (past events only)
        if (event.date.isBefore(DateTime.now()) && _loadedMemories) ...[
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.photo_library, size: 20, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  Text(
                    'Memories',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  if (_memoriesCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_memoriesCount',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primaryColor),
                      ),
                    ),
                ],
              ),
              if (_memoriesCount > 0)
                GestureDetector(
                  onTap: () {
                    final encodedTitle = Uri.encodeComponent(event.title);
                    final canUpload = event.isJoined ? 'true' : 'false';
                    context.push('/event/${event.id}/memories?title=$encodedTitle&canUpload=$canUpload');
                  },
                  child: Row(
                    children: [
                      Text('View All', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primaryColor)),
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right, size: 18, color: AppTheme.primaryColor),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_memoryPreviews.isNotEmpty)
            SizedBox(
              height: 100,
              child: Row(
                children: [
                  ..._memoryPreviews.map((m) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: GestureDetector(
                        onTap: () {
                          final encodedTitle = Uri.encodeComponent(event.title);
                          final canUpload = event.isJoined ? 'true' : 'false';
                          context.push('/event/${event.id}/memories?title=$encodedTitle&canUpload=$canUpload');
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CachedNetworkImage(
                            imageUrl: m['media_url'] ?? '',
                            height: 100,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              color: Theme.of(context).colorScheme.surface,
                              child: const Icon(Icons.broken_image_outlined, size: 20),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )),
                  // Fill remaining slots if fewer than 4
                  ...List.generate(
                    (4 - _memoryPreviews.length).clamp(0, 4),
                    (_) => Expanded(child: Container()),
                  ),
                ],
              ),
            )
          else
            Center(
              child: Column(
                children: [
                  Icon(Icons.photo_library_outlined, size: 40, color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.3)),
                  const SizedBox(height: 8),
                  Text('No memories yet', style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color)),
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (event.isJoined)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final encodedTitle = Uri.encodeComponent(event.title);
                  context.push('/event/${event.id}/memories?title=$encodedTitle&canUpload=true');
                },
                icon: const Icon(Icons.add_photo_alternate, size: 18),
                label: const Text('Add Photos'),
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

        const SizedBox(height: 100),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Venue Map Section — shown in both Trip and Event detail tabs
// ─────────────────────────────────────────────────────────────────────────────
class _VenueMapSection extends StatelessWidget {
  final double venueLat;
  final double venueLng;
  final String locationName;

  const _VenueMapSection({
    required this.venueLat,
    required this.venueLng,
    required this.locationName,
  });

  bool get _hasCoords => venueLat != 0 && venueLng != 0;

  Future<void> _openDirections() async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$venueLat,$venueLng',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _openInMaps() async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$venueLat,$venueLng',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!_hasCoords) {
      // No pin yet — show placeholder tappable card
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.grey[100],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(Icons.location_off_outlined, color: Colors.grey[500], size: 22),
            const SizedBox(width: 12),
            Text(
              locationName.isNotEmpty ? locationName : 'Venue not pinned yet',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
          ],
        ),
      );
    }

    final venueLatLng = LatLng(venueLat, venueLng);

    return Column(
      children: [
        // Map preview
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          child: SizedBox(
            height: 200,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: venueLatLng,
                zoom: 15,
              ),
              markers: {
                Marker(
                  markerId: const MarkerId('venue'),
                  position: venueLatLng,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueRed),
                  infoWindow: InfoWindow(
                    title: 'Venue',
                    snippet: locationName,
                  ),
                ),
              },
              zoomControlsEnabled: false,
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false,
              onTap: (_) => _openInMaps(),
            ),
          ),
        ),

        // Action row below map
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(14)),
            border: Border.all(
                color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
          ),
          child: Row(
            children: [
              // Address
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              color: Colors.red, size: 16),
                          const SizedBox(width: 6),
                          const Text('Venue',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.red)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        locationName.isNotEmpty
                            ? locationName
                            : '${venueLat.toStringAsFixed(5)}, ${venueLng.toStringAsFixed(5)}',
                        style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).textTheme.bodyLarge?.color),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),

              // Directions button
              GestureDetector(
                onTap: _openDirections,
                child: Container(
                  margin: const EdgeInsets.all(10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.directions, color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text('Directions',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _InfoCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Members Tab ───────────────────────────────────────────────────

class _MembersTab extends StatelessWidget {
  final CommunityEvent event;
  final List<EventParticipant> participants;
  final bool isLoadingParticipants;

  const _MembersTab({
    required this.event,
    required this.participants,
    required this.isLoadingParticipants,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Enrolled Members (${participants.length})',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (isLoadingParticipants)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (participants.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.people_outline, size: 48, color: Colors.grey[300]),
                  const SizedBox(height: 8),
                  Text(
                    'No one has enrolled yet. Be the first!',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          )
        else
          ...participants.map(
            (participant) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                leading: CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: participant.userProfileImage != null &&
                          participant.userProfileImage!.isNotEmpty
                      ? CachedNetworkImageProvider(
                          participant.userProfileImage!)
                      : null,
                  child: participant.userProfileImage == null ||
                          participant.userProfileImage!.isEmpty
                      ? Text(
                          (participant.userName ?? '?')
                              .substring(0, 1)
                              .toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.black54,
                          ),
                        )
                      : null,
                ),
                title: Text(
                  participant.userName ?? 'Unknown',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
                trailing:
                    const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  context.push('/user/${participant.userId}');
                },
              ),
            ),
          ),
        const SizedBox(height: 100),
      ],
    );
  }
}

// ── Bottom Bar ────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final CommunityEvent event;
  final bool isFull;
  final bool isPast;
  final bool isJoining;
  final VoidCallback onJoin;
  final List<EventParticipant> participants;
  final String communityId;

  const _BottomBar({
    required this.event,
    required this.isFull,
    required this.isPast,
    required this.isJoining,
    required this.onJoin,
    this.participants = const [],
    required this.communityId,
  });

  @override
  Widget build(BuildContext context) {
    if (event.isJoined) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Enrolled badge
                Container(
                  width: double.infinity,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 20),
                      SizedBox(width: 8),
                      Text(
                        "You're Enrolled!",
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Action buttons row
                Row(
                  children: [
                    // View Members
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton.icon(
                          onPressed: () => _showMembersSheet(context),
                          icon: const Icon(Icons.people_outline, size: 18),
                          label: Text(
                            'Members (${participants.length})',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black87,
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Contact Admin
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: () => _contactAdmin(context),
                          icon: const Icon(Icons.chat_bubble_outline, size: 18),
                          label: const Text(
                            'Contact Admin',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              // Price column
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.price > 0
                        ? '\u20B9${event.price.toStringAsFixed(0)}'
                        : 'FREE',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'per person',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
              const SizedBox(width: 20),
              // Enroll button
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: (isFull || isPast || isJoining) ? null : onJoin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: isJoining
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            isPast
                                ? 'Event Ended'
                                : isFull
                                    ? 'Fully Booked'
                                    : event.isTrip
                                        ? 'Book a tour'
                                        : 'Enroll Now',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMembersSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Enrolled Members (${participants.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: participants.isEmpty
                  ? Center(
                      child: Text(
                        'No members yet',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: participants.length,
                      itemBuilder: (ctx, index) {
                        final p = participants[index];
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 22,
                            backgroundColor: Colors.grey[200],
                            backgroundImage: p.userProfileImage != null &&
                                    p.userProfileImage!.isNotEmpty
                                ? CachedNetworkImageProvider(p.userProfileImage!)
                                : null,
                            child: p.userProfileImage == null ||
                                    p.userProfileImage!.isEmpty
                                ? Text(
                                    (p.userName ?? '?')[0].toUpperCase(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : null,
                          ),
                          title: Text(
                            p.userName ?? 'Unknown',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: p.bookedAt != null
                              ? Text(
                                  'Enrolled ${DateFormat('MMM d').format(p.bookedAt!)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                )
                              : null,
                          trailing: IconButton(
                            icon: const Icon(Icons.chevron_right),
                            onPressed: () {
                              Navigator.pop(ctx);
                              GoRouter.of(context).push('/user/${p.userId}');
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _contactAdmin(BuildContext context) async {
    try {
      final response = await ApiService().get('/communities/$communityId');
      final adminId = response.data['created_by']?.toString();
      final adminName = response.data['creator_name']?.toString() ?? 'Admin';
      final adminPhone = response.data['admin_phone']?.toString();
      final adminImage = response.data['creator_image']?.toString();

      if (adminId == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Admin info not available')),
          );
        }
        return;
      }

      if (context.mounted) {
        showModalBottomSheet(
          context: context,
          useRootNavigator: true,
          backgroundColor: const Color(0xFF1A1A1A),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Contact Admin',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Admin info card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      children: [
                        // Profile photo
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: const Color(0xFF333333),
                          backgroundImage: (adminImage != null && adminImage.isNotEmpty)
                              ? CachedNetworkImageProvider(adminImage)
                              : null,
                          child: (adminImage == null || adminImage.isEmpty)
                              ? Text(
                                  adminName.isNotEmpty ? adminName[0].toUpperCase() : 'A',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                adminName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                'Community Admin',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white54,
                                ),
                              ),
                              if (adminPhone != null && adminPhone.isNotEmpty) ...[
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    const Icon(Icons.phone, size: 14, color: Colors.white38),
                                    const SizedBox(width: 4),
                                    Text(
                                      adminPhone,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.white60,
                                        fontWeight: FontWeight.w500,
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
                  const SizedBox(height: 16),
                  // Send Message button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        GoRouter.of(context).push('/chat/$adminId?name=${Uri.encodeComponent(adminName)}');
                      },
                      icon: const Icon(Icons.chat, color: Colors.black),
                      label: const Text(
                        'Send Message',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // View Profile button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        GoRouter.of(context).push('/user/$adminId');
                      },
                      icon: const Icon(Icons.person_outline, color: Colors.white),
                      label: const Text(
                        'View Profile',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load admin info: $e')),
        );
      }
    }
  }
}
