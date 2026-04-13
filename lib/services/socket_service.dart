import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:developer';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  bool get isConnected => _socket?.connected ?? false;

  void connect(String userId) {
    if (_socket?.connected == true) return;

    // Thay đổi IP này theo IP máy tính của bạn nếu chạy trên điện thoại thật
    // Hoặc 10.0.2.2 nếu chạy trên Android Emulator
    _socket = IO.io(
      'http://localhost:8081', 
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setQuery({'userId': userId}) 
          .enableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      log('✅ Connected to Socket Server');
    });

    _socket!.onDisconnect((_) {
      log('❌ Disconnected from Socket Server');
    });

    _socket!.onConnectError((err) => log('⚠️ Connect Error: $err'));
  }

  // Lắng nghe sự kiện chung
  void on(String event, Function(dynamic) handler) {
    _socket?.on(event, handler);
  }

  // Hủy lắng nghe
  void off(String event) {
    _socket?.off(event);
  }

  // Gửi tin nhắn
  void sendMessage(Map<String, dynamic> data) {
    _socket?.emit('send_message', data);
  }

  // Signaling cho Call (Offer, Answer, ICE Candidate)
  void emit(String event, dynamic data) {
    _socket?.emit(event, data);
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }
}

final socketService = SocketService();