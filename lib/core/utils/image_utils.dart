import 'package:flutter/foundation.dart' show kIsWeb;

/// Trên Flutter Web, ảnh từ S3 bị chặn bởi CORS.
/// Hàm này route ảnh qua backend proxy khi chạy trên web.
String webSafeImageUrl(String url) {
  if (!kIsWeb) return url;
  if (url.isEmpty) return url;
  // Không proxy nếu đã là URL nội bộ
  if (url.startsWith('http://localhost') ||
      url.startsWith('http://127.0.0.1')) {
    return url;
  }
  const backendBase = 'http://localhost:8081';
  return '$backendBase/conversations/avatar/proxy?url=${Uri.encodeComponent(url)}';
}
