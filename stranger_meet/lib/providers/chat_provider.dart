import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/message.dart';
import '../services/api_service.dart';

// Conversations provider

class ConversationsState {
  final List<Conversation> conversations;
  final bool isLoading;
  final String? errorMessage;

  const ConversationsState({
    this.conversations = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  ConversationsState copyWith({
    List<Conversation>? conversations,
    bool? isLoading,
    String? errorMessage,
  }) {
    return ConversationsState(
      conversations: conversations ?? this.conversations,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class ConversationsNotifier extends StateNotifier<ConversationsState> {
  final ApiService _api;

  ConversationsNotifier(this._api) : super(const ConversationsState());

  Future<void> fetchConversations() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final response = await _api.get('/messages');
      final data = response.data;
      final List<dynamic> results = data is List
          ? data
          : (data['results'] ?? data['conversations'] ?? []);
      final conversations =
          results.map((e) => Conversation.fromJson(e)).toList();

      state = ConversationsState(conversations: conversations);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }
}

final conversationsProvider =
    StateNotifierProvider<ConversationsNotifier, ConversationsState>((ref) {
  return ConversationsNotifier(ApiService());
});

// Messages provider (per user)

class MessagesState {
  final List<Message> messages;
  final bool isLoading;
  final String? errorMessage;

  const MessagesState({
    this.messages = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  MessagesState copyWith({
    List<Message>? messages,
    bool? isLoading,
    String? errorMessage,
  }) {
    return MessagesState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class MessagesNotifier extends StateNotifier<MessagesState> {
  final ApiService _api;
  final String userId;

  MessagesNotifier(this._api, this.userId) : super(const MessagesState());

  Future<void> fetchMessages() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final response = await _api.get('/messages/$userId');
      final data = response.data;
      final List<dynamic> results =
          data is List ? data : (data['results'] ?? data['messages'] ?? []);
      final messages = results.map((e) => Message.fromJson(e)).toList();

      state = MessagesState(messages: messages);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  void addMessage(Message message) {
    // Avoid duplicates
    if (state.messages.any((m) => m.id == message.id)) return;
    state = state.copyWith(messages: [...state.messages, message]);
  }

  void setMessages(List<Message> messages) {
    state = state.copyWith(messages: messages);
  }

  Future<void> sendMessage(String text, {String imageUrl = '', String messageType = 'text'}) async {
    try {
      final response = await _api.post('/messages', data: {
        'receiver_id': userId,
        'message': text,
        'image_url': imageUrl,
        'message_type': messageType,
      });

      final newMessage = Message.fromJson(response.data);
      state = state.copyWith(
        messages: [...state.messages, newMessage],
      );
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }
}

final messagesProvider = StateNotifierProvider.family<MessagesNotifier,
    MessagesState, String>((ref, userId) {
  return MessagesNotifier(ApiService(), userId);
});

// Unread message count provider
class UnreadCountNotifier extends StateNotifier<int> {
  final ApiService _api;

  UnreadCountNotifier(this._api) : super(0);

  Future<void> fetchUnreadCount() async {
    try {
      final response = await _api.get('/messages/unread-count');
      state = response.data['count'] ?? 0;
    } catch (_) {
      state = 0;
    }
  }
}

final unreadCountProvider =
    StateNotifierProvider<UnreadCountNotifier, int>((ref) {
  return UnreadCountNotifier(ApiService());
});
