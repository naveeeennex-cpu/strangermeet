import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/map_location_picker.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class _RidePassenger {
  final String id;
  final String userId;
  final String userName;
  final String userImage;
  final String userPhone;
  final double pickupLat;
  final double pickupLng;
  final String pickupLocationName;
  final double calculatedFare;

  const _RidePassenger({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userImage,
    required this.userPhone,
    required this.pickupLat,
    required this.pickupLng,
    required this.pickupLocationName,
    required this.calculatedFare,
  });

  factory _RidePassenger.fromJson(Map<String, dynamic> j) => _RidePassenger(
        id: j['id'] ?? '',
        userId: j['user_id'] ?? '',
        userName: j['user_name'] ?? 'Unknown',
        userImage: j['user_profile_image'] ?? '',
        userPhone: j['user_phone'] ?? '',
        pickupLat: (j['pickup_lat'] as num?)?.toDouble() ?? 0,
        pickupLng: (j['pickup_lng'] as num?)?.toDouble() ?? 0,
        pickupLocationName: j['pickup_location_name'] ?? '',
        calculatedFare: (j['calculated_fare'] as num?)?.toDouble() ?? 0,
      );
}

class _Ride {
  final String id;
  final String userId;
  final String driverName;
  final String driverImage;
  final String driverPhone;
  final String vehicleType;
  final String vehicleModel;
  final String vehicleColor;
  final int totalSeats;
  final int availableSeats;
  final String startLocation;
  final double startLat;
  final double startLng;
  final double dropLat;
  final double dropLng;
  final DateTime startTime;
  final double ratePerKm;
  final double totalDistanceKm;
  final bool isFree;
  final String notes;
  final bool isDriver;
  final bool isPassenger;
  final double myFare;
  final List<_RidePassenger> passengers;
  final String routePolyline;

  const _Ride({
    required this.id,
    required this.userId,
    required this.driverName,
    required this.driverImage,
    required this.driverPhone,
    required this.vehicleType,
    required this.vehicleModel,
    required this.vehicleColor,
    required this.totalSeats,
    required this.availableSeats,
    required this.startLocation,
    required this.startLat,
    required this.startLng,
    required this.dropLat,
    required this.dropLng,
    required this.startTime,
    required this.ratePerKm,
    required this.totalDistanceKm,
    required this.isFree,
    required this.notes,
    required this.isDriver,
    required this.isPassenger,
    required this.myFare,
    required this.passengers,
    this.routePolyline = '',
  });

  factory _Ride.fromJson(Map<String, dynamic> j) => _Ride(
        id: j['id'] ?? '',
        userId: j['user_id'] ?? '',
        driverName: j['driver_name'] ?? 'Unknown',
        driverImage: j['driver_image'] ?? '',
        driverPhone: j['driver_phone'] ?? '',
        vehicleType: j['vehicle_type'] ?? 'car',
        vehicleModel: j['vehicle_model'] ?? '',
        vehicleColor: j['vehicle_color'] ?? '',
        totalSeats: (j['total_seats'] as num?)?.toInt() ?? 1,
        availableSeats: (j['available_seats'] as num?)?.toInt() ?? 1,
        startLocation: j['start_location'] ?? '',
        startLat: (j['start_lat'] as num?)?.toDouble() ?? 0,
        startLng: (j['start_lng'] as num?)?.toDouble() ?? 0,
        dropLat: (j['drop_lat'] as num?)?.toDouble() ?? 0,
        dropLng: (j['drop_lng'] as num?)?.toDouble() ?? 0,
        startTime: DateTime.tryParse(j['start_time'] ?? '') ?? DateTime.now(),
        ratePerKm: (j['rate_per_km'] as num?)?.toDouble() ?? 0,
        totalDistanceKm: (j['total_distance_km'] as num?)?.toDouble() ?? 0,
        isFree: j['is_free'] ?? true,
        notes: j['notes'] ?? '',
        isDriver: j['is_driver'] ?? false,
        isPassenger: j['is_passenger'] ?? false,
        myFare: (j['my_fare'] as num?)?.toDouble() ?? 0,
        passengers: (j['passengers'] as List<dynamic>? ?? [])
            .map((p) => _RidePassenger.fromJson(p as Map<String, dynamic>))
            .toList(),
        routePolyline: j['route_polyline'] ?? '',
      );

  bool get hasStartCoords => startLat != 0 && startLng != 0;
  bool get hasDropCoords => dropLat != 0 && dropLng != 0;

  /// Haversine distance in km (client-side preview)
  static double haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0;
    final phi1 = lat1 * pi / 180;
    final phi2 = lat2 * pi / 180;
    final dPhi = (lat2 - lat1) * pi / 180;
    final dLam = (lng2 - lng1) * pi / 180;
    final a = sin(dPhi / 2) * sin(dPhi / 2) +
        cos(phi1) * cos(phi2) * sin(dLam / 2) * sin(dLam / 2);
    return 2 * R * asin(sqrt(a));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────────────────────────────────────

class EventRidesScreen extends StatefulWidget {
  final String communityId;
  final String eventId;
  final String eventTitle;
  final String meetingPoint;
  final double venueLat;
  final double venueLng;

