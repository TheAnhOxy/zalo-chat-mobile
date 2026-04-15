import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/date_utils.dart' as du;
import '../../data/models/models.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/socket_service.dart';
import '../../widgets/common/common_widgets.dart';
import 'chat_detail_screen.dart';
import 'dart:developer';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  final Map<String, bool> _onlineStates = {};
  final Map<String, _ActiveUserItem> _knownUsers = {};
  final List<String> _activeUserOrder = [];
  List<ConversationModel> _conversations = [];
  // cache profile (tên + avatar) của các user trong chat 1-1
  final Map<String, UserModel> _userProfiles = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _initSocketListener();
  }

  // Load dữ liệu
  Future<void> _loadConversations() async {
    if (authService.userId == null) return;

    setState(() => _isLoading = true);

    try {
      final data = await apiService.getConversations(authService.userId!);
      _cacheKnownUsers(data);
      setState(() {
        _conversations = data;
        _isLoading = false;
      });
      log('✅ Đã load ${_conversations.length} cuộc trò chuyện');

      for (var conv in _conversations) {
        socketService.emit('join_conversation', {'conversationId': conv.id});
      }

      // Fetch profile của user kia trong mỗi chat 1-1
      _fetchUserProfiles(data);
    } catch (e) {
      log('❌ Lỗi load conversations: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchUserProfiles(List<ConversationModel> convs) async {
    final myId = authService.userId ?? '';
    final ids = convs
        .where((c) => !c.isGroup)
        .map((c) {
          final other = c.members.firstWhere(
            (m) => m.userId != myId,
            orElse: () => c.members.first,
          );
          return other.userId;
        })
        .where((id) => id.isNotEmpty && id != myId && !_userProfiles.containsKey(id))
        .toSet()
        .toList();

    if (ids.isEmpty) return;

    final futures = ids.map((id) => apiService.getUserById(id)).toList();
    final results = await Future.wait(futures, eagerError: false);

    final updated = <String, UserModel>{};
    for (final u in results) {
      if (u != null && u.id.isNotEmpty) updated[u.id] = u;
    }

    if (updated.isEmpty || !mounted) return;
    setState(() => _userProfiles.addAll(updated));
  }

  // Socket listener - realtime

  void _initSocketListener() {
    socketService.on('new_message', (data) {
      if (!mounted) return;

      try {
        final map = data is Map ? Map<String, dynamic>.from(data) : null;
        if (map == null) return;

        final newMsg = MessageModel.fromJson(map);

        setState(() {
          final index = _conversations.indexWhere(
            (c) => c.id == newMsg.conversationId,
          );

          if (index != -1) {
            final conv = _conversations[index];
            final isMe = newMsg.senderId == authService.userId;

            String previewContent = newMsg.content;

            if (newMsg.type == 'IMAGE' || _isImageUrl(newMsg.content)) {
              previewContent = 'đã gửi 1 ảnh';
            } else if (newMsg.type == 'FILE') {
              previewContent = '[Tệp đính kèm]';
            }

            final updatedConv = ConversationModel(
              id: conv.id,
              type: conv.type,
              name: conv.name,
              avatar: conv.avatar,
              members: conv.members,
              createdAt: conv.createdAt,
              updatedAt: newMsg.createdAt, // Cập nhật thời gian mới nhất
              unreadCount: isMe ? conv.unreadCount : conv.unreadCount + 1,
              lastMessage: LastMessagePreview(
                messageId: newMsg.id,
                content: previewContent,
                senderId: newMsg.senderId,
                createdAt: newMsg.createdAt,
              ),
            );

            _conversations.removeAt(index);
            _conversations.insert(0, updatedConv);
          } else {
            _loadConversations();
          }
        });
      } catch (e) {
        log('Lỗi parse socket data ở list screen: $e');
      }
    });

    // ✅ Cập nhật lastMessage khi có cuộc gọi
    socketService.on('conversation_call_updated', (data) {
      if (!mounted) return;
      try {
        final map = data is Map<String, dynamic>
            ? data
            : Map<String, dynamic>.from(data as Map);

        final convId = map['conversationId']?.toString();
        if (convId == null) return;

        final lastMsgRaw = map['lastMessage'];
        if (lastMsgRaw == null) return;

        final lastMsgMap = lastMsgRaw is Map<String, dynamic>
            ? lastMsgRaw
            : Map<String, dynamic>.from(lastMsgRaw as Map);

        setState(() {
          final index = _conversations.indexWhere((c) => c.id == convId);
          if (index == -1) return;

          final conv = _conversations[index];
          final updatedConv = ConversationModel(
            id: conv.id,
            type: conv.type,
            name: conv.name,
            avatar: conv.avatar,
            members: conv.members,
            createdAt: conv.createdAt,
            updatedAt: DateTime.now(),
            unreadCount: conv.unreadCount,
            lastMessage: LastMessagePreview(
              messageId: '',
              content: lastMsgMap['content']?.toString() ?? '',
              senderId: lastMsgMap['senderId']?.toString() ?? '',
              createdAt:
                  DateTime.tryParse(
                    lastMsgMap['createdAt']?.toString() ?? '',
                  ) ??
                  DateTime.now(),
            ),
          );

          _conversations.removeAt(index);
          _conversations.insert(0, updatedConv);
        });
      } catch (e) {
        log('❌ conversation_call_updated list error: $e');
      }
    });

    // ✅ message_seen
    socketService.on('message_seen', (data) {
      if (!mounted) return;

      try {
        final map = _tryMap(data);
        if (map == null) return;

        final convId = map['conversationId']?.toString();
        final userId = map['userId']?.toString();

        if (convId == null) return;

        setState(() {
          final index = _conversations.indexWhere((c) => c.id == convId);
          if (index == -1) return;

          final conv = _conversations[index];

          if (userId == authService.userId) {
            _conversations[index] = ConversationModel(
              id: conv.id,
              type: conv.type,
              name: conv.name,
              avatar: conv.avatar,
              members: conv.members,
              createdAt: conv.createdAt,
              updatedAt: conv.updatedAt,
              unreadCount: 0,
              lastMessage: conv.lastMessage,
            );
          }
        });
      } catch (e) {
        log('❌ message_seen list error: $e');
      }
    });

    // ✅ user_status_changed
    socketService.on('user_status_changed', (data) {
      final map = _tryMap(data);
      if (map == null) return;

      final userId = map['userId']?.toString();
      if (userId == null || userId.isEmpty) return;

      final isOnline = map['isOnline'] == true;

      setState(() {
        _onlineStates[userId] = isOnline;
      });
    });
  }

  @override
  void dispose() {
    socketService.off('new_message');
    socketService.off('user_status_changed');
    _searchCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _tryMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      try {
        return Map<String, dynamic>.from(data);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  bool _isImageUrl(String content) {
    return content.startsWith('http') &&
        (content.contains('.jpg') ||
            content.contains('.jpeg') ||
            content.contains('.png') ||
            content.contains('.webp'));
  }

  // 2. Các hàm Helper để xử lý logic hiển thị dựa trên Model thật
  String _getOtherUserId(ConversationModel c) {
    if (c.isGroup) return '';
    final uid = authService.userId;
    final other = c.members.firstWhere(
      (m) => m.userId != uid,
      orElse: () => c.members.first,
    );
    return other.userId;
  }

  String _getDisplayName(ConversationModel c) {
    if (c.isGroup) return c.name?.isNotEmpty == true ? c.name! : 'Nhóm';
    final otherId = _getOtherUserId(c);
    // Ưu tiên: profile đã fetch > nickname trong member > 'Người dùng'
    final profile = _userProfiles[otherId];
    if (profile != null && profile.fullName.isNotEmpty) return profile.fullName;
    final uid = authService.userId;
    final other = c.members.firstWhere(
      (m) => m.userId != uid,
      orElse: () => c.members.first,
    );
    return other.nickname?.isNotEmpty == true
        ? other.nickname!
        : other.name?.isNotEmpty == true
            ? other.name!
            : 'Người dùng';
  }

  String? _getAvatar(ConversationModel c) {
    if (c.isGroup) return c.avatar?.isNotEmpty == true ? c.avatar : null;
    final otherId = _getOtherUserId(c);
    final profile = _userProfiles[otherId];
    if (profile != null && profile.avatar.isNotEmpty) return profile.avatar;
    return c.avatar?.isNotEmpty == true ? c.avatar : null;
  }

  void _cacheKnownUsers(List<ConversationModel> conversations) {
    for (final c in conversations) {
      if (c.isGroup) continue;
      final otherId = _getOtherUserId(c);
      if (otherId.isEmpty || otherId == authService.userId) continue;
      _knownUsers[otherId] = _ActiveUserItem(
        userId: otherId,
        name: _getDisplayName(c),
        avatar: _getAvatar(c),
      );
    }
  }

  UserModel? _getOtherUser(ConversationModel c) {
    if (c.isGroup) return null;
    final otherId = _getOtherUserId(c);
    final profile = _userProfiles[otherId];
    if (profile != null) return profile;

    final uid = authService.userId;
    final other = c.members.firstWhere(
      (m) => m.userId != uid,
      orElse: () => c.members.first,
    );
    final name = other.nickname?.isNotEmpty == true
        ? other.nickname!
        : other.name?.isNotEmpty == true
            ? other.name!
            : 'Người dùng';
    return UserModel(
      id: other.userId,
      fullName: name,
      avatar: c.avatar?.isNotEmpty == true ? c.avatar! : '',
      phone: '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredConversations = _conversations.where((c) {
      if (_query.isEmpty) return true;
      return _getDisplayName(c).toLowerCase().contains(_query.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildActiveBar(),
            _buildSearch(),

            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadConversations,
                      color: AppColors.primary,
                      child: ListView(
                        padding: EdgeInsets.zero,
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          _buildAiCard(),
                          _buildStoryRow(),

                          if (filteredConversations.isEmpty)
                            _buildEmptyState()
                          else
                            ...filteredConversations.map(_buildConvTile),

                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Text(
          'Chưa có cuộc trò chuyện nào',
          style: TextStyle(color: AppColors.textHint, fontSize: 13),
        ),
      ),
    );
  }

  // ── Giữ nguyên các Widget UI gốc của bạn ───────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
      child: Row(
        children: [
          AvatarWidget(
            url: authService.currentUser?.avatar,
            name: authService.currentUser?.fullName ?? '',
            size: 36,
          ),
          const SizedBox(width: 12),
          const Text(
            'Tin nhắn',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              fontFamily: 'Inter',
            ),
          ),
          const Spacer(),
          _HeaderIconBtn(icon: Icons.search, onTap: () {}),
          const SizedBox(width: 4),
          _HeaderIconBtn(icon: Icons.add, onTap: () {}, filled: true),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontFamily: 'Inter',
          fontSize: 14,
        ),
        decoration: InputDecoration(
          hintText: 'Tìm kiếm cuộc trò chuyện...',
          prefixIcon: const Icon(
            Icons.search,
            color: AppColors.textHint,
            size: 20,
          ),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    Icons.clear,
                    color: AppColors.textHint,
                    size: 18,
                  ),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildActiveBar() {
    return SizedBox(
      height: 108,
      child: _activeUserOrder.isEmpty
          ? const SizedBox.shrink()
          : ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: _activeUserOrder.length,
              itemBuilder: (_, index) {
                final userId = _activeUserOrder[index];
                final user = _knownUsers[userId];
                if (user == null) return const SizedBox.shrink();

                return Container(
                  width: 78,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      AvatarWidget(
                        url: user.avatar,
                        name: user.name,
                        size: 60,
                        showOnline: true,
                        isOnline: _onlineStates[userId] ?? false,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        user.name,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'Inter',
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildAiCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A3A1A), Color(0xFF1F4A1F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: AppColors.aiGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trợ lý AI',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontFamily: 'Inter',
                  ),
                ),
                Text(
                  'Hôm nay tôi có thể giúp gì cho bạn?',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: AppColors.textSecondary,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildStoryRow() {
    return const SizedBox(height: 12); // Tạm thu nhỏ vì story đang dùng mock cũ
  }

  Widget _buildConvTile(ConversationModel c) {
    final name = _getDisplayName(c);
    final avatar = _getAvatar(c);
    final last = c.lastMessage;
    final uid = authService.userId ?? '';
    final otherUserId = _getOtherUserId(c);
    final isOnline = !c.isGroup && (_onlineStates[otherUserId] ?? false);
    final bool hasUnread = c.unreadCount > 0;
    String lastContent = last?.content ?? 'Bắt đầu cuộc trò chuyện';

    if (_isImageUrl(lastContent)) {
      lastContent = 'đã gửi 1 ảnh';
    }
    final bool isMe = last != null && last.senderId == uid;
    final bool isMissedCall = lastContent.toLowerCase().contains(
      'cuộc gọi nhỡ',
    );

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            conversationId: c.id,
            otherUser: _getOtherUser(c),
            conversation: c,
          ),
        ),
      ),
      onLongPress: () => _showContextMenu(c),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: hasUnread ? AppColors.bgCardLight : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            AvatarWidget(
              url: avatar,
              name: name,
              size: 52,
              showOnline: !c.isGroup,
              isOnline: isOnline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 15,
                            fontFamily: 'Inter',
                            fontWeight: hasUnread
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (last != null)
                        Text(
                          du.DateUtils.formatChatTime(last.createdAt),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textHint,
                            fontFamily: 'Inter',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isMe ? 'Bạn: $lastContent' : lastContent,
                          style: TextStyle(
                            fontSize: 13,

                            fontFamily: 'Inter',
                            color: isMissedCall
                                ? Colors
                                      .red
                                      .shade700 // 🔴 đỏ đậm hơn
                                : (hasUnread
                                      ? AppColors.textSecondary
                                      : AppColors.textHint),
                            fontWeight: !isMe
                                ? FontWeight.w600
                                : (hasUnread
                                      ? FontWeight.w500
                                      : FontWeight.w400),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasUnread)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${c.unreadCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContextMenu(ConversationModel c) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _MenuTile(
            Icons.push_pin_outlined,
            'Ghim cuộc trò chuyện',
            AppColors.textPrimary,
            () => Navigator.pop(context),
          ),
          _MenuTile(
            Icons.delete_outline,
            'Xoá cuộc trò chuyện',
            AppColors.error,
            () => Navigator.pop(context),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _HeaderIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  const _HeaderIconBtn({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: filled ? AppColors.primary : AppColors.bgCard,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: filled ? Colors.white : AppColors.textSecondary,
        size: 20,
      ),
    ),
  );
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MenuTile(this.icon, this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: color, size: 22),
    title: Text(
      label,
      style: TextStyle(
        color: color,
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
    onTap: onTap,
  );
}

class _ActiveUserItem {
  final String userId;
  final String name;
  final String? avatar;

  const _ActiveUserItem({
    required this.userId,
    required this.name,
    this.avatar,
  });
}
