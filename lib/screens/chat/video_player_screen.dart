import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;

  const VideoPlayerScreen({
    super.key,
    required this.videoUrl,
    this.title = 'Video',
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );
      await controller.initialize();

      final chewie = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowPlaybackSpeedChanging: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.white,
          handleColor: Colors.white,
          backgroundColor: Colors.white.withOpacity(0.2),
          bufferedColor: Colors.white.withOpacity(0.45),
        ),
      );

      if (!mounted) {
        chewie.dispose();
        await controller.dispose();
        return;
      }

      setState(() {
        _videoController = controller;
        _chewieController = chewie;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Không thể tải video. Vui lòng thử lại sau.';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : _errorMessage != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.white70,
                          size: 56,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _isLoading = true;
                              _errorMessage = null;
                            });
                            _initPlayer();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Thử lại'),
                        ),
                      ],
                    ),
                  )
                : AspectRatio(
                    aspectRatio: _videoController?.value.aspectRatio ??
                        (16 / 9),
                    child: Chewie(controller: _chewieController!),
                  ),
      ),
    );
  }
}
