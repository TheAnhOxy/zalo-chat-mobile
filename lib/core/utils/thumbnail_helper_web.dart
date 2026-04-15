// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

/// Web: dùng HTMLVideoElement + Canvas để capture frame đầu tiên
Future<Uint8List?> generateVideoThumbnail(
  String? videoPath,
  Uint8List? videoBytes,
) async {
  // Ưu tiên dùng blob URL từ image_picker (picked.path trên web là blob URL)
  String? src = videoPath?.isNotEmpty == true ? videoPath : null;
  String? createdBlobUrl;

  if (src == null) {
    if (videoBytes == null) return null;
    final blob = html.Blob([videoBytes], 'video/mp4');
    createdBlobUrl = html.Url.createObjectUrlFromBlob(blob);
    src = createdBlobUrl;
  }

  try {
    final completer = Completer<Uint8List?>();

    final video = html.VideoElement()
      ..src = src
      ..muted = true
      ..autoplay = false
      ..preload = 'auto'
      ..crossOrigin = 'anonymous';

    // Capture frame khi dữ liệu frame đầu tiên sẵn sàng
    late StreamSubscription loadSub;
    loadSub = video.onLoadedData.listen((_) {
      loadSub.cancel();
      if (completer.isCompleted) return;
      try {
        final vw = video.videoWidth > 0 ? video.videoWidth : 320;
        final vh = video.videoHeight > 0 ? video.videoHeight : 240;
        final maxW = 640;
        final scale = vw > maxW ? maxW / vw : 1.0;
        final w = (vw * scale).round().clamp(1, 1280);
        final h = (vh * scale).round().clamp(1, 1280);

        final canvas = html.CanvasElement(width: w, height: h);
        canvas.context2D.drawImageScaled(video, 0, 0, w, h);

        final dataUrl = canvas.toDataUrl('image/jpeg', 0.80);
        if (dataUrl.length < 100 || !dataUrl.contains(',')) {
          log('⚠️ [Thumbnail-Web] Canvas trống');
          completer.complete(null);
          return;
        }

        final base64Str = dataUrl.split(',')[1];
        final bytes = base64Decode(base64Str);
        log('✅ [Thumbnail-Web] Captured ${w}x${h} (${bytes.length} bytes)');
        completer.complete(bytes);
      } catch (e) {
        log('❌ [Thumbnail-Web] Canvas error: $e');
        completer.complete(null);
      }
    });

    video.onError.listen((_) {
      if (!completer.isCompleted) {
        log('❌ [Thumbnail-Web] Video load error');
        completer.complete(null);
      }
    });

    // Timeout 20 giây
    Future.delayed(const Duration(seconds: 20), () {
      if (!completer.isCompleted) {
        loadSub.cancel();
        log('⏰ [Thumbnail-Web] Timeout');
        completer.complete(null);
      }
    });

    return await completer.future;
  } catch (e) {
    log('❌ [Thumbnail-Web] Failed: $e');
    return null;
  } finally {
    if (createdBlobUrl != null) {
      html.Url.revokeObjectUrl(createdBlobUrl);
    }
  }
}
