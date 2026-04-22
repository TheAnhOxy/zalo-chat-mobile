import 'models.dart';

class ApiStoryModel {
  final String id;
  final String userId;
  final String mediaUrl;
  final String type;
  final String caption;
  final List<String> viewers;
  final DateTime expiresAt;
  final DateTime createdAt;

  // Custom field to populate user info
  final String? userName;
  final String? userAvatar;

  ApiStoryModel({
    required this.id,
    required this.userId,
    required this.mediaUrl,
    required this.type,
    required this.caption,
    required this.viewers,
    required this.expiresAt,
    required this.createdAt,
    this.userName,
    this.userAvatar,
  });

  factory ApiStoryModel.fromJson(Map<String, dynamic> json) {
    return ApiStoryModel(
      id: json['_id'] ?? '',
      userId: json['userId'] ?? '',
      mediaUrl: json['mediaUrl'] ?? '',
      type: json['type'] ?? 'IMAGE',
      caption: json['caption'] ?? '',
      viewers: (json['viewers'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'])
          : DateTime.now(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      userName: json['userName'],
      userAvatar: json['userAvatar'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'userId': userId,
      'mediaUrl': mediaUrl,
      'type': type,
      'caption': caption,
      'viewers': viewers,
      'expiresAt': expiresAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'userName': userName,
      'userAvatar': userAvatar,
    };
  }
}

class StoryUserModel {
  final String id;
  final String fullName;
  final String avatar;

  StoryUserModel({
    required this.id,
    required this.fullName,
    required this.avatar,
  });
}

class StoryGroupModel {
  final StoryUserModel user;
  final bool hasUnseen;
  final DateTime lastStoryTime;
  final List<ApiStoryModel> stories;

  StoryGroupModel({
    required this.user,
    required this.hasUnseen,
    required this.lastStoryTime,
    required this.stories,
  });

  factory StoryGroupModel.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'] ?? {};
    final user = StoryUserModel(
      id: userJson['id'] ?? userJson['_id'] ?? '',
      fullName: userJson['fullName'] ?? 'Unknown User',
      avatar: userJson['avatar'] ?? '',
    );

    return StoryGroupModel(
      user: user,
      hasUnseen: json['hasUnseen'] ?? false,
      lastStoryTime: json['lastStoryTime'] != null
          ? DateTime.parse(json['lastStoryTime'])
          : DateTime.now(),
      stories: (json['stories'] as List<dynamic>?)
              ?.map((e) {
                 // Clone map e to avoid modifying immutable json map
                 final Map<String, dynamic> eMap = Map.from(e);
                 eMap['userName'] = user.fullName;
                 eMap['userAvatar'] = user.avatar;
                 return ApiStoryModel.fromJson(eMap);
              })
              .toList() ??
          [],
    );
  }
}
