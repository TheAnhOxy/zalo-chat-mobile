import 'package:flutter/material.dart';
import '../../data/models/story_model.dart';
import '../../services/auth_service.dart';
import '../../services/story_service.dart';
import '../../services/story_socket_service.dart';
import '../../core/constants/app_colors.dart';
import '../../core/config/app_config.dart';
import '../../widgets/story/video_thumbnail_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

class StoryListWidget extends StatefulWidget {
  const StoryListWidget({super.key});

  @override
  State<StoryListWidget> createState() => _StoryListWidgetState();
}

class _StoryListWidgetState extends State<StoryListWidget> {
  final List<StoryGroupModel> _groups = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchStories();
    storySocketService.init();

    storySocketService.onNewStory.listen((story) {
      if (!mounted) return;
      setState(() {
        final groupIdx = _groups.indexWhere((g) => g.user.id == story.userId);
        if (groupIdx != -1) {
          final group = _groups.removeAt(groupIdx);
          group.stories.add(story); // story.userName/userAvatar có thể null nhưng backend tạo sẽ đẩy đủ
          // Update lastStoryTime & move to top
          _groups.insert(0, StoryGroupModel(
            user: group.user,
            hasUnseen: true, // vửa có story mới tức là chưa xem
            lastStoryTime: story.createdAt,
            stories: group.stories,
          ));
        } else {
          // Tạo group mới nếu user chưa có
          _groups.insert(0, StoryGroupModel(
            user: StoryUserModel(
              id: story.userId,
              fullName: story.userName ?? 'User',
              avatar: story.userAvatar ?? '',
            ),
            hasUnseen: true,
            lastStoryTime: story.createdAt,
            stories: [story],
          ));
        }
      });
    });

    storySocketService.onStorySeen.listen((data) {
      if (!mounted) return;
      final storyId = data['storyId'];
      final viewerId = data['viewerId'];
      
      setState(() {
        for (int i = 0; i < _groups.length; i++) {
          final group = _groups[i];
          final storyIdx = group.stories.indexWhere((s) => s.id == storyId);
          if (storyIdx != -1) {
            if (!group.stories[storyIdx].viewers.contains(viewerId)) {
               group.stories[storyIdx].viewers.add(viewerId);
            }
            // Re-eval hasUnseen for me
            final me = authService.currentUser?.id;
            if (me != null && viewerId == me) {
              final newHasUnseen = group.stories.any((s) => !s.viewers.contains(me));
              _groups[i] = StoryGroupModel(
                 user: group.user,
                 hasUnseen: newHasUnseen,
                 lastStoryTime: group.lastStoryTime,
                 stories: group.stories,
              );
            }
            break; // found and updated
          }
        }
      });
    });
  }

  Future<void> _fetchStories() async {
    final userId = authService.currentUser?.id;
    if (userId == null) return;
    final groups = await storyService.getStoryFeed(userId);
    if (!mounted) return;
    setState(() {
      _groups.clear();
      _groups.addAll(groups);
      _isLoading = false;
    });
  }

  void _navigateToCreate() {
    Navigator.pushNamed(context, '/create-story');
  }

  void _navigateToViewer(StoryGroupModel group) {
    final me = authService.currentUser?.id ?? '';
    // Tìm story chưa xem đầu tiên
    int initialIdx = group.stories.indexWhere((s) => !s.viewers.contains(me));
    if (initialIdx == -1) initialIdx = 0; // Nếu xem hết rồi thì xem từ đầu

    Navigator.pushNamed(context, '/story-viewer', arguments: {
      'stories': group.stories,
      'initialIndex': initialIdx,
    });
  }

  @override
  void dispose() {
    storySocketService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = authService.currentUser;
    return Container(
      height: 200,
      color: Colors.white,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _groups.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildCreateStoryItem(me?.avatar);
                }
                final group = _groups[index - 1];
                return _buildStoryItem(group);
              },
            ),
    );
  }

  Widget _buildCreateStoryItem(String? myAvatar) {
    final avatarUrl = _getAbsolutePath(myAvatar ?? '');
    return GestureDetector(
      onTap: _navigateToCreate,
      child: Container(
        width: 110,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey[200],
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Top portion: Avatar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 45,
              child: avatarUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: avatarUrl,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: Colors.grey[300],
                      child: const Icon(Icons.person, color: Colors.white, size: 40),
                    ),
            ),
            // Bottom portion: white box
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 45,
              child: Container(
                color: Colors.white,
                child: const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 15),
                    child: Text(
                      'Tạo Tin',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Floating "+" button
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: const Icon(
                    Icons.add,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryItem(StoryGroupModel group) {
    final bool hasUnseen = group.hasUnseen;
    final lastStory = group.stories.last; // Use the latest one for preview
    
    String? previewUrl;
    if (lastStory.type == 'VIDEO') {
      previewUrl = lastStory.thumbnailUrl ?? lastStory.mediaUrl;
    } else {
      previewUrl = lastStory.mediaUrl;
    }
    
    final avatarUrl = _getAbsolutePath(group.user.avatar);
    final featuredUrl = _getAbsolutePath(previewUrl ?? '');
    final name = group.user.fullName;

    return GestureDetector(
      onTap: () => _navigateToViewer(group),
      child: Container(
        width: 110,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey[200],
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background Image (Featured Story)
            (lastStory.type == 'VIDEO' && (lastStory.thumbnailUrl == null || lastStory.thumbnailUrl!.isEmpty))
              ? VideoThumbnailPlayer(videoUrl: _getAbsolutePath(lastStory.mediaUrl))
              : CachedNetworkImage(
                  imageUrl: featuredUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: Colors.grey[300]),
                  errorWidget: (_, __, ___) => Container(color: Colors.grey[300]),
                ),
            // Dark gradient overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.1),
                    Colors.transparent,
                    Colors.black.withOpacity(0.6),
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),
            // Avatar (Top left)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: hasUnseen ? AppColors.primary : Colors.white,
                    width: 2,
                  ),
                ),
                child: ClipOval(
                  child: avatarUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: avatarUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const Icon(Icons.person, size: 20),
                        )
                      : const Icon(Icons.person, color: Colors.grey, size: 20),
                ),
              ),
            ),
            // User name (Bottom)
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 2, color: Colors.black)],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _getAbsolutePath(String url) {
  if (url.isEmpty) return '';
  if (url.startsWith('http')) return url;
  return '${AppConfig.baseUrl}/$url'.replaceAll('//', '/').replaceFirst(':/', '://');
}
