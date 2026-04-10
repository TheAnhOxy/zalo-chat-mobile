// ─────────────────────────────────────────────────────────────────────────────
// SocketService — Mock implementation
// Khi có backend: uncomment phần socket_io_client và thay URL
// ─────────────────────────────────────────────────────────────────────────────

typedef SocketEventHandler = void Function(dynamic data);

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  bool _isConnected = false;
  final Map<String, List<SocketEventHandler>> _handlers = {};

  bool get isConnected => _isConnected;

  void connect(String token) {
    // TODO: Uncomment khi có backend
    // _socket = IO.io(
    //   'http://your-server.com',
    //   IO.OptionBuilder()
    //     .setTransports(['websocket'])
    //     .setExtraHeaders({'Authorization': 'Bearer $token'})
    //     .build(),
    // );
    // _socket!.on('connect', (_) { _isConnected = true; });
    // _socket!.on('new_message', (d) => _emit('new_message', d));
    // _socket!.on('typing', (d) => _emit('typing', d));
    // _socket!.on('call_user', (d) => _emit('call_user', d));
    _isConnected = true;
  }

  void on(String event, SocketEventHandler handler) {
    _handlers.putIfAbsent(event, () => []).add(handler);
  }

  void off(String event) => _handlers.remove(event);

  void _emit(String event, dynamic data) {
    for (final h in (_handlers[event] ?? [])) h(data);
  }

  void sendMessage(Map<String, dynamic> data) {
    // _socket?.emit('send_message', data);
  }

  void emitTyping(String conversationId) {
    // _socket?.emit('typing', {'conversationId': conversationId});
  }

  void emitStopTyping(String conversationId) {
    // _socket?.emit('stop_typing', {'conversationId': conversationId});
  }

  void disconnect() {
    _isConnected = false;
    // _socket?.disconnect();
  }
}

final socketService = SocketService();