  const EventRidesScreen({
    super.key,
    required this.communityId,
    required this.eventId,
    required this.eventTitle,
    required this.meetingPoint,
    this.venueLat = 0,
    this.venueLng = 0,
  });

  bool get hasVenueCoords => venueLat != 0 && venueLng != 0;

  @override
  State<EventRidesScreen> createState() => _EventRidesScreenState();
}

class _EventRidesScreenState extends State<EventRidesScreen> {
  final _api = ApiService();
  List<_Ride> _rides = [];
  bool _loading = true;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _currentUserId = await StorageService().getUserId();
    await _loadRides();
  }

  Future<void> _loadRides() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get(
        '/communities/${widget.communityId}/events/${widget.eventId}/rides',
      );
      final list = (res.data as List<dynamic>)
          .map((e) => _Ride.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) setState(() { _rides = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _hasOwnRide => _rides.any((r) => r.isDriver);

  // ── Join with midpoint picker ───────────────────────────────────────────────
  Future<void> _joinRide(_Ride ride) async {
    LatLng? pickupLatLng;
    String pickupName = '';

    if (ride.hasDropCoords) {
      // Show map picker to choose midpoint
      final result = await Navigator.of(context, rootNavigator: true).push<PickedLocation>(
        MaterialPageRoute(
          builder: (_) => MapLocationPicker(
            title: 'Pin Your Pickup Point',
            confirmLabel: 'Join from Here',
            dropMarker: LatLng(ride.dropLat, ride.dropLng),
            dropMarkerLabel: 'Event Venue',
          ),
        ),
      );
      if (result == null) return; // user cancelled
      pickupLatLng = result.latLng;
      pickupName = result.address;

      // Preview fare before confirming
      if (ride.ratePerKm > 0 && mounted) {
        final dist = _Ride.haversineKm(pickupLatLng.latitude, pickupLatLng.longitude, ride.dropLat, ride.dropLng);
        final fare = (dist * ride.ratePerKm).roundToDouble();
        final confirm = await _showFareConfirmDialog(dist, fare, ride.ratePerKm, pickupName);
        if (confirm != true) return;
      }
    }

    try {
      await _api.post(
        '/communities/${widget.communityId}/events/${widget.eventId}/rides/${ride.id}/join',
        data: {
          'pickup_lat': pickupLatLng?.latitude ?? 0,
          'pickup_lng': pickupLatLng?.longitude ?? 0,
          'pickup_location_name': pickupName,
        },
      );
      await _loadRides();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<bool?> _showFareConfirmDialog(double distKm, double fare, double ratePerKm, String pickup) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Confirm Fare', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FareRow(label: 'Pickup', value: pickup, icon: Icons.location_on),
            const SizedBox(height: 8),
            _FareRow(label: 'Distance to venue', value: '${distKm.toStringAsFixed(1)} km', icon: Icons.straighten),
            _FareRow(label: 'Rate', value: '₹${ratePerKm.toStringAsFixed(0)}/km', icon: Icons.speed),
            const Divider(color: Color(0xFF333333), height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Your fare', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                Text('₹${fare.toStringAsFixed(0)}', style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w800, fontSize: 20)),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.black),
            child: const Text('Join Ride', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _leaveRide(String rideId) async {
    try {
      await _api.delete('/communities/${widget.communityId}/events/${widget.eventId}/rides/$rideId/leave');
      await _loadRides();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _deleteRide(String rideId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete ride?', style: TextStyle(color: Colors.white)),
        content: const Text('This will remove your ride offer.', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _api.delete('/communities/${widget.communityId}/events/${widget.eventId}/rides/$rideId');
      await _loadRides();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _openOfferRide() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OfferRideSheet(
        communityId: widget.communityId,
        eventId: widget.eventId,
        meetingPoint: widget.meetingPoint,
        venueLat: widget.venueLat,
        venueLng: widget.venueLng,
        onCreated: _loadRides,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ride Sharing', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            Text(widget.eventTitle, style: TextStyle(color: Colors.grey[500], fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _loadRides),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : _rides.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  color: AppTheme.primaryColor,
                  onRefresh: _loadRides,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                    itemCount: _rides.length,
                    itemBuilder: (ctx, i) => GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => _RideDetailScreen(
                            ride: _rides[i],
                            onJoin: () { Navigator.pop(context); _joinRide(_rides[i]); },
                            onLeave: () { Navigator.pop(context); _leaveRide(_rides[i].id); },
                            onDelete: () { Navigator.pop(context); _deleteRide(_rides[i].id); },
                            onTapUser: (uid, name) => context.push('/user/$uid'),
                          ),
                        ),
                      ),
                      child: _RideCard(
                        ride: _rides[i],
                        venueLat: widget.venueLat,
                        venueLng: widget.venueLng,
                        onJoin: () => _joinRide(_rides[i]),
                        onLeave: () => _leaveRide(_rides[i].id),
                        onDelete: () => _deleteRide(_rides[i].id),
                        onTapUser: (uid, name) => context.push('/user/$uid'),
                      ),
                    ),
                  ),
                ),
      floatingActionButton: _hasOwnRide
          ? null
          : FloatingActionButton.extended(
              onPressed: _openOfferRide,
              backgroundColor: AppTheme.primaryColor,
              icon: const Icon(Icons.directions_car, color: Colors.black),
              label: const Text('Offer a Ride', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.directions_car_outlined, size: 52, color: AppTheme.primaryColor),
            ),
            const SizedBox(height: 20),
            const Text('No rides yet', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Be the first to offer a ride to\n${widget.meetingPoint.isNotEmpty ? widget.meetingPoint : "the event venue"}',
              style: TextStyle(color: Colors.grey[500], fontSize: 14, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _openOfferRide,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Offer a Ride', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ride Card
// ─────────────────────────────────────────────────────────────────────────────

class _RideCard extends StatefulWidget {
  final _Ride ride;
  final double venueLat;
  final double venueLng;
  final VoidCallback onJoin;
  final VoidCallback onLeave;
  final VoidCallback onDelete;
  final void Function(String uid, String name) onTapUser;

  const _RideCard({
    required this.ride,
    required this.venueLat,
    required this.venueLng,
    required this.onJoin,
    required this.onLeave,
    required this.onDelete,
    required this.onTapUser,
  });

  @override
  State<_RideCard> createState() => _RideCardState();
}

class _RideCardState extends State<_RideCard> {
  bool _showPassengers = false;
  bool _showMap = false;

  _Ride get r => widget.ride;
  bool get isFull => r.availableSeats <= 0;

  void _callNumber(String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  void _copyPhone(String phone) {
    Clipboard.setData(ClipboardData(text: phone));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Phone number copied'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('EEE, d MMM • h:mm a').format(r.startTime.toLocal());
    final fareStr = r.isFree ? 'Free' : '₹${r.ratePerKm.toStringAsFixed(0)}/km';
    final distStr = r.totalDistanceKm > 0 ? '${r.totalDistanceKm.toStringAsFixed(1)} km' : null;

    Color borderColor = const Color(0xFF2A2A2A);
    if (r.isDriver) borderColor = AppTheme.primaryColor.withValues(alpha: 0.6);
    else if (r.isPassenger) borderColor = Colors.blue.withValues(alpha: 0.5);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        children: [
          // ── Map preview ───────────────────────────────────────────────────
          if (_showMap && r.hasStartCoords)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: SizedBox(
                height: 180,
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(
                      (r.startLat + (r.dropLat > 0 ? r.dropLat : r.startLat)) / 2,
                      (r.startLng + (r.dropLng > 0 ? r.dropLng : r.startLng)) / 2,
                    ),
                    zoom: 11,
                  ),
                  markers: {
                    Marker(
                      markerId: const MarkerId('start'),
                      position: LatLng(r.startLat, r.startLng),
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                      infoWindow: const InfoWindow(title: 'Start'),
                    ),
                    if (r.hasDropCoords)
                      Marker(
                        markerId: const MarkerId('drop'),
                        position: LatLng(r.dropLat, r.dropLng),
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                        infoWindow: const InfoWindow(title: 'Event Venue'),
                      ),
                    // Passenger pickup pins
                    ...r.passengers.where((p) => p.pickupLat != 0).map((p) => Marker(
                          markerId: MarkerId('pickup_${p.id}'),
                          position: LatLng(p.pickupLat, p.pickupLng),
                          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
                          infoWindow: InfoWindow(title: p.userName),
                        )),
                  },
                  polylines: r.hasDropCoords
                      ? () {
                          // Decode real road polyline if available, else straight line
                          List<LatLng> routePoints = [];
                          if (r.routePolyline.isNotEmpty) {
                            final decoded = PolylinePoints()
                                .decodePolyline(r.routePolyline);
                            routePoints = decoded
                                .map((p) => LatLng(p.latitude, p.longitude))
                                .toList();
                          }
                          if (routePoints.isEmpty) {
                            routePoints = [
                              LatLng(r.startLat, r.startLng),
                              LatLng(r.dropLat, r.dropLng),
                            ];
                          }
                          return {
                            Polyline(
                              polylineId: const PolylineId('route'),
                              points: routePoints,
                              color: AppTheme.primaryColor,
                              width: 4,
                            ),
                          };
                        }()
                      : {},
                  zoomControlsEnabled: false,
                  myLocationButtonEnabled: false,
                  mapToolbarEnabled: false,
                  liteModeEnabled: true,
                ),
              ),
            ),

          // ── Card content ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Driver row
                Row(
                  children: [
                    // Avatar
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                      child: Text(
                        r.driverName.isNotEmpty ? r.driverName[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(r.driverName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                            if (r.isDriver) ...[
                              const SizedBox(width: 6),
                              _Badge(label: 'You', color: AppTheme.primaryColor),
                            ],
                          ]),
                          Row(children: [
                            Icon(r.vehicleType == 'bike' ? Icons.two_wheeler : Icons.directions_car,
                                size: 13, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text(
                              [
                                r.vehicleType == 'bike' ? 'Bike' : 'Car',
                                if (r.vehicleModel.isNotEmpty) r.vehicleModel,
                                if (r.vehicleColor.isNotEmpty) r.vehicleColor,
                              ].join(' • '),
                              style: TextStyle(color: Colors.grey[500], fontSize: 12),
                            ),
                          ]),
                        ],
                      ),
                    ),
                    // Fare badge
                    _FareBadge(label: fareStr, isFree: r.isFree),
                  ],
                ),

                // Driver contact (shown to passengers and driver)
                if (r.driverPhone.isNotEmpty && (r.isDriver || r.isPassenger)) ...[
                  const SizedBox(height: 12),
                  _ContactRow(
                    label: r.isDriver ? 'Your number' : 'Driver',
                    phone: r.driverPhone,
                    onCall: () => _callNumber(r.driverPhone),
                    onCopy: () => _copyPhone(r.driverPhone),
                  ),
                ],

                const SizedBox(height: 14),
                // Details chips
                Wrap(
                  spacing: 8, runSpacing: 6,
                  children: [
                    _Chip(icon: Icons.schedule, label: timeStr),
                    _Chip(
                      icon: Icons.event_seat,
                      label: '${r.availableSeats}/${r.totalSeats} seats',
                      color: isFull ? Colors.red[400] : Colors.grey[400],
                    ),
                    if (distStr != null) _Chip(icon: Icons.route, label: distStr),
                    _Chip(icon: Icons.location_on, label: r.startLocation.isNotEmpty ? r.startLocation : 'Location pinned on map'),
                  ],
                ),

                if (r.notes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Icon(Icons.notes, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 6),
                    Expanded(child: Text(r.notes, style: TextStyle(color: Colors.grey[400], fontSize: 13))),
                  ]),
                ],

                // My fare (shown to passenger)
                if (r.isPassenger && r.myFare > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.currency_rupee, size: 14, color: AppTheme.primaryColor),
                        Text(
                          'Your fare: ₹${r.myFare.toStringAsFixed(0)}',
                          style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 14),
                // Bottom row: map toggle + passengers toggle + action
                Row(
                  children: [
                    if (r.hasStartCoords)
                      _IconChipButton(
                        icon: _showMap ? Icons.map : Icons.map_outlined,
                        label: _showMap ? 'Hide map' : 'View route',
                        onTap: () => setState(() => _showMap = !_showMap),
                        active: _showMap,
                      ),
                    if (r.passengers.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _IconChipButton(
                        icon: Icons.people_outline,
                        label: '${r.passengers.length} rider${r.passengers.length > 1 ? "s" : ""}',
                        onTap: () => setState(() => _showPassengers = !_showPassengers),
                        active: _showPassengers,
                      ),
                    ],
                    const Spacer(),
                    // Action button
                    if (r.isDriver)
                      TextButton.icon(
                        onPressed: widget.onDelete,
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                        label: const Text('Remove', style: TextStyle(color: Colors.red, fontSize: 13)),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      )
                    else if (r.isPassenger)
                      OutlinedButton(
                        onPressed: widget.onLeave,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Leave', style: TextStyle(color: Colors.red, fontSize: 13)),
                      )
                    else
                      ElevatedButton(
                        onPressed: isFull ? null : widget.onJoin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isFull ? Colors.grey[800] : AppTheme.primaryColor,
                          foregroundColor: isFull ? Colors.grey : Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(isFull ? 'Full' : 'Join Ride',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      ),
                  ],
                ),

                // Passengers list
                if (_showPassengers && r.passengers.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(color: Color(0xFF2A2A2A)),
                  const SizedBox(height: 4),
                  ...r.passengers.map((p) => _PassengerTile(
                        passenger: p,
                        isDriver: r.isDriver,
                        onTap: () => widget.onTapUser(p.userId, p.userName),
                        onCall: () => _callNumber(p.userPhone),
                        onCopy: () => _copyPhone(p.userPhone),
                      )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Passenger tile
// ─────────────────────────────────────────────────────────────────────────────

class _PassengerTile extends StatelessWidget {
  final _RidePassenger passenger;
  final bool isDriver;
  final VoidCallback onTap;
  final VoidCallback onCall;
  final VoidCallback onCopy;

  const _PassengerTile({
    required this.passenger,
    required this.isDriver,
    required this.onTap,
    required this.onCall,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.blueGrey[800],
              child: Text(passenger.userName.isNotEmpty ? passenger.userName[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(passenger.userName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  if (passenger.pickupLocationName.isNotEmpty)
                    Text('📍 ${passenger.pickupLocationName}',
                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (passenger.calculatedFare > 0)
              Text('₹${passenger.calculatedFare.toStringAsFixed(0)}',
                  style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w700, fontSize: 13)),
            // Show passenger phone to driver only
            if (isDriver && passenger.userPhone.isNotEmpty) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.call, size: 18, color: Colors.green),
                onPressed: onCall,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Offer Ride Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _OfferRideSheet extends StatefulWidget {
  final String communityId;
  final String eventId;
  final String meetingPoint;
  final double venueLat;
  final double venueLng;
  final VoidCallback onCreated;

  const _OfferRideSheet({
    required this.communityId,
    required this.eventId,
    required this.meetingPoint,
    required this.venueLat,
    required this.venueLng,
    required this.onCreated,
  });

  @override
  State<_OfferRideSheet> createState() => _OfferRideSheetState();
}

class _OfferRideSheetState extends State<_OfferRideSheet> {
  final _formKey = GlobalKey<FormState>();
  final _api = ApiService();

  String _vehicleType = 'car';
  final _modelCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  int _seats = 2;
  final _locationCtrl = TextEditingController();
  double _startLat = 0;
  double _startLng = 0;
  DateTime _startTime = DateTime.now().add(const Duration(hours: 1));
  bool _isFree = true;
  double _ratePerKm = 0;
  final _rateCtrl = TextEditingController(text: '0');
  final _notesCtrl = TextEditingController();
  bool _submitting = false;

  // Calculated live preview
  double get _previewDistance {
    if (_startLat == 0 || _startLng == 0 || widget.venueLat == 0 || widget.venueLng == 0) return 0;
    return _Ride.haversineKm(_startLat, _startLng, widget.venueLat, widget.venueLng);
  }
  double get _previewTotalFare => _isFree ? 0 : (_previewDistance * _ratePerKm);

  @override
  void dispose() {
    _modelCtrl.dispose();
    _colorCtrl.dispose();
    _locationCtrl.dispose();
    _rateCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStartLocation() async {
    final dropMarker = (widget.venueLat != 0 && widget.venueLng != 0)
        ? LatLng(widget.venueLat, widget.venueLng)
        : null;

    final result = await Navigator.of(context, rootNavigator: true).push<PickedLocation>(
      MaterialPageRoute(
        builder: (_) => MapLocationPicker(
          title: 'Pin Your Start Location',
          confirmLabel: 'Set as Start',
          dropMarker: dropMarker,
          dropMarkerLabel: 'Event Venue',
          initialLocation: _startLat != 0 ? LatLng(_startLat, _startLng) : null,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      _startLat = result.latLng.latitude;
      _startLng = result.latLng.longitude;
      _locationCtrl.text = result.address;
    });
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(data: ThemeData.dark(), child: child!),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startTime),
      builder: (ctx, child) => Theme(data: ThemeData.dark(), child: child!),
    );
    if (time == null || !mounted) return;
    setState(() => _startTime = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_locationCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please pin your start location on the map')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await _api.post(
        '/communities/${widget.communityId}/events/${widget.eventId}/rides',
        data: {
          'vehicle_type': _vehicleType,
          'vehicle_model': _modelCtrl.text.trim(),
          'vehicle_color': _colorCtrl.text.trim(),
          'total_seats': _seats,
          'start_location': _locationCtrl.text.trim(),
          'start_lat': _startLat,
          'start_lng': _startLng,
          'start_time': _startTime.toUtc().toIso8601String(),
          'rate_per_km': _isFree ? 0.0 : _ratePerKm,
          'notes': _notesCtrl.text.trim(),
        },
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onCreated();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('EEE, MMM d • h:mm a').format(_startTime);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              const Text('Offer a Ride', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
              if (widget.meetingPoint.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.flag, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Heading to: ${widget.meetingPoint}', style: TextStyle(color: Colors.grey[500], fontSize: 13))),
                ]),
              ],
              const SizedBox(height: 20),

              // Vehicle type
              const _SectionLabel('Vehicle type'),
              const SizedBox(height: 8),
              Row(children: [
                _TypeToggle(icon: Icons.directions_car, label: 'Car', selected: _vehicleType == 'car',
                    onTap: () => setState(() => _vehicleType = 'car')),
                const SizedBox(width: 12),
                _TypeToggle(icon: Icons.two_wheeler, label: 'Bike', selected: _vehicleType == 'bike',
                    onTap: () => setState(() { _vehicleType = 'bike'; if (_seats > 1) _seats = 1; })),
              ]),
              const SizedBox(height: 16),

              Row(children: [
                Expanded(child: _SheetField(controller: _modelCtrl, hint: 'e.g. Swift', label: 'Model')),
                const SizedBox(width: 12),
                Expanded(child: _SheetField(controller: _colorCtrl, hint: 'e.g. White', label: 'Color')),
              ]),
              const SizedBox(height: 16),

              // Seats (car only)
              if (_vehicleType == 'car') ...[
                const _SectionLabel('Available seats'),
                const SizedBox(height: 8),
                Row(children: [
                  IconButton(onPressed: _seats > 1 ? () => setState(() => _seats--) : null,
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.white)),
                  Text('$_seats', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                  IconButton(onPressed: _seats < 6 ? () => setState(() => _seats++) : null,
                      icon: const Icon(Icons.add_circle_outline, color: Colors.white)),
                  const Spacer(),
                  Text('passenger seat${_seats > 1 ? "s" : ""}', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                ]),
                const SizedBox(height: 16),
              ],

              // Start location — map pin
              const _SectionLabel('Start location'),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickStartLocation,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(12),
                    border: _startLat != 0
                        ? Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.5))
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.location_on,
                          color: _startLat != 0 ? AppTheme.primaryColor : Colors.grey[600], size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _locationCtrl.text.isNotEmpty ? _locationCtrl.text : 'Tap to pin on map',
                          style: TextStyle(
                            color: _locationCtrl.text.isNotEmpty ? Colors.white : Colors.grey[600],
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.map, color: Colors.grey[600], size: 18),
                    ],
                  ),
                ),
              ),

              // Live distance + fare preview
              if (_startLat != 0 && widget.venueLat != 0 && _previewDistance > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.route, size: 14, color: Colors.green),
                      const SizedBox(width: 6),
                      Text('Distance to venue: ${_previewDistance.toStringAsFixed(1)} km',
                          style: const TextStyle(color: Colors.green, fontSize: 13)),
                      if (!_isFree && _previewTotalFare > 0) ...[
                        const Text('  •  ', style: TextStyle(color: Colors.green)),
                        Text('Total: ₹${_previewTotalFare.toStringAsFixed(0)}',
                            style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w700, fontSize: 13)),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // Departure time
              const _SectionLabel('Departure time'),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickDateTime,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    const Icon(Icons.schedule, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Text(timeStr, style: const TextStyle(color: Colors.white, fontSize: 14)),
                    const Spacer(),
                    Icon(Icons.edit, color: Colors.grey[600], size: 16),
                  ]),
                ),
              ),
              const SizedBox(height: 16),

              // Cost
              const _SectionLabel('Fuel sharing'),
              const SizedBox(height: 8),
              Row(children: [
                _TypeToggle(label: 'Free', selected: _isFree, onTap: () => setState(() => _isFree = true)),
                const SizedBox(width: 12),
                _TypeToggle(label: 'Paid (₹/km)', selected: !_isFree, onTap: () => setState(() => _isFree = false)),
              ]),
              if (!_isFree) ...[
                const SizedBox(height: 12),
                _SheetField(
                  controller: _rateCtrl,
                  hint: 'e.g. 8',
                  label: 'Rate per km (₹)',
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setState(() => _ratePerKm = double.tryParse(v) ?? 0),
                ),
              ],
              const SizedBox(height: 16),

              _SheetField(controller: _notesCtrl, hint: 'Any extra info...', label: 'Notes (optional)', maxLines: 2),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                  child: _submitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Text('Post Ride Offer', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
        child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

class _FareBadge extends StatelessWidget {
  final String label;
  final bool isFree;
  const _FareBadge({required this.label, required this.isFree});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: (isFree ? Colors.green : Colors.orange).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            style: TextStyle(
                color: isFree ? Colors.green[400] : Colors.orange[400],
                fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _Chip({required this.icon, required this.label, this.color});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color ?? Colors.grey[600]),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(color: color ?? Colors.grey[400], fontSize: 12)),
        ],
      );
}

class _IconChipButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  const _IconChipButton({required this.icon, required this.label, required this.onTap, this.active = false});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? AppTheme.primaryColor.withValues(alpha: 0.15) : const Color(0xFF242424),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? AppTheme.primaryColor.withValues(alpha: 0.4) : Colors.transparent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: active ? AppTheme.primaryColor : Colors.grey[400]),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: active ? AppTheme.primaryColor : Colors.grey[400], fontSize: 12)),
            ],
          ),
        ),
      );
}

