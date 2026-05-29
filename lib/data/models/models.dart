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
  final String? name;
  final bool isMuted;
  final bool isPinned;
  final DateTime joinedAt;

  const ConversationMember({
    required this.userId,
    this.role = 'MEMBER',
    this.nickname,
    this.name,
    this.isMuted = false,
    this.isPinned = false,
    required this.joinedAt,
  });

  static String _extractId(dynamic raw) {
    if (raw == null) return '';
    if (raw is String) return raw;
    if (raw is Map)
      return (raw['\$oid'] ?? raw['oid'] ?? raw['_id'] ?? '').toString();
    return raw.toString();
  }

  factory ConversationMember.fromJson(Map<String, dynamic> json) {
    return ConversationMember(
      userId: _extractId(json['userId'] ?? json['_id']),
      role: json['role'] ?? 'MEMBER',
      nickname: json['nickname']?.toString(),
      name: json['name']?.toString() ?? json['fullName']?.toString(),
      isMuted: json['isMuted'] ?? false,
      isPinned: json['isPinned'] ?? false,
      joinedAt: json['joinedAt'] != null
          ? DateTime.tryParse(json['joinedAt'].toString()) ?? DateTime.now()
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
      messageId: json['messageId']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'].toString())
          : DateTime.now(),
    );
  }
}

class ConversationModel {
  final String id;
  final String type; // PRIVATE | GROUP
  final String? name;
  final String? avatar;
  final List<ConversationMember> members;
  final List<String> pinnedMessageIds;
  final List<MessageModel> pinnedMessages;
  final LastMessagePreview? lastMessage;
  final int unreadCount; // ← Thêm / sửa
  final DateTime createdAt;
  final DateTime updatedAt;

