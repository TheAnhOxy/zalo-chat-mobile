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
  final List<ApiStoryModel> _stories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchStories();
    storySocketService.init();

    storySocketService.onNewStory.listen((story) {
      if (!mounted) return;
      setState(() {
        _stories.insert(0, story);
      });
    });

    storySocketService.onStorySeen.listen((data) {
      if (!mounted) return;
      // Mark story as seen if needed locally
      // data: {'storyId': ..., 'viewerId': ...}
      final storyId = data['storyId'];
      final idx = _stories.indexWhere((s) => s.id == storyId);
      if (idx != -1) {
        setState(() {
          if (!_stories[idx].viewers.contains(data['viewerId'])) {
            _stories[idx].viewers.add(data['viewerId']);
          }
        });
      }
    });
  }

  Future<void> _fetchStories() async {
    final userId = authService.currentUser?.id;
    if (userId == null) return;
    final stories = await storyService.getFriendsStories(userId);
    if (!mounted) return;
    setState(() {
      _stories.clear();
      _stories.addAll(stories);
      _isLoading = false;
    });
  }

  void _navigateToCreate() {
    Navigator.pushNamed(context, '/create-story');
  }

  void _navigateToViewer(int initialIndex) {
    Navigator.pushNamed(context, '/story-viewer', arguments: {
      'stories': _stories,
      'initialIndex': initialIndex,
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
              itemCount: _stories.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildCreateStoryItem(me?.avatar);
                }
                final story = _stories[index - 1];
                return _buildStoryItem(story, index - 1);
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

  Widget _buildStoryItem(ApiStoryModel story, int listIndex) {
    final bool hasSeen = story.viewers.contains(authService.currentUser?.id ?? '');
    
    // In UI we use userAvatar. Since API didn't populate user info tightly, we fallback to story.userId if userName is null
    final avatar = story.userAvatar ?? '';
    final name = story.userName ?? 'User';

    return GestureDetector(
      onTap: () => _navigateToViewer(listIndex),
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
                  color: hasSeen ? Colors.grey.shade300 : AppColors.primary,
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
                color: hasSeen ? Colors.grey : Colors.black,
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
