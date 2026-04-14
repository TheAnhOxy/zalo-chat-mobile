import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';
import 'dart:developer';
import 'dart:io';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;

  bool get isConnected => _socket?.connected ?? false;

  String get socketUrl {
    if (kIsWeb) {
      // Chrome chạy trên máy thật
      return 'http://localhost:8081';
    } else if (Platform.isAndroid) {
      // Android emulator trỏ về máy host
      return 'http://10.0.2.2:8081';
    } else {
      return 'http://localhost:8081';
    }
  }

  void connect(String userId) {
    if (_socket?.connected == true) return;

    log('🌐 Connecting socket to: $socketUrl');

    _socket = IO.io(
      socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setQuery({'userId': userId})
          .enableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      log('✅ Socket connected');

      _socket!.emit('join_user_room', {
        'userId': userId,
      });
    });

    _socket!.onDisconnect((_) {
      log('❌ Socket disconnected');
    });

    _socket!.onConnectError((err) {
      log('⚠️ Connect Error: $err');
    });

    _socket!.onError((err) {
      log('🚨 Socket Error: $err');
    });
  }

  void on(String event, Function(dynamic) handler) {
    _socket?.on(event, handler);
  }

  void off(String event) {
    _socket?.off(event);
  }

  void sendMessage(Map<String, dynamic> data) {
    _socket?.emit('send_message', data);
  }

  void emit(String event, dynamic data) {
    _socket?.emit(event, data);
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }
}

final socketService = SocketService();