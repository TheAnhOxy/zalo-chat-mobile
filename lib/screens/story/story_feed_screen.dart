import 'package:flutter/material.dart';
import '../../data/models/story_model.dart';
import '../../services/story_service.dart';
import '../../core/constants/app_colors.dart';
import '../../core/config/app_config.dart';
import '../../widgets/story/story_list_widget.dart';
import '../../widgets/story/video_thumbnail_player.dart';
import '../../core/utils/image_utils.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'dart:ui' as ui;

class StoryFeedScreen extends StatefulWidget {
  const StoryFeedScreen({super.key});

  @override
  State<StoryFeedScreen> createState() => _StoryFeedScreenState();
}

class _StoryFeedScreenState extends State<StoryFeedScreen> {
  List<ApiStoryModel> _stories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchStories();
  }

  Future<void> _fetchStories() async {
    final stories = await storyService.getStories();
    if (!mounted) return;
    setState(() {
      _stories = stories;
      _isLoading = false;
    });
  }

  void _onStoryTap(ApiStoryModel story, int index) {
    Navigator.pushNamed(context, '/story-viewer', arguments: {
      'stories': [story],
      'initialIndex': 0,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5), // Light grey FB background
      appBar: AppBar(
        title: const Text(
          'Tin',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _fetchStories,
            icon: const Icon(Icons.refresh, color: Colors.black),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchStories,
              child: CustomScrollView(
                slivers: [
                  // Story Horizontal Tray (Thanh ngang)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12, left: 12, right: 12),
                      child: const StoryListWidget(),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  
                  // Feed Grid (Lưới 2 cột)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    sliver: _stories.isEmpty
                        ? SliverToBoxAdapter(child: _buildEmptyState())
                        : SliverGrid(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                return _GridStoryCard(
                                  story: _stories[index],
                                  onTap: () => _onStoryTap(_stories[index], 0),
                                );
                              },
                              childCount: _stories.length,
                            ),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: 0.55, // Taller for 3 columns
                            ),
                          ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.amp_stories_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Chưa có tin nào mới',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Vừa xong';
  if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
  if (diff.inHours < 24) return '${diff.inHours} giờ trước';
  return '${diff.inDays} ngày trước';
}

String _getAbsolutePath(String url) {
  if (url.isEmpty) return '';
  if (url.startsWith('http')) {
    return webSafeImageUrl(url);
  }
  return webSafeImageUrl('${AppConfig.baseUrl}/$url'.replaceAll('//', '/').replaceFirst(':/', '://'));
}

// VideoThumbnailPlayer moved to its own file lib/widgets/story/video_thumbnail_player.dart

class _GridStoryCard extends StatelessWidget {
  final ApiStoryModel story;
  final VoidCallback onTap;

  const _GridStoryCard({required this.story, required this.onTap});

  @override
  Widget build(BuildContext context) {
    String coverUrl = (story.type == 'VIDEO' && story.thumbnailUrl != null && story.thumbnailUrl!.isNotEmpty) 
        ? story.thumbnailUrl! 
        : story.mediaUrl;
    
    coverUrl = _getAbsolutePath(coverUrl);
    final avatarUrl = _getAbsolutePath(story.userAvatar ?? '');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Background Image/Video Thumbnail
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: (story.type == 'VIDEO' && (story.thumbnailUrl == null || story.thumbnailUrl!.isEmpty))
                  ? VideoThumbnailPlayer(videoUrl: _getAbsolutePath(story.mediaUrl))
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        // Background mờ
                        ImageFiltered(
                          imageFilter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                          child: CachedNetworkImage(
                            imageUrl: coverUrl,
                            fit: BoxFit.cover,
                          ),
                        ),
                        // Lớp phủ tối nhẹ cho background
                        Container(color: Colors.black.withOpacity(0.3)),
                        // Ảnh chính (không bị tràn hay nhòe)
                        CachedNetworkImage(
                          imageUrl: coverUrl,
                          fit: BoxFit.contain,
                          placeholder: (_, __) => const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2, 
                              color: Colors.white54,
                            ),
                          ),
                          errorWidget: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image_outlined, color: Colors.white54),
                          ),
                        ),
                      ],
                    ),
              ),
            ),
            // Bottom Gradient
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.4),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withOpacity(0.7),
                    ],
                    stops: const [0.0, 0.2, 0.6, 1.0],
                  ),
                ),
              ),
            ),
            // Top Header: Avatar + User Info (Responsive with Row/Expanded)
            Positioned(
              top: 8,
              left: 8,
              right: 4,
              child: Row(
                children: [
                  // Avatar
                  Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primary, width: 1.5),
                    ),
                    child: CircleAvatar(
                      radius: 12, // Slightly smaller for more text space
                      backgroundImage: avatarUrl.isNotEmpty
                          ? CachedNetworkImageProvider(avatarUrl)
                          : null,
                      backgroundColor: Colors.grey[300],
                      child: story.userAvatar == null || story.userAvatar!.isEmpty
                          ? const Icon(Icons.person, size: 12, color: Colors.white)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Name and Time (Expanded to prevent overflow)
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          story.userName ?? 'User',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 1)),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _timeAgo(story.createdAt),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Views Overlay (Bottom)
            Positioned(
              bottom: 8,
              left: 8,
              child: Text(
                '${story.viewers.length} views',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // Video Icon
            if (story.type == 'VIDEO')
              const Center(
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  color: Colors.white70,
                  size: 44,
                ),
              ),
          ],
        ),
      ),
    );
  }
}


