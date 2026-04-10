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

  bool get isGroup => type == 'GROUP';
  bool get isPinned => members.any((m) => m.isPinned);
}

// ── messages collection ───────────────────────────────────────────────────────
class Reaction {
  final String userId;
  final String type; // LIKE | LOVE | HAHA | WOW | SAD | ANGRY

  const Reaction({required this.userId, required this.type});

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
}

class MessageMetadata {
  final String? fileName;
  final int? fileSize;
  final String? thumbnail;
  final double? lat;
  final double? lng;
  final int? duration; // seconds (voice)

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
