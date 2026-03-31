import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

import '../../config/theme.dart';
import '../../models/community.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

class ExploreState {
  final List<CommunityEvent> events;
  final bool isLoading;
  final String? error;

  const ExploreState({this.events = const [], this.isLoading = false, this.error});
  ExploreState copyWith({List<CommunityEvent>? events, bool? isLoading, String? error}) =>
      ExploreState(
        events: events ?? this.events,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class ExploreNotifier extends StateNotifier<ExploreState> {
  final ApiService _api;
  ExploreNotifier(this._api) : super(const ExploreState());

  Future<void> fetchEvents({
    String eventType = 'all',
    String location = '',
    String difficulty = '',
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _api.get('/communities/explore/all-events', queryParameters: {
        'event_type': eventType,
        if (location.isNotEmpty) 'location': location,
        if (difficulty.isNotEmpty) 'difficulty': difficulty,
        'limit': 50,
      });
      final data = response.data;
      final List<dynamic> results = data is List ? data : (data['results'] ?? []);
      final events = results.map((e) => CommunityEvent.fromJson(e)).toList();
      state = ExploreState(events: events);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final exploreProvider = StateNotifierProvider<ExploreNotifier, ExploreState>((ref) {
  return ExploreNotifier(ApiService());
});

// ── Screen ────────────────────────────────────────────────────────────────────

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _searchController = TextEditingController();
  String _selectedType = 'All';
  String _selectedLocation = 'All';
  String _selectedDifficulty = 'All';
  String _selectedPrice = 'All';
  String _sortBy = 'date'; // date, price_low, price_high, nearest
  int _activeFilterCount = 0;

  static const _typeFilters = ['All', 'Trips', 'Events'];

  String? _userCity;

  @override
  void initState() {
    super.initState();
    _detectUserLocation();
    Future.microtask(() => ref.read(exploreProvider.notifier).fetchEvents());
  }

  Future<void> _detectUserLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Fallback to IP-based
        await _detectViaIP();
        return;
      }

      // Check permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          await _detectViaIP();
          return;
        }
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 10),
      );

