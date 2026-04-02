import 'dart:async';

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

class MapLocationPicker extends StatefulWidget {
  final String title;
  final String confirmLabel;
  final LatLng? initialLocation;
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

  // Search
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  List<_PlaceSuggestion> _suggestions = [];
  bool _searchLoading = false;
  Timer? _debounce;
  bool _showSuggestions = false;

  static const _defaultCenter = LatLng(20.5937, 78.9629);

  @override
  void initState() {
    super.initState();
    if (widget.initialLocation != null) {
      _pickedLatLng = widget.initialLocation;
    }
    _goToCurrentLocation();
    _searchFocus.addListener(() {
      if (!_searchFocus.hasFocus) {
        setState(() => _showSuggestions = false);
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── Places Autocomplete ─────────────────────────────────────────────────────

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() { _suggestions = []; _showSuggestions = false; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _fetchSuggestions(value));
  }

  Future<void> _fetchSuggestions(String input) async {
    setState(() => _searchLoading = true);
    try {
      final dio = Dio();
      // Try Places Autocomplete first
      final res = await dio.get(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json',
        queryParameters: {
          'input': input,
          'key': _kMapsApiKey,
          'language': 'en',
        },
      );
      final status = res.data['status'] as String? ?? '';
      final predictions = res.data['predictions'] as List<dynamic>? ?? [];

      if (status == 'OK' && predictions.isNotEmpty) {
        if (mounted) {
          setState(() {
            _suggestions = predictions.map((p) => _PlaceSuggestion(
              placeId: p['place_id'] ?? '',
              description: p['description'] ?? '',
              mainText: p['structured_formatting']?['main_text'] ?? p['description'] ?? '',
              secondaryText: p['structured_formatting']?['secondary_text'] ?? '',
            )).toList();
            _showSuggestions = true;
          });
        }
        return;
      }

      // Fallback: Geocoding API search (works without Places API enabled)
      final geo = await dio.get(
        'https://maps.googleapis.com/maps/api/geocode/json',
        queryParameters: {
          'address': input,
          'key': _kMapsApiKey,
          'language': 'en',
        },
      );
      final results = geo.data['results'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _suggestions = results.take(5).map((r) {
            final addr = r['formatted_address'] as String? ?? '';
            final parts = addr.split(',');
            return _PlaceSuggestion(
              placeId: '',
              description: addr,
              mainText: parts.isNotEmpty ? parts[0].trim() : addr,
              secondaryText: parts.length > 1 ? parts.sublist(1).join(',').trim() : '',
              latLng: r['geometry']?['location'] != null
                  ? LatLng(r['geometry']['location']['lat'], r['geometry']['location']['lng'])
                  : null,
            );
          }).toList();
          _showSuggestions = _suggestions.isNotEmpty;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _suggestions = []; _showSuggestions = false; });
    } finally {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  Future<void> _selectSuggestion(_PlaceSuggestion suggestion) async {
    _searchFocus.unfocus();
    _searchCtrl.text = suggestion.mainText;
    setState(() { _showSuggestions = false; _loadingAddress = true; });

    try {
      LatLng? latLng;
      String address = suggestion.description;

      if (suggestion.latLng != null) {
        // Geocoding fallback result — lat/lng already known
        latLng = suggestion.latLng;
      } else if (suggestion.placeId.isNotEmpty) {
        // Places API result — fetch coords via Place Details
        final dio = Dio();
        final res = await dio.get(
          'https://maps.googleapis.com/maps/api/place/details/json',
          queryParameters: {
            'place_id': suggestion.placeId,
            'fields': 'geometry,formatted_address',
            'key': _kMapsApiKey,
          },
        );
        final result = res.data['result'];
        if (result != null) {
          final loc = result['geometry']['location'];
          latLng = LatLng(loc['lat'], loc['lng']);
          address = result['formatted_address'] ?? suggestion.description;
        }
      }

      if (latLng != null && mounted) {
        setState(() {
          _pickedLatLng = latLng;
          _pickedAddress = address;
          _searchCtrl.text = address;
          _routePoints = [];
        });
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng!, 15));
        if (widget.dropMarker != null) {
          _fetchRoute(latLng!, widget.dropMarker!);
        }
      }
    } catch (_) {
      // silently ignore
    } finally {
      if (mounted) setState(() => _loadingAddress = false);
    }
  }

  // ── Location + geocoding ────────────────────────────────────────────────────

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

      if (widget.initialLocation == null) {
        setState(() => _pickedLatLng = latLng);
        await _fetchAddress(latLng);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  Future<void> _fetchAddress(LatLng latLng) async {
    setState(() => _loadingAddress = true);
    try {
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
        final addr = results[0]['formatted_address'] ?? '';
        setState(() {
          _pickedAddress = addr;
          if (_searchCtrl.text.isEmpty || _searchCtrl.text.contains(',')) {
            _searchCtrl.text = addr;
          }
        });
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
          _routePoints = result.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _routePoints = []);
    }
  }

  void _onMapTap(LatLng latLng) {
    _searchFocus.unfocus();
    setState(() {
      _pickedLatLng = latLng;
      _pickedAddress = '';
      _routePoints = [];
      _showSuggestions = false;
    });
    _fetchAddress(latLng);
    if (widget.dropMarker != null) {
      _fetchRoute(latLng, widget.dropMarker!);
    }
  }

  // ── Map data ────────────────────────────────────────────────────────────────

  Set<Marker> get _markers {
    final markers = <Marker>{};
    if (_pickedLatLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('picked'),
        position: _pickedLatLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: 'Selected', snippet: _pickedAddress),
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
        patterns: _routePoints.isEmpty ? [PatternItem.dash(20), PatternItem.gap(10)] : [],
      ),
    };
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // ── Google Map ────────────────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.initialLocation ?? widget.dropMarker ?? _defaultCenter,
              zoom: widget.initialLocation != null || widget.dropMarker != null ? 13 : 5,
            ),
            onMapCreated: (c) {
              _mapController = c;
              if (widget.initialLocation != null) {
                _mapController!.animateCamera(
                  CameraUpdate.newLatLngZoom(widget.initialLocation!, 15),
                );
              }
            },
            onTap: _onMapTap,
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
            mapType: MapType.normal,
            // Push map up so bottom panel doesn't cover markers
            padding: EdgeInsets.only(bottom: 150 + botPad),
          ),

          // ── Top bar + search ──────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              color: Colors.black,
              padding: EdgeInsets.fromLTRB(0, topPad, 0, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title row
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(widget.title,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                      ),
                      if (_loadingLocation || _loadingAddress)
                        const Padding(
                          padding: EdgeInsets.only(right: 16),
                          child: SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor)),
                        ),
                    ],
                  ),

                  // Search bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: const Color(0xFF333333)),
                      ),
                      child: Row(
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(left: 14),
                            child: Icon(Icons.search, color: Colors.grey, size: 20),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              focusNode: _searchFocus,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'Search place or address...',
                                hintStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                              ),
                              onChanged: _onSearchChanged,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (v) {
                                if (v.trim().isNotEmpty) _fetchSuggestions(v);
                              },
                            ),
                          ),
                          if (_searchLoading)
                            const Padding(
                              padding: EdgeInsets.only(right: 12),
                              child: SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor)),
                            )
                          else if (_searchCtrl.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.grey, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() { _suggestions = []; _showSuggestions = false; });
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Autocomplete dropdown ─────────────────────────────────────────
          if (_showSuggestions && _suggestions.isNotEmpty)
            Positioned(
              top: topPad + 110,
              left: 12, right: 12,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 280),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF333333)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 16)],
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: _suggestions.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: Color(0xFF2A2A2A)),
                    itemBuilder: (_, i) {
                      final s = _suggestions[i];
                      return InkWell(
                        onTap: () => _selectSuggestion(s),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.location_on,
                                    color: AppTheme.primaryColor, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.mainText,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    if (s.secondaryText.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(s.secondaryText,
                                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

          // ── My location FAB ───────────────────────────────────────────────
          Positioned(
            right: 16,
            bottom: 155 + botPad,
            child: FloatingActionButton.small(
              heroTag: 'myLocation',
              backgroundColor: Colors.white,
              onPressed: _goToCurrentLocation,
              child: const Icon(Icons.my_location, color: Colors.black, size: 20),
            ),
          ),

          // ── Bottom confirm panel ──────────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 16, 20, botPad + 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Selected address row
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: AppTheme.primaryColor, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _loadingAddress
                            ? Row(children: [
                                const SizedBox(width: 14, height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor)),
                                const SizedBox(width: 8),
                                Text('Getting address...', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                              ])
                            : _pickedLatLng == null
                                ? Text('Tap map or search to select', style: TextStyle(color: Colors.grey[500], fontSize: 13))
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
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _pickedLatLng == null || _loadingAddress
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
                      child: Text(widget.confirmLabel,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
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

// ── Internal model ─────────────────────────────────────────────────────────────

class _PlaceSuggestion {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;
  final LatLng? latLng; // set when result comes from Geocoding API fallback

  const _PlaceSuggestion({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
    this.latLng,
  });
}
