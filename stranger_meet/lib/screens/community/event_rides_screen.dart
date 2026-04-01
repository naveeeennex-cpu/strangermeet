import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class _RidePassenger {
  final String userId;
  final String userName;
  final String userImage;

  const _RidePassenger({
    required this.userId,
    required this.userName,
    required this.userImage,
  });

  factory _RidePassenger.fromJson(Map<String, dynamic> j) => _RidePassenger(
        userId: j['user_id'] ?? '',
        userName: j['user_name'] ?? 'Unknown',
        userImage: j['user_profile_image'] ?? '',
      );
}

class _Ride {
  final String id;
  final String userId;
  final String driverName;
  final String driverImage;
  final String vehicleType;
  final String vehicleModel;
  final String vehicleColor;
  final int totalSeats;
  final int availableSeats;
  final String startLocation;
  final DateTime startTime;
  final bool isFree;
  final double costPerPerson;
  final String notes;
  final bool isDriver;
  final bool isPassenger;
  final List<_RidePassenger> passengers;

  const _Ride({
    required this.id,
    required this.userId,
    required this.driverName,
    required this.driverImage,
    required this.vehicleType,
    required this.vehicleModel,
    required this.vehicleColor,
    required this.totalSeats,
    required this.availableSeats,
    required this.startLocation,
    required this.startTime,
    required this.isFree,
    required this.costPerPerson,
    required this.notes,
    required this.isDriver,
    required this.isPassenger,
    required this.passengers,
  });