      // Reverse geocode to get city name
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty && mounted) {
        final place = placemarks.first;
        final city = place.locality ??
            place.subAdministrativeArea ??
            place.administrativeArea ??
            '';
        if (city.isNotEmpty) {
          setState(() {
            _userCity = city;
            if (_selectedLocation == 'All') {
              _selectedLocation = 'Nearby';
            }
          });
          _applyFilters();
          return;
        }
      }

      // Fallback if reverse geocoding returns nothing
      await _detectViaIP();
    } catch (_) {
      // Fallback to IP-based on any error
      await _detectViaIP();
    }
  }

  Future<void> _detectViaIP() async {
    try {
      final response = await Dio().get('https://ipapi.co/json/');
      final city = response.data['city']?.toString() ?? '';
      if (city.isNotEmpty && mounted) {
        setState(() {
          _userCity = city;
          if (_selectedLocation == 'All') {
            _selectedLocation = 'Nearby';
          }
        });
        _applyFilters();
      }
    } catch (_) {
      // Silently fail
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    String eventType = 'all';
    if (_selectedType == 'Trips') eventType = 'trip';
    if (_selectedType == 'Events') eventType = 'event';

    String location = '';
    if (_selectedLocation == 'Nearby' && _userCity != null) {
      location = _userCity!;
    } else if (_selectedLocation != 'All' && _selectedLocation != 'Nearby') {
      location = _selectedLocation;
    }

    // Count active filters
    int count = 0;
    if (_selectedType != 'All') count++;
    if (_selectedLocation != 'All') count++;
    if (_selectedDifficulty != 'All') count++;
    if (_selectedPrice != 'All') count++;
    if (_sortBy != 'date') count++;
    setState(() => _activeFilterCount = count);

    ref.read(exploreProvider.notifier).fetchEvents(
          eventType: eventType,
          location: location,
          difficulty: _selectedDifficulty == 'All' ? '' : _selectedDifficulty.toLowerCase(),
        );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final theme = Theme.of(ctx);
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.5,
              maxChildSize: 0.9,
              expand: false,
              builder: (ctx, scrollController) {
                return Column(
                  children: [
                    // Handle
                    Container(
                      width: 40, height: 4,
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
                    ),
                    // Title row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Row(
                        children: [
                          const Text('Filters', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setSheetState(() {
                                _selectedType = 'All';
                                _selectedLocation = 'All';
                                _selectedDifficulty = 'All';
                                _selectedPrice = 'All';
                                _sortBy = 'date';
                              });
                            },
                            child: Text('Reset', style: TextStyle(color: Colors.red[400])),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(20),
                        children: [
                          // Sort By
                          _filterSectionTitle('Sort by', theme),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8, runSpacing: 8,
                            children: [
                              _filterChip('Soonest', _sortBy == 'date', () => setSheetState(() => _sortBy = 'date'), theme),
                              _filterChip('Price: Low→High', _sortBy == 'price_low', () => setSheetState(() => _sortBy = 'price_low'), theme),
                              _filterChip('Price: High→Low', _sortBy == 'price_high', () => setSheetState(() => _sortBy = 'price_high'), theme),
                              if (_userCity != null)
                                _filterChip('Nearest', _sortBy == 'nearest', () => setSheetState(() => _sortBy = 'nearest'), theme),
                            ],
                          ),

                          const SizedBox(height: 24),

                          // Type
                          _filterSectionTitle('Type', theme),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8, runSpacing: 8,
                            children: _typeFilters.map((t) =>
                              _filterChip(t, _selectedType == t, () => setSheetState(() => _selectedType = t), theme),
                            ).toList(),
                          ),

                          const SizedBox(height: 24),

                          // Location
                          _filterSectionTitle('Location', theme),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8, runSpacing: 8,
                            children: [
                              _filterChip('All', _selectedLocation == 'All', () => setSheetState(() => _selectedLocation = 'All'), theme),
                              if (_userCity != null)
                                _filterChip('Nearby ($_userCity)', _selectedLocation == 'Nearby', () => setSheetState(() => _selectedLocation = 'Nearby'), theme),
                              ...['Chennai', 'Mumbai', 'Bangalore', 'Delhi', 'Goa', 'Manali', 'Kodaikanal', 'Pondicherry']
                                  .map((l) => _filterChip(l, _selectedLocation == l, () => setSheetState(() => _selectedLocation = l), theme)),
                            ],
                          ),

                          const SizedBox(height: 24),

                          // Price
                          _filterSectionTitle('Price', theme),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8, runSpacing: 8,
                            children: [
                              _filterChip('All', _selectedPrice == 'All', () => setSheetState(() => _selectedPrice = 'All'), theme),
                              _filterChip('Free', _selectedPrice == 'Free', () => setSheetState(() => _selectedPrice = 'Free'), theme),
                              _filterChip('Under \u20B91000', _selectedPrice == 'under1000', () => setSheetState(() => _selectedPrice = 'under1000'), theme),
                              _filterChip('\u20B91000-5000', _selectedPrice == '1000to5000', () => setSheetState(() => _selectedPrice = '1000to5000'), theme),
                              _filterChip('\u20B95000+', _selectedPrice == 'above5000', () => setSheetState(() => _selectedPrice = 'above5000'), theme),
                            ],
                          ),

                          const SizedBox(height: 24),

                          // Difficulty
                          _filterSectionTitle('Difficulty', theme),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8, runSpacing: 8,
                            children: ['All', 'Easy', 'Moderate', 'Hard'].map((d) =>
                              _filterChip(d, _selectedDifficulty == d, () => setSheetState(() => _selectedDifficulty = d), theme),
                            ).toList(),
                          ),

                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                    // Apply button
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: SafeArea(
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              setState(() {}); // Update parent
                              _applyFilters();
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _filterSectionTitle(String title, ThemeData theme) {
    return Text(
      title,
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: theme.textTheme.bodyLarge?.color),
    );
  }

  Widget _filterChip(String label, bool isSelected, VoidCallback onTap, ThemeData theme) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : theme.dividerColor,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.black : theme.textTheme.bodySmall?.color,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(exploreProvider);
    final user = ref.watch(currentUserProvider);
    final firstName = (user?.name ?? 'Explorer').split(' ').first;

    // Filter by search text + price locally
    final searchQuery = _searchController.text.trim().toLowerCase();
    var filteredEvents = state.events.where((e) {
      // Search filter
      if (searchQuery.isNotEmpty) {
        final matches = e.title.toLowerCase().contains(searchQuery) ||
            e.location.toLowerCase().contains(searchQuery) ||
            (e.communityName ?? '').toLowerCase().contains(searchQuery);
        if (!matches) return false;
      }
      // Price filter
      if (_selectedPrice == 'Free' && e.price > 0) return false;
      if (_selectedPrice == 'under1000' && (e.price <= 0 || e.price > 1000)) return false;
      if (_selectedPrice == '1000to5000' && (e.price < 1000 || e.price > 5000)) return false;
      if (_selectedPrice == 'above5000' && e.price < 5000) return false;
      return true;
    }).toList();

    // Sort
    if (_sortBy == 'price_low') {
      filteredEvents.sort((a, b) => a.price.compareTo(b.price));
    } else if (_sortBy == 'price_high') {
      filteredEvents.sort((a, b) => b.price.compareTo(a.price));
    } else if (_sortBy == 'nearest' && _userCity != null) {
      // Put events in user's city first
      final city = _userCity!.toLowerCase();
      filteredEvents.sort((a, b) {
        final aMatch = a.location.toLowerCase().contains(city) ? 0 : 1;
        final bMatch = b.location.toLowerCase().contains(city) ? 0 : 1;
        return aMatch.compareTo(bMatch);
      });
    } else {
      // Default: sort by date (soonest first)
      filteredEvents.sort((a, b) => a.date.compareTo(b.date));
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _applyFilters(),
          child: CustomScrollView(
            slivers: [
              // ── Header ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hello, $firstName \u{1F44B}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Welcome to StrangerMeet',
                              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => context.push('/profile'),
                        child: CircleAvatar(
                          radius: 24,
                          backgroundColor: Theme.of(context).colorScheme.surface,
                          backgroundImage:
                              user?.profileImageUrl != null && user!.profileImageUrl!.isNotEmpty
                                  ? CachedNetworkImageProvider(user.profileImageUrl!)
                                  : null,
                          child: user?.profileImageUrl == null || user!.profileImageUrl!.isEmpty
                              ? Text(
                                  firstName.isNotEmpty ? firstName[0].toUpperCase() : '?',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Search ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search trips, events, locations...',
                      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
                      prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                      filled: true,
                      fillColor: Theme.of(context).inputDecorationTheme.fillColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),

              // ── Section Title ──
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: Text(
                    'Select your next trip',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
              ),

              // ── Filter Bar ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      // Type chips (compact)
                      ..._typeFilters.map((f) {
                        final isSelected = _selectedType == f;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _selectedType = f);
                              _applyFilters();
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected ? AppTheme.primaryColor : Theme.of(context).dividerColor,
                                ),
                              ),
                              child: Text(
                                f,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  fontSize: 13,
                                  color: isSelected ? Colors.black : Theme.of(context).textTheme.bodySmall?.color,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                      const Spacer(),
                      // Filter button
                      GestureDetector(
                        onTap: _showFilterSheet,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: _activeFilterCount > 0
                                ? AppTheme.primaryColor.withOpacity(0.15)
                                : Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _activeFilterCount > 0
                                  ? AppTheme.primaryColor
                                  : Theme.of(context).dividerColor,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.tune, size: 16,
                                  color: _activeFilterCount > 0
                                      ? AppTheme.primaryColor
                                      : Theme.of(context).textTheme.bodySmall?.color),
                              const SizedBox(width: 4),
                              Text(
                                'Filter',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _activeFilterCount > 0
                                      ? AppTheme.primaryColor
                                      : Theme.of(context).textTheme.bodySmall?.color,
                                ),
                              ),
                              if (_activeFilterCount > 0) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: AppTheme.primaryColor,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '$_activeFilterCount',
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.black),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // ── Content ──
              if (state.isLoading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (filteredEvents.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.explore_off_outlined, size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text(
                          'No trips or events found',
                          style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedType = 'All';
                              _selectedLocation = 'All';
                              _searchController.clear();
                            });
                            _applyFilters();
                          },
                          child: const Text('Clear filters'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index >= filteredEvents.length) return null;
                        final event = filteredEvents[index];
                        return _EventCard(event: event);
                      },
                      childCount: filteredEvents.length,
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Event/Trip Card ──────────────────────────────────────────────────────────

class _EventCard extends StatefulWidget {
  final CommunityEvent event;

  const _EventCard({required this.event});

  @override
  State<_EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<_EventCard> {
  bool _isSaved = false;

  CommunityEvent get event => widget.event;

  @override
  void initState() {
    super.initState();
    _checkIfSaved();
  }

  Future<void> _checkIfSaved() async {
    try {
      final res = await ApiService().get('/bookings/saved/check/${event.id}');
      if (mounted) setState(() => _isSaved = res.data['is_saved'] == true);
    } catch (_) {}
  }

  Future<void> _toggleSave() async {
    final wasSaved = _isSaved;
    setState(() => _isSaved = !wasSaved);
    try {
      if (wasSaved) {
        await ApiService().delete('/bookings/saved/${event.id}');
      } else {
        await ApiService().post('/bookings/saved', data: {
          'item_id': event.id,
          'item_type': event.isTrip ? 'trip' : 'event',
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSaved = wasSaved);
    }
  }

  Color _difficultyColor(String d) {
    switch (d.toLowerCase()) {
      case 'easy':
        return Colors.green;
      case 'moderate':
        return Colors.orange;
      case 'hard':
      case 'difficult':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTrip = event.isTrip;
    final priceText = event.price <= 0 ? 'FREE' : '\u20B9${event.price.toStringAsFixed(0)}';
    final dateText = DateFormat('MMM d, yyyy').format(event.date);
    final spotsLeft = event.slots - event.participantsCount;

    return GestureDetector(
      onTap: () => context.push(
        '/community/${event.communityId}/event/${event.id}',
      ),
      child: Container(
        height: 300,
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              // ── Background Image ──
              Positioned.fill(
                child: event.imageUrl != null && event.imageUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: event.imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: Colors.grey[300],
                          child: const Center(child: Icon(Icons.landscape, size: 48, color: Colors.white54)),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.grey[400],
                          child: const Center(child: Icon(Icons.landscape, size: 48, color: Colors.white54)),
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.grey.shade500, Colors.grey.shade800],
                          ),
                        ),
                      ),
              ),

              // ── Gradient Overlay ──
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.1),
                        Colors.black.withOpacity(0.75),
                      ],
                      stops: const [0.3, 1.0],
                    ),
                  ),
                ),
              ),

              // ── Top Badges ──
              Positioned(
                top: 16,
                left: 16,
                child: Row(
                  children: [
                    // Type badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isTrip ? Colors.deepOrange : Colors.blue,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isTrip ? Icons.terrain : Icons.event,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isTrip ? 'Trip' : 'Event',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    if (isTrip) ...[
                      const SizedBox(width: 8),
                      // Duration badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          event.shortDurationLabel,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Difficulty badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _difficultyColor(event.difficulty).withOpacity(0.85),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          event.difficulty[0].toUpperCase() + event.difficulty.substring(1),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Bookmark Icon ──
              Positioned(
                top: 16,
                right: 16,
                child: GestureDetector(
                  onTap: _toggleSave,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isSaved ? Icons.bookmark : Icons.bookmark_border,
                      color: _isSaved ? AppTheme.primaryColor : Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),

              // ── Price Badge ──
              Positioned(
                top: 16,
                right: 64,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: event.price <= 0 ? Colors.green : AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    priceText,
                    style: TextStyle(
                      color: event.price <= 0 ? Colors.white : Colors.black,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),

              // ── Bottom Content ──
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Community name
                      if (event.communityName != null)
                        Text(
                          event.communityName!,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      const SizedBox(height: 4),
                      // Event title
                      Text(
                        event.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      // Info row
                      Row(
                        children: [
                          Icon(Icons.location_on, color: Colors.white.withOpacity(0.8), size: 15),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              event.location,
                              style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Icon(Icons.calendar_today, color: Colors.white.withOpacity(0.8), size: 13),
                          const SizedBox(width: 4),
                          Text(
                            dateText,
                            style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Spots + enrolled
                      Row(
                        children: [
                          Icon(Icons.people_outline, color: Colors.white.withOpacity(0.7), size: 15),
                          const SizedBox(width: 4),
                          Text(
                            '${event.participantsCount}/${event.slots} enrolled',
                            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13),
                          ),
                          if (spotsLeft > 0 && spotsLeft <= 5) ...[
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$spotsLeft spots left!',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                          const Spacer(),
                          if (isTrip && event.maxAltitude > 0)
                            Text(
                              '${event.maxAltitude.toStringAsFixed(0)}m',
                              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
