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

  // Lấy URL phù hợp với môi trường chạy
  String get socketUrl {
    if (kIsWeb) {
      return 'http://localhost:8081';
    } else if (Platform.isAndroid) {
      return 'http://10.0.2.2:8081';
    } else {
      return 'http://localhost:8081';
    }
  }

  /// Khởi tạo kết nối với Server
  void connect(String userId) {
    if (_socket?.connected == true) return;

    log('🌐 Connecting socket to: $socketUrl with userId: $userId');

    _socket = IO.io(
      socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setQuery({'userId': userId})
          .enableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      log('✅ Socket connected: ${_socket!.id}');
    });

    _socket!.onDisconnect((_) {
      log('❌ Socket disconnected');
    });

    _socket!.onConnectError((err) {
      log('⚠️ Connect Error: $err');
    });
  }

  // --- ROOM MANAGEMENT ---

  /// Tham gia vào phòng chat cụ thể để nhận tin nhắn real-time
  void joinConversation(String conversationId) {
    _socket?.emit('join_conversation', {'conversationId': conversationId});
    log('👥 Joined conversation room: $conversationId');
  }

  // --- MESSAGE ACTIONS ---

  /// Gửi tin nhắn mới
  void sendMessage(Map<String, dynamic> data) {
    _socket?.emit('send_message', data);
  }

  /// Chỉnh sửa nội dung tin nhắn
  void editMessage(String messageId, String content, String conversationId) {
    _socket?.emit('edit_message', {
      'messageId': messageId,
      'content': content,
      'conversationId': conversationId,
    });
  }

  /// Thu hồi tin nhắn (Xóa phía mọi người)
  void recallMessage(String messageId, String conversationId) {
    _socket?.emit('recall_message', {
      'messageId': messageId,
      'conversationId': conversationId,
    });
  }

  /// Xóa tin nhắn chỉ ở phía tôi (Delete for me)
  void deleteMessageMe(String messageId, String userId) {
    _socket?.emit('delete_message_me', {
      'messageId': messageId,
      'userId': userId,
    });
  }

  // --- INTERACTION ---

  /// Thả cảm xúc (Reaction) cho tin nhắn
  /// [type] nhận các giá trị: LIKE, LOVE, HAHA, WOW, SAD, ANGRY
  void sendReaction(String messageId, String userId, String type, String conversationId) {
    _socket?.emit('add_reaction', {
      'messageId': messageId,
      'userId': userId,
      'type': type,
      'conversationId': conversationId,
    });
  }

  /// Thông báo trạng thái đang soạn thảo
  void sendTyping(String conversationId, String userId, bool isTyping) {
    _socket?.emit('typing', {
      'conversationId': conversationId,
      'userId': userId,
      'isTyping': isTyping,
    });
  }

  // --- LISTENER HELPERS ---

  /// Đăng ký lắng nghe một sự kiện từ server
  void on(String event, Function(dynamic) handler) {
    _socket?.on(event, handler);
  }

  /// Phát một sự kiện tùy ý lên server
  void emit(String event, [dynamic data]) {
    _socket?.emit(event, data);
  }

  /// Hủy lắng nghe một sự kiện
  void off(String event) {
    _socket?.off(event);
  }

  /// Ngắt kết nối hoàn toàn
  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }
}

// Global instance để sử dụng thuận tiện
final socketService = SocketService();