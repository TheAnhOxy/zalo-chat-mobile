import 'package:flutter/material.dart';
import '../../data/models/story_model.dart';
import '../../services/auth_service.dart';
import '../../services/story_service.dart';
import '../../services/story_socket_service.dart';
import '../../core/constants/app_colors.dart';
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
      height: 100,
      color: Colors.white,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
    return GestureDetector(
      onTap: _navigateToCreate,
      child: Container(
        width: 60,
        margin: const EdgeInsets.only(right: 16),
        child: Column(
          children: [
            Stack(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade300, width: 2),
                    image: myAvatar != null && myAvatar.isNotEmpty
                        ? DecorationImage(
                            image: CachedNetworkImageProvider(myAvatar),
                            fit: BoxFit.cover,
                          )
                        : null,
                    color: myAvatar == null || myAvatar.isEmpty ? Colors.grey.shade300 : null,
                  ),
                  child: myAvatar == null || myAvatar.isEmpty
                      ? const Icon(Icons.person, color: Colors.white)
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add_circle,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Tạo mới',
              style: TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryItem(StoryGroupModel group) {
    final bool hasUnseen = group.hasUnseen;
    
    final avatar = group.user.avatar;
    final name = group.user.fullName;

    return GestureDetector(
      onTap: () => _navigateToViewer(group),
      child: Container(
        width: 60,
        margin: const EdgeInsets.only(right: 16),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: hasUnseen ? AppColors.primary : Colors.grey.shade300,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: avatar.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: avatar,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const Icon(Icons.person),
                      )
                    : const Icon(Icons.person, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: TextStyle(
                fontSize: 12,
                color: hasUnseen ? Colors.black : Colors.grey,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
