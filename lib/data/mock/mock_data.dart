import '../models/models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Mock Data — Tham chiếu MongoDB schema từ db_mongo_zalo
// ─────────────────────────────────────────────────────────────────────────────

// ── USERS ────────────────────────────────────────────────────────────────────
final mockUsers = <String, UserModel>{
  'USR_001': const UserModel(
    id: 'USR_001',
    fullName: 'Nguyễn Văn An',
    phone: '0901234567',
    email: 'an@azureconnect.vn',
    avatar: 'https://i.pravatar.cc/150?img=11',
    bio: 'Flutter Developer 🚀',
    status: UserStatus(isOnline: true),
    isVerified: true,
  ),
  'USR_002': const UserModel(
    id: 'USR_002',
    fullName: 'Nguyễn Linh',
    phone: '0912345678',
    avatar: 'https://i.pravatar.cc/150?img=5',
    bio: 'UI/UX Designer ✨',
    status: UserStatus(isOnline: true),
  ),
  'USR_003': const UserModel(
    id: 'USR_003',
    fullName: 'Phạm Hoàng',
    phone: '0923456789',
    avatar: 'https://i.pravatar.cc/150?img=3',
    bio: 'Backend Engineer ⚙️',
    status: UserStatus(isOnline: false),
  ),
  'USR_004': const UserModel(
    id: 'USR_004',
    fullName: 'Trần Tùng',
    phone: '0934567890',
    avatar: 'https://i.pravatar.cc/150?img=8',
    bio: 'Product Manager 📱',
    status: UserStatus(isOnline: false),
  ),
  'USR_005': const UserModel(
    id: 'USR_005',
    fullName: 'Lê Mai',
    phone: '0945678901',
    avatar: 'https://i.pravatar.cc/150?img=9',
    bio: 'QA Engineer 🧪',
    status: UserStatus(isOnline: true),
  ),
  'USR_006': const UserModel(
    id: 'USR_006',
    fullName: 'Minh Quân',
    phone: '0956789012',
    avatar: 'https://i.pravatar.cc/150?img=15',
    status: UserStatus(isOnline: true),
  ),
  'USR_007': const UserModel(
    id: 'USR_007',
    fullName: 'Linh Chi',
    phone: '0967890123',
    avatar: 'https://i.pravatar.cc/150?img=25',
    bio: 'Design Lead 🎨',
    status: UserStatus(isOnline: true),
  ),
  // AI Bot
  'BOT_AI': const UserModel(
    id: 'BOT_AI',
    fullName: 'Trợ lý AI',
    phone: '',
    avatar: 'https://i.pravatar.cc/150?img=60',
    bio: 'AI Assistant — Hôm nay tôi có thể giúp gì cho bạn?',
    status: UserStatus(isOnline: true),
    isVerified: true,
  ),
};

UserModel? getUser(String id) => mockUsers[id];

// ── CONVERSATIONS ─────────────────────────────────────────────────────────────
final now = DateTime.now();