class _ContactRow extends StatelessWidget {
  final String label;
  final String phone;
  final VoidCallback onCall;
  final VoidCallback onCopy;
  const _ContactRow({required this.label, required this.phone, required this.onCall, required this.onCopy});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFF222222), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(Icons.phone, size: 15, color: Colors.green[400]),
            const SizedBox(width: 8),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                Text(phone, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            )),
            IconButton(icon: Icon(Icons.call, size: 18, color: Colors.green[400]), onPressed: onCall,
                padding: EdgeInsets.zero, constraints: const BoxConstraints()),
            const SizedBox(width: 8),
            IconButton(icon: Icon(Icons.copy, size: 16, color: Colors.grey[500]), onPressed: onCopy,
                padding: EdgeInsets.zero, constraints: const BoxConstraints()),
          ],
        ),
      );
}

class _FareRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _FareRow({required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(icon, size: 15, color: Colors.grey[500]),
          const SizedBox(width: 8),
          Text('$label: ', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis)),
        ]),
      );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500));
}

class _TypeToggle extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TypeToggle({this.icon, required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primaryColor.withValues(alpha: 0.15) : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? AppTheme.primaryColor : Colors.transparent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 15, color: selected ? AppTheme.primaryColor : Colors.grey[400]), const SizedBox(width: 6)],
              Text(label, style: TextStyle(color: selected ? AppTheme.primaryColor : Colors.grey[400],
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal, fontSize: 14)),
            ],
          ),
        ),
      );
}