  const ConversationModel({
    required this.id,
    required this.type,
    this.name,
    this.avatar,
    required this.members,
    this.pinnedMessageIds = const [],
    this.pinnedMessages = const [],
    this.lastMessage,
    this.unreadCount = 0, // default = 0
    required this.createdAt,
    required this.updatedAt,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    String extractPinnedId(dynamic raw) {
      if (raw == null) return '';
      if (raw is String) return raw;
      if (raw is Map) {
        final map = Map<String, dynamic>.from(raw);
        final idRaw = map['_id'] ?? map['id'];
        if (idRaw is Map) {
          final idMap = Map<String, dynamic>.from(idRaw);
          return (idMap['\$oid'] ?? idMap['oid'] ?? idMap['id'] ?? '')
              .toString();
        }
        return idRaw?.toString() ?? '';
      }
      return raw.toString();
    }

    final rawPinned = json['pinnedMessageIds'] as List? ?? const [];
    final parsedPinnedMessages = rawPinned
        .whereType<Map>()
        .map((raw) {
          try {
            return MessageModel.fromJson(Map<String, dynamic>.from(raw));
          } catch (_) {
            return null;
          }
        })
        .whereType<MessageModel>()
        .toList();

    final parsedPinnedIdsFromRaw = rawPinned
        .map(extractPinnedId)
        .where((id) => id.isNotEmpty)
        .toList();

    final parsedPinnedIds = <String>{
      ...parsedPinnedIdsFromRaw,
      ...parsedPinnedMessages.map((m) => m.id).where((id) => id.isNotEmpty),
      ...(json['pinnedMessages'] as List? ?? const [])
          .whereType<Map>()
          .map(extractPinnedId)
          .where((id) => id.isNotEmpty),
    };

    final parsedPinnedMessagesField =
        (json['pinnedMessages'] as List? ?? const [])
            .whereType<Map>()
            .map((raw) {
              try {
                return MessageModel.fromJson(Map<String, dynamic>.from(raw));
              } catch (_) {
                return null;
              }
            })
            .whereType<MessageModel>()
            .toList();

    final mergedPinnedMessages = <String, MessageModel>{
      for (final m in parsedPinnedMessages) m.id: m,
      for (final m in parsedPinnedMessagesField) m.id: m,
    }.values.toList();

    return ConversationModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'PRIVATE',
      name: json['name'],
      avatar: json['avatar'],

      // ← Quan trọng: parse unreadCount từ backend
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,

      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'].toString())
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'].toString())
          : DateTime.now(),

      members: (json['members'] as List? ?? [])
          .map((m) => ConversationMember.fromJson(m as Map<String, dynamic>))
          .toList(),

      pinnedMessageIds: parsedPinnedIds.toList(),
      pinnedMessages: mergedPinnedMessages,

      lastMessage: json['lastMessage'] != null
          ? LastMessagePreview.fromJson(
              json['lastMessage'] as Map<String, dynamic>,
            )
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
      'LIKE': '👍',
      'LOVE': '❤️',
      'HAHA': '😂',
      'WOW': '😮',
      'SAD': '😢',
      'ANGRY': '😠',
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
  final String? thumbnailUrl;
  final double? lat;
  final double? lng;
  final int? duration; // seconds (voice)

  factory MessageMetadata.fromJson(Map<String, dynamic> json) {
    return MessageMetadata(
      fileName: json['fileName'],
      fileSize: json['fileSize'],
      thumbnail: json['thumbnail'] ?? json['thumbnailUrl'],
      thumbnailUrl: json['thumbnailUrl'] ?? json['thumbnail'],
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      duration: json['duration'],
    );
  }

  const MessageMetadata({
    this.fileName,
    this.fileSize,
    this.thumbnail,
    this.thumbnailUrl,
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
      metadata: json['metadata'] != null
          ? MessageMetadata.fromJson(json['metadata'])
          : null,
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

  bool get isText => type == 'TEXT';
  bool get isImage => type == 'IMAGE';
  bool get isVoice => type == 'VOICE';
  bool get isFile => type == 'FILE';
  bool get isLocation => type == 'LOCATION';
}

// ── calls collection ─────────────────────────────────────────────────────────
class CallModel {
  final String id;
  final String conversationId;
  final String callerId;
  final List<String> participants;
  final List<String> activeParticipants;
  final String type; // VOICE | VIDEO
  final String status; // ENDED | MISSED | REJECTED | CALLING
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int duration; // giây
  final DateTime createdAt;

  const CallModel({
    required this.id,
    required this.conversationId,
    required this.callerId,
    required this.participants,
    this.activeParticipants = const [],
    required this.type,
    required this.status,
    this.startedAt,
    this.endedAt,
    required this.duration,
    required this.createdAt,
  });

  factory CallModel.fromJson(Map<String, dynamic> json) {
    String extractId(dynamic val) {
      if (val is Map) return val['\$oid']?.toString() ?? val.toString();
      return val?.toString() ?? '';
    }

    DateTime? parseDate(dynamic val) {
      if (val == null) return null;
      if (val is Map) return DateTime.tryParse(val['\$date']?.toString() ?? '');
      return DateTime.tryParse(val.toString());
    }

    return CallModel(
      id: extractId(json['_id']),
      conversationId: extractId(json['conversationId']),
      callerId: extractId(json['callerId']),
      participants: ((json['participants'] as List?) ?? [])
          .map((e) => extractId(e))
          .toList(),
        activeParticipants: ((json['activeParticipants'] as List?) ?? [])
          .map((e) => extractId(e))
          .toList(),
      type: json['type']?.toString() ?? 'VOICE',
      status: json['status']?.toString() ?? 'ENDED',
      startedAt: parseDate(json['startedAt']),
      endedAt: parseDate(json['endedAt']),
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      createdAt: parseDate(json['createdAt']) ?? DateTime.now(),
    );
  }

  // Format thời lượng
  String get durationLabel {
    if (duration <= 0) return '';
    final m = duration ~/ 60;
    final s = duration % 60;
    if (m > 0) return '$m phút $s giây';
    return '$s giây';
  }

  bool get isMissed => status == 'MISSED' || status == 'REJECTED';
  bool get isEnded => status == 'ENDED';
  bool get isVideo => type == 'VIDEO';
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
