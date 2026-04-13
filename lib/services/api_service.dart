import 'package:dio/dio.dart';
import '../data/models/models.dart';
import 'dart:developer';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final Dio _dio = Dio(BaseOptions(
    // Dùng 10.0.2.2 nếu test trên Android Emulator
    // Dùng localhost nếu test trên iOS Simulator hoặc Web
    baseUrl: 'http://localhost:8081', 
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 3),
  ));

  // 1. Lấy danh sách hội thoại của User
  Future<List<ConversationModel>> getConversations(String userId) async {
    try {
      final response = await _dio.get('/conversations/member/$userId');
      final List data = response.data;
      return data.map((json) => ConversationModel.fromJson(json)).toList();
    } catch (e) {
      log('❌ Lỗi getConversations: $e');
      return [];
    }
  }

  Future<List<MessageModel>> getMessages(String conversationId) async {
    try {
      final response = await _dio.get('/messages/conversation/$conversationId');
      final List data = response.data;
      return data.map((json) => MessageModel.fromJson(json)).toList();
    } catch (e) {
      log('❌ Lỗi getMessages: $e');
      return [];
    }
  }
}

final apiService = ApiService();