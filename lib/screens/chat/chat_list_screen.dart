import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/date_utils.dart' as du;
import '../../data/models/models.dart';
import '../../services/api_service.dart'; // Thêm mới
import '../../services/auth_service.dart';
import '../../services/socket_service.dart'; // Thêm mới
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
  
  // 1. Quản lý trạng thái dữ liệu từ API
  late Future<List<ConversationModel>> _conversationsFuture;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _initSocketListener();
  }

  // Hàm tải dữ liệu từ Server
  void _loadConversations() {
    if (authService.userId != null) {
      setState(() {
        _conversationsFuture = apiService.getConversations(authService.userId!);
      });
    }
  }

  // Lắng nghe Socket để cập nhật danh sách khi có tin nhắn mới
  void _initSocketListener() {
    socketService.on('new_message', (data) {
      log('📩 Có tin nhắn mới, tự động tải lại danh sách...');
      _loadConversations();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // 2. Các hàm Helper để xử lý logic hiển thị dựa trên Model thật
  String _getDisplayName(ConversationModel c) {
    if (c.isGroup) return c.name ?? 'Nhóm';
    final uid = authService.userId;
    final other = c.members.firstWhere((m) => m.userId != uid, orElse: () => c.members.first);
    return other.nickname ?? 'Người dùng';
  }

  String? _getAvatar(ConversationModel c) {
    if (c.isGroup) return c.avatar;
    return c.avatar; // Trong DB thật, avatar thường lưu ở cấp Conversation hoặc Member
  }

  UserModel? _getOtherUser(ConversationModel c) {
    if (c.isGroup) return null;
    final uid = authService.userId;
    final other = c.members.firstWhere((m) => m.userId != uid, orElse: () => c.members.first);
    
    // Convert từ Member sang UserModel tạm thời để truyền sang màn hình Detail
    return UserModel(
      id: other.userId,
      fullName: other.nickname ?? 'Người dùng',
      avatar: c.avatar ?? '',
      phone: '',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSearch(),

            Expanded(
              child: FutureBuilder<List<ConversationModel>>(
                future: _conversationsFuture,
                builder: (context, snapshot) {
                  // Hiển thị loading
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                  }

                  // Hiển thị lỗi
                  if (snapshot.hasError) {
                    return Center(child: Text('Lỗi kết nối Server', style: TextStyle(color: AppColors.textSecondary)));
                  }

                  final allConvs = snapshot.data ?? [];
                  
                  // Lọc theo tìm kiếm
                  final filteredList = allConvs.where((c) {
                    if (_query.isEmpty) return true;
                    return _getDisplayName(c).toLowerCase().contains(_query.toLowerCase());
                  }).toList();

                  return RefreshIndicator(
                    onRefresh: () async => _loadConversations(),
                    color: AppColors.primary,
                    child: ListView(
                      padding: EdgeInsets.zero,
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        _buildAiCard(),
                        _buildStoryRow(), // Giữ giao diện story (có thể tích hợp API sau)

                        if (filteredList.isEmpty)
                          _buildEmptyState()
                        else
                          ...filteredList.map(_buildConvTile),

                        const SizedBox(height: 16),
                      ],
                    ),
                  );
                },
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
        child: Text('Chưa có cuộc trò chuyện nào', style: TextStyle(color: AppColors.textHint, fontSize: 13)),
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
          const Text('Tin nhắn',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontFamily: 'Inter')),
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
        style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Inter', fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Tìm kiếm cuộc trò chuyện...',
          prefixIcon: const Icon(Icons.search, color: AppColors.textHint, size: 20),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: AppColors.textHint, size: 18),
                  onPressed: () { _searchCtrl.clear(); setState(() => _query = ''); })
              : null,
        ),
      ),
    );
  }

  Widget _buildAiCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A35), Color(0xFF1E2A4A)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(gradient: AppColors.aiGradient, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Trợ lý AI', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white, fontFamily: 'Inter')),
                Text('Hôm nay tôi có thể giúp gì cho bạn?', style: TextStyle(fontSize: 12, color: Colors.white70, fontFamily: 'Inter')),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
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
    final isMe = last?.senderId == uid;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          conversationId: c.id,
          otherUser: _getOtherUser(c),
          conversation: c,
        ),
      )),
      onLongPress: () => _showContextMenu(c),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.unreadCount > 0 ? AppColors.bgCardLight : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            AvatarWidget(url: avatar, name: name, size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name,
                            style: TextStyle(
                              fontSize: 15, fontFamily: 'Inter',
                              fontWeight: c.unreadCount > 0 ? FontWeight.w700 : FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      if (last != null)
                        Text(du.DateUtils.formatChatTime(last.createdAt),
                          style: TextStyle(fontSize: 12, color: AppColors.textHint, fontFamily: 'Inter')),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          last != null ? (isMe ? 'Bạn: ${last.content}' : last.content) : 'Bắt đầu cuộc trò chuyện',
                          style: TextStyle(
                            fontSize: 13, fontFamily: 'Inter',
                            color: c.unreadCount > 0 ? AppColors.textSecondary : AppColors.textHint,
                            fontWeight: c.unreadCount > 0 ? FontWeight.w500 : FontWeight.w400,
                          ),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (c.unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                          child: Text('${c.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          _MenuTile(Icons.push_pin_outlined, 'Ghim cuộc trò chuyện', AppColors.textPrimary, () => Navigator.pop(context)),
          _MenuTile(Icons.delete_outline, 'Xoá cuộc trò chuyện', AppColors.error, () => Navigator.pop(context)),
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
  const _HeaderIconBtn({required this.icon, required this.onTap, this.filled = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(color: filled ? AppColors.primary : AppColors.bgCard, shape: BoxShape.circle),
      child: Icon(icon, color: filled ? Colors.white : AppColors.textSecondary, size: 20),
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
    title: Text(label, style: TextStyle(color: color, fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500)),
    onTap: onTap,
  );
}