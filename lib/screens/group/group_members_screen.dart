import 'dart:developer';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/image_utils.dart';
import '../../data/models/models.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/contacts_api_service.dart';
import '../../services/socket_service.dart';

class GroupMembersScreen extends StatefulWidget {
  final ApiGroupModel group;

  const GroupMembersScreen({super.key, required this.group});

  @override
  State<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends State<GroupMembersScreen> {
  late ApiGroupModel _group;
  Map<String, UserModel> _userMap = {};
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();
  String _query = '';

  String get _myId => authService.userId ?? '';

  bool get _amAdmin => _group.members
      .any((m) => m.userId == _myId && m.role == 'ADMIN');

  bool get _canManage => _amAdmin;

  int get _adminCount =>
      _group.members.where((m) => m.role == 'ADMIN').length;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _loadUsers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ids = _group.members.map((m) => m.userId).toList();
      log('🔄 Loading ${ids.length} members: $ids');

      // Dùng apiService (Dio) thay vì http.Client để đảm bảo hoạt động trên web
      final Map<String, UserModel> map = {};
      await Future.wait(ids.map((id) async {
        final user = await apiService.getUserById(id);
        if (user != null) {
          map[id] = user;
          log('✅ Loaded user: ${user.fullName} (id=$id)');
        } else {
          log('⚠️ Không lấy được user: $id');
        }
      }));

      log('✅ Loaded ${map.length}/${ids.length} members');
      if (mounted) {
        setState(() {
          _userMap = map;
          _loading = false;
        });
      }
    } catch (e) {
      log('❌ Lỗi load members: $e');
      if (mounted) {
        setState(() {
          _error = 'Không thể tải danh sách thành viên';
          _loading = false;
        });
      }
    }
  }

  List<ApiGroupMember> get _filteredMembers {
    final q = _query.toLowerCase().trim();
    if (q.isEmpty) return _group.members;
    return _group.members.where((m) {
      final name = _userMap[m.userId]?.fullName ?? '';
      return name.toLowerCase().contains(q);
    }).toList();
  }

  // ── Kick member ─────────────────────────────────────────────────────────────

  Future<void> _kickMember(ApiGroupMember member) async {
    final user = _userMap[member.userId];
    final name = user?.fullName ?? 'thành viên này';

    final confirmed = await _showConfirmDialog(
      title: 'Xóa khỏi nhóm',
      message: 'Bạn có chắc muốn xóa $name khỏi nhóm?',
      confirmText: 'Xóa',
      isDestructive: true,
    );
    if (!confirmed) return;

    _showLoading();
    final result = await ContactsApiService.instance.kickMember(
      conversationId: _group.id,
      targetUserId: member.userId,
      currentMembers: _group.members,
    );
    if (mounted) Navigator.pop(context); // đóng loading

    if (result.isSuccess) {
      // Thông báo system trong nhóm giống Zalo
      final myId = authService.userId ?? '';
      final actorName = (authService.currentUser?.fullName.trim().isNotEmpty ==
                  true)
          ? authService.currentUser!.fullName.trim()
          : (authService.currentUser?.displayName.trim().isNotEmpty == true)
              ? authService.currentUser!.displayName.trim()
              : 'Bạn';
      final peerName = (user?.fullName ?? '').trim();
      socketService.sendMessage({
        'conversationId': _group.id,
        'senderId': myId,
        'type': 'SYSTEM',
        'content':
            'REMOVE_MEMBER|$actorName|${peerName.isEmpty ? 'một thành viên' : peerName}',
      });

      setState(() {
        _group = ApiGroupModel(
          id: _group.id,
          name: _group.name,
          avatar: _group.avatar,
          members: _group.members.where((m) => m.userId != member.userId).toList(),
          description: _group.description,
          lastMessageContent: _group.lastMessageContent,
          lastMessageAt: _group.lastMessageAt,
          updatedAt: _group.updatedAt,
        );
      });
      _showSnack('Đã xóa $name khỏi nhóm');
    } else {
      _showSnack(result.error ?? 'Lỗi không xác định', isError: true);
    }
  }

  // ── Update role ─────────────────────────────────────────────────────────────

  Future<void> _changeRole(ApiGroupMember member, String newRole) async {
    final user = _userMap[member.userId];
    final name = user?.fullName ?? 'thành viên này';

    if (newRole == 'MEMBER' && member.role == 'ADMIN') {
      if (_adminCount <= 1) {
        _showSnack('Nhóm phải có ít nhất một quản trị viên',
            isError: true);
        return;
      }
    }

    final isPromote = newRole == 'ADMIN';
    final confirmed = await _showConfirmDialog(
      title: isPromote ? 'Thêm quản trị viên' : 'Hủy quản trị viên',
      message: isPromote
          ? 'Phân quyền quản trị viên cho $name? Người này có thể quản lý thành viên và cài đặt nhóm.'
          : 'Thu hồi quyền quản trị viên của $name? Họ chỉ còn là thành viên thường.',
      confirmText: 'Xác nhận',
    );
    if (!confirmed) return;

    _showLoading();
    final result = await ContactsApiService.instance.updateMemberRole(
      conversationId: _group.id,
      targetUserId: member.userId,
      newRole: newRole,
      currentMembers: _group.members,
    );
    if (mounted) Navigator.pop(context); // đóng loading

    if (result.isSuccess) {
      setState(() {
        _group = ApiGroupModel(
          id: _group.id,
          name: _group.name,
          avatar: _group.avatar,
          members: _group.members
              .map((m) => m.userId == member.userId
                  ? ApiGroupMember(userId: m.userId, role: newRole)
                  : m)
              .toList(),
          description: _group.description,
          lastMessageContent: _group.lastMessageContent,
          lastMessageAt: _group.lastMessageAt,
          updatedAt: _group.updatedAt,
        );
      });
      _showSnack(
        newRole == 'ADMIN'
            ? 'Đã thêm quản trị viên: $name'
            : 'Đã hủy quyền quản trị viên: $name',
      );
    } else {
      _showSnack(result.error ?? 'Lỗi không xác định', isError: true);
    }
  }

  // ── Leave group ─────────────────────────────────────────────────────────────

  Future<void> _leaveGroup() async {
    final confirmed = await _showConfirmDialog(
      title: 'Rời nhóm',
      message: 'Bạn có chắc muốn rời khỏi "${_group.name}"?',
      confirmText: 'Rời nhóm',
      isDestructive: true,
    );
    if (!confirmed) return;

    _showLoading();
    final result = await ContactsApiService.instance.leaveGroup(
      conversationId: _group.id,
      myUserId: _myId,
      currentMembers: _group.members,
    );
    if (mounted) Navigator.pop(context); // đóng loading

    if (result.isSuccess) {
      // Thông báo system trong nhóm giống Zalo
      final actorName = (authService.currentUser?.fullName.trim().isNotEmpty ==
                  true)
          ? authService.currentUser!.fullName.trim()
          : (authService.currentUser?.displayName.trim().isNotEmpty == true)
              ? authService.currentUser!.displayName.trim()
              : 'Bạn';
      socketService.sendMessage({
        'conversationId': _group.id,
        'senderId': _myId,
        'type': 'SYSTEM',
        'content': 'LEAVE_GROUP|$actorName',
      });

      if (mounted) Navigator.pop(context, true); // trả về để refresh danh sách
    } else {
      _showSnack(result.error ?? 'Lỗi không xác định', isError: true);
    }
  }

  // ── Member action sheet ──────────────────────────────────────────────────────

  void _showMemberActions(ApiGroupMember member) {
    if (member.userId == _myId) return;

    final user = _userMap[member.userId];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
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
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(children: [
                    _AvatarWidget(url: user?.avatar, name: user?.fullName ?? '?', size: 40),
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
                            _roleLabel(member.role),
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),
                const Divider(height: 1, color: AppColors.divider),
                // Actions
                _ActionTile(
                  icon: Icons.person_outline_rounded,
                  color: AppColors.textPrimary,
                  label: 'Xem trang cá nhân',
                  onTap: () {
                    Navigator.pop(context);
                    if (user != null) {
                      final apiUser = ApiUserModel(
                        id: user.id,
                        fullName: user.fullName ?? user.displayName ?? '',
                        phone: user.phone ?? '',
                        avatar: user.avatar ?? '',
                        isOnline: user.status.isOnline,
                        lastSeen: user.status.lastSeen,
                      );
                      Navigator.pushNamed(context, '/contacts/found-user', arguments: apiUser);
                    }
                  },
                ),
                if (_canManage && member.role != 'ADMIN')
                  _ActionTile(
                    icon: Icons.star_rounded,
                    color: AppColors.primary,
                    label: 'Thêm quản trị viên',
                    onTap: () {
                      Navigator.pop(context);
                      _changeRole(member, 'ADMIN');
                    },
                  ),
                if (_canManage && member.role == 'ADMIN')
                  _ActionTile(
                    icon: Icons.person_rounded,
                    color: AppColors.textSecondary,
                    label: 'Hủy quản trị viên',
                    onTap: () {
                      Navigator.pop(context);
                      _changeRole(member, 'MEMBER');
                    },
                  ),
                if (_canManage)
                  _ActionTile(
                    icon: Icons.person_remove_rounded,
                    color: AppColors.error,
                    label: 'Xóa khỏi nhóm',
                    onTap: () {
                      Navigator.pop(context);
                      _kickMember(member);
                    },
                  ),
                _ActionTile(
                  icon: Icons.close_rounded,
                  color: AppColors.textHint,
                  label: 'Hủy',
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _roleLabel(String role) {
    if (role == 'ADMIN') return 'Quản trị viên';
    return 'Thành viên';
  }

  Color _roleColor(String role) =>
      role == 'ADMIN' ? AppColors.primary : AppColors.textHint;

  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmText,
    bool isDestructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
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
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                color: isDestructive ? AppColors.error : AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _showLoading() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
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

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final memberCount = _group.members.length;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quản lý thành viên',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
            Text(
              '$memberCount thành viên',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context, _group),
        ),
        actions: [
          if (_canManage)
            IconButton(
              icon: const Icon(Icons.person_add_rounded, color: Colors.white),
              tooltip: 'Thêm thành viên',
              onPressed: _openAddMembers,
            ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: AppColors.bgCard,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Tìm kiếm thành viên...',
                hintStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: AppColors.textHint,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.textHint,
                  size: 20,
                ),
                filled: true,
                fillColor: AppColors.bgDark,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Body
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _error != null
                    ? _buildError()
                    : _buildMemberList(),
          ),

          // Bottom: Leave group
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text(
            _error!,
            style: const TextStyle(
              fontFamily: 'Inter',
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _loadUsers,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Thử lại'),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberList() {
    final members = _filteredMembers;

    // Sắp xếp: ADMIN → MODERATOR → MEMBER
    members.sort((a, b) {
      const order = {'ADMIN': 0, 'MODERATOR': 1, 'MEMBER': 2};
      return (order[a.role] ?? 2).compareTo(order[b.role] ?? 2);
    });

    if (members.isEmpty) {
      return Center(
        child: Text(
          _query.isNotEmpty
              ? 'Không tìm thấy "${_query}"'
              : 'Chưa có thành viên',
          style: const TextStyle(
            fontFamily: 'Inter',
            color: AppColors.textHint,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadUsers,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        itemCount: members.length,
          itemBuilder: (_, i) {
            final member = members[i];
            final UserModel? user = _userMap[member.userId];
            final isMe = member.userId == _myId;
            final canTap = _amAdmin && !isMe;

          return _MemberTile(
            member: member,
            user: user,
            isMe: isMe,
            roleLabel: _roleLabel(member.role),
            roleColor: _roleColor(member.role),
            canManage: canTap, // true if amAdmin and not me (used to show 3 dots maybe?)
            onTap: isMe ? null : () => _showMemberActions(member),
          );
        },
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      color: AppColors.bgCard,
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.exit_to_app_rounded, color: AppColors.error),
          label: const Text(
            'Rời khỏi nhóm',
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
              color: AppColors.error,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.error),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _leaveGroup,
        ),
      ),
    );
  }

  // ── Add member sheet ─────────────────────────────────────────────────────────

  Future<void> _openAddMembers() async {
    final picked = await Navigator.push<List<String>?>(
      context,
      MaterialPageRoute(
        builder: (_) => AddMembersScreen(group: _group),
      ),
    );
    final newUserIds = picked ?? const <String>[];
    if (newUserIds.isEmpty) return;

    _showLoading();
    final result = await ContactsApiService.instance.addMembersToGroup(
      conversationId: _group.id,
      currentMembers: _group.members,
      newUserIds: newUserIds,
    );
    if (mounted) Navigator.pop(context); // đóng loading
    if (result.isSuccess) {
      // Thông báo system trong nhóm giống Zalo
      final myId = authService.userId ?? '';
      final actorName = (authService.currentUser?.fullName.trim().isNotEmpty ==
                  true)
          ? authService.currentUser!.fullName.trim()
          : (authService.currentUser?.displayName.trim().isNotEmpty == true)
              ? authService.currentUser!.displayName.trim()
              : 'Bạn';

      try {
        final users = await Future.wait(
          newUserIds.map((id) => apiService.getUserById(id)),
        );
        for (final u in users) {
          final peerName = (u?.fullName ?? u?.displayName ?? '').trim();
          socketService.sendMessage({
            'conversationId': _group.id,
            'senderId': myId,
            'type': 'SYSTEM',
            'content':
                'ADD_MEMBER|$actorName|${peerName.isEmpty ? 'một thành viên' : peerName}',
          });
        }
      } catch (_) {
        for (final _ in newUserIds) {
          socketService.sendMessage({
            'conversationId': _group.id,
            'senderId': myId,
            'type': 'SYSTEM',
            'content': 'ADD_MEMBER|$actorName|một thành viên',
          });
        }
      }

      await _loadUsers();
      _showSnack('Đã thêm ${newUserIds.length} thành viên');
    } else {
      _showSnack(result.error ?? 'Lỗi không xác định', isError: true);
    }
  }
}

// ── Add Members Screen (full screen giống Zalo) ────────────────────────────────

class AddMembersScreen extends StatefulWidget {
  final ApiGroupModel group;

  const AddMembersScreen({required this.group});

  @override
  State<AddMembersScreen> createState() => _AddMembersScreenState();
}

class _AddMembersScreenState extends State<AddMembersScreen> {
  List<ApiUserModel> _allFriends = []; // dùng ApiUserModel từ contacts service
  final Set<String> _selected = {};
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String _query = '';

  Set<String> get _existingIds =>
      widget.group.members.map((m) => m.userId).toSet();

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    final myId = authService.userId ?? '';
    final result = await ContactsApiService.instance.fetchFriends(myId);
    if (mounted) {
      setState(() {
        _allFriends = result.data ?? [];
        _loading = false;
      });
    }
  }

  List<ApiUserModel> get _filtered {
    final q = _query.toLowerCase().trim();
    return _allFriends
        .where((u) => !_existingIds.contains(u.id))
        .where((u) => q.isEmpty || u.fullName.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _filtered;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Thêm vào nhóm',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
            Text(
              'Đã chọn: ${_selected.length}',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.pop(context, _selected.toList()),
            child: Text(
              'Thêm',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                color: _selected.isEmpty ? Colors.white70 : Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Tìm tên hoặc số điện thoại',
                hintStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: AppColors.textHint,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.textHint,
                  size: 20,
                ),
                filled: true,
                fillColor: const Color(0xFFF2F3F5),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : (shown.isEmpty
                    ? const Center(
                        child: Text(
                          'Không có bạn bè để thêm',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.textHint,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: shown.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: AppColors.divider),
                        itemBuilder: (_, i) {
                          final u = shown[i];
                          final sel = _selected.contains(u.id);
                          return ListTile(
                            onTap: () {
                              setState(() {
                                if (sel) {
                                  _selected.remove(u.id);
                                } else {
                                  _selected.add(u.id);
                                }
                              });
                            },
                            leading: _AvatarWidget(
                              url: u.avatar,
                              name: u.fullName,
                              size: 44,
                            ),
                            title: Text(
                              u.fullName,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            trailing: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: sel
                                      ? AppColors.primary
                                      : AppColors.textHint,
                                  width: 2,
                                ),
                                color: sel
                                    ? AppColors.primary
                                    : Colors.transparent,
                              ),
                              child: sel
                                  ? const Icon(
                                      Icons.check,
                                      size: 16,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          );
                        },
                      )),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

// ── Member Tile ───────────────────────────────────────────────────────────────

class _MemberTile extends StatelessWidget {
  final ApiGroupMember member;
  final UserModel? user;
  final bool isMe;
  final String roleLabel;
  final Color roleColor;
  final bool canManage;
  final VoidCallback? onTap;

  const _MemberTile({
    required this.member,
    required this.user,
    required this.isMe,
    required this.roleLabel,
    required this.roleColor,
    required this.canManage,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = user?.fullName ?? member.userId;
    final isOnline = user?.isOnline ?? false;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: AppColors.bgCard,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Avatar + online indicator
            Stack(
              children: [
                _AvatarWidget(url: user?.avatar, name: name, size: 46),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.online,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: AppColors.bgCard, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),

            // Name + role
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          isMe ? '$name (Tôi)' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: roleColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          roleLabel,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: roleColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Trailing
            if (canManage)
              const Icon(
                Icons.more_vert_rounded,
                color: AppColors.textHint,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Action Tile ───────────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _ActionTile({
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

// ── Avatar Widget ─────────────────────────────────────────────────────────────

class _AvatarWidget extends StatelessWidget {
  final String? url;
  final String name;
  final double size;

  const _AvatarWidget({required this.url, required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    final safeUrl =
        (url == null || url!.isEmpty) ? null : webSafeImageUrl(url!);
    final initials = _initials(name);

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppColors.primary.withOpacity(0.15),
      foregroundImage: safeUrl != null ? NetworkImage(safeUrl) : null,
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: size * 0.32,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }

  String _initials(String n) {
    final parts =
        n.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.take(1).toString().toUpperCase();
    return (parts.first.characters.take(1).toString() +
            parts.last.characters.take(1).toString())
        .toUpperCase();
  }
}
