// ─────────────────────────────────────────────────────────────────────────────
// models.dart — Tất cả models, mapping 1-1 với MongoDB schema (db_mongo_zalo)
// ─────────────────────────────────────────────────────────────────────────────

// ── users collection ─────────────────────────────────────────────────────────
class UserStatus {
  final bool isOnline;
  final DateTime? lastSeen;
  const UserStatus({required this.isOnline, this.lastSeen});
}

class UserPrivacy {
  final String showPhone; // ALL | FRIEND | PRIVATE
  final bool showOnline;
  final bool allowStrangerMessage;
  const UserPrivacy({
    this.showPhone = 'FRIEND',
    this.showOnline = true,
    this.allowStrangerMessage = false,
  });
}

class UserModel {
  final String id;
  final String fullName;
  final String phone;
  final String? email;
  final String avatar;
  final String? coverImage;
  final String? bio;
  final String gender; // male | female | other
  final UserStatus status;
  final UserPrivacy privacy;
  final bool isVerified;

  const UserModel({
    required this.id,
    required this.fullName,
    required this.phone,
    this.email,
    required this.avatar,
    this.coverImage,
    this.bio,
    this.gender = 'other',
    this.status = const UserStatus(isOnline: false),
    this.privacy = const UserPrivacy(),
    this.isVerified = false,
  });

  String get displayName => fullName;
  bool get isOnline => status.isOnline;
}

// ── conversations collection ──────────────────────────────────────────────────
class ConversationMember {
  final String userId;
  final String role; // ADMIN | MODERATOR | MEMBER
  final String? nickname;
  final bool isMuted;
  final bool isPinned;
  final DateTime joinedAt;

  const ConversationMember({
    required this.userId,
    this.role = 'MEMBER',
    this.nickname,
    this.isMuted = false,
    this.isPinned = false,
    required this.joinedAt,
  });

  factory ConversationMember.fromJson(Map<String, dynamic> json) {
    return ConversationMember(
      userId: json['userId'] ?? '',
      role: json['role'] ?? 'MEMBER',
      nickname: json['nickname'],
      isMuted: json['isMuted'] ?? false,
      isPinned: json['isPinned'] ?? false,
      joinedAt: json['joinedAt'] != null 
          ? DateTime.parse(json['joinedAt']) 
          : DateTime.now(),
    );
  }
}

class LastMessagePreview {
  final String messageId;
  final String content;
  final String senderId;
  final DateTime createdAt;

  const LastMessagePreview({
    required this.messageId,
    required this.content,
    required this.senderId,
    required this.createdAt,
  });

  factory LastMessagePreview.fromJson(Map<String, dynamic> json) {
    return LastMessagePreview(
      messageId: json['messageId'] ?? '',
      content: json['content'] ?? '',
      senderId: json['senderId'] ?? '',
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
    );
  }
}

class ConversationModel {
  final String id;
  final String type; // PRIVATE | GROUP
  final String? name; // null nếu PRIVATE
  final String? avatar;
  final List<ConversationMember> members;
  final LastMessagePreview? lastMessage;
  final int unreadCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ConversationModel({
    required this.id,
    required this.type,
    this.name,
    this.avatar,
    required this.members,
    this.lastMessage,
    this.unreadCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    return ConversationModel(
      id: json['_id'] ?? '',
      type: json['type'] ?? 'PRIVATE',
      name: json['name'],
      avatar: json['avatar'],
      unreadCount: json['unreadCount'] ?? 0,
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : DateTime.now(),
      // Map list members
      members: (json['members'] as List? ?? [])
          .map((m) => ConversationMember.fromJson(m))
          .toList(),
      // Map last message preview nếu có
      lastMessage: json['lastMessage'] != null 
          ? LastMessagePreview.fromJson(json['lastMessage']) 
          : null,
    );
  }

  bool get isGroup => type == 'GROUP';
  bool get isPinned => members.any((m) => m.isPinned);
}

// ── messages collection ───────────────────────────────────────────────────────
class Reaction {
  final String userId;
  final String type; // LIKE | LOVE | HAHA | WOW | SAD | ANGRY

  const Reaction({required this.userId, required this.type});

  // Bổ sung hàm này để parse từ Backend
  factory Reaction.fromJson(Map<String, dynamic> json) {
    return Reaction(
      userId: json['userId'] ?? '',
      type: json['reactionType'] ?? json['type'] ?? 'LIKE',
    );
  }

