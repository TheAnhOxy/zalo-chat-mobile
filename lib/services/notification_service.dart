import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'api_service.dart';

class RealNotification {
  final String id;
  final String receiverId;
  final String type; // 'MESSAGE' | 'FRIEND_REQUEST' | 'CALL'
  final String content;
  final bool isRead;
  final DateTime createdAt;
  
  // Data parsed from nested MongoDB subdocument
  final String? senderId;
  final String? senderName;
  final String? senderAvatar;
  final String? conversationId;
  final String? messageId;

  RealNotification({
    required this.id,
    required this.receiverId,
    required this.type,
    required this.content,
    required this.isRead,
    required this.createdAt,
    this.senderId,
    this.senderName,
    this.senderAvatar,
    this.conversationId,
    this.messageId,
  });

  factory RealNotification.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'] as Map<String, dynamic>? ?? {};
    
    // Attempting to resolve sender fields if nested user details are populated/provided
    final senderData = rawData['sender'] as Map<String, dynamic>? ?? {};
    final String sId = rawData['senderId']?.toString() ?? senderData['_id']?.toString() ?? '';
    final String sName = senderData['fullName']?.toString() ?? senderData['name']?.toString() ?? 'Người dùng';
    final String sAvatar = senderData['avatar']?.toString() ?? 'https://i.pravatar.cc/150?img=3';

    return RealNotification(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      receiverId: json['receiverId']?.toString() ?? '',
      type: json['type']?.toString() ?? 'MESSAGE',
      content: json['content']?.toString() ?? '',
      isRead: json['isRead'] == true || json['isRead'] == 'true',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      senderId: sId.isNotEmpty ? sId : null,
      senderName: sName,
      senderAvatar: sAvatar,
      conversationId: rawData['conversationId']?.toString(),
      messageId: rawData['messageId']?.toString(),
    );
  }
}

class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  List<RealNotification> _notifications = [];
  bool _isLoading = false;

  List<RealNotification> get notifications => _notifications;
  bool get isLoading => _isLoading;
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  /// Tải thông báo từ MongoDB database qua ApiService
  Future<void> fetchNotifications() async {
    final myId = authService.userId;
    if (myId == null || myId.isEmpty) return;

    _isLoading = true;
    notifyListeners();

    try {
      final list = await apiService.getNotifications(myId);
      final parsed = <RealNotification>[];
      for (final item in list) {
        final notif = RealNotification.fromJson(item);
        
        // Dynamic profile resolution: nếu senderId được trả về, nạp chi tiết profile để UI nhìn đẹp mắt
        if (notif.senderId != null && notif.senderId!.isNotEmpty) {
          final userProfile = await apiService.getUserById(notif.senderId!);
          if (userProfile != null) {
            parsed.add(RealNotification(
              id: notif.id,
              receiverId: notif.receiverId,
              type: notif.type,
              content: notif.content,
              isRead: notif.isRead,
              createdAt: notif.createdAt,
              senderId: notif.senderId,
              senderName: userProfile.fullName,
              senderAvatar: userProfile.avatar,
              conversationId: notif.conversationId,
              messageId: notif.messageId,
            ));
            continue;
          }
        }
        parsed.add(notif);
      }
      _notifications = parsed;
    } catch (_) {
      // Fallback
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Đánh dấu đã đọc trên MongoDB
  Future<void> markAsRead(String id) async {
    final success = await apiService.markNotificationAsRead(id);
    if (success) {
      final index = _notifications.indexWhere((n) => n.id == id);
      if (index != -1) {
        _notifications[index] = RealNotification(
          id: _notifications[index].id,
          receiverId: _notifications[index].receiverId,
          type: _notifications[index].type,
          content: _notifications[index].content,
          isRead: true,
          createdAt: _notifications[index].createdAt,
          senderId: _notifications[index].senderId,
          senderName: _notifications[index].senderName,
          senderAvatar: _notifications[index].senderAvatar,
          conversationId: _notifications[index].conversationId,
          messageId: _notifications[index].messageId,
        );
        notifyListeners();
      }
    }
  }

  /// Đánh dấu đã đọc tất cả trên MongoDB
  Future<void> markAllAsRead() async {
    final myId = authService.userId;
    if (myId == null || myId.isEmpty) return;

    final success = await apiService.markAllNotificationsAsRead(myId);
    if (success) {
      _notifications = _notifications.map((n) {
        return RealNotification(
          id: n.id,
          receiverId: n.receiverId,
          type: n.type,
          content: n.content,
          isRead: true,
          createdAt: n.createdAt,
          senderId: n.senderId,
          senderName: n.senderName,
          senderAvatar: n.senderAvatar,
          conversationId: n.conversationId,
          messageId: n.messageId,
        );
      }).toList();
      notifyListeners();
    }
  }

  /// Xóa thông báo khỏi MongoDB database
  Future<void> removeNotification(String id) async {
    final success = await apiService.deleteNotification(id);
    if (success) {
      _notifications.removeWhere((n) => n.id == id);
      notifyListeners();
    }
  }
}

final notificationService = NotificationService();
