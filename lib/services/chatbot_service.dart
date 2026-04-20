import 'dart:developer';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import '../core/config/app_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ChatMessage — model tin nhắn trong chat UI
// ─────────────────────────────────────────────────────────────────────────────
class ChatAttachment {
  final String name;
  final String url;
  final String mimeType;

  const ChatAttachment({
    required this.name,
    required this.url,
    required this.mimeType,
  });
}

class ChatMessage {
  final String id;
  final String content;
  final bool isUser; // true = user, false = AI bot
  final DateTime createdAt;
  final List<String> toolsUsed; // Các tools AI đã gọi
  final bool isLoading; // Đang chờ phản hồi
  final List<ChatAttachment> attachments; // File user đã gửi (UI)

  const ChatMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.createdAt,
    this.toolsUsed = const [],
    this.isLoading = false,
    this.attachments = const [],
  });

  ChatMessage copyWith({
    String? content,
    bool? isLoading,
    List<String>? toolsUsed,
    List<ChatAttachment>? attachments,
  }) {
    return ChatMessage(
      id: id,
      content: content ?? this.content,
      isUser: isUser,
      createdAt: createdAt,
      toolsUsed: toolsUsed ?? this.toolsUsed,
      isLoading: isLoading ?? this.isLoading,
      attachments: attachments ?? this.attachments,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ChatbotService — gọi API backend chatbot
// ─────────────────────────────────────────────────────────────────────────────
class ChatbotService {
  static final ChatbotService _instance = ChatbotService._internal();
  factory ChatbotService() => _instance;
  ChatbotService._internal();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60), // AI cần thời gian suy nghĩ
    ),
  );

  String get _baseUrl => AppConfig.baseUrl;

  Future<String> getPresignedDownloadUrl({
    required String fileUrl,
    required String fileName,
  }) async {
    final res = await _dio.get(
      '$_baseUrl/upload/presigned-download-url',
      queryParameters: {
        'url': fileUrl,
        'name': fileName,
      },
    );
    final data = res.data as Map<String, dynamic>;
    final url = data['url']?.toString();
    if (url == null || url.isEmpty) {
      throw Exception('Không lấy được presigned download url');
    }
    return url;
  }

  String _guessMimeType(PlatformFile file) {
    final ext = (file.extension ?? '').toLowerCase();
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'txt':
        return 'text/plain';
      case 'csv':
        return 'text/csv';
      case 'json':
        return 'application/json';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'doc':
        return 'application/msword';
      default:
        return 'application/octet-stream';
    }
  }

  Future<({String fileUrl, String mimeType, String name})> uploadChatbotFile({
    required PlatformFile file,
  }) async {
    // 1) Lấy presigned URL từ backend
    final fileName = file.name;
    final mimeType = _guessMimeType(file);

    final presignRes = await _dio.get(
      '$_baseUrl/upload/presigned-url',
      queryParameters: {
        'fileName': fileName,
        'contentType': mimeType,
      },
    );

    final data = presignRes.data as Map<String, dynamic>;
    final url = data['url']?.toString();
    final fileUrl = data['fileUrl']?.toString();
    if (url == null || url.isEmpty || fileUrl == null || fileUrl.isEmpty) {
      throw Exception('Không lấy được presigned url để upload file');
    }

    // 2) Upload lên S3 qua presigned URL
    final bytes = file.bytes;
    if (bytes != null) {
      await Dio().put(
        url,
        data: Stream.fromIterable([bytes]),
        options: Options(
          headers: {
            Headers.contentLengthHeader: bytes.length,
            Headers.contentTypeHeader: mimeType,
          },
        ),
      );
      return (fileUrl: fileUrl, mimeType: mimeType, name: fileName);
    }

    final path = file.path;
    if (path == null || path.isEmpty) {
      throw Exception('Không đọc được bytes/path của file để upload');
    }

    final f = File(path);
    final length = await f.length();
    final stream = f.openRead();
    await Dio().put(
      url,
      data: stream,
      options: Options(
        headers: {
          Headers.contentLengthHeader: length,
          Headers.contentTypeHeader: mimeType,
        },
      ),
    );

    return (fileUrl: fileUrl, mimeType: mimeType, name: fileName);
  }

  Future<List<({String fileUrl, String mimeType, String name})>> uploadChatbotFiles({
    required List<PlatformFile> files,
  }) async {
    final out = <({String fileUrl, String mimeType, String name})>[];
    for (final f in files) {
      out.add(await uploadChatbotFile(file: f));
    }
    return out;
  }

  /// Gửi tin nhắn tới AI chatbot
  /// [userId] - ID của user hiện tại
  /// [message] - Nội dung tin nhắn
  /// [fileUrl] - URL file trên S3 (nếu có)
  /// [fileMimeType] - MIME type của file
  /// [history] - Lịch sử chat để AI nhớ context
  Future<
      ({
        String reply,
        List<String> toolsUsed,
        String? conversationId,
        String? userMessageId,
      })> sendMessage({
    required String userId,
    required String message,
    String? fileUrl,
    String? fileMimeType,
    List<Map<String, String>>? files,
    String? conversationId,
    List<ChatMessage> history = const [],
  }) async {
    try {
      // Chuyển history sang format backend cần
      final historyPayload = history
          .where((m) => !m.isLoading)
          .map((m) => {
                'role': m.isUser ? 'user' : 'model',
                'content': m.content,
              })
          .toList();

      final body = <String, dynamic>{
        'userId': userId,
        'message': message,
        'history': historyPayload,
      };
      if (conversationId != null && conversationId.isNotEmpty) {
        body['conversationId'] = conversationId;
      }

      if (fileUrl != null && fileUrl.isNotEmpty) {
        body['fileUrl'] = fileUrl;
      }
      if (fileMimeType != null && fileMimeType.isNotEmpty) {
        body['fileMimeType'] = fileMimeType;
      }
      if (files != null && files.isNotEmpty) {
        body['files'] = files;
      }

      final response = await _dio.post(
        '$_baseUrl/chatbot/chat',
        data: body,
      );

      final data = response.data as Map<String, dynamic>;
      final reply = data['reply']?.toString() ?? 'Xin lỗi, có lỗi xảy ra.';
      final tools = (data['toolsUsed'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      final convId = data['conversationId']?.toString();
      final userMessageId = data['userMessageId']?.toString();

      return (
        reply: reply,
        toolsUsed: tools,
        conversationId: convId,
        userMessageId: userMessageId,
      );
    } on DioException catch (e) {
      log('❌ ChatbotService error: ${e.message}');
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return (
          reply: 'Kết nối tới server quá lâu. Vui lòng thử lại.',
          toolsUsed: <String>[],
          conversationId: null,
          userMessageId: null,
        );
      }
      return (
        reply: 'Không thể kết nối tới trợ lý AI. Kiểm tra lại server.',
        toolsUsed: <String>[],
        conversationId: null,
        userMessageId: null,
      );
    } catch (e) {
      log('❌ ChatbotService unexpected: $e');
      return (
        reply: 'Đã có lỗi xảy ra: $e',
        toolsUsed: <String>[],
        conversationId: null,
        userMessageId: null,
      );
    }
  }

  Future<List<Map<String, dynamic>>> listConversations({
    required String userId,
  }) async {
    final res = await _dio.get(
      '$_baseUrl/chatbot/conversations',
      queryParameters: {'userId': userId},
    );
    final data = res.data as Map<String, dynamic>;
    final list = (data['conversations'] as List<dynamic>? ?? []);
    return list.map((e) => e as Map<String, dynamic>).toList();
  }

  Future<String> createConversation({
    required String userId,
    String? title,
  }) async {
    final res = await _dio.post(
      '$_baseUrl/chatbot/conversations',
      data: {'userId': userId, if (title != null) 'title': title},
    );
    final data = res.data as Map<String, dynamic>;
    return data['id']?.toString() ?? '';
  }

  Future<void> deleteConversation({
    required String userId,
    required String conversationId,
  }) async {
    await _dio.delete(
      '$_baseUrl/chatbot/conversations/$conversationId',
      queryParameters: {'userId': userId},
    );
  }

  Future<void> renameConversation({
    required String userId,
    required String conversationId,
    required String title,
  }) async {
    await _dio.patch(
      '$_baseUrl/chatbot/conversations/$conversationId',
      data: {'userId': userId, 'title': title},
    );
  }

  Future<List<Map<String, dynamic>>> getConversationMessages({
    required String userId,
    required String conversationId,
  }) async {
    final res = await _dio.get(
      '$_baseUrl/chatbot/conversations/$conversationId/messages',
      queryParameters: {'userId': userId},
    );
    final data = res.data as Map<String, dynamic>;
    final list = (data['messages'] as List<dynamic>? ?? []);
    return list.map((e) => e as Map<String, dynamic>).toList();
  }

  Future<void> deleteChatbotMessage({
    required String userId,
    required String conversationId,
    required String messageId,
  }) async {
    await _dio.delete(
      '$_baseUrl/chatbot/conversations/$conversationId/messages/$messageId',
      queryParameters: {'userId': userId},
    );
  }
}

final chatbotService = ChatbotService();
