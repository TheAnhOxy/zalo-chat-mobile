import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/image_utils.dart';
import '../../data/models/models.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/contacts_api_service.dart';
import '../../widgets/common/common_widgets.dart';

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
      (m) => m.userId == myId && m.role == 'ADMIN',
    );
  }

  /// Chỉ còn một admin và đó là mình — không cho rời (cần thêm QTV khác trước).
  bool get _isSoleAdmin {
    final myId = authService.userId ?? '';
    final adminCount = _group.members.where((m) => m.role == 'ADMIN').length;
    if (adminCount != 1) return false;
    return _group.members
        .any((m) => m.userId == myId && m.role == 'ADMIN');
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

  // ── Rời nhóm (API) ────────────────────────────────────────────
  void _showLeaveSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Inter')),
        backgroundColor: isError ? AppColors.error : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showLeaveLoading() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }

  Future<void> _confirmLeave() async {
    final confirmed = await showDialog<bool>(
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
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rời nhóm',
                style: TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    if (_isSoleAdmin) {
      _showLeaveSnack(
        'Bạn là quản trị viên duy nhất. Hãy thêm quản trị viên khác trước khi rời nhóm.',
        isError: true,
      );
      return;
    }

    final myId = authService.userId;
    if (myId == null || myId.isEmpty) {
      _showLeaveSnack('Chưa đăng nhập', isError: true);
      return;
    }

    _showLeaveLoading();
    final result = await ContactsApiService.instance.leaveGroup(
      conversationId: _group.id,
      myUserId: myId,
      currentMembers: _group.members,
    );
    if (mounted) Navigator.of(context, rootNavigator: true).pop();

    if (!mounted) return;
    if (result.isSuccess) {
      Navigator.pop(context, true);
    } else {
      _showLeaveSnack(result.error ?? 'Không thể rời nhóm', isError: true);
    }
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
                color: const Color(0xFFE8F5E9),
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
                      const Color(0xFFE8F5E9)),
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
                color: const Color(0xFFE8F5E9),
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

  // ── Xem thành viên sheet (tải tên qua API) ─────────────────────
  void _showMembersSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => _GroupMembersSheetBody(
        conversationId: _group.id,
        members: _group.members,
        canManage: _isAdmin,
        myUserId: authService.userId,
        onMembersUpdated: (updated) {
          setState(() {
            _group = ApiGroupModel(
              id: _group.id,
              name: _group.name,
              avatar: _group.avatar,
              members: updated,
              lastMessageContent: _group.lastMessageContent,
              lastMessageAt: _group.lastMessageAt,
              updatedAt: _group.updatedAt,
            );
          });
        },
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

/// Sheet "Thành viên": tên/avatar + quản trị viên có thể thêm/hủy QTV (giống màn quản lý).
class _GroupMembersSheetBody extends StatefulWidget {
  final String conversationId;
  final List<ApiGroupMember> members;
  final bool canManage;
  final String? myUserId;
  final ValueChanged<List<ApiGroupMember>>? onMembersUpdated;

  const _GroupMembersSheetBody({
    required this.conversationId,
    required this.members,
    required this.canManage,
    required this.myUserId,
    this.onMembersUpdated,
  });

  @override
  State<_GroupMembersSheetBody> createState() => _GroupMembersSheetBodyState();
}

class _GroupMembersSheetBodyState extends State<_GroupMembersSheetBody> {
  late List<ApiGroupMember> _members;
  Map<String, UserModel> _userMap = {};
  bool _loading = true;
  String? _error;

  int get _adminCount =>
      _members.where((m) => m.role == 'ADMIN').length;

  @override
  void initState() {
    super.initState();
    _members = List<ApiGroupMember>.from(widget.members);
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ids = _members.map((m) => m.userId).toList();
      final Map<String, UserModel> map = {};
      await Future.wait(ids.map((id) async {
        final user = await apiService.getUserById(id);
        if (user != null) map[id] = user;
      }));
      if (mounted) {
        setState(() {
          _userMap = map;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Không thể tải danh sách thành viên';
          _loading = false;
        });
      }
    }
  }

  String _displayName(ApiGroupMember m) {
    final u = _userMap[m.userId];
    final n = u?.fullName.trim();
    if (n != null && n.isNotEmpty) return n;
    return m.userId;
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Inter')),
        backgroundColor: isError ? AppColors.error : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showLoading() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmText,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(
            fontFamily: 'Inter',
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Hủy',
              style: TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              confirmText,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _changeRole(ApiGroupMember member, String newRole) async {
    final user = _userMap[member.userId];
    final name = user?.fullName ?? 'thành viên này';

    if (newRole == 'MEMBER' && member.role == 'ADMIN') {
      if (_adminCount <= 1) {
        _showSnack('Nhóm phải có ít nhất một quản trị viên', isError: true);
        return;
      }
    }

    final isPromote = newRole == 'ADMIN';
    final ok = await _showConfirmDialog(
      title: isPromote ? 'Thêm quản trị viên' : 'Hủy quản trị viên',
      message: isPromote
          ? 'Phân quyền quản trị viên cho $name? Người này có thể quản lý thành viên và cài đặt nhóm.'
          : 'Thu hồi quyền quản trị viên của $name? Họ chỉ còn là thành viên thường.',
      confirmText: 'Xác nhận',
    );
    if (!ok) return;

    _showLoading();
    final result = await ContactsApiService.instance.updateMemberRole(
      conversationId: widget.conversationId,
      targetUserId: member.userId,
      newRole: newRole,
      currentMembers: _members,
    );
    if (mounted) Navigator.of(context, rootNavigator: true).pop();

    if (result.isSuccess) {
      setState(() {
        _members = _members
            .map((m) => m.userId == member.userId
                ? ApiGroupMember(userId: m.userId, role: newRole)
                : m)
            .toList();
      });
      widget.onMembersUpdated?.call(_members);
      _showSnack(
        isPromote
            ? 'Đã thêm quản trị viên: $name'
            : 'Đã hủy quyền quản trị viên: $name',
      );
    } else {
      _showSnack(result.error ?? 'Không thể cập nhật vai trò', isError: true);
    }
  }

  Future<void> _kickMember(ApiGroupMember member) async {
    final user = _userMap[member.userId];
    final name = user?.fullName ?? 'thành viên này';
    final confirmed = await _showConfirmDialog(
      title: 'Xóa khỏi nhóm',
      message: 'Xóa $name khỏi nhóm?',
      confirmText: 'Xóa',
    );
    if (!confirmed) return;

    _showLoading();
    final result = await ContactsApiService.instance.kickMember(
      conversationId: widget.conversationId,
      targetUserId: member.userId,
      currentMembers: _members,
    );
    if (mounted) Navigator.of(context, rootNavigator: true).pop();

    if (result.isSuccess) {
      setState(() {
        _members =
            _members.where((m) => m.userId != member.userId).toList();
      });
      widget.onMembersUpdated?.call(_members);
      _showSnack('Đã xóa $name khỏi nhóm');
    } else {
      _showSnack(result.error ?? 'Không thể xóa thành viên', isError: true);
    }
  }

  void _showMemberActions(ApiGroupMember member) {
    if (!widget.canManage) return;
    if (member.userId == (widget.myUserId ?? '')) return;

    final user = _userMap[member.userId];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgCard,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      AvatarWidget(
                        url: user?.avatar,
                        name: user?.fullName ?? '?',
                        size: 40,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.fullName ?? member.userId,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              member.role == 'ADMIN'
                                  ? 'Quản trị viên'
                                  : 'Thành viên',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.divider),
                if (member.role != 'ADMIN')
                  _MembersSheetActionTile(
                    icon: Icons.star_rounded,
                    color: AppColors.primary,
                    label: 'Thêm quản trị viên',
                    onTap: () {
                      Navigator.pop(context);
                      _changeRole(member, 'ADMIN');
                    },
                  ),
                if (member.role == 'ADMIN')
                  _MembersSheetActionTile(
                    icon: Icons.person_rounded,
                    color: AppColors.textSecondary,
                    label: 'Hủy quản trị viên',
                    onTap: () {
                      Navigator.pop(context);
                      _changeRole(member, 'MEMBER');
                    },
                  ),
                _MembersSheetActionTile(
                  icon: Icons.person_remove_rounded,
                  color: AppColors.error,
                  label: 'Xóa khỏi nhóm',
                  onTap: () {
                    Navigator.pop(context);
                    _kickMember(member);
                  },
                ),
                _MembersSheetActionTile(
                  icon: Icons.close_rounded,
                  color: AppColors.textHint,
                  label: 'Đóng',
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
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
                  'Thành viên (${_members.length})',
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
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              color: AppColors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: ctrl,
                        itemCount: _members.length,
                        itemBuilder: (_, i) {
                          final m = _members[i];
                          final user = _userMap[m.userId];
                          final name = _displayName(m);
                          final isAdmin = m.role == 'ADMIN';
                          final canTap = widget.canManage &&
                              m.userId != (widget.myUserId ?? '');
                          return ListTile(
                            onTap: canTap ? () => _showMemberActions(m) : null,
                            leading: AvatarWidget(
                              url: user?.avatar,
                              name: name,
                              size: 40,
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            subtitle: isAdmin
                                ? const Text(
                                    'Quản trị viên',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 12,
                                      color: AppColors.primary,
                                    ),
                                  )
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isAdmin)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryLight,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'Admin',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                if (canTap) ...[
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.more_vert_rounded,
                                    size: 20,
                                    color: AppColors.textHint,
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _MembersSheetActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _MembersSheetActionTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: color == AppColors.textHint
              ? AppColors.textSecondary
              : AppColors.textPrimary,
        ),
      ),
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
