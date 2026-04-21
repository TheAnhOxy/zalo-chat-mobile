import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../data/models/models.dart';
import '../core/config/app_config.dart';
import '../navigation/app_navigator.dart';
import '../navigation/app_router.dart';
import 'auth_service.dart';
import 'fake_auth_flow_service.dart';
import 'socket_service.dart';
import 'dart:developer';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal() {
    _configureInterceptors();
  }

  String get baseUrl => AppConfig.baseUrl;

  // Khởi tạo Dio với cấu hình cơ bản
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  Future<AuthTokens>? _refreshFuture;
  bool _isForceLogoutHandling = false;

  void _configureInterceptors() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = authService.accessToken;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final statusCode = error.response?.statusCode;
          final alreadyRetried = error.requestOptions.extra['retried'] == true;

          if (statusCode != 401 || alreadyRetried) {
            handler.next(error);
            return;
          }

          if (_isSessionRevoked(error)) {
            await _handleForcedLogout();
            handler.next(error);
            return;
          }

          final refreshed = await _refreshAccessTokenOnce();
          if (refreshed == null) {
            authService.logout();
            handler.next(error);
            return;
          }

          final retryOptions = error.requestOptions;
          retryOptions.headers['Authorization'] =
              'Bearer ${refreshed.accessToken}';
          retryOptions.extra['retried'] = true;

          try {
            final response = await _dio.fetch(retryOptions);
            handler.resolve(response);
            return;
          } catch (retryError) {
            handler.next(error);
            return;
          }
        },
      ),
    );
  }

  bool _isSessionRevoked(DioException error) {
    final data = error.response?.data;

    String? code;
    String? message;

    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final errorMapRaw = map['error'];
      final errorMap = errorMapRaw is Map
          ? Map<String, dynamic>.from(errorMapRaw)
          : <String, dynamic>{};

      code = (errorMap['code'] ?? map['code'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      message = (errorMap['message'] ?? map['message'] ?? '').toString().trim();
    }

    if (code == 'SESSION_REVOKED') return true;
    return message?.toLowerCase().contains('session has been revoked') == true;
  }

  Future<void> _handleForcedLogout() async {
    if (_isForceLogoutHandling) return;
    _isForceLogoutHandling = true;

    authService.logout();
    socketService.disconnect();

    final navigator = AppNavigator.navigatorKey.currentState;
    navigator?.pushNamedAndRemoveUntil(AppRouter.login, (route) => false);

    final context = AppNavigator.navigatorKey.currentContext;
    if (context != null) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Phiên đăng nhập đã bị thu hồi'),
            content: const Text(
              'Tài khoản của bạn đã đăng nhập ở thiết bị khác. Vui lòng đăng nhập lại.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Đăng nhập lại'),
              ),
            ],
          );
        },
      );
    }

    _isForceLogoutHandling = false;
  }

  Future<AuthTokens?> _refreshAccessTokenOnce() async {
    if (_refreshFuture != null) return _refreshFuture!;

    final refreshToken = authService.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return null;

    _refreshFuture = fakeAuthFlowService.refreshToken(refreshToken);
    try {
      final refreshed = await _refreshFuture!;
      final currentUser = authService.currentUser;
      if (currentUser != null) {
        authService.setUser(
          currentUser,
          token: refreshed.accessToken,
          refreshToken: refreshed.refreshToken,
          accessExpiredAt: refreshed.accessExpiredAt,
        );
      }
      return refreshed;
    } catch (_) {
      return null;
    } finally {
      _refreshFuture = null;
    }
  }

  // --- USERS ---

  /// Lấy profile của một user theo ID. Trả về null nếu không tìm thấy.
  Future<UserModel?> getUserById(String userId) async {
    if (userId.isEmpty) return null;
    try {
      final response = await _dio.get('$baseUrl/users/$userId');
      final data = Map<String, dynamic>.from(response.data as Map);
      return UserModel(
        id: _extractId(data['_id'] ?? data['id']),
        fullName: (data['fullName'] ?? data['name'] ?? '').toString(),
        phone: (data['phone'] ?? '').toString(),
        email: data['email']?.toString(),
        avatar: (data['avatar'] ?? '').toString(),
        coverImage: data['coverImage']?.toString(),
        bio: data['bio']?.toString(),
        gender: (data['gender'] ?? 'other').toString(),
        isVerified: data['isVerified'] == true,
      );
    } catch (e) {
      log('❌ getUserById($userId): $e');
      return null;
    }
  }

  static String _extractId(dynamic raw) {
    if (raw == null) return '';
    if (raw is String) return raw;
    if (raw is Map) {
      return (raw['\$oid'] ?? raw['oid'] ?? raw['_id'] ?? '').toString();
    }
    return raw.toString();
  }

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

  /// Tìm cuộc trò chuyện 1-1 đã tồn tại giữa 2 user, hoặc tạo mới nếu chưa có.
  Future<ConversationModel?> findOrCreateDirectConversation({
    required String currentUserId,
    required String targetUserId,
  }) async {
    try {
      // 1. Tìm trong danh sách hội thoại hiện có
      final existing = await getConversations(currentUserId);
      final found = existing.firstWhere(
        (c) =>
            c.type == 'PRIVATE' &&
            c.members.any((m) => m.userId == targetUserId),
        orElse: () => ConversationModel(
          id: '',
          type: '',
          name: '',
          avatar: '',
          members: [],
          lastMessage: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      if (found.id.isNotEmpty) return found;

      // 2. Nếu chưa có, tạo cuộc trò chuyện PRIVATE mới
      final response = await _dio.post(
        '$baseUrl/conversations',
        data: {
          'type': 'PRIVATE',
          'members': [
            {'userId': currentUserId},
            {'userId': targetUserId},
          ],
        },
      );
      return ConversationModel.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } catch (e) {
      log('❌ findOrCreateDirectConversation: $e');
      return null;
    }
  }

  // --- MESSAGES ---

  /// Lấy lịch sử tin nhắn của một cuộc hội thoại
  /// [userId] là tham số bắt buộc để Backend lọc bỏ các tin nhắn người dùng đã nhấn "Xóa phía tôi"
  Future<List<MessageModel>> getMessages(
    String conversationId,
    String userId, {
    int limit = 50,
    int skip = 0,
  }) async {
    try {
      final response = await _dio.get(
        '$baseUrl/messages/conversation/$conversationId',
        queryParameters: {
          'userId':
              userId, // Truyền userId lên để Backend thực hiện lọc deletedBy
          'limit': limit,
          'skip': skip,
        },
      );

      final List data = response.data;
      return data.map((json) => MessageModel.fromJson(json)).toList();
    } catch (e) {
      log('❌ Lỗi getMessages: $e');
      return [];
    }
  }

  /// Lấy danh sách tin nhắn đã ghim của 1 hội thoại
  Future<List<MessageModel>> getPinnedMessages(
    String conversationId,
    String userId,
  ) async {
    try {
      final response = await _dio.get(
        '$baseUrl/messages/conversation/$conversationId',
        queryParameters: {
          'userId': userId,
          'pinned': true,
          'limit': 50,
          'skip': 0,
        },
      );
      final List data = response.data;
      return data.map((json) => MessageModel.fromJson(json)).toList();
    } catch (e) {
      log('❌ Lỗi getPinnedMessages: $e');
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

  /// Xóa lịch sử cuộc trò chuyện (phía tôi) theo hội thoại
  Future<bool> deleteConversationHistoryForMe(
    String conversationId,
    String userId,
  ) async {
    try {
      await _dio.post(
        '$baseUrl/messages/conversation/$conversationId/deleted-by',
        data: {'userId': userId},
      );
      return true;
    } catch (e) {
      log('❌ Lỗi deleteConversationHistoryForMe: $e');
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
      final normalizedFileName = fileName.trim();
      final normalizedContentType = contentType.trim().toLowerCase();
      if (normalizedFileName.isEmpty || normalizedContentType.isEmpty) {
        throw ArgumentError('fileName/contentType không được rỗng');
      }

      final response = await _dio.get(
        '$baseUrl/upload/presigned-url',
        queryParameters: {
          'fileName': normalizedFileName,
          'contentType': normalizedContentType,
        },
      );

      final raw = response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : Map<String, dynamic>.from(response.data as Map);

      final uploadUrl = _pickString(raw, const ['uploadUrl', 'url']);
      final fileUrl = _pickString(raw, const ['fileUrl']);

      if (uploadUrl == null || uploadUrl.isEmpty) return null;

      return {'uploadUrl': uploadUrl, 'fileUrl': fileUrl};
    } catch (e) {
      log('❌ Lỗi lấy Presigned URL: $e');
      return null;
    }
  }

  String? _pickString(Map<String, dynamic> raw, List<String> keys) {
    for (final key in keys) {
      final value = raw[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
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
          headers: {'Content-Type': contentType},
          contentType: contentType,
        ),
        onSendProgress: onSendProgress,
      );
      return response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300;
    } catch (e) {
      log('❌ Lỗi PUT S3: $e');
      return false;
    }
  }

  /// Upload file/media qua backend multipart và trả về fileUrl công khai.
  Future<String?> uploadFileAndGetUrl({
    required String fileName,
    required Uint8List bytes,
    required String contentType,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: fileName),
      });

      final response = await _dio.post(
        '$baseUrl/conversations/avatar/upload',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
        onSendProgress: onSendProgress,
      );

      final raw = response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : Map<String, dynamic>.from(response.data as Map);
      return _pickString(raw, const ['fileUrl']);
    } catch (e) {
      log('❌ Lỗi uploadFileAndGetUrl: $e');
      return null;
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
