import 'dart:developer';
import 'socket_service.dart';
import '../data/models/story_model.dart';
import 'dart:async';

class StorySocketService {
  static final StorySocketService _instance = StorySocketService._internal();
  factory StorySocketService() => _instance;
  StorySocketService._internal();

  final _newStoryController = StreamController<ApiStoryModel>.broadcast();
  final _storySeenController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<ApiStoryModel> get onNewStory => _newStoryController.stream;
  Stream<Map<String, dynamic>> get onStorySeen => _storySeenController.stream;

  void init() {
    socketService.on('new_story', (data) {
      if (data == null) return;
      try {
        final parsed = Map<String, dynamic>.from(data);
        final story = ApiStoryModel.fromJson(parsed);
        _newStoryController.add(story);
        log('🟢 Nhận event new_story: ${story.id}');
      } catch (e) {
        log('❌ Lỗi parse new_story event: $e');
      }
    });

    socketService.on('story_seen', (data) {
      if (data == null) return;
      try {
        final parsed = Map<String, dynamic>.from(data);
        _storySeenController.add(parsed);
        log('🟢 Nhận event story_seen: ${parsed['storyId']}');
      } catch (e) {
        log('❌ Lỗi parse story_seen event: $e');
      }
    });
  }

  void emitViewStory(String storyId, String creatorId, String viewerId) {
    socketService.emit('view_story', {
      'storyId': storyId,
      'creatorId': creatorId,
      'viewerId': viewerId,
    });
  }

  void dispose() {
    socketService.off('new_story');
    socketService.off('story_seen');
  }
}

final storySocketService = StorySocketService();
