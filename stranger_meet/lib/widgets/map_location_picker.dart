import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';

import '../config/theme.dart';

const _kMapsApiKey = 'AIzaSyCRoRzp4kOtaSxQGKOBP4Ke8L1oe8Xn5zA';

/// Result returned when user confirms a location.
class PickedLocation {
  final LatLng latLng;
  final String address;

  const PickedLocation({required this.latLng, required this.address});
}

/// Full-screen Google Map that lets the user tap to pin a single location.
///
/// Usage:
/// ```dart
/// final result = await Navigator.of(context, rootNavigator: true).push<PickedLocation>(
///   MaterialPageRoute(builder: (_) => MapLocationPicker(title: 'Pick Pickup Point')),
/// );
/// if (result != null) { use result.latLng, result.address }
/// ```
class MapLocationPicker extends StatefulWidget {
  final String title;
  final String confirmLabel;
  final LatLng? initialLocation;
  /// Show a second fixed marker (e.g. event venue/drop point)
  final LatLng? dropMarker;
  final String dropMarkerLabel;

  const MapLocationPicker({
    super.key,
    this.title = 'Pick Location',
    this.confirmLabel = 'Confirm Location',
    this.initialLocation,
    this.dropMarker,
    this.dropMarkerLabel = 'Drop',
  });

  @override
  State<MapLocationPicker> createState() => _MapLocationPickerState();
}

class _MapLocationPickerState extends State<MapLocationPicker> {
  GoogleMapController? _mapController;
  LatLng? _pickedLatLng;
  String _pickedAddress = '';
  bool _loadingAddress = false;
  bool _loadingLocation = false;
  List<LatLng> _routePoints = [];

  // Default center — India
  static const _defaultCenter = LatLng(20.5937, 78.9629);

  @override
  void initState() {
    super.initState();
    if (widget.initialLocation != null) {
      _pickedLatLng = widget.initialLocation;
    }
    _goToCurrentLocation();
  }

  Future<void> _goToCurrentLocation() async {
    setState(() => _loadingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final latLng = LatLng(pos.latitude, pos.longitude);

      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 15));

      // Auto-pin current location only if no initial location given
      if (widget.initialLocation == null) {
        setState(() => _pickedLatLng = latLng);
        await _fetchAddress(latLng);
      }
    } catch (_) {
      // silently fail — user can still tap on map
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  Future<void> _fetchAddress(LatLng latLng) async {
    setState(() => _loadingAddress = true);
    try {
      // Use Google Geocoding API reverse geocode
      final dio = Dio();
      final res = await dio.get(
        'https://maps.googleapis.com/maps/api/geocode/json',
        queryParameters: {
          'latlng': '${latLng.latitude},${latLng.longitude}',
          'key': _kMapsApiKey,
        },
      );
      final results = res.data['results'] as List<dynamic>? ?? [];
      if (results.isNotEmpty) {
        setState(() => _pickedAddress = results[0]['formatted_address'] ?? '');
      }
    } catch (_) {
      setState(() => _pickedAddress =
          '${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}');
    } finally {
      if (mounted) setState(() => _loadingAddress = false);
    }
  }

  Future<void> _fetchRoute(LatLng origin, LatLng destination) async {
    try {
      final result = await PolylinePoints().getRouteBetweenCoordinates(
        googleApiKey: _kMapsApiKey,
        request: PolylineRequest(
          origin: PointLatLng(origin.latitude, origin.longitude),
          destination: PointLatLng(destination.latitude, destination.longitude),
          mode: TravelMode.driving,
        ),
      );
      if (result.points.isNotEmpty && mounted) {
        setState(() {
          _routePoints = result.points
              .map((p) => LatLng(p.latitude, p.longitude))
              .toList();
        });
      }
    } catch (_) {
      // silently fall back to straight line shown in _polylines getter
      if (mounted) setState(() => _routePoints = []);
    }
  }

  void _onMapTap(LatLng latLng) {
    setState(() {
      _pickedLatLng = latLng;
      _pickedAddress = '';
      _routePoints = [];
    });
    _fetchAddress(latLng);
    if (widget.dropMarker != null) {
      _fetchRoute(latLng, widget.dropMarker!);
    }
  }

  Set<Marker> get _markers {
    final markers = <Marker>{};
    if (_pickedLatLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('picked'),
        position: _pickedLatLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: 'Your pin', snippet: _pickedAddress),
      ));
    }
    if (widget.dropMarker != null) {
      markers.add(Marker(
        markerId: const MarkerId('drop'),
        position: widget.dropMarker!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: widget.dropMarkerLabel),
      ));
    }
    return markers;
  }

  Set<Polyline> get _polylines {
    if (_pickedLatLng == null || widget.dropMarker == null) return {};
    final points = _routePoints.isNotEmpty
        ? _routePoints
        : [_pickedLatLng!, widget.dropMarker!];
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: points,
        color: AppTheme.primaryColor,
        width: 4,
        // Only dash if it's a straight-line fallback
        patterns: _routePoints.isEmpty
            ? [PatternItem.dash(20), PatternItem.gap(10)]
            : [],
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.initialLocation ??
                  widget.dropMarker ??
                  _defaultCenter,
              zoom: widget.initialLocation != null || widget.dropMarker != null ? 13 : 5,
            ),
            onMapCreated: (c) => _mapController = c,
            onTap: _onMapTap,
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
            mapType: MapType.normal,
          ),

          // Top bar
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(8, MediaQuery.of(context).padding.top + 4, 8, 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (_loadingLocation)
                    const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                    ),
                ],
              ),
            ),
          ),

          // Current location button
          Positioned(
            right: 16,
            bottom: 140,
            child: FloatingActionButton.small(
              heroTag: 'myLocation',
              backgroundColor: Colors.white,
              onPressed: _goToCurrentLocation,
              child: const Icon(Icons.my_location, color: Colors.black, size: 20),
            ),
          ),

          // Instruction hint
          if (_pickedLatLng == null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 72,
              left: 24, right: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.touch_app, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text('Tap on the map to pin your location', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
            ),

          // Bottom confirm panel
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_pickedLatLng != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: AppTheme.primaryColor, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _loadingAddress
                              ? const Text('Getting address...', style: TextStyle(color: Colors.grey, fontSize: 13))
                              : Text(
                                  _pickedAddress.isNotEmpty
                                      ? _pickedAddress
                                      : '${_pickedLatLng!.latitude.toStringAsFixed(5)}, ${_pickedLatLng!.longitude.toStringAsFixed(5)}',
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text('No location selected', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _pickedLatLng == null
                          ? null
                          : () => Navigator.pop(
                                context,
                                PickedLocation(
                                  latLng: _pickedLatLng!,
                                  address: _pickedAddress.isNotEmpty
                                      ? _pickedAddress
                                      : '${_pickedLatLng!.latitude.toStringAsFixed(4)}, ${_pickedLatLng!.longitude.toStringAsFixed(4)}',
                                ),
                              ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        disabledBackgroundColor: Colors.grey[800],
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      child: Text(widget.confirmLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
