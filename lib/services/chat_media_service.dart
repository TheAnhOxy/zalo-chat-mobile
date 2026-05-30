import 'dart:developer';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../core/utils/thumbnail_helper.dart' as thumbnail_helper;
import 'api_service.dart';

typedef ChatMediaProgressCallback = void Function(double progress);

class ChatMediaUploadResult {
  final String fileUrl;
  final String fileName;
  final int fileSize;
  final String contentType;
  final String? thumbnailUrl;

  const ChatMediaUploadResult({
    required this.fileUrl,
    required this.fileName,
    required this.fileSize,
    required this.contentType,
    this.thumbnailUrl,
  });
}

class ChatMediaService {
  ChatMediaService._internal();

  static final ChatMediaService _instance = ChatMediaService._internal();
  factory ChatMediaService() => _instance;

  final ImagePicker _imagePicker = ImagePicker();

  Future<XFile?> pickImage() async {
    return _imagePicker.pickImage(source: ImageSource.gallery);
  }

  Future<XFile?> pickVideo() async {
    return _imagePicker.pickVideo(source: ImageSource.gallery);
  }

  Future<List<XFile>> pickMultipleMedia() async {
    return _imagePicker.pickMultipleMedia();
  }

  Future<PlatformFile?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return null;
    return result.files.first;
  }

  String normalizeImageFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return fileName;

    final dot = fileName.lastIndexOf('.');
    final baseName = dot > 0 ? fileName.substring(0, dot) : fileName;
    return '$baseName.jpg';
  }

  String detectContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.zip')) return 'application/zip';
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.avi')) return 'video/x-msvideo';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (lower.endsWith('.webm')) return 'video/webm';
    return 'application/octet-stream';
  }

  String detectImageContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }

  String safeFileExtension(String fileName, {String fallback = 'bin'}) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return fallback;
    return fileName.substring(dot + 1).toLowerCase();
  }

  Future<Uint8List?> generateVideoThumbnail(
    String videoPath,
    Uint8List videoBytes,
  ) async {
    log('🎞 [ChatMediaService] Generating thumbnail... path=$videoPath');
    final bytes = await thumbnail_helper.generateVideoThumbnail(
      videoPath,
      videoBytes,
    );
    if (bytes != null) {
      log('✅ [ChatMediaService] Thumbnail ready (${bytes.length} bytes)');
    } else {
      log('⚠️ [ChatMediaService] Thumbnail is null');
    }
    return bytes;
  }

  Future<ChatMediaUploadResult> uploadPickedImage(
    XFile picked, {
    ChatMediaProgressCallback? onProgress,
  }) async {
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) throw Exception('Image rỗng');

    final rawFileName = picked.name.isNotEmpty
        ? picked.name
        : (picked.path.isNotEmpty ? picked.path.split('/').last : 'image.jpg');
    final fileName = normalizeImageFileName(rawFileName);
    final contentType = detectImageContentType(fileName);
    final fileUrl = await _uploadBytesViaBackend(
      fileName: fileName,
      bytes: bytes,
      contentType: contentType,
      onUploadProgress: onProgress == null
          ? null
          : (sent, total) {
              if (total <= 0) return;
              onProgress(sent / total);
            },
    );

    return ChatMediaUploadResult(
      fileUrl: fileUrl,
      fileName: fileName,
      fileSize: bytes.length,
      contentType: contentType,
    );
  }

  Future<ChatMediaUploadResult> uploadPickedFile(
    PlatformFile file, {
    ChatMediaProgressCallback? onProgress,
  }) async {
    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null && file.path!.isNotEmpty) {
      bytes = await XFile(file.path!).readAsBytes();
    }
    if (bytes == null) throw Exception('Không đọc được dữ liệu file');

    final contentType = detectContentType(file.name);
    final fileUrl = await _uploadBytesViaBackend(
      fileName: file.name,
      bytes: bytes,
      contentType: contentType,
      onUploadProgress: onProgress == null
          ? null
          : (sent, total) {
              if (total <= 0) return;
              onProgress(sent / total);
            },
    );

    return ChatMediaUploadResult(
      fileUrl: fileUrl,
      fileName: file.name,
      fileSize: file.size,
      contentType: contentType,
    );
  }

  Future<ChatMediaUploadResult> uploadPickedVideo(
    XFile picked, {
    ChatMediaProgressCallback? onProgress,
  }) async {
    final videoBytes = await picked.readAsBytes();
    if (videoBytes.isEmpty) throw Exception('Video rỗng');

    final now = DateTime.now().millisecondsSinceEpoch;
    final videoExt = safeFileExtension(picked.name, fallback: 'mp4');
    final videoFileName = picked.name.isNotEmpty
        ? picked.name
        : 'video_$now.$videoExt';

    final thumbnailBytes = await generateVideoThumbnail(
      picked.path,
      videoBytes,
    );

    String? thumbnailUrl;
    if (thumbnailBytes != null && thumbnailBytes.isNotEmpty) {
      thumbnailUrl = await _uploadBytesViaBackend(
        fileName: 'video_thumb_$now.jpg',
        bytes: thumbnailBytes,
        contentType: 'image/jpeg',
        onUploadProgress: onProgress == null
            ? null
            : (sent, total) {
                if (total <= 0) return;
                onProgress((sent / total) * 0.3);
              },
      );
    }

    final videoProgressStart = thumbnailUrl != null ? 0.3 : 0.0;
    final videoUrl = await _uploadBytesViaBackend(
      fileName: videoFileName,
      bytes: videoBytes,
      contentType: 'video/mp4',
      onUploadProgress: onProgress == null
          ? null
          : (sent, total) {
              if (total <= 0) return;
              onProgress(
                videoProgressStart + (sent / total) * (1 - videoProgressStart),
              );
            },
    );

    return ChatMediaUploadResult(
      fileUrl: videoUrl,
      fileName: videoFileName,
      fileSize: videoBytes.length,
      contentType: 'video/mp4',
      thumbnailUrl: thumbnailUrl,
    );
  }

  Future<ChatMediaUploadResult> uploadVoiceRecording(
    String voicePath,
    int durationSec, {
    ChatMediaProgressCallback? onProgress,
  }) async {
    final bytes = await XFile(voicePath).readAsBytes();
    if (bytes.isEmpty) throw Exception('Voice rỗng');

    final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final signed = await apiService.getPresignedUrl(fileName, 'audio/mpeg');
    if (signed == null) throw Exception('Không lấy được presigned URL');

    final uploadUrl = signed['uploadUrl']?.toString();
    final fileUrl = signed['fileUrl']?.toString();
    if (uploadUrl == null || uploadUrl.isEmpty) {
      throw Exception('Thiếu uploadUrl');
    }
    if (fileUrl == null || fileUrl.isEmpty) throw Exception('Thiếu fileUrl');

    final uploaded = await apiService.uploadFileToS3(
      uploadUrl,
      bytes,
      'audio/mpeg',
      onSendProgress: onProgress == null
          ? null
          : (sent, total) {
              if (total <= 0) return;
              onProgress(sent / total);
            },
    );

    if (!uploaded) throw Exception('Upload voice thất bại');

    return ChatMediaUploadResult(
      fileUrl: fileUrl,
      fileName: fileName,
      fileSize: bytes.length,
      contentType: 'audio/mpeg',
    );
  }

  Future<String> _uploadBytesViaBackend({
    required String fileName,
    required Uint8List bytes,
    required String contentType,
    void Function(int sent, int total)? onUploadProgress,
  }) async {
    final fileUrl = await apiService.uploadFileAndGetUrl(
      fileName: fileName,
      bytes: bytes,
      contentType: contentType,
      onSendProgress: onUploadProgress,
    );
    if (fileUrl == null || fileUrl.isEmpty) {
      throw Exception('Upload file thất bại');
    }
    return fileUrl;
  }
}