  String get emoji {
    const map = {
      'LIKE': '👍', 'LOVE': '❤️', 'HAHA': '😂',
      'WOW': '😮', 'SAD': '😢', 'ANGRY': '😠',
    };
    return map[type] ?? '👍';
  }
}

class SeenBy {
  final String userId;
  final DateTime seenAt;
  const SeenBy({required this.userId, required this.seenAt});

  factory SeenBy.fromJson(Map<String, dynamic> json) {
    return SeenBy(
      userId: json['userId'] ?? '',
      seenAt: json['seenAt'] != null 
          ? DateTime.parse(json['seenAt']) 
          : DateTime.now(),
    );
  }
}

class MessageMetadata {
  final String? fileName;
  final int? fileSize;
  final String? thumbnail;
  final double? lat;
  final double? lng;
  final int? duration; // seconds (voice)

  factory MessageMetadata.fromJson(Map<String, dynamic> json) {
    return MessageMetadata(
      fileName: json['fileName'],
      fileSize: json['fileSize'],
      thumbnail: json['thumbnail'],
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      duration: json['duration'],
    );
  }

  const MessageMetadata({
    this.fileName,
    this.fileSize,
    this.thumbnail,
    this.lat,
    this.lng,
    this.duration,
  });
}

class MessageModel {
  final String id;
  final String conversationId;
  final String senderId;
  // TEXT | IMAGE | VIDEO | FILE | VOICE | LOCATION | CONTACT
  final String type;
  final String content;
  final MessageMetadata? metadata;
  final String? replyToId;
  // SENDING | SENT | DELIVERED | SEEN
  final String status;
  final bool isRecalled;
  final List<String> deletedBy;
  final List<Reaction> reactions;
  final List<SeenBy> seenBy;
  final DateTime createdAt;

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['_id'] ?? '',
      conversationId: json['conversationId'] ?? '',
      senderId: json['senderId'] ?? '',
      // Map từ messageType (tên thật trong DB) hoặc type (alias)
      type: json['messageType'] ?? json['type'] ?? 'TEXT',
      content: json['content'] ?? '',
      metadata: json['metadata'] != null ? MessageMetadata.fromJson(json['metadata']) : null,
      replyToId: json['replyTo'],
      status: json['status'] ?? 'SENT',
      isRecalled: json['isRecalled'] ?? false,
      deletedBy: List<String>.from(json['deletedBy'] ?? []),
      reactions: (json['reactions'] as List? ?? [])
          .map((r) => Reaction.fromJson(r))
          .toList(),
      seenBy: (json['seenBy'] as List? ?? [])
          .map((s) => SeenBy.fromJson(s))
          .toList(),
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt']) 
          : DateTime.now(),
    );
  }

  const MessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.type = 'TEXT',
    required this.content,
    this.metadata,
    this.replyToId,
    this.status = 'SENT',
    this.isRecalled = false,
    this.deletedBy = const [],
    this.reactions = const [],
    this.seenBy = const [],
    required this.createdAt,
  });

  bool get isText     => type == 'TEXT';
  bool get isImage    => type == 'IMAGE';
  bool get isVoice    => type == 'VOICE';
  bool get isFile     => type == 'FILE';
  bool get isLocation => type == 'LOCATION';
}

// ── calls collection ─────────────────────────────────────────────────────────
class CallModel {
  final String id;
  final String conversationId;
  final String callerId;
  final List<String> participants;
  final String type;   // VOICE | VIDEO
  final String status; // CALLING | ACCEPTED | REJECTED | MISSED | ENDED
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? duration; // seconds
  final DateTime createdAt;

  const CallModel({
    required this.id,
    required this.conversationId,
    required this.callerId,
    required this.participants,
    required this.type,
    required this.status,
    this.startedAt,
    this.endedAt,
    this.duration,
    required this.createdAt,
  });

  bool get isVideo => type == 'VIDEO';
  bool get isMissed => status == 'MISSED';
}

// ── friendships collection ────────────────────────────────────────────────────
class FriendshipModel {
  final String id;
  final String requesterId;
  final String addresseeId;
  final String status; // PENDING | ACCEPTED | BLOCKED
  final DateTime createdAt;

  const FriendshipModel({
    required this.id,
    required this.requesterId,
    required this.addresseeId,
    required this.status,
    required this.createdAt,
  });
}

// ── notifications collection ──────────────────────────────────────────────────
class AppNotification {
  final String id;
  final String receiverId;
  final String type; // MESSAGE | FRIEND_REQUEST | CALL
  final String content;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.receiverId,
    required this.type,
    required this.content,
    this.isRead = false,
    required this.createdAt,
  });
}
