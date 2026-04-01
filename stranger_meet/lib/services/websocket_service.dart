import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'storage_service.dart';
import '../config/constants.dart';

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._();
  factory WebSocketService() => _instance;
  WebSocketService._();

  WebSocketChannel? _channel;
  bool _isConnected = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectDelay = 30; // seconds

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  /// Emits when the WebSocket reconnects after a disconnect.
  /// Listeners should use this to re-fetch missed messages.
  final _reconnectedController = StreamController<void>.broadcast();
  Stream<void> get onReconnected => _reconnectedController.stream;

  bool get isConnected => _isConnected;

  Future<void> connect() async {
    if (_isConnected) return;

    final token = await StorageService().getToken();
    if (token == null) return;

    // Convert http://localhost:8000/api to ws://localhost:8000/api/messages/ws/{token}
    final baseUrl = AppConstants.baseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final wsUrl = '$baseUrl/messages/ws/$token';

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;
      _reconnectTimer?.cancel();

      // If this is a reconnection (not the first connect), notify listeners
      if (_reconnectAttempts > 0) {
        _reconnectedController.add(null);
      }
      _reconnectAttempts = 0;

      _channel!.stream.listen(
        (data) {
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            _messageController.add(json);
          } catch (_) {}
        },
        onDone: () {
          _isConnected = false;
          _scheduleReconnect();
        },
        onError: (_) {
          _isConnected = false;
          _scheduleReconnect();
        },
      );
    } catch (_) {
      _isConnected = false;
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    // Exponential backoff: 3s, 6s, 12s, ... up to maxReconnectDelay
    final delay = (_reconnectAttempts * 3).clamp(3, _maxReconnectDelay);
    _reconnectTimer = Timer(Duration(seconds: delay), connect);
  }

  void sendMessage(String receiverId, String message,
      {String imageUrl = '', String messageType = 'text'}) {
    if (!_isConnected || _channel == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'message',
      'receiver_id': receiverId,
      'message': message,
      'image_url': imageUrl,
      'message_type': messageType,
    }));
  }

  void markAsRead(String senderId) {
    if (!_isConnected || _channel == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'read',
      'sender_id': senderId,
    }));
  }

  void sendTyping(String receiverId) {
    if (!_isConnected || _channel == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'typing',
      'receiver_id': receiverId,
    }));
  }

  void sendCallOffer(String receiverId, String sdp, {bool isVideo = false}) {
    if (!_isConnected || _channel == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'call_offer',
      'receiver_id': receiverId,
      'sdp': sdp,
      'is_video': isVideo,
    }));
  }

  void sendCallAnswer(String receiverId, String sdp) {
    if (!_isConnected || _channel == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'call_answer',
      'receiver_id': receiverId,
      'sdp': sdp,
    }));
  }

  void sendCallReject(String receiverId) {
    if (!_isConnected || _channel == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'call_reject',
      'receiver_id': receiverId,
    }));
  }

  void sendCallEnd(String receiverId) {
    if (!_isConnected || _channel == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'call_end',
      'receiver_id': receiverId,
    }));
  }

  void sendIceCandidate(String receiverId, String candidate, String sdpMid, int sdpMLineIndex) {
    if (!_isConnected || _channel == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'ice_candidate',
      'receiver_id': receiverId,
      'candidate': candidate,
      'sdp_mid': sdpMid,
      'sdp_m_line_index': sdpMLineIndex,
    }));
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _isConnected = false;
    _reconnectAttempts = 0;
  }
}
