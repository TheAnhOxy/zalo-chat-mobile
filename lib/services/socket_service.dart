import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';

String get socketUrl {
  if (kIsWeb) {
    return 'http://localhost:8081';
  } else if (Platform.isAndroid) {
    return 'http://10.0.2.2:8081';
  } else {
    return 'http://localhost:8081';
  }
}

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  bool get isConnected => _socket?.connected ?? false;

void connect(String userId) {
  if (_socket?.connected == true) return;

  _socket = IO.io(
    socketUrl,
    IO.OptionBuilder()
        .setTransports(['websocket'])
        .setQuery({'userId': userId})
        .enableForceNew()           // ← quan trọng cho emulator
        .enableReconnection()
        .setReconnectionAttempts(10)
        .build(),
  );

  _socket!.onConnect((_) => log('✅ Socket Connected'));
  _socket!.onConnectError((err) => log('❌ Socket Connect Error: $err'));
  _socket!.onError((err) => log('❌ Socket Error: $err'));
  _socket!.onDisconnect((_) => log('❌ Socket Disconnected'));
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