import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/image_utils.dart';
import '../../services/auth_service.dart';
import '../../services/contacts_api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CreateGroupScreen
// ─────────────────────────────────────────────────────────────────────────────
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();

  // Danh sách bạn bè và gần đây
  List<ApiUserModel>? _friends;
  List<RecentContact>? _recent;
  String? _friendsError;
  String? _recentError;

  // Tập hợp ID đang được chọn
  final Set<String> _selected = {};

  // Ảnh nhóm
  XFile? _avatarFile;

  // Keyboard type toggle: false = text (ABC), true = number (123)
  bool _numericKeyboard = false;
  final FocusNode _searchFocus = FocusNode();

  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tab.dispose();
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: AppColors.primary),
              title: const Text('Chụp ảnh',
                  style: TextStyle(
                      fontFamily: 'Inter', color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library_outlined, color: AppColors.primary),
              title: const Text('Chọn từ thư viện',
                  style: TextStyle(
                      fontFamily: 'Inter', color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;
    final file = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (file != null) setState(() => _avatarFile = file);
  }

  void _toggleKeyboard() {
    setState(() => _numericKeyboard = !_numericKeyboard);
    // Re-focus để bàn phím cập nhật type
    _searchFocus.unfocus();
    Future.microtask(() => _searchFocus.requestFocus());
  }

  Future<void> _loadData() async {
    final userId = authService.userId ?? '';
    final friendRes =
        await ContactsApiService.instance.fetchFriends(userId);
    final recentRes =
        await ContactsApiService.instance.fetchRecentContacts(userId);

    if (!mounted) return;
    setState(() {
      _friends = friendRes.data ?? [];
      _friendsError = friendRes.error;
      _recent = recentRes.data ?? [];
      _recentError = recentRes.error;
    });
  }

  void _toggleSelect(String userId) {
    setState(() {
      if (_selected.contains(userId)) {
        _selected.remove(userId);
      } else {
        _selected.add(userId);
      }
    });
  }

  List<ApiUserModel> get _filteredFriends {
    final q = _normalize(_searchCtrl.text);
    final friends = _friends ?? [];
    if (q.isEmpty) return friends;
    return friends
        .where((u) =>
            _normalize(u.fullName).contains(q) ||
            u.phone.contains(q))
        .toList();
  }

  List<RecentContact> get _filteredRecent {
    final q = _normalize(_searchCtrl.text);
    final recent = _recent ?? [];
    if (q.isEmpty) return recent;
    return recent
        .where((r) =>
            _normalize(r.user.fullName).contains(q) ||
            r.user.phone.contains(q))
        .toList();
  }

  String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[àáạảãâầấậẩẫăằắặẳẵ]'), 'a')
      .replaceAll(RegExp(r'[èéẹẻẽêềếệểễ]'), 'e')
      .replaceAll(RegExp(r'[ìíịỉĩ]'), 'i')
      .replaceAll(RegExp(r'[òóọỏõôồốộổỗơờớợởỡ]'), 'o')
      .replaceAll(RegExp(r'[ùúụủũưừứựửữ]'), 'u')
      .replaceAll(RegExp(r'[ỳýỵỷỹ]'), 'y')
      .replaceAll('đ', 'd');

  /// Chỉ lấy tên gọi (từ cuối), không lấy họ đệm — giống cách Zalo rút gọn tên nhóm.
  String _givenName(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    return parts.last;
  }

  Future<void> _createGroup() async {
    if (_selected.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn ít nhất 2 thành viên'),
          backgroundColor: Color(0xFF1C1C1C),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final myId = authService.userId ?? '';
    final me = authService.currentUser;
    final myGiven = _givenName(me?.fullName ?? '');
    final myName = myGiven.isNotEmpty ? myGiven : 'Bạn';

    // Tên nhóm mặc định nếu user bỏ trống
    String groupName = _nameCtrl.text.trim();
    if (groupName.isEmpty) {
      // Giống Zalo: ghép tên gọi của tất cả thành viên (gồm cả người tạo nhóm).
      final pool = <ApiUserModel>[
        ...(_recent?.map((r) => r.user) ?? const Iterable<ApiUserModel>.empty()),
        ...(_friends ?? const <ApiUserModel>[]),
      ];

      final otherNames = <String>[];
      final seen = <String>{};
      if (myId.isNotEmpty) seen.add(myId);
      for (final u in pool) {
        if (!_selected.contains(u.id)) continue;
        if (!seen.add(u.id)) continue;
        final n = _givenName(u.fullName);
        if (n.isNotEmpty) otherNames.add(n);
      }

      final allNames = <String>[myName, ...otherNames];

      // Không map được tên thành viên đã chọn → fallback
      if (otherNames.isEmpty) {
        groupName = 'Nhóm mới';
      } else {
        const maxShow = 4; // thường Zalo hiển thị 3-4 tên đầu
        final show = allNames.take(maxShow).toList();
        final remain = allNames.length - show.length;
        groupName = remain > 0
            ? '${show.join(', ')}, và $remain người khác'
            : show.join(', ');
      }
    }

    setState(() => _creating = true);

    // Upload ảnh lên S3, lấy URL công khai
    String? avatarUrl;
    if (_avatarFile != null) {
      try {
        final bytes = await _avatarFile!.readAsBytes();
        final ext = _avatarFile!.name.split('.').last.toLowerCase();
        const mimeMap = {
          'png': 'image/png',
          'gif': 'image/gif',
          'webp': 'image/webp',
          'bmp': 'image/bmp',
          'tiff': 'image/tiff',
          'tif': 'image/tiff',
          'svg': 'image/svg+xml',
          'ico': 'image/x-icon',
        };
        final mime = mimeMap[ext] ?? 'image/jpeg';
        avatarUrl = await ContactsApiService.instance.uploadGroupAvatar(
          bytes: bytes,
          fileName: _avatarFile!.name,
          mimeType: mime,
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => _creating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload ảnh thất bại: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    final allMemberIds = [myId, ..._selected.toList()];
    final result = await ContactsApiService.instance.createGroup(
      name: groupName,
      memberIds: allMemberIds,
      creatorId: myId,
      avatar: avatarUrl,
    );

    if (!mounted) return;
    setState(() => _creating = false);

    if (result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã tạo nhóm "$groupName"'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.pop(context, result.data);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Có lỗi xảy ra'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _selected.length;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nhóm mới',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            Text(
              'Đã chọn: $count',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        actions: count >= 2
            ? [
                _creating
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        ),
                      )
                    : TextButton(
                        onPressed: _createGroup,
                        child: const Text(
                          'Tạo nhóm',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
              ]
            : null,
      ),
      body: Column(
        children: [
          // ── Group name + avatar ────────────────────────────────────────
          Container(
            color: AppColors.bgCard,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                // Camera / avatar button
                GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.bgDark,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.border),
                        ),
                        child: _avatarFile == null
                            ? const Icon(
                                Icons.camera_alt_outlined,
                                size: 22,
                                color: AppColors.textSecondary,
                              )
                            : ClipOval(
                                child: kIsWeb
                                    ? Image.network(
                                        _avatarFile!.path,
                                        width: 44,
                                        height: 44,
                                        fit: BoxFit.cover,
                                      )
                                    : Image.file(
                                        File(_avatarFile!.path),
                                        width: 44,
                                        height: 44,
                                        fit: BoxFit.cover,
                                      ),
                              ),
                      ),
                      if (_avatarFile != null)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.edit,
                                size: 9, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Đặt tên nhóm',
                      hintStyle: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        color: AppColors.textHint,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Search bar ────────────────────────────────────────────────
          Container(
            color: AppColors.bgCard,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.bgDark,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  const Icon(Icons.search, size: 18, color: AppColors.textHint),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      keyboardType: _numericKeyboard
                          ? TextInputType.phone
                          : TextInputType.text,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Tìm tên hoặc số điện thoại',
                        hintStyle: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          color: AppColors.textHint,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  // Keyboard toggle button
                  GestureDetector(
                    onTap: _toggleKeyboard,
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0E0E0),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _numericKeyboard ? 'ABC' : '123',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Selected chips ─────────────────────────────────────────────
          if (_selected.isNotEmpty) _SelectedChips(
            selectedIds: _selected,
            allUsers: [
              ...(_friends ?? []),
              ...(_recent?.map((r) => r.user) ?? []),
            ],
            onRemove: _toggleSelect,
          ),

          // ── Tabs ───────────────────────────────────────────────────────
          Container(
            color: AppColors.bgCard,
            child: TabBar(
              controller: _tab,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              labelStyle: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              tabs: const [
                Tab(text: 'GẦN ĐÂY'),
                Tab(text: 'DANH BẠ'),
              ],
            ),
          ),

          // ── Tab content ────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                // GẦN ĐÂY
                _RecentTab(
                  recent: _filteredRecent,
                  error: _recentError,
                  loading: _recent == null && _recentError == null,
                  selected: _selected,
                  onToggle: _toggleSelect,
                  onRefresh: _loadData,
                ),
                // DANH BẠ
                _FriendsTab(
                  friends: _filteredFriends,
                  error: _friendsError,
                  loading: _friends == null && _friendsError == null,
                  selected: _selected,
                  onToggle: _toggleSelect,
                  onRefresh: _loadData,
                ),
              ],
            ),
          ),

          // ── Bottom create button (when ≥ 2 selected) ──────────────────
          if (count >= 2)
            _BottomCreateBar(
              count: count,
              creating: _creating,
              onTap: _createGroup,
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Selected chips
// ─────────────────────────────────────────────────────────────────────────────

class _SelectedChips extends StatelessWidget {
  final Set<String> selectedIds;
  final List<ApiUserModel> allUsers;
  final void Function(String) onRemove;

  const _SelectedChips({
    required this.selectedIds,
    required this.allUsers,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final users = allUsers
        .where((u) => selectedIds.contains(u.id))
        .fold<Map<String, ApiUserModel>>({}, (map, u) {
          map[u.id] = u;
          return map;
        })
        .values
        .toList();

    return Container(
      color: AppColors.bgCard,
      height: 70,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: users.length,
        itemBuilder: (_, i) {
          final u = users[i];
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Column(
              children: [
                Stack(
                  children: [
                    _Avatar(url: u.avatar, name: u.fullName, size: 38),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: GestureDetector(
                        onTap: () => onRemove(u.id),
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: Color(0xFF666666),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              size: 10, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GẦN ĐÂY tab
// ─────────────────────────────────────────────────────────────────────────────

class _RecentTab extends StatelessWidget {
  final List<RecentContact> recent;
  final String? error;
  final bool loading;
  final Set<String> selected;
  final void Function(String) onToggle;
  final Future<void> Function() onRefresh;

  const _RecentTab({
    required this.recent,
    required this.error,
    required this.loading,
    required this.selected,
    required this.onToggle,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (error != null && recent.isEmpty) {
      return _ErrorView(message: error!, onRetry: onRefresh);
    }
    if (recent.isEmpty) {
      return const _EmptyView(message: 'Chưa có cuộc trò chuyện nào');
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.primary,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: recent.length,
        itemBuilder: (_, i) {
          final r = recent[i];
          return _ContactTile(
            user: r.user,
            subtitle: r.lastAt != null ? _formatRelative(r.lastAt!) : '',
            isSelected: selected.contains(r.user.id),
            onTap: () => onToggle(r.user.id),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DANH BẠ tab
// ─────────────────────────────────────────────────────────────────────────────

class _FriendsTab extends StatelessWidget {
  final List<ApiUserModel> friends;
  final String? error;
  final bool loading;
  final Set<String> selected;
  final void Function(String) onToggle;
  final Future<void> Function() onRefresh;

  const _FriendsTab({
    required this.friends,
    required this.error,
    required this.loading,
    required this.selected,
    required this.onToggle,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (error != null && friends.isEmpty) {
      return _ErrorView(message: error!, onRetry: onRefresh);
    }
    if (friends.isEmpty) {
      return const _EmptyView(message: 'Chưa có bạn bè nào');
    }

    // Nhóm theo chữ cái đầu
    final grouped = <String, List<ApiUserModel>>{};
    for (final f in friends) {
      final key = _firstChar(f.fullName);
      grouped.putIfAbsent(key, () => []).add(f);
    }
    final keys = grouped.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.primary,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: keys.fold<int>(
            0, (sum, k) => sum + 1 + (grouped[k]?.length ?? 0)),
        itemBuilder: (_, index) {
          int offset = 0;
          for (final k in keys) {
            final items = grouped[k]!;
            if (index == offset) {
              return _AlphaHeader(letter: k);
            }
            offset++;
            if (index < offset + items.length) {
              final u = items[index - offset];
              return _ContactTile(
                user: u,
                subtitle: u.phone,
                isSelected: selected.contains(u.id),
                onTap: () => onToggle(u.id),
              );
            }
            offset += items.length;
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  String _firstChar(String name) {
    if (name.isEmpty) return '#';
    final c = name.trim().toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(c[0]) ? c[0] : '#';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Contact Tile
// ─────────────────────────────────────────────────────────────────────────────

class _ContactTile extends StatelessWidget {
  final ApiUserModel user;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _ContactTile({
    required this.user,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: AppColors.bgCard,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _Avatar(url: user.avatar, name: user.fullName, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.fullName.isEmpty ? 'Người dùng' : user.fullName,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Selection circle
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.border,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded,
                      size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom create bar
// ─────────────────────────────────────────────────────────────────────────────

class _BottomCreateBar extends StatelessWidget {
  final int count;
  final bool creating;
  final VoidCallback onTap;

  const _BottomCreateBar({
    required this.count,
    required this.creating,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: creating ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            elevation: 0,
          ),
          child: creating
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  'Tạo nhóm ($count)',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _AlphaHeader extends StatelessWidget {
  final String letter;
  const _AlphaHeader({required this.letter});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgDark,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Text(
        letter,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String url;
  final String name;
  final double size;

  const _Avatar({required this.url, required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    if (url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          webSafeImageUrl(url),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    final colors = [
      const Color(0xFF2E7D32),
      const Color(0xFF26A69A),
      const Color(0xFFEF5350),
      const Color(0xFFAB47BC),
      const Color(0xFF66BB6A),
      const Color(0xFFFF7043),
    ];
    final idx = name.isEmpty ? 0 : name.codeUnitAt(0) % colors.length;
    final letter = name.isEmpty ? '?' : name[0].toUpperCase();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: colors[idx], shape: BoxShape.circle),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: size * 0.4,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            message,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            child: const Text(
              'Thử lại',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final String message;
  const _EmptyView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color: AppColors.textHint,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

String _formatRelative(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Vừa xong';
  if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
  if (diff.inHours < 24) return '${diff.inHours} giờ trước';
  if (diff.inDays == 1) return '1 ngày trước';
  if (diff.inDays < 7) return '${diff.inDays} ngày trước';
  return '${dt.day}/${dt.month}/${dt.year}';
}
