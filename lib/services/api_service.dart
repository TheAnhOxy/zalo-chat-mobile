import 'package:dio/dio.dart';
import '../data/models/models.dart';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:typed_data';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  // Getter cho baseUrl động tùy theo nền tảng
  String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:8081'; // Web
    } else if (Platform.isAndroid) {
      return 'http://10.0.2.2:8081'; // Android Emulator
    } else {
      return 'http://localhost:8081'; // iOS / Desktop / Real Device (nếu dùng chung mạng)
    }
  }

  // Khởi tạo Dio với cấu hình cơ bản
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  // --- CONVERSATIONS ---

  /// Lấy danh sách cuộc hội thoại của một người dùng
  Future<List<ConversationModel>> getConversations(String userId) async {
    try {
      final response = await _dio.get('$baseUrl/conversations/member/$userId');
      final List data = response.data;
      return data.map((e) => ConversationModel.fromJson(e)).toList();
    } catch (e) {
      log('❌ Lỗi getConversations: $e');
      return [];
    }
  }

  // --- MESSAGES ---

  /// Lấy lịch sử tin nhắn của một cuộc hội thoại
  /// [userId] là tham số bắt buộc để Backend lọc bỏ các tin nhắn người dùng đã nhấn "Xóa phía tôi"
  Future<List<MessageModel>> getMessages(String conversationId, String userId) async {
    try {
      final response = await _dio.get(
        '$baseUrl/messages/conversation/$conversationId',
        queryParameters: {
          'userId': userId, // Truyền userId lên để Backend thực hiện lọc deletedBy
          'limit': 50,
          'skip': 0,
        },
      );
      
      final List data = response.data;
      return data.map((json) => MessageModel.fromJson(json)).toList();
    } catch (e) {
      log('❌ Lỗi getMessages: $e');
      return [];
    }
  }

  /// Cập nhật trạng thái xóa tin nhắn ở phía người dùng (API dự phòng cho Socket)
  Future<bool> deleteMessageForMe(String messageId, String userId) async {
    try {
      await _dio.post(
        '$baseUrl/messages/$messageId/deleted-by',
        data: {'userId': userId},
      );
      return true;
    } catch (e) {
      log('❌ Lỗi deleteMessageForMe: $e');
      return false;
    }
  }

  // --- CALLS ---

  /// Tạo một bản ghi cuộc gọi mới
  Future<Map<String, dynamic>> createCall({
    required String conversationId,
    required String callerId,
    required List<String> participants,
    required String type,
  }) async {
    try {
      final response = await _dio.post(
        '$baseUrl/calls',
        data: {
          'conversationId': conversationId,
          'callerId': callerId,
          'participants': participants,
          'type': type,
          'status': 'CALLING',
          'startedAt': DateTime.now().toIso8601String(),
        },
      );
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      log('❌ Lỗi createCall: $e');
      rethrow;
    }
  }
  /// Lấy presigned URL để upload trực tiếp lên S3
  /// Trả về map có key chuẩn hóa: `uploadUrl`, `fileUrl`
  Future<Map<String, dynamic>?> getPresignedUrl(
    String fileName,
    String contentType,
  ) async {
    try {
      // ĐỔI THÀNH .get VÀ DÙNG queryParameters
      final response = await _dio.get(
        '$baseUrl/upload/presigned-url',
        queryParameters: {
          'fileName': fileName,
          'contentType': contentType,
        },
      );

      final raw = response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : Map<String, dynamic>.from(response.data as Map);

      // Backend của bạn trả về { url, fileUrl }, hãy map đúng tên key
      final uploadUrl = raw['url']?.toString() ?? raw['uploadUrl']?.toString();
      final fileUrl = raw['fileUrl']?.toString();

      if (uploadUrl == null) return null;

      return {
        'uploadUrl': uploadUrl,
        'fileUrl': fileUrl,
      };
    } catch (e) {
      log('❌ Lỗi lấy Presigned URL: $e');
      return null;
    }
  }

  /// Upload trực tiếp lên S3 bằng phương thức PUT
  Future<bool> uploadFileToS3(
    String presignedUrl,
    Uint8List fileBytes,
    String contentType, {
    void Function(int sent, int total)? onSendProgress,
  }) async {
    try {
      final uploadDio = Dio();
      final response = await uploadDio.put(
        presignedUrl,
        data: fileBytes,
        options: Options(
          contentType: contentType,
          headers: {
            'Content-Type': contentType,
            'Content-Length': fileBytes.length,
          },
        ),
        onSendProgress: onSendProgress,
      );
      return response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300;
    } catch (e) {
      log('❌ Lỗi PUT S3: $e');
      return false;
    }
  }

  /// Lấy lịch sử cuộc gọi của một cuộc hội thoại
  Future<List<Map<String, dynamic>>> getCalls(String conversationId) async {
    try {
      final response = await _dio.get(
        '$baseUrl/calls/conversation/$conversationId',
      );
      final List data = response.data;
      return data.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      log('❌ Lỗi getCalls: $e');
      return [];
    }
  }
}

// Instance duy nhất để sử dụng toàn ứng dụng
final apiService = ApiService();