final mockConversations = <ConversationModel>[
  // AI Bot — luôn đứng đầu
  ConversationModel(
    id: 'CONV_AI',
    type: 'PRIVATE',
    members: [
      ConversationMember(userId: 'USR_001', joinedAt: now.subtract(const Duration(days: 30))),
      ConversationMember(userId: 'BOT_AI', joinedAt: now.subtract(const Duration(days: 30))),
    ],
    lastMessage: LastMessagePreview(
      messageId: 'MSG_AI_1',
      content: 'Hôm nay tôi có thể giúp gì cho bạn?',
      senderId: 'BOT_AI',
      createdAt: now.subtract(const Duration(hours: 1)),
    ),
    unreadCount: 0,
    createdAt: now.subtract(const Duration(days: 30)),
    updatedAt: now.subtract(const Duration(hours: 1)),
  ),

  // 1-1: Nguyễn Linh
  ConversationModel(
    id: 'CONV_001',
    type: 'PRIVATE',
    members: [
      ConversationMember(userId: 'USR_001', joinedAt: now.subtract(const Duration(days: 15))),
      ConversationMember(userId: 'USR_002', joinedAt: now.subtract(const Duration(days: 15))),
    ],
    lastMessage: LastMessagePreview(
      messageId: 'MSG_001_5',
      content: 'Gửi mình tài liệu họp chiều nay ...',
      senderId: 'USR_002',
      createdAt: now.subtract(const Duration(minutes: 10)),
    ),
    unreadCount: 2,
    createdAt: now.subtract(const Duration(days: 15)),
    updatedAt: now.subtract(const Duration(minutes: 10)),
  ),

  // 1-1: Phạm Hoàng
  ConversationModel(
    id: 'CONV_002',
    type: 'PRIVATE',
    members: [
      ConversationMember(userId: 'USR_001', joinedAt: now.subtract(const Duration(days: 10))),
      ConversationMember(userId: 'USR_003', joinedAt: now.subtract(const Duration(days: 10))),
    ],
    lastMessage: LastMessagePreview(
      messageId: 'MSG_002_3',
      content: 'Ok ông, hen gặp lúc 12h tại quán...',
      senderId: 'USR_001',
      createdAt: now.subtract(const Duration(hours: 3)),
    ),
    unreadCount: 0,
    createdAt: now.subtract(const Duration(days: 10)),
    updatedAt: now.subtract(const Duration(hours: 3)),
  ),

  // GROUP: Team Project Alpha
  ConversationModel(
    id: 'CONV_GRP_001',
    type: 'GROUP',
    name: 'Team Project Alpha',
    avatar: 'https://i.pravatar.cc/150?img=50',
    members: [
      ConversationMember(userId: 'USR_001', role: 'ADMIN', joinedAt: now.subtract(const Duration(days: 20))),
      ConversationMember(userId: 'USR_002', joinedAt: now.subtract(const Duration(days: 20))),
      ConversationMember(userId: 'USR_006', joinedAt: now.subtract(const Duration(days: 20))),
      ConversationMember(userId: 'USR_007', joinedAt: now.subtract(const Duration(days: 20))),
    ],
    lastMessage: LastMessagePreview(
      messageId: 'MSG_GRP_4',
      content: 'Quỳnh: Mọi người đã check UI mới...',
      senderId: 'USR_002',
      createdAt: now.subtract(const Duration(days: 1)),
    ),
    unreadCount: 5,
    createdAt: now.subtract(const Duration(days: 20)),
    updatedAt: now.subtract(const Duration(days: 1)),
  ),

  // 1-1: Trần Tùng
  ConversationModel(
    id: 'CONV_003',
    type: 'PRIVATE',
    members: [
      ConversationMember(userId: 'USR_001', joinedAt: now.subtract(const Duration(days: 5))),
      ConversationMember(userId: 'USR_004', joinedAt: now.subtract(const Duration(days: 5))),
    ],
    lastMessage: LastMessagePreview(
      messageId: 'MSG_003_2',
      content: 'Cảm ơn anh đã hỗ trợ!',
      senderId: 'USR_004',
      createdAt: now.subtract(const Duration(days: 2)),
    ),
    unreadCount: 0,
    createdAt: now.subtract(const Duration(days: 5)),
    updatedAt: now.subtract(const Duration(days: 2)),
  ),

  // 1-1: Lê Mai
  ConversationModel(
    id: 'CONV_004',
    type: 'PRIVATE',
    members: [
      ConversationMember(userId: 'USR_001', joinedAt: now.subtract(const Duration(days: 7))),
      ConversationMember(userId: 'USR_005', joinedAt: now.subtract(const Duration(days: 7))),
    ],
    lastMessage: LastMessagePreview(
      messageId: 'MSG_004_2',
      content: 'Bạn đã gửi file chưa nhỉ?',
      senderId: 'USR_005',
      createdAt: now.subtract(const Duration(days: 3)),
    ),
    unreadCount: 0,
    createdAt: now.subtract(const Duration(days: 7)),
    updatedAt: now.subtract(const Duration(days: 3)),
  ),
];

