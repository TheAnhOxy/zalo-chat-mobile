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
