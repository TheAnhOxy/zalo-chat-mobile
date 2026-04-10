// Group detail screen reuses ChatDetailScreen
// This file just re-exports with group-specific header behavior
// The ChatDetailScreen already handles isGroup logic

// Group Info screen
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../../widgets/common/common_widgets.dart';
import '../chat/chat_detail_screen.dart';

class GroupDetailScreen extends StatelessWidget {
  final ConversationModel conversation;
  const GroupDetailScreen({super.key, required this.conversation});

  @override
  Widget build(BuildContext context) {
    return ChatDetailScreen(
      conversationId: conversation.id,
      otherUser: null,
      conversation: conversation,
    );
  }
}

// Group Info (shown when tap ℹ️ in group chat)
class GroupInfoScreen extends StatelessWidget {
  final ConversationModel conversation;
  const GroupInfoScreen({super.key, required this.conversation});

  @override
  Widget build(BuildContext context) {
    final members = conversation.members.map((m) => getUser(m.userId)).whereType<UserModel>().toList();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgDark,
        title: const Text('Thông tin nhóm', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary), onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(
        children: [
          // Group avatar + name
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              CircleAvatar(radius: 48, backgroundImage: conversation.avatar != null ? NetworkImage(conversation.avatar!) : null,
                  backgroundColor: AppColors.bgCard,
                  child: conversation.avatar == null ? const Icon(Icons.group, color: AppColors.textSecondary, size: 40) : null),
              const SizedBox(height: 12),
              Text(conversation.name ?? 'Nhóm', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontFamily: 'Inter')),
              Text('${members.length} thành viên', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontFamily: 'Inter')),
            ]),
          ),
          // Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _ActionBtn(Icons.search, 'Tìm kiếm', () {}),
              _ActionBtn(Icons.notifications_outlined, 'Thông báo', () {}),
              _ActionBtn(Icons.person_add_outlined, 'Thêm thành viên', () {}),
              _ActionBtn(Icons.more_horiz, 'Thêm', () {}),
            ]),
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.divider),

          // Members
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('Thành viên (${members.length})',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary, fontFamily: 'Inter')),
          ),
          ...members.map((u) {
            final member = conversation.members.firstWhere((m) => m.userId == u.id);
            return ListTile(
              leading: AvatarWidget(url: u.avatar, name: u.fullName, size: 44, showOnline: true, isOnline: u.isOnline),
              title: Text(u.fullName, style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Inter', fontWeight: FontWeight.w500)),
              subtitle: Text(member.role == 'ADMIN' ? 'Quản trị viên' : 'Thành viên',
                  style: TextStyle(color: member.role == 'ADMIN' ? AppColors.primary : AppColors.textHint, fontSize: 12, fontFamily: 'Inter')),
              trailing: u.isOnline
                  ? Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.online.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                      child: const Text('Đang online', style: TextStyle(fontSize: 11, color: AppColors.online, fontFamily: 'Inter')))
                  : null,
            );
          }),
          const SizedBox(height: 24),

          // Leave group
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.exit_to_app, color: AppColors.error),
              label: const Text('Rời khỏi nhóm', style: TextStyle(color: AppColors.error, fontFamily: 'Inter')),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.error), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () {},
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionBtn(this.icon, this.label, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(children: [
      Container(width: 48, height: 48,
          decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: AppColors.textSecondary, size: 22)),
      const SizedBox(height: 6),
      SizedBox(width: 64, child: Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontFamily: 'Inter'), textAlign: TextAlign.center)),
    ]),
  );
}
