import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/event.dart';
import '../services/api_service.dart';

class EventsState {
  final List<Event> events;
  final bool isLoading;
  final String? errorMessage;

  const EventsState({
    this.events = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  EventsState copyWith({
    List<Event>? events,
    bool? isLoading,
    String? errorMessage,
  }) {
    return EventsState(
      events: events ?? this.events,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class EventsNotifier extends StateNotifier<EventsState> {
  final ApiService _api;

  EventsNotifier(this._api) : super(const EventsState());

  Future<void> fetchEvents({bool refresh = false}) async {
    if (state.isLoading && !refresh) return;

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final response = await _api.get('/events/');
      final data = response.data;
      final List<dynamic> results =
          data is List ? data : (data['results'] ?? data['events'] ?? []);
      final events = results.map((e) => Event.fromJson(e)).toList();

      state = EventsState(events: events);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<Event> fetchEventById(String eventId) async {
    final response = await _api.get('/events/$eventId');
    return Event.fromJson(response.data);
  }

  Future<void> createEvent({
    required String title,
    required String description,
    required String location,
    required DateTime date,
    double price = 0,
    int slots = 0,
  }) async {
    try {
      await _api.post('/events/', data: {
        'title': title,
        'description': description,
        'location': location,
        'date': date.toIso8601String(),
        'price': price,
        'slots': slots,
      });
      await fetchEvents(refresh: true);
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> joinEvent(String eventId) async {
    try {
      await _api.post('/events/$eventId/join');

      // Update participant count locally
      final index = state.events.indexWhere((e) => e.id == eventId);
      if (index != -1) {
        final event = state.events[index];
        final updated = List<Event>.from(state.events);
        updated[index] = event.copyWith(
          participantsCount: event.participantsCount + 1,
        );
        state = state.copyWith(events: updated);
      }
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }
}

final eventsProvider =
    StateNotifierProvider<EventsNotifier, EventsState>((ref) {
  return EventsNotifier(ApiService());
});
