import 'dart:developer' as dev;

import 'package:dio/dio.dart';

import 'api_service.dart';
import 'auth_service.dart';
import '../data/models/models.dart';

class NotificationApiService {
  NotificationApiService._();
  static final NotificationApiService instance = NotificationApiService._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  String get _baseUrl => ApiService().baseUrl;

  Future<List<AppNotification>> getMyNotifications({int limit = 30}) async {
    final me = authService.userId;
    if (me == null || me.isEmpty) return [];
    try {
      final res = await _dio.get(
        '$_baseUrl/notifications/receiver/$me',
        queryParameters: {'limit': limit, 'skip': 0},
      );
      final items = res.data as List? ?? [];
      return items.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return AppNotification(
          id: (m['_id'] ?? m['id'] ?? '').toString(),
          receiverId: (m['receiverId'] ?? '').toString(),
          type: (m['type'] ?? 'MESSAGE').toString(),
          content: (m['content'] ?? '').toString(),
          isRead: m['isRead'] == true,
          createdAt: m['createdAt'] != null
              ? DateTime.tryParse(m['createdAt'].toString()) ?? DateTime.now()
              : DateTime.now(),
        );
      }).toList();
    } catch (e) {
      dev.log('❌ getMyNotifications: $e');
      return [];
    }
  }

  Future<bool> markAllRead() async {
    final me = authService.userId;
    if (me == null || me.isEmpty) return false;
    try {
      await _dio.patch('$_baseUrl/notifications/receiver/$me/read-all');
      return true;
    } catch (e) {
      dev.log('❌ markAllRead: $e');
      return false;
    }
  }
}

