import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/image_utils.dart';
import '../../services/auth_service.dart';
import '../../services/contacts_api_service.dart';

class GroupOptionsScreen extends StatefulWidget {
  final ApiGroupModel group;

  const GroupOptionsScreen({super.key, required this.group});

  @override
  State<GroupOptionsScreen> createState() => _GroupOptionsScreenState();
}

class _GroupOptionsScreenState extends State<GroupOptionsScreen> {
  bool _isPinned = false;
  bool _isHidden = false;
  bool _isMuted = false;

  late ApiGroupModel _group;

  bool get _isAdmin {
    final myId = authService.userId ?? '';
    return _group.members.any(
      (m) => m.userId == myId && (m.role == 'ADMIN' || m.role == 'MODERATOR'),
    );
  }

  @override
  void initState() {
    super.initState();
    _group = widget.group;
  }

  // ── Đổi tên nhóm ──────────────────────────────────────────────
  void _showRenameDialog() {
    final ctrl = TextEditingController(text: _group.name);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text(
          'Đổi tên nhóm',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(
              fontFamily: 'Inter', color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Nhập tên nhóm',
            hintStyle: const TextStyle(color: AppColors.textHint),
            filled: true,
            fillColor: AppColors.bgDark,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Huỷ',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                setState(() => _group = ApiGroupModel(
                      id: _group.id,
                      name: name,
                      avatar: _group.avatar,
                      members: _group.members,
                      lastMessageContent: _group.lastMessageContent,
                      lastMessageAt: _group.lastMessageAt,
                      updatedAt: _group.updatedAt,
                    ));
              }
              Navigator.pop(context);
            },
            child: const Text('Lưu',
                style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── Xác nhận rời nhóm ─────────────────────────────────────────
  void _confirmLeave() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text(
          'Rời nhóm',
          style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary),
        ),
        content: Text(
          'Bạn có chắc muốn rời khỏi nhóm "${_group.name}"?',
          style: const TextStyle(
              fontFamily: 'Inter', color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Huỷ',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              // Đóng dialog → đóng Options → đóng Chat
              Navigator.pop(context);
              Navigator.pop(context, null); // null = thoát khỏi nhóm
              Navigator.pop(context);
            },
            child: const Text('Rời nhóm',
                style: TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── Xác nhận xoá lịch sử ──────────────────────────────────────
  void _confirmDeleteHistory() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text(
          'Xoá lịch sử trò chuyện',
          style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary),
        ),
        content: const Text(
          'Toàn bộ tin nhắn sẽ bị xoá khỏi thiết bị của bạn. Thao tác này không thể hoàn tác.',
          style: TextStyle(
              fontFamily: 'Inter', color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Huỷ',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Xoá',
                style: TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final memberCount = _group.members.length;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, _group),
        ),
        title: const Text(
          'Tùy chọn',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Header: Avatar + tên ────────────────────────────────
          _buildHeader(),

          const SizedBox(height: 8),

          // ── 4 nút hành động ─────────────────────────────────────
          _buildActionRow(),

          const SizedBox(height: 8),

          // ── Section 1: Mô tả / Ảnh-file / Lịch / Ghim / Bình chọn
          _buildSection([
            _buildDescriptionTile(),
            _buildDivider(),
            _buildMediaTile(),
            _buildDivider(),
            _buildNavTile(
              icon: Icons.calendar_month_outlined,
              label: 'Lịch nhóm',
              onTap: () {},
            ),
            _buildDivider(),
            _buildNavTile(
              icon: Icons.push_pin_outlined,
              label: 'Tin nhắn đã ghim',
              onTap: () {},
            ),
            _buildDivider(),
            _buildNavTile(
              icon: Icons.bar_chart_rounded,
              label: 'Bình chọn',
              onTap: () {},
            ),
          ]),

          const SizedBox(height: 8),

          // ── Section 2: Thành viên / Link / Ghim CV / Ẩn / Cá nhân
          _buildSection([
            _buildNavTile(
              icon: Icons.group_outlined,
              label: 'Xem thành viên',
              trailing: Text(
                '($memberCount)',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: AppColors.textHint,
                ),
              ),
              onTap: () => _showMembersSheet(),
            ),
            _buildDivider(),
            _buildLinkTile(),
            _buildDivider(),
            _buildToggleTile(
              icon: Icons.push_pin_outlined,
              label: 'Ghim trò chuyện',
              value: _isPinned,
              onChanged: (v) => setState(() => _isPinned = v),
            ),
            _buildDivider(),
            _buildToggleTile(
              icon: Icons.visibility_off_outlined,
              label: 'Ẩn trò chuyện',
              value: _isHidden,
              onChanged: (v) => setState(() => _isHidden = v),
            ),
            _buildDivider(),
            _buildNavTile(
              icon: Icons.person_outline_rounded,
              label: 'Cài đặt cá nhân',
              onTap: () {},
            ),
          ]),

          const SizedBox(height: 8),

          // ── Section 3: Báo xấu / Dung lượng
          _buildSection([
            _buildNavTile(
              icon: Icons.warning_amber_outlined,
              label: 'Báo xấu',
              onTap: () {},
            ),
            _buildDivider(),
            _buildNavTile(
              icon: Icons.storage_outlined,
              label: 'Dung lượng trò chuyện',
              onTap: () {},
            ),
          ]),

          const SizedBox(height: 8),

          // ── Section 4: Xoá lịch sử / Rời nhóm (đỏ)
          _buildSection([
            _buildNavTile(
              icon: Icons.delete_outline_rounded,
              label: 'Xóa lịch sử trò chuyện',
              labelColor: AppColors.error,
              iconColor: AppColors.error,
              onTap: _confirmDeleteHistory,
            ),
            _buildDivider(),
            _buildNavTile(
              icon: Icons.logout_rounded,
              label: 'Rời nhóm',
              labelColor: AppColors.error,
              iconColor: AppColors.error,
              onTap: _confirmLeave,
            ),
          ]),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          // Avatar
          Stack(
            children: [
              _group.avatar.isNotEmpty
                  ? ClipOval(
                      child: Image.network(
                        webSafeImageUrl(_group.avatar),
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _defaultGroupAvatar(80),
                      ),
                    )
                  : _defaultGroupAvatar(80),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: AppColors.bgDark,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.bgCard, width: 2),
                  ),
                  child: const Icon(Icons.camera_alt_outlined,
                      size: 14, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Tên nhóm + nút edit
          GestureDetector(
            onTap: _isAdmin ? _showRenameDialog : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _group.name.isEmpty ? 'Nhóm' : _group.name,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (_isAdmin) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.edit_outlined,
                      size: 18, color: AppColors.textSecondary),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 4 nút hành động ──────────────────────────────────────────
  Widget _buildActionRow() {
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(
            icon: Icons.search_rounded,
            label: 'Tìm\ntin nhắn',
            onTap: () {},
          ),
          _ActionButton(
            icon: Icons.person_add_alt_1_outlined,
            label: 'Thêm\nthành viên',
            onTap: () {},
          ),
          _ActionButton(
            icon: Icons.wallpaper_rounded,
            label: 'Đổi\nhinh nền',
            onTap: () {},
          ),
          _ActionButton(
            icon: _isMuted
                ? Icons.notifications_off_outlined
                : Icons.notifications_outlined,
            label: _isMuted ? 'Bật\nthông báo' : 'Tắt\nthông báo',
            onTap: () => setState(() => _isMuted = !_isMuted),
          ),
        ],
      ),
    );
  }

  // ── Mô tả nhóm ───────────────────────────────────────────────
  Widget _buildDescriptionTile() {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F0FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.info_outline_rounded,
                  size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            const Text(
              'Thêm mô tả nhóm',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Ảnh, file, link ──────────────────────────────────────────
  Widget _buildMediaTile() {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.folder_outlined,
                      size: 18, color: Color(0xFFFF9800)),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Ảnh, file, link',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textHint, size: 20),
              ],
            ),
            const SizedBox(height: 10),
            // Preview thumbnails placeholder
            SizedBox(
              height: 60,
              child: Row(
                children: [
                  _mediaThumbnail(Icons.image_outlined,
                      const Color(0xFFE3F2FD)),
                  const SizedBox(width: 6),
                  _mediaThumbnail(Icons.code_rounded,
                      const Color(0xFFE8F5E9)),
                  const SizedBox(width: 6),
                  _mediaThumbnail(Icons.link_rounded,
                      const Color(0xFFF3E5F5)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: InkWell(
                      onTap: () {},
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.bgDark,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Icon(Icons.arrow_forward_rounded,
                              color: AppColors.primary, size: 20),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mediaThumbnail(IconData icon, Color bg) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: AppColors.textSecondary, size: 24),
    );
  }

  // ── Link nhóm ────────────────────────────────────────────────
  Widget _buildLinkTile() {
    final link = 'https://zalo.me/g/${_group.id.substring(0, 8)}';
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: link));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã sao chép link nhóm'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
            backgroundColor: Color(0xFF1C1C1C),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F0FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.link_rounded,
                  size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Link nhóm',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    link,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: AppColors.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.copy_outlined,
                size: 16, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }

  // ── Xem thành viên sheet ──────────────────────────────────────
  void _showMembersSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        builder: (_, ctrl) => Column(
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Text(
                    'Thành viên (${_group.members.length})',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            Expanded(
              child: ListView.builder(
                controller: ctrl,
                itemCount: _group.members.length,
                itemBuilder: (_, i) {
                  final m = _group.members[i];
                  final isAdmin =
                      m.role == 'ADMIN' || m.role == 'MODERATOR';
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.bgDark,
                      child: Text(
                        m.userId.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    title: Text(
                      m.userId,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    subtitle: isAdmin
                        ? Text(
                            m.role == 'ADMIN'
                                ? 'Quản trị viên'
                                : 'Điều hành viên',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: AppColors.primary,
                            ),
                          )
                        : null,
                    trailing: isAdmin
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              m.role == 'ADMIN' ? 'Admin' : 'Mod',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          )
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────
  Widget _buildSection(List<Widget> children) {
    return Container(
      color: AppColors.bgCard,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _buildDivider() => const Padding(
        padding: EdgeInsets.only(left: 62),
        child: Divider(height: 1, thickness: 1, color: AppColors.divider),
      );

  Widget _buildNavTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? labelColor,
    Color? iconColor,
    Widget? trailing,
  }) {
    final fg = labelColor ?? AppColors.textPrimary;
    final ic = iconColor ?? AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: ic),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
            ),
            if (trailing != null) ...[
              trailing,
              const SizedBox(width: 4),
            ],
            if (trailing == null && labelColor == null)
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleTile({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppColors.textSecondary),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _defaultGroupAvatar(double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFFE5E7EB),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.group,
          color: AppColors.textSecondary, size: size * 0.5),
    );
  }
}

// ── Action button ─────────────────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.bgDark,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 24, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: AppColors.textSecondary,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}
