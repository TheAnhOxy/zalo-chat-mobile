import 'dart:developer';
import 'dart:typed_data';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Mobile/Desktop: dùng video_thumbnail package
Future<Uint8List?> generateVideoThumbnail(
  String? videoPath,
  Uint8List? videoBytes,
) async {
  if (videoPath == null || videoPath.isEmpty) return null;
  try {
    log('🎞 [Thumbnail-IO] Generating from: $videoPath');
    final bytes = await VideoThumbnail.thumbnailData(
      video: videoPath,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 640,
      quality: 75,
      timeMs: 0,
    );
    if (bytes != null) {
      log('✅ [Thumbnail-IO] Done (${bytes.length} bytes)');
    }
    return bytes;
  } catch (e) {
    log('❌ [Thumbnail-IO] Failed: $e');
    return null;
  }
}