  factory _Ride.fromJson(Map<String, dynamic> j) => _Ride(
        id: j['id'] ?? '',
        userId: j['user_id'] ?? '',
        driverName: j['driver_name'] ?? 'Unknown',
        driverImage: j['driver_image'] ?? '',
        vehicleType: j['vehicle_type'] ?? 'car',
        vehicleModel: j['vehicle_model'] ?? '',
        vehicleColor: j['vehicle_color'] ?? '',
        totalSeats: (j['total_seats'] as num?)?.toInt() ?? 1,
        availableSeats: (j['available_seats'] as num?)?.toInt() ?? 1,
        startLocation: j['start_location'] ?? '',
        startTime: DateTime.tryParse(j['start_time'] ?? '') ?? DateTime.now(),
        isFree: j['is_free'] ?? true,
        costPerPerson: (j['cost_per_person'] as num?)?.toDouble() ?? 0,
        notes: j['notes'] ?? '',
        isDriver: j['is_driver'] ?? false,
        isPassenger: j['is_passenger'] ?? false,
        passengers: (j['passengers'] as List<dynamic>? ?? [])
            .map((p) => _RidePassenger.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}

// ── Screen ─────────────────────────────────────────────────────────────────────

class EventRidesScreen extends StatefulWidget {
  final String communityId;
  final String eventId;
  final String eventTitle;
  final String meetingPoint;

  const EventRidesScreen({
    super.key,
    required this.communityId,
    required this.eventId,
    required this.eventTitle,
    required this.meetingPoint,
  });

  @override
  State<EventRidesScreen> createState() => _EventRidesScreenState();
}

class _EventRidesScreenState extends State<EventRidesScreen> {
  final _api = ApiService();
  List<_Ride> _rides = [];
  bool _loading = true;
  String? _currentUserId;
  bool _hasOwnRide = false;

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
      if (mounted) {
        setState(() {
          _rides = list;
          _hasOwnRide = list.any((r) => r.isDriver);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _joinRide(String rideId) async {
    try {
      await _api.post(
        '/communities/${widget.communityId}/events/${widget.eventId}/rides/$rideId/join',
      );
      await _loadRides();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _leaveRide(String rideId) async {
    try {
      await _api.delete(
        '/communities/${widget.communityId}/events/${widget.eventId}/rides/$rideId/leave',
      );
      await _loadRides();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _deleteRide(String rideId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete ride?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will remove your ride offer and notify your passengers.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _api.delete(
        '/communities/${widget.communityId}/events/${widget.eventId}/rides/$rideId',
      );
      await _loadRides();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
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
        onCreated: _loadRides,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ride Sharing', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            Text(widget.eventTitle, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadRides,
          ),
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
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _rides.length,
                    itemBuilder: (context, index) => _RideCard(
                      ride: _rides[index],
                      currentUserId: _currentUserId ?? '',
                      onJoin: () => _joinRide(_rides[index].id),
                      onLeave: () => _leaveRide(_rides[index].id),
                      onDelete: () => _deleteRide(_rides[index].id),
                      onTapPassenger: (userId, name) => context.push('/user/$userId?name=${Uri.encodeComponent(name)}'),
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.directions_car_outlined, size: 72, color: Colors.grey[700]),
          const SizedBox(height: 16),
          Text('No rides yet', style: TextStyle(color: Colors.grey[400], fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            'Be the first to offer a ride to\n${widget.meetingPoint.isNotEmpty ? widget.meetingPoint : 'the meeting point'}',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _openOfferRide,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            icon: const Icon(Icons.directions_car),
            label: const Text('Offer a Ride', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ── Ride Card ──────────────────────────────────────────────────────────────────

class _RideCard extends StatefulWidget {
  final _Ride ride;
  final String currentUserId;
  final VoidCallback onJoin;
  final VoidCallback onLeave;
  final VoidCallback onDelete;
  final void Function(String userId, String name) onTapPassenger;

  const _RideCard({
    required this.ride,
    required this.currentUserId,
    required this.onJoin,
    required this.onLeave,
    required this.onDelete,
    required this.onTapPassenger,
  });

  @override
  State<_RideCard> createState() => _RideCardState();
}

class _RideCardState extends State<_RideCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final isCarFull = ride.availableSeats <= 0;
    final timeStr = DateFormat('EEE, MMM d • h:mm a').format(ride.startTime.toLocal());
    final costStr = ride.isFree ? 'Free' : '₹${ride.costPerPerson.toStringAsFixed(0)}/person';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ride.isDriver
              ? AppTheme.primaryColor.withValues(alpha: 0.5)
              : ride.isPassenger
                  ? Colors.blue.withValues(alpha: 0.4)
                  : const Color(0xFF2A2A2A),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Driver row
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.3),
                      child: Text(
                        ride.driverName.isNotEmpty ? ride.driverName[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                ride.driverName,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                              ),
                              if (ride.isDriver) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text('You', style: TextStyle(color: AppTheme.primaryColor, fontSize: 11, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(ride.vehicleType == 'bike' ? Icons.two_wheeler : Icons.directions_car,
                                  size: 14, color: Colors.grey[500]),
                              const SizedBox(width: 4),
                              Text(
                                '${ride.vehicleType == 'bike' ? 'Bike' : 'Car'}${ride.vehicleModel.isNotEmpty ? ' • ${ride.vehicleModel}' : ''}${ride.vehicleColor.isNotEmpty ? ' • ${ride.vehicleColor}' : ''}',
                                style: TextStyle(color: Colors.grey[500], fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Cost badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: ride.isFree
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        costStr,
                        style: TextStyle(
                          color: ride.isFree ? Colors.green[400] : Colors.orange[400],
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Details row
                Row(
                  children: [
                    _DetailChip(icon: Icons.schedule, text: timeStr),
                    const SizedBox(width: 8),
                    _DetailChip(
                      icon: Icons.event_seat,
                      text: '${ride.availableSeats}/${ride.totalSeats} seats',
                      color: isCarFull ? Colors.red[400] : null,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _DetailChip(icon: Icons.location_on, text: ride.startLocation),

                if (ride.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(ride.notes, style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                ],

                const SizedBox(height: 14),

                // Passenger avatars
                if (ride.passengers.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Row(
                      children: [
                        ...ride.passengers.take(5).map((p) => Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: GestureDetector(
                                onTap: () => widget.onTapPassenger(p.userId, p.userName),
                                child: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: Colors.blueGrey[700],
                                  child: Text(p.userName.isNotEmpty ? p.userName[0].toUpperCase() : '?',
                                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                                ),
                              ),
                            )),
                        if (ride.passengers.length > 5)
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: const Color(0xFF2A2A2A),
                            child: Text('+${ride.passengers.length - 5}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                          ),
                        const SizedBox(width: 8),
                        Text(
                          '${ride.passengers.length} passenger${ride.passengers.length > 1 ? 's' : ''}',
                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                        ),
                        const Spacer(),
                        Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey[600], size: 20),
                      ],
                    ),
                  ),
                  if (_expanded)
                    Column(
                      children: ride.passengers
                          .map((p) => ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                leading: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: Colors.blueGrey[700],
                                  child: Text(p.userName.isNotEmpty ? p.userName[0].toUpperCase() : '?',
                                      style: const TextStyle(color: Colors.white, fontSize: 11)),
                                ),
                                title: Text(p.userName, style: const TextStyle(color: Colors.white, fontSize: 13)),
                                onTap: () => widget.onTapPassenger(p.userId, p.userName),
                              ))
                          .toList(),
                    ),
                ],

                const SizedBox(height: 12),

                // Action buttons
                Row(
                  children: [
                    if (ride.isDriver)
                      TextButton.icon(
                        onPressed: widget.onDelete,
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                        label: const Text('Remove', style: TextStyle(color: Colors.red, fontSize: 13)),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      )
                    else if (ride.isPassenger)
                      OutlinedButton(
                        onPressed: widget.onLeave,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: const Text('Leave', style: TextStyle(color: Colors.red, fontSize: 13)),
                      )
                    else ...[
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isCarFull ? null : widget.onJoin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isCarFull ? Colors.grey[800] : AppTheme.primaryColor,
                            foregroundColor: isCarFull ? Colors.grey : Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          child: Text(
                            isCarFull ? 'Full' : 'Join Ride',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ),
                      ),
                    ],
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

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _DetailChip({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color ?? Colors.grey[500]),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: TextStyle(color: color ?? Colors.grey[400], fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Offer Ride Bottom Sheet ────────────────────────────────────────────────────

class _OfferRideSheet extends StatefulWidget {
  final String communityId;
  final String eventId;
  final String meetingPoint;
  final VoidCallback onCreated;

  const _OfferRideSheet({
    required this.communityId,
    required this.eventId,
    required this.meetingPoint,
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
  DateTime _startTime = DateTime.now().add(const Duration(hours: 1));
  bool _isFree = true;
  double _cost = 0;
  final _costCtrl = TextEditingController(text: '0');
  final _notesCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _modelCtrl.dispose();
    _colorCtrl.dispose();
    _locationCtrl.dispose();
    _costCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
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
    setState(() {
      _startTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
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
          'start_time': _startTime.toUtc().toIso8601String(),
          'is_free': _isFree,
          'cost_per_person': _isFree ? 0 : _cost,
          'notes': _notesCtrl.text.trim(),
        },
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onCreated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
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
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Offer a Ride', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
              if (widget.meetingPoint.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Heading to: ${widget.meetingPoint}', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
              ],
              const SizedBox(height: 20),

              // Vehicle type
              const Text('Vehicle type', style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _TypeToggle(
                    icon: Icons.directions_car,
                    label: 'Car',
                    selected: _vehicleType == 'car',
                    onTap: () => setState(() => _vehicleType = 'car'),
                  ),
                  const SizedBox(width: 12),
                  _TypeToggle(
                    icon: Icons.two_wheeler,
                    label: 'Bike',
                    selected: _vehicleType == 'bike',
                    onTap: () => setState(() {
                      _vehicleType = 'bike';
                      if (_seats > 1) _seats = 1;
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Vehicle details
              Row(
                children: [
                  Expanded(
                    child: _SheetField(controller: _modelCtrl, hint: 'Model (e.g. Swift)', label: 'Model'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SheetField(controller: _colorCtrl, hint: 'Color', label: 'Color'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Seats
              if (_vehicleType == 'car') ...[
                const Text('Available seats', style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      onPressed: _seats > 1 ? () => setState(() => _seats--) : null,
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.white),
                    ),
                    Text('$_seats', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                    IconButton(
                      onPressed: _seats < 6 ? () => setState(() => _seats++) : null,
                      icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                    ),
                    const Spacer(),
                    Text('seat${_seats > 1 ? 's' : ''} for passengers', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Start location
              _SheetField(
                controller: _locationCtrl,
                hint: 'e.g. City Mall Bus Stop, MG Road',
                label: 'Pickup location',
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              // Departure time
              const Text('Departure time', style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickDateTime,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule, color: Colors.white, size: 18),
                      const SizedBox(width: 10),
                      Text(timeStr, style: const TextStyle(color: Colors.white, fontSize: 14)),
                      const Spacer(),
                      Icon(Icons.edit, color: Colors.grey[600], size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Cost
              const Text('Cost sharing', style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _TypeToggle(label: 'Free', selected: _isFree, onTap: () => setState(() => _isFree = true)),
                  const SizedBox(width: 12),
                  _TypeToggle(label: 'Fuel share', selected: !_isFree, onTap: () => setState(() => _isFree = false)),
                ],
              ),
              if (!_isFree) ...[
                const SizedBox(height: 12),
                _SheetField(
                  controller: _costCtrl,
                  hint: 'Amount per person (₹)',
                  label: 'Cost per person',
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _cost = double.tryParse(v) ?? 0,
                ),
              ],
              const SizedBox(height: 16),

              // Notes
              _SheetField(controller: _notesCtrl, hint: 'Any additional info...', label: 'Notes (optional)', maxLines: 2),
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

class _TypeToggle extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TypeToggle({this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryColor.withValues(alpha: 0.15) : const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.primaryColor : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: selected ? AppTheme.primaryColor : Colors.grey[400]),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? AppTheme.primaryColor : Colors.grey[400],
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String label;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;

  const _SheetField({
    required this.controller,
    required this.hint,
    required this.label,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          validator: validator,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
            filled: true,
            fillColor: const Color(0xFF2A2A2A),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}
