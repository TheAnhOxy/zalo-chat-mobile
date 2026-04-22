import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoThumbnailPlayer extends StatefulWidget {
  final String videoUrl;

  const VideoThumbnailPlayer({super.key, required this.videoUrl});

  @override
  State<VideoThumbnailPlayer> createState() => _VideoThumbnailPlayerState();
}

class _VideoThumbnailPlayerState extends State<VideoThumbnailPlayer> {
  VideoPlayerController? _controller;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await _controller!.initialize();
      await _controller!.setVolume(0); // Mute
      // Seek to 1s to get a good frame
      await _controller!.seekTo(const Duration(seconds: 1));
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _isError = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isError) {
      return Container(
        color: Colors.black12,
        child: const Icon(Icons.broken_image, color: Colors.grey, size: 24),
      );
    }
    if (_controller == null || !_controller!.value.isInitialized) {
      return Container(
        color: Colors.black12,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: _controller!.value.size.width,
        height: _controller!.value.size.height,
        child: VideoPlayer(_controller!),
      ),
    );
  }
}
