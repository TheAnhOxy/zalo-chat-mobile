import 'package:dio/dio.dart';
import '../data/models/models.dart';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'dart:io';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:8081'; // Web dùng localhost
    } else if (Platform.isAndroid) {
      return 'http://10.0.2.2:8081'; // Android Emulator
    } else {
      return 'http://localhost:8081'; // iOS / desktop
    }
  }

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: '', // 👈 để trống
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 3),
    ),
  );

  // dùng baseUrl động
  Future<List<ConversationModel>> getConversations(String userId) async {
    try {
      final response = await _dio.get('$baseUrl/conversations/member/$userId');
      final List data = response.data;
      return data.map((e) => ConversationModel.fromJson(e)).toList();
    } catch (e) {
      print('❌ $e');
      return [];
    }
  }

  Future<List<MessageModel>> getMessages(String conversationId) async {
  try {
    final response = await _dio.get('$baseUrl/messages/conversation/$conversationId');
    final List data = response.data;
    return data.map((json) => MessageModel.fromJson(json)).toList();
  } catch (e) {
    log('❌ Lỗi getMessages: $e');
    return [];
  }
}

Future<Map<String, dynamic>> createCall({
  required String conversationId,
  required String callerId,
  required List<String> participants,
  required String type,
}) async {
  try {
    final response = await _dio.post('$baseUrl/calls', data: {
      'conversationId': conversationId,
      'callerId': callerId,
      'participants': participants,
      'type': type,
    });
    return Map<String, dynamic>.from(response.data);
  } catch (e) {
    log('❌ Lỗi createCall: $e');
    rethrow;
  }
}
}

final apiService = ApiService();