// ── MESSAGES ─────────────────────────────────────────────────────────────────
final Map<String, List<MessageModel>> mockMessages = {

  // AI Conversation
  'CONV_AI': [
    MessageModel(
      id: 'MSG_AI_0', conversationId: 'CONV_AI', senderId: 'BOT_AI',
      content: 'Xin chào! Tôi là Trợ lý AI của QuickChat. Hôm nay tôi có thể giúp gì cho bạn?',
      createdAt: now.subtract(const Duration(hours: 2)),
    ),
    MessageModel(
      id: 'MSG_AI_1', conversationId: 'CONV_AI', senderId: 'USR_001',
      content: 'Bạn có thể tóm tắt cuộc họp không?',
      createdAt: now.subtract(const Duration(hours: 1, minutes: 30)),
    ),
    MessageModel(
      id: 'MSG_AI_2', conversationId: 'CONV_AI', senderId: 'BOT_AI',
      content: 'Tất nhiên! Hãy cho tôi biết nội dung cuộc họp hoặc đính kèm file và tôi sẽ tóm tắt ngay.',
      createdAt: now.subtract(const Duration(hours: 1)),
    ),
  ],

  // CONV_001 — 1-1 với Linh
  'CONV_001': [
    MessageModel(
      id: 'MSG_001_1', conversationId: 'CONV_001', senderId: 'USR_002',
      content: 'An ơi, bạn có thời gian họp chiều nay không?',
      createdAt: now.subtract(const Duration(hours: 3)),
      status: 'SEEN',
    ),
    MessageModel(
      id: 'MSG_001_2', conversationId: 'CONV_001', senderId: 'USR_001',
      content: 'Có, mình rảnh từ 2h chiều. Họp ở đâu vậy?',
      createdAt: now.subtract(const Duration(hours: 2, minutes: 50)),
      status: 'SEEN',
    ),
    MessageModel(
      id: 'MSG_001_3', conversationId: 'CONV_001', senderId: 'USR_002',
      content: 'Họp online qua Meet nha. Mình sẽ gửi link sau.',
      createdAt: now.subtract(const Duration(hours: 2, minutes: 40)),
      status: 'SEEN',
      reactions: [const Reaction(userId: 'USR_001', type: 'LIKE')],
    ),
    MessageModel(
      id: 'MSG_001_4', conversationId: 'CONV_001', senderId: 'USR_002',
      type: 'FILE',
      content: 'Tài liệu thiết kế Q4.pdf',
      metadata: const MessageMetadata(fileName: 'Tài liệu thiết kế Q4.pdf', fileSize: 2048576),
      createdAt: now.subtract(const Duration(minutes: 20)),
      status: 'DELIVERED',
    ),
    MessageModel(
      id: 'MSG_001_5', conversationId: 'CONV_001', senderId: 'USR_002',
      content: 'Gửi mình tài liệu họp chiều nay nhé 📎',
      createdAt: now.subtract(const Duration(minutes: 10)),
      status: 'DELIVERED',
    ),
  ],

  // CONV_002 — 1-1 với Hoàng
  'CONV_002': [
    MessageModel(
      id: 'MSG_002_1', conversationId: 'CONV_002', senderId: 'USR_001',
      content: 'Hoàng ơi, API endpoint /messages đã fix chưa bạn?',
      createdAt: now.subtract(const Duration(hours: 5)),
      status: 'SEEN',
    ),
    MessageModel(
      id: 'MSG_002_2', conversationId: 'CONV_002', senderId: 'USR_003',
      content: 'Fix xong rồi, đang deploy lên staging. Khoảng 30 phút nữa là xong nha.',
      createdAt: now.subtract(const Duration(hours: 4, minutes: 30)),
      status: 'SEEN',
    ),
    MessageModel(
      id: 'MSG_002_3', conversationId: 'CONV_002', senderId: 'USR_001',
      content: 'Ok ông, hen gặp lúc 12h tại quán cà phê để demo nhé!',
      createdAt: now.subtract(const Duration(hours: 3)),
      status: 'SEEN',
      seenBy: [SeenBy(userId: 'USR_003', seenAt: now.subtract(const Duration(hours: 2, minutes: 55)))],
    ),
  ],

  // CONV_GRP_001 — Group Team Project Alpha
  'CONV_GRP_001': [
    MessageModel(
      id: 'MSG_GRP_1', conversationId: 'CONV_GRP_001', senderId: 'USR_006',
      content: 'Chào cả nhà, mình đã cập nhật file thiết kế Figma rồi nhé. Mọi người xem qua lợi mình feedback nha!',
      createdAt: now.subtract(const Duration(days: 1, hours: 3)),
    ),
    MessageModel(
      id: 'MSG_GRP_2', conversationId: 'CONV_GRP_001', senderId: 'USR_007',
      type: 'IMAGE',
      content: 'https://picsum.photos/400/300?random=1',
      metadata: const MessageMetadata(thumbnail: 'https://picsum.photos/400/300?random=1'),
      createdAt: now.subtract(const Duration(days: 1, hours: 2)),
    ),
    MessageModel(
      id: 'MSG_GRP_3', conversationId: 'CONV_GRP_001', senderId: 'USR_007',
      content: 'Màn hình Dashboard này nhìn ổn phết Quân ơi, mình sẽ tích hợp vào hôm nay luôn nha!',
      createdAt: now.subtract(const Duration(days: 1, hours: 1, minutes: 45)),
      reactions: [
        const Reaction(userId: 'USR_001', type: 'LOVE'),
        const Reaction(userId: 'USR_006', type: 'HAHA'),
      ],
    ),
    MessageModel(
      id: 'MSG_GRP_4', conversationId: 'CONV_GRP_001', senderId: 'USR_001',
      content: 'Đồng ý luôn! Để mình check lại phần Flow của User nữa rồi báo lại cho team trong chiều nay nhé. À, còn phần AI module thì sao?',
      createdAt: now.subtract(const Duration(days: 1, hours: 1, minutes: 21)),
    ),
    MessageModel(
      id: 'MSG_GRP_5', conversationId: 'CONV_GRP_001', senderId: 'BOT_AI',
      content: 'Tôi đã phân tích 15 bản feedback trước đó. Phần AI module nên ưu tiên:',
      createdAt: now.subtract(const Duration(days: 1, hours: 1)),
    ),
  ],

  // CONV_003 — 1-1 với Tùng
  'CONV_003': [
    MessageModel(
      id: 'MSG_003_1', conversationId: 'CONV_003', senderId: 'USR_004',
      content: 'Anh An ơi, em có thể hỏi về architecture của project không?',
      createdAt: now.subtract(const Duration(days: 3)),
      status: 'SEEN',
    ),
    MessageModel(
      id: 'MSG_003_2', conversationId: 'CONV_003', senderId: 'USR_004',
      content: 'Cảm ơn anh đã hỗ trợ!',
      createdAt: now.subtract(const Duration(days: 2)),
      status: 'SEEN',
    ),
  ],

  // CONV_004 — 1-1 với Mai
  'CONV_004': [
    MessageModel(
      id: 'MSG_004_1', conversationId: 'CONV_004', senderId: 'USR_001',
      content: 'Mai ơi, test case cho màn Chat xong chưa?',
      createdAt: now.subtract(const Duration(days: 4)),
      status: 'SEEN',
    ),
    MessageModel(
      id: 'MSG_004_2', conversationId: 'CONV_004', senderId: 'USR_005',
      content: 'Bạn đã gửi file test case chưa nhỉ?',
      createdAt: now.subtract(const Duration(days: 3)),
      status: 'SEEN',
    ),
  ],
};

List<MessageModel> getMessages(String conversationId) =>
    mockMessages[conversationId] ?? [];

// ── Story/Online users (hiển thị ở đầu Chat List) ─────────────────────────
final storyUsers = [
  mockUsers['USR_002']!,
  mockUsers['USR_003']!,
  mockUsers['USR_005']!,
  mockUsers['USR_004']!,
  mockUsers['USR_006']!,
  mockUsers['USR_007']!,
];
