import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';
import 'auth_service.dart';
import '../data/models/story_model.dart';
import 'dart:developer' as dev;

class StoryService {
  static final StoryService _instance = StoryService._internal();
  factory StoryService() => _instance;
  StoryService._internal();

  final _client = http.Client();
  String get baseUrl => AppConfig.baseUrl;

  Map<String, String> get _headers {
    final token = authService.accessToken;
    final headers = {'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<List<ApiStoryModel>> getFriendsStories(String userId) async {
    try {
      // In a real scenario, the backend could provide an aggregation.
      // For now, if we don't have a specific endpoint for ALL friends' stories,
      // we might just fetch user stories or explore.
      // In Zalo, usually there is /stories/feed or Explore
      // Here we will use the new Explore API for strangers, but for friends we need them.
      // Wait, backend provides `GET /stories` which returns all stories?
      // Actually `findAll()` in backend returns all stories without filter.
      final res = await _client
          .get(Uri.parse('$baseUrl/stories'), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        return data.map((e) => ApiStoryModel.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      dev.log('❌ getFriendsStories error: $e');
      return [];
    }
  }

  Future<List<ApiStoryModel>> getExploreStories(String excludeUserId) async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/stories/explore?excludeUserId=$excludeUserId'), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        return data.map((e) => ApiStoryModel.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      dev.log('❌ getExploreStories error: $e');
      return [];
    }
  }

  Future<ApiStoryModel?> createStory({
    required String userId,
    required String mediaUrl,
    required String type, // IMAGE | VIDEO
    String caption = '',
    required DateTime expiresAt,
  }) async {
    try {
      final body = jsonEncode({
        'userId': userId,
        'mediaUrl': mediaUrl,
        'type': type,
        'caption': caption,
        'expiresAt': expiresAt.toIso8601String(),
      });

      final res = await _client
          .post(Uri.parse('$baseUrl/stories'), headers: _headers, body: body)
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 || res.statusCode == 201) {
        return ApiStoryModel.fromJson(jsonDecode(res.body));
      }
      return null;
    } catch (e) {
      dev.log('❌ createStory error: $e');
      return null;
    }
  }
}

final storyService = StoryService();
