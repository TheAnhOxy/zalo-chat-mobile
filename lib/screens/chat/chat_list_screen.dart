import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/date_utils.dart' as du;
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../../services/auth_service.dart';
import '../../widgets/common/common_widgets.dart';
import 'chat_detail_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  List<ConversationModel> get _filteredConvs {
    final uid = authService.userId ?? '';
    final list = mockConversations.where((c) => c.members.any((m) => m.userId == uid)).toList();
    if (_query.isEmpty) return list;
    return list.where((c) {
      final name = _getDisplayName(c).toLowerCase();
      return name.contains(_query.toLowerCase());
    }).toList();
  }

  String _getDisplayName(ConversationModel c) {
    if (c.isGroup) return c.name ?? 'Nhóm';
    final uid = authService.userId;
    final other = c.members.firstWhere((m) => m.userId != uid, orElse: () => c.members.first);
    return getUser(other.userId)?.fullName ?? 'Người dùng';
  }

  String? _getAvatar(ConversationModel c) {
    if (c.id == 'CONV_AI') return null;
    if (c.isGroup) return c.avatar;
    final uid = authService.userId;
    final other = c.members.firstWhere((m) => m.userId != uid, orElse: () => c.members.first);
    return getUser(other.userId)?.avatar;
  }

  bool _isOtherOnline(ConversationModel c) {
    if (c.isGroup) return false;
    final uid = authService.userId;
    final other = c.members.firstWhere((m) => m.userId != uid, orElse: () => c.members.first);
    return getUser(other.userId)?.isOnline ?? false;
  }

  UserModel? _getOtherUser(ConversationModel c) {
    if (c.isGroup) return null;
    final uid = authService.userId;
    final other = c.members.firstWhere((m) => m.userId != uid, orElse: () => c.members.first);
    return getUser(other.userId);
  }

  List<String?> _getGroupAvatars(ConversationModel c) =>
      c.members.take(3).map((m) => getUser(m.userId)?.avatar).toList();

  List<String> _getGroupNames(ConversationModel c) =>
      c.members.take(3).map((m) => getUser(m.userId)?.fullName ?? '').toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────
            _buildHeader(),

            // ── Search ───────────────────────────────────────────
            _buildSearch(),

            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // ── AI Assistant Card ───────────────────────────
                  _buildAiCard(),

                  // ── Story / Online Row ──────────────────────────
                  _buildStoryRow(),

                  // ── Conversation List ───────────────────────────
                  ..._filteredConvs.map(_buildConvTile),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

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
          _HeaderIconBtn(
            icon: Icons.add,
            onTap: () {},
            filled: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    if (_query.isEmpty && true) return const SizedBox.shrink();
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

  // AI Assistant Card
  Widget _buildAiCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A35), Color(0xFF1E2A4A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              gradient: AppColors.aiGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Trợ lý AI',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontFamily: 'Inter')),
                SizedBox(height: 2),
                Text('Hôm nay tôi có thể giúp gì cho bạn?',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontFamily: 'Inter')),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
        ],
      ),
    );
  }

  // Story / Online row
  Widget _buildStoryRow() {
    return SizedBox(
      height: 96,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: storyUsers.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return _StoryItem(
              label: 'Tin mới',
              child: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border, width: 1.5),
                ),
                child: const Icon(Icons.add, color: AppColors.textSecondary, size: 22),
              ),
            );
          }
          final u = storyUsers[i - 1];
          return _StoryItem(
            label: u.fullName.split(' ').last,
            child: Stack(children: [
              AvatarWidget(url: u.avatar, name: u.fullName, size: 48),
              if (u.isOnline)
                Positioned(
                  right: 1, bottom: 1,
                  child: Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(
                      color: AppColors.online,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.bgDark, width: 2),
                    ),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }

  // Conversation Tile
  Widget _buildConvTile(ConversationModel c) {
    final name     = _getDisplayName(c);
    final avatar   = _getAvatar(c);
    final isOnline = _isOtherOnline(c);
    final last     = c.lastMessage;
    final isAI     = c.id == 'CONV_AI';
    final uid      = authService.userId ?? '';
    final isMe     = last?.senderId == uid;

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
            // Avatar
            Stack(children: [
              isAI
                  ? Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(
                        gradient: AppColors.aiGradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 26),
                    )
                  : c.isGroup
                      ? GroupAvatarWidget(
                          avatarUrls: _getGroupAvatars(c),
                          names: _getGroupNames(c),
                          size: 52,
                        )
                      : AvatarWidget(url: avatar, name: name, size: 52),
              if (!isAI && !c.isGroup && c.unreadCount > 0)
                Positioned(
                  top: 0, right: 0,
                  child: Container(
                    width: 18, height: 18,
                    decoration: BoxDecoration(
                      color: AppColors.badge,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.bgDark, width: 2),
                    ),
                    child: Center(
                      child: Text('${c.unreadCount}',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700, fontFamily: 'Inter')),
                    ),
                  ),
                ),
            ]),
            const SizedBox(width: 12),

            // Content
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
                        Text(
                          du.DateUtils.formatChatTime(last.createdAt),
                          style: TextStyle(
                            fontSize: 12, fontFamily: 'Inter',
                            color: c.unreadCount > 0 ? AppColors.primary : AppColors.textHint,
                            fontWeight: c.unreadCount > 0 ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          last != null
                              ? (isMe ? 'Bạn: ${last.content}' : last.content)
                              : 'Bắt đầu cuộc trò chuyện',
                          style: TextStyle(
                            fontSize: 13, fontFamily: 'Inter',
                            color: c.unreadCount > 0 ? AppColors.textSecondary : AppColors.textHint,
                            fontWeight: c.unreadCount > 0 ? FontWeight.w500 : FontWeight.w400,
                          ),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (c.unreadCount > 1)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                          child: Text('${c.unreadCount}',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, fontFamily: 'Inter')),
                        ),
                      if (isMe && c.unreadCount == 0)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.done_all, size: 14, color: AppColors.primary),
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
          _MenuTile(Icons.notifications_off_outlined, 'Tắt thông báo', AppColors.textPrimary, () => Navigator.pop(context)),
          _MenuTile(Icons.mark_chat_unread_outlined, 'Đánh dấu chưa đọc', AppColors.textPrimary, () => Navigator.pop(context)),
          _MenuTile(Icons.delete_outline, 'Xoá cuộc trò chuyện', AppColors.error, () => Navigator.pop(context)),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _StoryItem extends StatelessWidget {
  final String label;
  final Widget child;
  const _StoryItem({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 16),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      child,
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontFamily: 'Inter'), maxLines: 1),
    ]),
  );
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
      decoration: BoxDecoration(
        color: filled ? AppColors.primary : AppColors.bgCard,
        shape: BoxShape.circle,
        boxShadow: filled ? [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 8)] : null,
      ),
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
