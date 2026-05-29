import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../../data/models/story_model.dart';
import '../../services/auth_service.dart';
import '../../services/story_socket_service.dart';
import '../../core/config/app_config.dart';
import '../../widgets/story/video_thumbnail_player.dart';
import 'dart:ui' as ui;

class StoryViewerScreen extends StatefulWidget {
  final List<ApiStoryModel> stories;
  final int initialIndex;

  const StoryViewerScreen({
    super.key,
    required this.stories,
    this.initialIndex = 0,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _progressController;
  int _currentIndex = 0;

  VideoPlayerController? _videoController;
  bool _videoReady = false;

  static const Duration _imageDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);

    _progressController =
        AnimationController(vsync: this, duration: _imageDuration);
    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) _goToNext();
    });

    _loadStory(_currentIndex);
  }

  // ─── Story loading ────────────────────────────────────────────────────────

  Future<void> _loadStory(int index) async {
    _markAsSeen(index);
    final story = widget.stories[index];

    if (story.type == 'VIDEO') {
      await _initVideo(story.mediaUrl);
    } else {
      await _disposeVideo();
      _progressController.duration = _imageDuration;
      _progressController.forward(from: 0);
    }
  }

  Future<void> _initVideo(String url) async {
    await _disposeVideo();
    _progressController.stop();
    _progressController.reset();

    if (!mounted) return;
    setState(() => _videoReady = false);

    final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
    _videoController = ctrl;

    try {
      await ctrl.initialize();
      if (!mounted) return;

      final dur = ctrl.value.duration;
      _progressController.duration =
          dur.inMilliseconds > 0 ? dur : _imageDuration;

      ctrl.addListener(_onVideoTick);
      ctrl.play();
      setState(() => _videoReady = true);
      _progressController.forward(from: 0);
    } catch (_) {
      if (!mounted) return;
      setState(() => _videoReady = false);
      _progressController.duration = _imageDuration;
      _progressController.forward(from: 0);
    }
  }

  void _onVideoTick() {
    final ctrl = _videoController;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (!ctrl.value.isPlaying && ctrl.value.position >= ctrl.value.duration) {
      _goToNext();
    }
  }

  Future<void> _disposeVideo() async {
    final old = _videoController;
    _videoController = null;
    _videoReady = false;
    if (old != null) {
      old.removeListener(_onVideoTick);
      await old.dispose();
    }
  }

  void _markAsSeen(int index) {
    final story = widget.stories[index];
    final me = authService.currentUser;
    if (me != null && !story.viewers.contains(me.id)) {
      storySocketService.emitViewStory(story.id, story.userId, me.id);
      story.viewers.add(me.id);
    }
  }

  // ─── Navigation ───────────────────────────────────────────────────────────

  void _goToNext() {
    if (!mounted) return;
    if (_currentIndex + 1 < widget.stories.length) {
      _pageController.animateToPage(
        _currentIndex + 1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeIn,
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  void _onPageChanged(int idx) {
    _progressController.stop();
    _progressController.reset();
    setState(() {
      _currentIndex = idx;
      _videoReady = false;
    });
    _loadStory(idx);
  }

  void _onTapDown(TapDownDetails d) {
    final w = MediaQuery.of(context).size.width;
    if (d.globalPosition.dx < w / 3) {
      if (_currentIndex > 0) {
        _pageController.animateToPage(_currentIndex - 1,
            duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
      }
    } else {
      _goToNext();
    }
  }

  void _pause() {
    _progressController.stop();
    _videoController?.pause();
  }

  void _resume() {
    _progressController.forward();
    _videoController?.play();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _progressController.dispose();
    _disposeVideo();
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.stories.isEmpty) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;
    final story = widget.stories[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: _onTapDown,
        onLongPress: _pause,
        onLongPressUp: _resume,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── PageView for Stories (Content + Blur Background) ──
            PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: _onPageChanged,
              itemCount: widget.stories.length,
              itemBuilder: (_, i) => _buildStoryPage(widget.stories[i], i),
            ),

            // ── Floating Overlays ──
            
            // Progress bars
            Positioned(
              top: topPad + 12,
              left: 12,
              right: 12,
              child: _buildProgressBars(),
            ),

            // User header
            Positioned(
              top: topPad + 40,
              left: 16,
              right: 16,
              child: _buildUserHeader(story),
            ),

            // Caption above interaction bar
            if (story.caption.isNotEmpty)
              Positioned(
                bottom: botPad + 70,
                left: 16,
                right: 16,
                child: _buildCaption(story.caption),
              ),

            // Bottom Interaction Bar (Facebook style)
            Positioned(
              bottom: botPad + 12,
              left: 16,
              right: 16,
              child: _buildBottomReplyBar(story),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryPage(ApiStoryModel story, int index) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Blurred Background layer
        _buildBlurredBackground(story, index),
        
        // 2. Black semi-transparent overlay to darken background
        Container(color: Colors.black.withOpacity(0.35)),

        // 3. Main Content Card
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 100, horizontal: 8),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: _buildStoryContent(story, index),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBlurredBackground(ApiStoryModel story, int index) {
    // For background, we use the same media but with BoxFit.cover and Sigma blur
    return Container(
      width: double.infinity,
      height: double.infinity,
      child: ImageFiltered(
        imageFilter: ColorFilter.mode(Colors.black.withOpacity(0.1), BlendMode.darken), // Subtle darken
        child: ShaderMask(
          shaderCallback: (rect) {
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black, Colors.black.withOpacity(0.1), Colors.black],
            ).createShader(rect);
          },
          blendMode: BlendMode.dstIn,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: (story.type == 'VIDEO' && index == _currentIndex && _videoReady && _videoController != null)
                ? VideoPlayer(_videoController!)
                : (story.type == 'VIDEO' && (story.thumbnailUrl == null || story.thumbnailUrl!.isEmpty))
                    ? VideoThumbnailPlayer(videoUrl: _getAbsolutePath(story.mediaUrl))
                    : CachedNetworkImage(
                        imageUrl: _getAbsolutePath(story.type == 'VIDEO' ? (story.thumbnailUrl ?? story.mediaUrl) : story.mediaUrl),
                        fit: BoxFit.cover,
                      ),
          ),
        ),
      ),
    );
  }

  // ─── Story content ────────────────────────────────────────────────────────

  Widget _buildStoryContent(ApiStoryModel story, int index) {
    if (story.type == 'VIDEO') {
      return _buildVideoContent(index);
    }
    return _buildImageContent(story.mediaUrl);
  }

  Widget _buildImageContent(String url) {
    return CachedNetworkImage(
      imageUrl: _getAbsolutePath(url),
      fit: BoxFit.cover, // Fill the card
      width: double.infinity,
      height: double.infinity,
      placeholder: (_, __) => const Center(
        child: CircularProgressIndicator(
          color: Colors.white54,
          strokeWidth: 2,
        ),
      ),
      errorWidget: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 56),
      ),
    );
  }

  Widget _buildVideoContent(int index) {
    // Only render active page's video
    if (index != _currentIndex) return const SizedBox.expand();

    if (!_videoReady || _videoController == null) {
      final story = widget.stories[index];
      final thumb = story.thumbnailUrl ?? '';
      return Stack(
        fit: StackFit.expand,
        children: [
          if (thumb.isNotEmpty)
            CachedNetworkImage(
              imageUrl: _getAbsolutePath(thumb),
              fit: BoxFit.cover,
            )
          else
            VideoThumbnailPlayer(videoUrl: _getAbsolutePath(story.mediaUrl)),
          const Center(
            child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2),
          ),
        ],
      );
    }

    return VideoPlayer(_videoController!);
  }

  String _getAbsolutePath(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    return '${AppConfig.baseUrl}/$url'.replaceAll('//', '/').replaceFirst(':/', '://');
  }

  // ─── UI pieces ────────────────────────────────────────────────────────────

  Widget _buildProgressBars() {
    return Row(
      children: List.generate(widget.stories.length, (i) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: AnimatedBuilder(
              animation: _progressController,
              builder: (_, __) {
                double val = 0;
                if (i < _currentIndex) val = 1.0;
                if (i == _currentIndex) val = _progressController.value;
                return LinearProgressIndicator(
                  value: val,
                  minHeight: 2,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                );
              },
            ),
          ),
        );
      }),
    );
  }

  Widget _buildUserHeader(ApiStoryModel story) {
    final avatar = story.userAvatar ?? '';
    return Row(
      children: [
        // Avatar
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1),
          ),
          child: ClipOval(
            child: avatar.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: _getAbsolutePath(avatar),
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        const Icon(Icons.person, color: Colors.white70),
                  )
                : const Icon(Icons.person, color: Colors.white70),
          ),
        ),
        const SizedBox(width: 10),
        // Name + time
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                story.userName ?? 'User',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  shadows: [
                    Shadow(blurRadius: 8, color: Colors.black),
                    Shadow(blurRadius: 4, color: Colors.black54),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _timeAgo(story.createdAt),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        // Video icon badge
        if (story.type == 'VIDEO')
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.75),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam, color: Colors.white, size: 13),
                SizedBox(width: 3),
                Text(
                  'VIDEO',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        // Close button
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            child: const Icon(Icons.close, color: Colors.white, size: 24),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomReplyBar(ApiStoryModel story) {
    return Row(
      children: [
        // Text field
        Expanded(
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: const Row(
              children: [
                Expanded(
                  child: Text(
                    'Gửi tin nhắn...',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Reaction icon (Heart)
        _buildReactionIcon(Icons.favorite_rounded, Colors.redAccent),
        const SizedBox(width: 10),
        // Share icon
        _buildReactionIcon(Icons.share_rounded, Colors.white),
      ],
    );
  }

  Widget _buildReactionIcon(IconData icon, Color color) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 22),
    );
  }

  Widget _buildCaption(String caption) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        caption,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.4,
          shadows: [Shadow(blurRadius: 6, color: Colors.black)],
        ),
        textAlign: TextAlign.start,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    return '${diff.inDays} ngày trước';
  }
}
