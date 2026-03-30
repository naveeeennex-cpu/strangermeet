import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../config/theme.dart';
import '../../providers/admin_provider.dart';
import '../../services/api_service.dart';

class CreateTripScreen extends ConsumerStatefulWidget {
  final String communityId;
  final String? eventId;
  final String eventType;

  const CreateTripScreen({
    super.key,
    required this.communityId,
    this.eventId,
    this.eventType = 'trip',
  });

  bool get isEditing => eventId != null;

  @override
  ConsumerState<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends ConsumerState<CreateTripScreen> {
  final _formKey = GlobalKey<FormState>();
  int _currentStep = 0;
  bool _isSubmitting = false;
  bool _isLoadingEvent = false;

  // Step 1: Basic Details
  String _selectedEventType = 'trip';
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _meetingPointController = TextEditingController();
  final _meetingPointUrlController = TextEditingController();
  String? _coverImageUrl;
  bool _isUploadingCover = false;

  // Step 2: Schedule & Pricing
  DateTime _startDate = DateTime.now().add(const Duration(days: 7));
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  DateTime? _endDate;
  final _durationController = TextEditingController(text: '1');
  final _priceController = TextEditingController(text: '0');
  final _slotsController = TextEditingController(text: '30');
  bool _isFreeEntry = true;
  String _difficulty = 'Easy';
  final _maxAltitudeController = TextEditingController();
  final _totalDistanceController = TextEditingController();

  // Step 3: Itinerary
  List<_ItineraryDayData> _itineraryDays = [];

  // Step 4: Includes/Excludes
  List<String> _includedItems = ['Transport', 'Meals', 'Accommodation', 'Guide'];
  List<String> _excludedItems = ['Personal expenses', 'Travel insurance'];

  bool get _isTrip => _selectedEventType == 'trip';

  @override
  void initState() {
    super.initState();
    _selectedEventType = widget.eventType;
    if (widget.isEditing) {
      _loadExistingEvent();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _meetingPointController.dispose();
    _meetingPointUrlController.dispose();
    _durationController.dispose();
    _priceController.dispose();
    _slotsController.dispose();
    _maxAltitudeController.dispose();
    _totalDistanceController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingEvent() async {
    setState(() => _isLoadingEvent = true);
    try {
      final response = await ApiService().get(
        '/communities/${widget.communityId}/events/${widget.eventId}',
      );
      final event = response.data as Map<String, dynamic>;

      _selectedEventType = event['event_type'] ?? 'trip';
      _titleController.text = event['title'] ?? '';
      _descriptionController.text = event['description'] ?? '';
      _locationController.text = event['location'] ?? '';
      final mp = event['meeting_point'] ?? '';
      if (mp.contains('|')) {
        final parts = mp.split('|');
        _meetingPointController.text = parts[0].trim();
        _meetingPointUrlController.text = parts.length > 1 ? parts[1].trim() : '';
      } else {
        _meetingPointController.text = mp;
      }
      _coverImageUrl = event['image_url'];
      final price = (event['price'] ?? 0).toDouble();
      _priceController.text = price.toString();
      _isFreeEntry = price <= 0;
      _slotsController.text = (event['slots'] ?? 30).toString();
      _difficulty = event['difficulty'] ?? 'Easy';
      _durationController.text = (event['duration_days'] ?? 1).toString();
      _maxAltitudeController.text =
          (event['max_altitude'] ?? 0) > 0 ? event['max_altitude'].toString() : '';
      _totalDistanceController.text =
          (event['total_distance'] ?? 0) > 0 ? event['total_distance'].toString() : '';

      final date = DateTime.tryParse(event['date'] ?? '');
      if (date != null) {
        _startDate = date;
        _startTime = TimeOfDay.fromDateTime(date);
      }
      final endDateStr = event['end_date']?.toString();
      if (endDateStr != null && endDateStr.isNotEmpty) {
        _endDate = DateTime.tryParse(endDateStr);
      }

      // Load includes/excludes
      if (event['includes'] != null && (event['includes'] as List).isNotEmpty) {
        _includedItems = List<String>.from(event['includes']);
      }
      if (event['excludes'] != null && (event['excludes'] as List).isNotEmpty) {
        _excludedItems = List<String>.from(event['excludes']);
      }

      // Load itinerary
      if (_isTrip) {
        try {
          final itineraryResponse = await ApiService().get(
            '/communities/${widget.communityId}/events/${widget.eventId}/itinerary',
          );
          final List<dynamic> days =
              itineraryResponse.data is List ? itineraryResponse.data : [];
          _itineraryDays = days.map((d) {
            final activities = List<String>.from(d['activities'] ?? []);
            return _ItineraryDayData(
              id: d['id']?.toString(),
              titleController: TextEditingController(text: d['title'] ?? ''),
              descriptionController:
                  TextEditingController(text: d['description'] ?? ''),
              morningController: TextEditingController(
                  text: activities.isNotEmpty ? activities[0] : ''),
              afternoonController: TextEditingController(
                  text: activities.length > 1 ? activities[1] : ''),
              eveningController: TextEditingController(
                  text: activities.length > 2 ? activities[2] : ''),
              accommodationController:
                  TextEditingController(text: d['accommodation'] ?? ''),
              elevationController: TextEditingController(
                  text: (d['elevation_m'] ?? 0) > 0
                      ? d['elevation_m'].toString()
                      : ''),
              distanceController: TextEditingController(
                  text: (d['distance_km'] ?? 0) > 0
                      ? d['distance_km'].toString()
                      : ''),
              imageUrl: d['image_url'],
            );
          }).toList();
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load event: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingEvent = false);
    }
  }

  Future<String?> _pickAndUploadImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (picked == null) return null;

      final FormData formData;
      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes,
              filename: picked.name),
          'folder': 'events',
        });
      } else {
        formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(picked.path,
              filename: picked.name),
          'folder': 'events',
        });
      }

      final response =
          await ApiService().uploadFile('/upload/image', formData: formData);
      return response.data['url']?.toString();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image upload failed: $e')),
        );
      }
      return null;
    }
  }

  void _recalculateDuration() {
    if (_endDate != null) {
      final days = _endDate!.difference(_startDate).inDays + 1;
      if (days > 0) {
        _durationController.text = days.toString();
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final startDateTime = DateTime(
        _startDate.year,
        _startDate.month,
        _startDate.day,
        _startTime.hour,
        _startTime.minute,
      );

      final data = <String, dynamic>{
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'location': _locationController.text.trim(),
        'date': startDateTime.toUtc().toIso8601String(),
        'price': _isFreeEntry ? 0.0 : (double.tryParse(_priceController.text) ?? 0),
        'slots': int.tryParse(_slotsController.text) ?? 0,
        'image_url': _coverImageUrl ?? '',
        'event_type': _selectedEventType,
      };

      if (_isTrip) {
        final mpTitle = _meetingPointController.text.trim();
        final mpUrl = _meetingPointUrlController.text.trim();
        data['meeting_point'] = mpUrl.isNotEmpty ? '$mpTitle|$mpUrl' : mpTitle;
        data['duration_days'] = int.tryParse(_durationController.text) ?? 1;
        data['difficulty'] = _difficulty.toLowerCase();
        data['max_altitude'] =
            double.tryParse(_maxAltitudeController.text) ?? 0;
        data['total_distance'] =
            double.tryParse(_totalDistanceController.text) ?? 0;
        data['includes'] = _includedItems.where((s) => s.trim().isNotEmpty).toList();
        data['excludes'] = _excludedItems.where((s) => s.trim().isNotEmpty).toList();
        if (_endDate != null) {
          data['end_date'] = _endDate!.toUtc().toIso8601String();
        }
      }

      String? createdEventId;

      if (widget.isEditing) {
        await ref
            .read(adminCommunitiesProvider.notifier)
            .updateEvent(widget.communityId, widget.eventId!, data);
        createdEventId = widget.eventId;
      } else {
        final response = await ApiService().post(
          '/communities/${widget.communityId}/events',
          data: data,
        );
        createdEventId = response.data['id']?.toString() ??
            response.data['_id']?.toString();
      }

      // Save itinerary days for trips
      if (_isTrip && createdEventId != null && _itineraryDays.isNotEmpty) {
        for (int i = 0; i < _itineraryDays.length; i++) {
          final day = _itineraryDays[i];
          final activities = <String>[
            day.morningController.text.trim(),
            day.afternoonController.text.trim(),
            day.eveningController.text.trim(),
          ].where((s) => s.isNotEmpty).toList();

          final itineraryData = {
            'day_number': i + 1,
            'title': day.titleController.text.trim(),
            'description': day.descriptionController.text.trim(),
            'activities': activities,
            'accommodation': day.accommodationController.text.trim(),
            'elevation_m':
                double.tryParse(day.elevationController.text) ?? 0,
            'distance_km':
                double.tryParse(day.distanceController.text) ?? 0,
            if (day.imageUrl != null) 'image_url': day.imageUrl,
          };

          if (day.id != null) {
            // Update existing day
            await ApiService().put(
              '/communities/${widget.communityId}/events/$createdEventId/itinerary/${day.id}',
              data: itineraryData,
            );
          } else {
            // Create new day
            await ApiService().post(
              '/communities/${widget.communityId}/events/$createdEventId/itinerary',
              data: itineraryData,
            );
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isEditing
                ? '${_isTrip ? "Trip" : "Event"} updated successfully!'
                : '${_isTrip ? "Trip" : "Event"} created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoadingEvent) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final steps = <_StepInfo>[
      _StepInfo(title: 'Basic Details', icon: Icons.info_outline),
      _StepInfo(title: 'Schedule & Pricing', icon: Icons.calendar_month),
      if (_isTrip) _StepInfo(title: 'Itinerary', icon: Icons.map_outlined),
      if (_isTrip)
        _StepInfo(title: "What's Included", icon: Icons.checklist),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing
            ? 'Edit ${_isTrip ? "Trip" : "Event"}'
            : 'Create ${_isTrip ? "Trip" : "Event"}'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Step indicator
            _buildStepIndicator(steps, theme),
            // Step content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildCurrentStep(theme),
              ),
            ),
            // Bottom bar
            _buildBottomBar(steps, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator(List<_StepInfo> steps, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: List.generate(steps.length, (index) {
          final isActive = index == _currentStep;
          final isCompleted = index < _currentStep;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (index < _currentStep) {
                  setState(() => _currentStep = index);
                }
              },
              child: Row(
                children: [
                  if (index > 0)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: isCompleted
                            ? AppTheme.primaryColor
                            : theme.dividerColor,
                      ),
                    ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive
                          ? AppTheme.primaryColor
                          : isCompleted
                              ? AppTheme.primaryColor.withOpacity(0.3)
                              : theme.colorScheme.surface,
                      border: Border.all(
                        color: isActive || isCompleted
                            ? AppTheme.primaryColor
                            : theme.dividerColor,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: isCompleted
                          ? const Icon(Icons.check, size: 16, color: Colors.black)
                          : Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isActive
                                    ? Colors.black
                                    : theme.textTheme.bodySmall?.color,
                              ),
                            ),
                    ),
                  ),
                  if (index < steps.length - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: isCompleted
                            ? AppTheme.primaryColor
                            : theme.dividerColor,
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStep(ThemeData theme) {
    // Map the step index to the correct step depending on whether it's a trip
    if (_currentStep == 0) return _buildBasicDetailsStep(theme);
    if (_currentStep == 1) return _buildSchedulePricingStep(theme);
    if (_isTrip && _currentStep == 2) return _buildItineraryStep(theme);
    if (_isTrip && _currentStep == 3) return _buildIncludesStep(theme);
    return const SizedBox.shrink();
  }

  // =========================================================================
  // STEP 1: Basic Details
  // =========================================================================
  Widget _buildBasicDetailsStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Type', theme),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _EventTypeChip(
                label: 'Event',
                icon: Icons.event,
                isSelected: _selectedEventType == 'event',
                onTap: () => setState(() => _selectedEventType = 'event'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _EventTypeChip(
                label: 'Trip',
                icon: Icons.terrain,
                isSelected: _selectedEventType == 'trip',
                onTap: () => setState(() => _selectedEventType = 'trip'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Cover Image
        _sectionHeader('Cover Image', theme),
        const SizedBox(height: 8),
        _buildImagePicker(
          imageUrl: _coverImageUrl,
          isUploading: _isUploadingCover,
          onPick: () async {
            setState(() => _isUploadingCover = true);
            final url = await _pickAndUploadImage();
            if (mounted) {
              setState(() {
                _coverImageUrl = url ?? _coverImageUrl;
                _isUploadingCover = false;
              });
            }
          },
          onRemove: () => setState(() => _coverImageUrl = null),
          height: 200,
        ),
        const SizedBox(height: 24),

        _sectionHeader('Title', theme),
        const SizedBox(height: 8),
        TextFormField(
          controller: _titleController,
          decoration: const InputDecoration(
            hintText: 'Enter title',
            prefixIcon: Icon(Icons.title),
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Title is required' : null,
        ),
        const SizedBox(height: 20),

        _sectionHeader('Description', theme),
        const SizedBox(height: 8),
        TextFormField(
          controller: _descriptionController,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Describe the event or trip...',
            prefixIcon: Padding(
              padding: EdgeInsets.only(bottom: 72),
              child: Icon(Icons.description_outlined),
            ),
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Description is required' : null,
        ),
        const SizedBox(height: 20),

        _sectionHeader('Location', theme),
        const SizedBox(height: 8),
        TextFormField(
          controller: _locationController,
          decoration: const InputDecoration(
            hintText: 'Event location',
            prefixIcon: Icon(Icons.location_on_outlined),
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Location is required' : null,
        ),

        if (_isTrip) ...[
          const SizedBox(height: 20),
          _sectionHeader('Meeting Point', theme),
          const SizedBox(height: 8),
          TextFormField(
            controller: _meetingPointController,
            decoration: const InputDecoration(
              hintText: 'e.g., Koyambedu Bus Stand - 6:00 AM',
              prefixIcon: Icon(Icons.pin_drop_outlined),
              labelText: 'Location Name & Time',
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _meetingPointUrlController,
            decoration: InputDecoration(
              hintText: 'https://maps.google.com/...',
              prefixIcon: const Icon(Icons.map_outlined),
              labelText: 'Google Maps Link (optional)',
              suffixIcon: _meetingPointUrlController.text.isNotEmpty
                  ? Icon(Icons.open_in_new, size: 18, color: Colors.blue[400])
                  : null,
            ),
          ),
        ],
      ],
    );
  }

  // =========================================================================
  // STEP 2: Schedule & Pricing
  // =========================================================================
  Widget _buildSchedulePricingStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Start Date & Time', theme),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildDateSelector(
                label: 'Start Date',
                date: _startDate,
                onPick: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _startDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (picked != null) {
                    setState(() {
                      _startDate = picked;
                      _recalculateDuration();
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTimeSelector(
                label: 'Start Time',
                time: _startTime,
                onPick: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _startTime,
                  );
                  if (picked != null) {
                    setState(() => _startTime = picked);
                  }
                },
              ),
            ),
          ],
        ),

        if (_isTrip) ...[
          const SizedBox(height: 20),
          _sectionHeader('End Date', theme),
          const SizedBox(height: 8),
          _buildDateSelector(
            label: _endDate != null
                ? DateFormat('MMM d, yyyy').format(_endDate!)
                : 'Select End Date',
            date: _endDate,
            onPick: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _endDate ?? _startDate.add(const Duration(days: 1)),
                firstDate: _startDate,
                lastDate: _startDate.add(const Duration(days: 30)),
              );
              if (picked != null) {
                setState(() {
                  _endDate = picked;
                  _recalculateDuration();
                });
              }
            },
          ),
          const SizedBox(height: 20),
          _sectionHeader('Duration (Days)', theme),
          const SizedBox(height: 8),
          TextFormField(
            controller: _durationController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: 'Number of days',
              prefixIcon: Icon(Icons.timelapse),
            ),
          ),
        ],

        const SizedBox(height: 20),
        _sectionHeader('Pricing & Capacity', theme),
        const SizedBox(height: 8),
        // Free entry toggle
        Container(
          decoration: BoxDecoration(
            color: _isFreeEntry
                ? Colors.green.withOpacity(0.1)
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFreeEntry ? Colors.green : theme.dividerColor,
            ),
          ),
          child: CheckboxListTile(
            value: _isFreeEntry,
            onChanged: (val) {
              setState(() {
                _isFreeEntry = val ?? false;
                if (_isFreeEntry) {
                  _priceController.text = '0';
                }
              });
            },
            title: Text(
              'Free Entry',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: _isFreeEntry ? Colors.green[700] : theme.textTheme.bodyLarge?.color,
              ),
            ),
            subtitle: Text(
              _isFreeEntry ? 'This event is free for everyone' : 'Set a price per person',
              style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
            ),
            secondary: Icon(
              _isFreeEntry ? Icons.celebration : Icons.currency_rupee,
              color: _isFreeEntry ? Colors.green : theme.textTheme.bodySmall?.color,
            ),
            activeColor: Colors.green,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                enabled: !_isFreeEntry,
                decoration: InputDecoration(
                  hintText: _isFreeEntry ? 'FREE' : 'Price',
                  prefixIcon: const Icon(Icons.currency_rupee),
                  prefixText: '\u20B9 ',
                  filled: _isFreeEntry,
                  fillColor: _isFreeEntry ? theme.colorScheme.surface.withOpacity(0.5) : null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _slotsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Total Slots',
                  prefixIcon: Icon(Icons.people_outline),
                ),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'Enter valid slots';
                  return null;
                },
              ),
            ),
          ],
        ),

        if (_isTrip) ...[
          const SizedBox(height: 20),
          _sectionHeader('Trip Details', theme),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _difficulty,
            decoration: const InputDecoration(
              labelText: 'Difficulty',
              prefixIcon: Icon(Icons.trending_up),
            ),
            items: ['Easy', 'Moderate', 'Hard']
                .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _difficulty = v);
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _maxAltitudeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Max Altitude',
                    labelText: 'Max Altitude (m)',
                    prefixIcon: Icon(Icons.height),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _totalDistanceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Total Distance',
                    labelText: 'Distance (km)',
                    prefixIcon: Icon(Icons.straighten),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // =========================================================================
  // STEP 3: Itinerary
  // =========================================================================
  Widget _buildItineraryStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionHeader(
                'Day-wise Itinerary (${_itineraryDays.length} days)', theme),
            FilledButton.tonalIcon(
              onPressed: () {
                setState(() {
                  _itineraryDays.add(_ItineraryDayData(
                    titleController: TextEditingController(),
                    descriptionController: TextEditingController(),
                    morningController: TextEditingController(),
                    afternoonController: TextEditingController(),
                    eveningController: TextEditingController(),
                    accommodationController: TextEditingController(),
                    elevationController: TextEditingController(),
                    distanceController: TextEditingController(),
                  ));
                });
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Day'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (_itineraryDays.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Column(
              children: [
                Icon(Icons.map_outlined,
                    size: 48, color: theme.textTheme.bodySmall?.color),
                const SizedBox(height: 12),
                Text(
                  'No itinerary days added yet',
                  style: TextStyle(color: theme.textTheme.bodySmall?.color),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap "Add Day" to start building your trip itinerary',
                  style: TextStyle(
                      color: theme.textTheme.bodySmall?.color, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

        ...List.generate(_itineraryDays.length, (index) {
          return _buildItineraryDayCard(index, theme);
        }),
      ],
    );
  }

  Widget _buildItineraryDayCard(int index, ThemeData theme) {
    final day = _itineraryDays[index];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: () {
              setState(() => day.isExpanded = !day.isExpanded);
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.08),
                borderRadius: day.isExpanded
                    ? const BorderRadius.vertical(top: Radius.circular(14))
                    : BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.primaryColor.withOpacity(0.3),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      day.titleController.text.isEmpty
                          ? 'Day ${index + 1}'
                          : 'Day ${index + 1}: ${day.titleController.text}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        size: 20, color: AppTheme.errorColor),
                    onPressed: () {
                      setState(() {
                        _itineraryDays[index].dispose();
                        _itineraryDays.removeAt(index);
                      });
                    },
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    day.isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ],
              ),
            ),
          ),

          // Expandable body
          if (day.isExpanded)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: day.titleController,
                    decoration: const InputDecoration(
                      labelText: 'Day Title',
                      hintText: 'e.g. Arrival & Acclimatization',
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: day.descriptionController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Day Description',
                      hintText: 'What happens on this day...',
                      prefixIcon: Padding(
                        padding: EdgeInsets.only(bottom: 24),
                        child: Icon(Icons.notes),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Day Image
                  _sectionHeader('Day Image', theme),
                  const SizedBox(height: 8),
                  _buildImagePicker(
                    imageUrl: day.imageUrl,
                    isUploading: day.isUploadingImage,
                    onPick: () async {
                      setState(() => day.isUploadingImage = true);
                      final url = await _pickAndUploadImage();
                      if (mounted) {
                        setState(() {
                          day.imageUrl = url ?? day.imageUrl;
                          day.isUploadingImage = false;
                        });
                      }
                    },
                    onRemove: () => setState(() => day.imageUrl = null),
                    height: 140,
                  ),
                  const SizedBox(height: 18),

                  _sectionHeader('Activities', theme),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: day.morningController,
                    decoration: const InputDecoration(
                      labelText: 'Morning',
                      hintText: 'Morning activity',
                      prefixIcon: Icon(Icons.wb_sunny_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: day.afternoonController,
                    decoration: const InputDecoration(
                      labelText: 'Afternoon',
                      hintText: 'Afternoon activity',
                      prefixIcon: Icon(Icons.wb_cloudy_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: day.eveningController,
                    decoration: const InputDecoration(
                      labelText: 'Evening',
                      hintText: 'Evening activity',
                      prefixIcon: Icon(Icons.nights_stay_outlined),
                    ),
                  ),
                  const SizedBox(height: 18),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: day.accommodationController,
                          decoration: const InputDecoration(
                            labelText: 'Accommodation',
                            hintText: 'Stay details',
                            prefixIcon: Icon(Icons.hotel_outlined),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: day.elevationController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Elevation (m)',
                            prefixIcon: Icon(Icons.height),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: day.distanceController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Distance (km)',
                            prefixIcon: Icon(Icons.straighten),
                          ),
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

  // =========================================================================
  // STEP 4: What's Included
  // =========================================================================
  Widget _buildIncludesStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDynamicList(
          header: 'Included',
          icon: Icons.check_circle_outline,
          iconColor: Colors.green,
          items: _includedItems,
          onChanged: (items) => setState(() => _includedItems = items),
          theme: theme,
        ),
        const SizedBox(height: 28),
        _buildDynamicList(
          header: 'Excluded',
          icon: Icons.cancel_outlined,
          iconColor: AppTheme.errorColor,
          items: _excludedItems,
          onChanged: (items) => setState(() => _excludedItems = items),
          theme: theme,
        ),
      ],
    );
  }

  Widget _buildDynamicList({
    required String header,
    required IconData icon,
    required Color iconColor,
    required List<String> items,
    required ValueChanged<List<String>> onChanged,
    required ThemeData theme,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: 8),
                _sectionHeader(header, theme),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 22),
              onPressed: () {
                final updated = List<String>.from(items)..add('');
                onChanged(updated);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...List.generate(items.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: items[index],
                    decoration: InputDecoration(
                      hintText: 'Item ${index + 1}',
                      isDense: true,
                    ),
                    onChanged: (val) {
                      items[index] = val;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.remove_circle_outline,
                      size: 20, color: AppTheme.errorColor),
                  onPressed: () {
                    final updated = List<String>.from(items)..removeAt(index);
                    onChanged(updated);
                  },
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // =========================================================================
  // Bottom Bar
  // =========================================================================
  Widget _buildBottomBar(List<_StepInfo> steps, ThemeData theme) {
    final isLastStep = _currentStep == steps.length - 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (_currentStep > 0)
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _currentStep--),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Back'),
                ),
              ),
            if (_currentStep > 0) const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _isSubmitting
                    ? null
                    : () {
                        if (isLastStep) {
                          _submit();
                        } else {
                          setState(() => _currentStep++);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : Text(isLastStep
                        ? (widget.isEditing
                            ? 'Update ${_isTrip ? "Trip" : "Event"}'
                            : 'Create ${_isTrip ? "Trip" : "Event"}')
                        : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // Shared Widgets
  // =========================================================================
  Widget _sectionHeader(String title, ThemeData theme) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: theme.textTheme.bodyLarge?.color,
      ),
    );
  }

  Widget _buildDateSelector({
    required String label,
    DateTime? date,
    required VoidCallback onPick,
  }) {
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today),
        ),
        child: Text(
          date != null ? DateFormat('MMM d, yyyy').format(date) : 'Select',
          style: TextStyle(
            color: date != null
                ? Theme.of(context).textTheme.bodyLarge?.color
                : Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
      ),
    );
  }

  Widget _buildTimeSelector({
    required String label,
    required TimeOfDay time,
    required VoidCallback onPick,
  }) {
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.access_time),
        ),
        child: Text(time.format(context)),
      ),
    );
  }

  Widget _buildImagePicker({
    required String? imageUrl,
    required bool isUploading,
    required VoidCallback onPick,
    required VoidCallback onRemove,
    double height = 200,
  }) {
    if (isUploading) {
      return Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(strokeWidth: 2),
              SizedBox(height: 10),
              Text('Uploading image...', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      );
    }

    if (imageUrl != null && imageUrl.isNotEmpty) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              width: double.infinity,
              height: height,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                height: height,
                color: Theme.of(context).dividerColor,
                child: const Center(child: Icon(Icons.broken_image, size: 40)),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black54,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: onPick,
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: Theme.of(context).dividerColor,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_outlined,
                size: 40, color: Theme.of(context).textTheme.bodySmall?.color),
            const SizedBox(height: 8),
            Text(
              'Tap to upload image',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Helper Classes
// ============================================================================

class _StepInfo {
  final String title;
  final IconData icon;

  _StepInfo({required this.title, required this.icon});
}

class _ItineraryDayData {
  final String? id;
  final TextEditingController titleController;
  final TextEditingController descriptionController;
  final TextEditingController morningController;
  final TextEditingController afternoonController;
  final TextEditingController eveningController;
  final TextEditingController accommodationController;
  final TextEditingController elevationController;
  final TextEditingController distanceController;
  String? imageUrl;
  bool isExpanded;
  bool isUploadingImage;

  _ItineraryDayData({
    this.id,
    required this.titleController,
    required this.descriptionController,
    required this.morningController,
    required this.afternoonController,
    required this.eveningController,
    required this.accommodationController,
    required this.elevationController,
    required this.distanceController,
    this.imageUrl,
    this.isExpanded = true,
    this.isUploadingImage = false,
  });

  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    morningController.dispose();
    afternoonController.dispose();
    eveningController.dispose();
    accommodationController.dispose();
    elevationController.dispose();
    distanceController.dispose();
  }
}

// Reused event type chip widget
class _EventTypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _EventTypeChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withOpacity(0.2)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isSelected ? AppTheme.primaryColor : Theme.of(context).dividerColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18,
                color: isSelected
                    ? Theme.of(context).textTheme.bodyLarge?.color
                    : Theme.of(context).textTheme.bodySmall?.color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? Theme.of(context).textTheme.bodyLarge?.color
                    : Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