class _SheetField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String label;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  const _SheetField({required this.controller, required this.hint, required this.label,
      this.maxLines = 1, this.keyboardType, this.validator, this.onChanged});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller, maxLines: maxLines, keyboardType: keyboardType,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            validator: validator, onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hint, hintStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
              filled: true, fillColor: const Color(0xFF2A2A2A),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Ride Detail Screen (Uber/Ola style full-page)
// ─────────────────────────────────────────────────────────────────────────────

class _RideDetailScreen extends StatefulWidget {
  final _Ride ride;
  final VoidCallback onJoin;
  final VoidCallback onLeave;
  final VoidCallback onDelete;
  final void Function(String uid, String name) onTapUser;

  const _RideDetailScreen({
    required this.ride,
    required this.onJoin,
    required this.onLeave,
    required this.onDelete,
    required this.onTapUser,
  });

  @override
  State<_RideDetailScreen> createState() => _RideDetailScreenState();
}

class _RideDetailScreenState extends State<_RideDetailScreen> {
  _Ride get r => widget.ride;

  void _callNumber(String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  void _copyPhone(String phone) {
    Clipboard.setData(ClipboardData(text: phone));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Phone number copied'),
          duration: Duration(seconds: 2)),
    );
  }

  Set<Polyline> _buildPolylines() {
    if (!r.hasDropCoords) return {};
    List<LatLng> routePoints = [];
    if (r.routePolyline.isNotEmpty) {
      final decoded = PolylinePoints().decodePolyline(r.routePolyline);
      routePoints =
          decoded.map((p) => LatLng(p.latitude, p.longitude)).toList();
    }
    if (routePoints.isEmpty) {
      routePoints = [
        LatLng(r.startLat, r.startLng),
        LatLng(r.dropLat, r.dropLng),
      ];
    }
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: routePoints,
        color: Colors.green,
        width: 5,
      ),
    };
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    if (r.hasStartCoords) {
      markers.add(Marker(
        markerId: const MarkerId('start'),
        position: LatLng(r.startLat, r.startLng),
        icon:
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Pickup'),
      ));
    }
    if (r.hasDropCoords) {
      markers.add(Marker(
        markerId: const MarkerId('drop'),
        position: LatLng(r.dropLat, r.dropLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Event Venue'),
      ));
    }
    for (final p in r.passengers.where((p) => p.pickupLat != 0)) {
      markers.add(Marker(
        markerId: MarkerId('pickup_${p.id}'),
        position: LatLng(p.pickupLat, p.pickupLng),
        icon:
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: InfoWindow(title: p.userName),
      ));
    }
    return markers;
  }

  LatLng get _mapCenter {
    final lat =
        (r.startLat + (r.dropLat > 0 ? r.dropLat : r.startLat)) / 2;
    final lng =
        (r.startLng + (r.dropLng > 0 ? r.dropLng : r.startLng)) / 2;
    return LatLng(lat, lng);
  }

  @override
  Widget build(BuildContext context) {
    final isFull = r.availableSeats <= 0;
    final timeStr = DateFormat('EEE d MMM \u2022 h:mm a')
        .format(r.startTime.toLocal());

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
          // ── Full-screen map ─────────────────────────────────────────────
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _mapCenter,
                zoom: 11,
              ),
              markers: _buildMarkers(),
              polylines: _buildPolylines(),
              zoomControlsEnabled: false,
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),

          // ── Back button ─────────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: CircleAvatar(
              backgroundColor: Colors.black87,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),

          // ── Bottom draggable sheet ──────────────────────────────────────
          DraggableScrollableSheet(
            initialChildSize: 0.45,
            minChildSize: 0.35,
            maxChildSize: 0.90,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF111111),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey[700],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // ── Driver row ────────────────────────────────────────
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor:
                              AppTheme.primaryColor.withOpacity(0.2),
                          child: Text(
                            r.driverName.isNotEmpty
                                ? r.driverName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 20),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Text(r.driverName,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 17)),
                                if (r.isDriver) ...[
                                  const SizedBox(width: 6),
                                  _Badge(label: 'You', color: Colors.green),
                                ],
                              ]),
                              Row(children: [
                                Icon(
                                  r.vehicleType == 'bike'
                                      ? Icons.two_wheeler
                                      : Icons.directions_car,
                                  size: 13,
                                  color: Colors.grey[500],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  [
                                    r.vehicleType == 'bike' ? 'Bike' : 'Car',
                                    if (r.vehicleModel.isNotEmpty)
                                      r.vehicleModel,
                                    if (r.vehicleColor.isNotEmpty)
                                      r.vehicleColor,
                                  ].join(' \u00b7 '),
                                  style: TextStyle(
                                      color: Colors.grey[500], fontSize: 12),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        const Spacer(),
                        // Fare badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.15),
                            border: Border.all(color: Colors.green),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: r.isFree
                              ? const Text('FREE',
                                  style: TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold))
                              : Text(
                                  '\u20b9${r.ratePerKm.toStringAsFixed(0)}/km',
                                  style: const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),

                    const Divider(height: 28, color: Color(0xFF2A2A2A)),

                    // ── Route section ─────────────────────────────────────
                    const Text('Route',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.radio_button_checked,
                            color: AppTheme.primaryColor, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Pickup',
                                  style: TextStyle(
                                      color: Colors.grey[500], fontSize: 12)),
                              Text(
                                r.startLocation.isNotEmpty
                                    ? r.startLocation
                                    : 'Pinned on map',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      width: 2,
                      height: 24,
                      color: AppTheme.primaryColor.withOpacity(0.4),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on,
                            color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Event Venue',
                                  style: TextStyle(
                                      color: Colors.grey[500], fontSize: 12)),
                              Text(
                                r.totalDistanceKm > 0
                                    ? '${r.totalDistanceKm.toStringAsFixed(1)} km road distance'
                                    : 'Destination',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ── Stats chips ───────────────────────────────────────
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Chip(icon: Icons.schedule, label: timeStr),
                        _Chip(
                          icon: Icons.event_seat,
                          label: '${r.availableSeats}/${r.totalSeats} seats',
                          color: isFull ? Colors.red[400] : Colors.grey[400],
                        ),
                        if (r.totalDistanceKm > 0)
                          _Chip(
                              icon: Icons.route,
                              label:
                                  '${r.totalDistanceKm.toStringAsFixed(1)} km'),
                        if (!r.isFree)
                          _Chip(
                              icon: Icons.currency_rupee,
                              label:
                                  '\u20b9${r.ratePerKm.toStringAsFixed(0)}/km'),
                      ],
                    ),

                    // ── My fare (passenger) ───────────────────────────────
                    if (r.isPassenger && r.myFare > 0) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.1),
                          border: Border.all(
                              color: AppTheme.primaryColor.withOpacity(0.4)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.currency_rupee,
                                color: AppTheme.primaryColor, size: 16),
                            Text(
                              'Your fare: \u20b9${r.myFare.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  color: AppTheme.primaryColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ── Driver contact ────────────────────────────────────
                    if (r.driverPhone.isNotEmpty &&
                        (r.isDriver || r.isPassenger)) ...[
                      const Divider(height: 28),
                      const Text('Contact',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                      const SizedBox(height: 8),
                      _ContactRow(
                        label: r.isDriver ? 'Your number' : 'Driver',
                        phone: r.driverPhone,
                        onCall: () => _callNumber(r.driverPhone),
                        onCopy: () => _copyPhone(r.driverPhone),
                      ),
                    ],

                    // ── Passengers ────────────────────────────────────────
                    if (r.passengers.isNotEmpty) ...[
                      const Divider(height: 28),
                      Row(
                        children: [
                          const Text('Passengers',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15)),
                          const Spacer(),
                          Text('${r.passengers.length} riders',
                              style: TextStyle(
                                  color: Colors.grey[500], fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...r.passengers.map((p) => _PassengerTile(
                            passenger: p,
                            isDriver: r.isDriver,
                            onTap: () =>
                                widget.onTapUser(p.userId, p.userName),
                            onCall: () => _callNumber(p.userPhone),
                            onCopy: () => _copyPhone(p.userPhone),
                          )),
                    ],

                    // ── Notes ─────────────────────────────────────────────
                    if (r.notes.isNotEmpty) ...[
                      const Divider(height: 28),
                      Row(
                        children: [
                          Icon(Icons.notes,
                              size: 16, color: Colors.grey[500]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(r.notes,
                                style: TextStyle(
                                    color: Colors.grey[400], fontSize: 14)),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 16),

                    // ── Action button ─────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: r.isDriver
                          ? OutlinedButton.icon(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              label: const Text('Remove My Ride',
                                  style: TextStyle(color: Colors.red)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.red),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(28)),
                              ),
                              onPressed: widget.onDelete,
                            )
                          : r.isPassenger
                              ? OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    side:
                                        const BorderSide(color: Colors.red),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(28)),
                                  ),
                                  onPressed: widget.onLeave,
                                  child: const Text('Leave Ride',
                                      style: TextStyle(color: Colors.red)),
                                )
                              : isFull
                                  ? ElevatedButton(
                                      onPressed: null,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.grey[800],
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 14),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(28)),
                                      ),
                                      child: const Text('Ride Full'),
                                    )
                                  : ElevatedButton(
                                      onPressed: widget.onJoin,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 14),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(28)),
                                      ),
                                      child: const Text('Join This Ride',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16)),
                                    ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
