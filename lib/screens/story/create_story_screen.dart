import 'dart:typed_data';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Thêm foundation.dart cho kIsWeb
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../../services/story_service.dart';
import '../../services/auth_service.dart';
import '../../services/api_service.dart';
import '../../core/constants/app_colors.dart';

enum _MediaType { image, video }

class CreateStoryScreen extends StatefulWidget {
  const CreateStoryScreen({super.key});

  @override
  State<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends State<CreateStoryScreen> {
  XFile? _pickedFile;
  Uint8List? _previewBytes;
  _MediaType _mediaType = _MediaType.image;

  // Video preview controller
  VideoPlayerController? _videoController;
  bool _videoReady = false;
  bool _videoPlaying = false;

  final TextEditingController _captionController = TextEditingController();
  bool _isUploading = false;
  double _uploadProgress = 0;

  // ─── Pick media ──────────────────────────────────────────────────────────
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (picked == null) return;
    await _disposeVideo();
    final bytes = await picked.readAsBytes();
    setState(() {
      _pickedFile = picked;
      _previewBytes = bytes;
      _mediaType = _MediaType.image;
      _videoReady = false;
    });
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 60),
    );
    if (picked == null) return;

    // Read bytes for upload later, but use network URL for preview on web
    final bytes = await picked.readAsBytes();
    setState(() {
      _pickedFile = picked;
      _previewBytes = bytes;
      _mediaType = _MediaType.video;
      _videoReady = false;
    });
    await _initVideoPreview(picked.path);
  }

  Future<void> _initVideoPreview(String path) async {
    await _disposeVideo();

    VideoPlayerController ctrl;
    // Đảm bảo parse uri không lỗi trên web với blob url
    if (kIsWeb) {
      // Phải ignore warning deprecated nếu network() an toàn hơn trên web cho blob, nhưng networkUrl vẫn là chuẩn mới. 
      // Dùng networkUrl với Uri.parse thường lỗi trên Web nếu scheme lạ, nên fallback network
      ctrl = VideoPlayerController.network(path);
    } else {
      ctrl = VideoPlayerController.networkUrl(Uri.parse(path));
    }

    _videoController = ctrl;
    try {
      await ctrl.initialize();
      ctrl.setLooping(true);
      if (!mounted) return;
      setState(() {
        _videoReady = true;
        _videoPlaying = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _videoReady = false);
    }
  }

  Future<void> _disposeVideo() async {
    final old = _videoController;
    _videoController = null;
    _videoReady = false;
    _videoPlaying = false;
    if (old != null) await old.dispose();
  }

  void _toggleVideoPlayback() {
    if (_videoController == null || !_videoReady) return;
    setState(() {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
        _videoPlaying = false;
      } else {
        _videoController!.play();
        _videoPlaying = true;
      }
    });
  }

  // ─── Upload & Post ────────────────────────────────────────────────────────
  Future<void> _uploadStory() async {
    if (_pickedFile == null || _previewBytes == null) return;
    final user = authService.currentUser;
    if (user == null) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    try {
      final fileName = _pickedFile!.name.isEmpty
          ? (_mediaType == _MediaType.image ? 'story.jpg' : 'story.mp4')
          : _pickedFile!.name;
      final contentType =
          _mediaType == _MediaType.image ? 'image/jpeg' : 'video/mp4';

      // ─── Extract Thumbnail if VIDEO ───
      String? thumbnailUrl;
      if (_mediaType == _MediaType.video) {
        try {
          final thumbBytes = await VideoThumbnail.thumbnailData(
            video: _pickedFile!.path,
            imageFormat: ImageFormat.JPEG,
            maxWidth: 512,
            quality: 75,
            timeMs: 1000, // 1 second mark
          );
          if (thumbBytes != null) {
            thumbnailUrl = await apiService.uploadFileAndGetUrl(
              fileName: 'thumb_${DateTime.now().millisecondsSinceEpoch}.jpg',
              bytes: thumbBytes,
              contentType: 'image/jpeg',
            );
          }
        } catch (e) {
          log('❌ Error generating thumbnail: $e');
        }
      }

      final mediaUrl = await apiService.uploadFileAndGetUrl(
        fileName: fileName,
        bytes: _previewBytes!,
        contentType: contentType,
        onSendProgress: (sent, total) {
          if (total > 0 && mounted) {
            setState(() => _uploadProgress = sent / total);
          }
        },
      );

      if (mediaUrl != null && mounted) {
        final expiresAt = DateTime.now().add(const Duration(hours: 24));
        final newStory = await storyService.createStory(
          userId: user.id,
          mediaUrl: mediaUrl,
          type: _mediaType == _MediaType.image ? 'IMAGE' : 'VIDEO',
          caption: _captionController.text.trim(),
          expiresAt: expiresAt,
          thumbnailUrl: thumbnailUrl,
        );
        if (newStory != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Đăng Story thành công!'),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.pop(context);
        }
      } else {
        _showError('Upload thất bại, vui lòng thử lại');
      }
    } catch (e) {
      _showError('Lỗi: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  @override
  void dispose() {
    _captionController.dispose();
    _disposeVideo();
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Hủy bỏ',
        ),
        title: const Text(
          'Tạo Story mới',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: _previewBytes == null ? _buildPickerUI() : _buildPreviewUI(),
      ),
    );
  }

  // ─── Picker UI ────────────────────────────────────────────────────────────
  Widget _buildPickerUI() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white12, width: 2),
              ),
              child: const Icon(
                Icons.add_photo_alternate_outlined,
                color: Colors.white38,
                size: 52,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Chọn nội dung để chia sẻ',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 36),
            _PickerButton(
              icon: Icons.image_outlined,
              label: 'Chọn ảnh',
              subtitle: 'JPG, PNG, WEBP',
              color: AppColors.primary,
              onTap: _pickImage,
            ),
            const SizedBox(height: 16),
            _PickerButton(
              icon: Icons.videocam_outlined,
              label: 'Chọn video',
              subtitle: 'Tối đa 60 giây',
              color: Colors.redAccent,
              onTap: _pickVideo,
            ),
            const SizedBox(height: 32),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Hủy bỏ',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Preview UI ───────────────────────────────────────────────────────────
  Widget _buildPreviewUI() {
    return Column(
      children: [
        // Media preview — fill remaining space
        Expanded(
          child: ClipRect(
            child: _mediaType == _MediaType.image
                ? _buildImagePreview()
                : _buildVideoPreview(),
          ),
        ),

        // Caption + controls bar
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildImagePreview() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(color: Colors.black),
        if (kIsWeb)
          Image.network(
            _pickedFile!.path,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
          )
        else if (_previewBytes != null)
          Image.memory(
            _previewBytes!,
            fit: BoxFit.contain, // contain: không bị bể, không tràn
            width: double.infinity,
            height: double.infinity,
          ),
        // Badge
        Positioned(
          top: 12,
          left: 12,
          child: _MediaBadge(label: 'ẢNH', icon: Icons.image, color: Colors.black54),
        ),
      ],
    );
  }

  Widget _buildVideoPreview() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(color: Colors.black),
        // Video player or loading
        if (_videoReady && _videoController != null)
          Center(
            child: AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio.isFinite &&
                      _videoController!.value.aspectRatio > 0
                  ? _videoController!.value.aspectRatio
                  : 9 / 16,
              child: VideoPlayer(_videoController!),
            ),
          )
        else
          const CircularProgressIndicator(color: Colors.white),

        // Play/Pause overlay
        if (_videoReady)
          GestureDetector(
            onTap: _toggleVideoPlayback,
            child: AnimatedOpacity(
              opacity: _videoPlaying ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _videoPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
          ),

        // Badge
        Positioned(
          top: 12,
          left: 12,
          child: _MediaBadge(
            label: 'VIDEO',
            icon: Icons.videocam,
            color: Colors.red.withOpacity(0.8),
          ),
        ),

        // Duration info
        if (_videoReady && _videoController != null)
          Positioned(
            bottom: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ValueListenableBuilder(
                valueListenable: _videoController!,
                builder: (_, VideoPlayerValue val, __) {
                  final pos = val.position;
                  final dur = val.duration;
                  String fmt(Duration d) =>
                      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
                  return Text(
                    '${fmt(pos)} / ${fmt(dur)}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Caption input
          TextField(
            controller: _captionController,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            maxLines: 2,
            maxLength: 200,
            decoration: InputDecoration(
              hintText: 'Thêm caption cho Story của bạn...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
              counterStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white10,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // X Hủy & Re-pick and Post row
          Row(
            children: [
              if (!_isUploading) ...[
                // Nút X Hủy quay lại màn tin nhắn
                InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.redAccent, size: 22),
                  ),
                ),
                const SizedBox(width: 12),
                // Nút Đổi/Chọn lại
                _SmallButton(
                  icon: Icons.photo_library_outlined,
                  label: 'Chọn lại',
                  onTap: _mediaType == _MediaType.image ? _pickImage : _pickVideo,
                ),
              ],
              const Spacer(),
              if (!_isUploading)
                ElevatedButton(
                  onPressed: _uploadStory,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: Size.zero, // Ngăn chặn lỗi w=Infinity từ main theme
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Đăng', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      SizedBox(width: 6),
                      Icon(Icons.send, size: 18),
                    ],
                  ),
                ),
            ],
          ),
          // Upload progress
          if (_isUploading) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _uploadProgress > 0 ? _uploadProgress : null,
                backgroundColor: Colors.white12,
                color: AppColors.primary,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _uploadProgress > 0
                  ? 'Đang tải lên ${(_uploadProgress * 100).toInt()}%...'
                  : 'Đang xử lý...',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Helper Widgets ──────────────────────────────────────────────────────────

class _MediaBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _MediaBadge({required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 13),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
}

class _PickerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _PickerButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            border: Border.all(color: color.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                  ),
                ],
              ),
              const Spacer(),
              Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.4)),
            ],
          ),
        ),
      );
}

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SmallButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white60, size: 16),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Colors.white60, fontSize: 13)),
            ],
          ),
        ),
      );
}
