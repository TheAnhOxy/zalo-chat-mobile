import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../controllers/chat_controller.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/image_utils.dart';
import '../../data/models/models.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/contacts_api_service.dart';
import '../../widgets/common/common_widgets.dart';
import '../contacts/create_group_screen.dart';
import 'group_chat_backgrounds.dart';
import 'group_members_screen.dart';
import 'group_media_screen.dart';
import 'group_message_search_screen.dart';
import '../chat/pinned_messages_screen.dart';

class ChatOptionsScreen extends StatefulWidget {
  final ApiGroupModel group;
  final bool isGroup;
  final String? peerName;
  final ChatController? chatController;
  final Map<String, String>? memberNames;
  final Map<String, String>? memberAvatars;

  const ChatOptionsScreen({
    super.key,
    required this.group,
    this.isGroup = true,
    this.peerName,
    this.chatController,
    this.memberNames,
    this.memberAvatars,
  });

  @override
  State<ChatOptionsScreen> createState() => _ChatOptionsScreenState();
}

class _ChatOptionsScreenState extends State<ChatOptionsScreen> {
  bool _isPinned = false;
  bool _isMuted = false;
  DateTime? _muteUntil;

  late ApiGroupModel _group;

  bool get _isAdmin {
    final myId = authService.userId ?? '';
    return _group.members.any((m) => m.userId == myId && m.role == 'ADMIN');
  }

  /// Chỉ còn một admin và đó là mình — không cho rời (cần thêm QTV khác trước).
  bool get _isSoleAdmin {
    final myId = authService.userId ?? '';
    final adminCount = _group.members.where((m) => m.role == 'ADMIN').length;
    if (adminCount != 1) return false;
    return _group.members.any((m) => m.userId == myId && m.role == 'ADMIN');
  }

  String get _mutePrefKey => 'group_mute_${_group.id}';
  String get _muteUntilPrefKey => 'group_mute_until_${_group.id}';
  String get _bgPrefKey => 'group_chat_bg_${_group.id}';
  String get _bgCustomPrefKey => 'group_chat_bg_custom_${_group.id}';
  String get _bgOverridePrefKey => 'group_chat_bg_override_${_group.id}';
  String get _descPrefKey => 'group_description_${_group.id}';
  String get _pinPrefKey =>
      'conv_pin_${authService.userId ?? 'me'}_${_group.id}';

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _loadMutePref();
    _loadDescriptionPref();
    _loadPinPref();
  }

  void _loadPinPref() {
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() => _isPinned = p.getBool(_pinPrefKey) ?? false);
    });
  }

  Future<void> _setPinned(bool v) async {
    setState(() => _isPinned = v);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_pinPrefKey, v);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(v ? 'Đã ghim trò chuyện' : 'Đã bỏ ghim trò chuyện'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _loadMutePref() {
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      final isMuted = p.getBool(_mutePrefKey) ?? false;
      final untilMs = p.getInt(_muteUntilPrefKey);
      final until = untilMs != null
          ? DateTime.fromMillisecondsSinceEpoch(untilMs)
          : null;

      // Nếu đã hết hạn thì tự bật lại
      if (until != null && DateTime.now().isAfter(until)) {
        p.remove(_muteUntilPrefKey);
        p.setBool(_mutePrefKey, false);
        setState(() {
          _isMuted = false;
          _muteUntil = null;
        });
        return;
      }

      setState(() {
        _isMuted = isMuted;
        _muteUntil = until;
      });
    });
  }

  void _loadDescriptionPref() {
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      final local = p.getString(_descPrefKey);
      if (local == null) return;

      final current = _group.description?.trim() ?? '';
      final parsed = local.trim();
      // Ưu tiên backend/khởi tạo group; chỉ dùng local khi đang rỗng.
      if (current.isNotEmpty) return;
      if (parsed.isEmpty) return;

      setState(() {
        _group = ApiGroupModel(
          id: _group.id,
          name: _group.name,
          avatar: _group.avatar,
          members: _group.members,
          description: parsed,
          lastMessageContent: _group.lastMessageContent,
          lastMessageAt: _group.lastMessageAt,
          updatedAt: _group.updatedAt,
        );
      });
    });
  }

  Future<void> _persistMute(bool value, {DateTime? until}) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_mutePrefKey, value);
    if (!value) {
      await p.remove(_muteUntilPrefKey);
      return;
    }
    if (until != null) {
      await p.setInt(_muteUntilPrefKey, until.millisecondsSinceEpoch);
    } else {
      await p.remove(_muteUntilPrefKey);
    }
  }

  void _openSearchMessages() {
    final uid = authService.userId;
    if (uid == null) return;
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            GroupMessageSearchScreen(conversationId: _group.id, userId: uid),
      ),
    );
  }

  Future<void> _openAddMembers() async {
    if (!_isAdmin) {
      _showLeaveSnack(
        'Chỉ quản trị viên mới thêm được thành viên',
        isError: true,
      );
      return;
    }
    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(builder: (_) => GroupMembersScreen(group: _group)),
    );
    if (!mounted) return;
    if (result == true) {
      Navigator.pop(context, true);
    } else if (result is ApiGroupModel) {
      setState(() => _group = result);
    }
  }

  String get _peerDisplayName {
    final name = widget.peerName?.trim() ?? '';
    return name.isEmpty ? 'người này' : name;
  }

  void _openPeerProfile() {
    _showLeaveSnack('Trang cá nhân sẽ được bổ sung ở bản cập nhật tới');
  }

  Future<void> _createGroupWithPeer() async {
    final created = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
    );
    if (!mounted) return;
    if (created is ApiGroupModel) {
      Navigator.pop(context, created);
    }
  }

  void _addPeerToGroup() {
    _showLeaveSnack('Tính năng thêm thành viên vào nhóm sẽ sớm ra mắt');
  }

  Future<void> _showWallpaperPicker() async {
    final prefs = await SharedPreferences.getInstance();
    final current = (prefs.getInt(_bgPrefKey) ?? 0).clamp(
      0,
      GroupChatBackgrounds.count - 1,
    );
    final currentCustom = prefs.getString(_bgCustomPrefKey);

    if (!mounted) return;
    final result =
        await Navigator.push<
          ({int? index, String? customBase64, bool applyForAll})
        >(
          context,
          MaterialPageRoute(
            builder: (_) => _GroupWallpaperPickerScreen(
              initialIndex: current,
              initialCustomBase64: currentCustom,
            ),
          ),
        );
    if (result == null) return;

    if (result.customBase64 != null) {
      await prefs.setString(_bgCustomPrefKey, result.customBase64!);
    } else {
      await prefs.remove(_bgCustomPrefKey);
    }
    if (result.index != null) {
      await prefs.setInt(_bgPrefKey, result.index!);
    }

    // Nếu tick "toàn nhóm" → không override cá nhân; nếu không tick → override.
    await prefs.setBool(_bgOverridePrefKey, !result.applyForAll);

    if (!mounted) return;
    if (result.applyForAll) {
      // Sync lên backend để tất cả thành viên thấy.
      final isCustom = result.customBase64 != null;
      if (isCustom) {
        // Giới hạn để tránh payload quá lớn (demo).
        if ((result.customBase64?.length ?? 0) > 350000) {
          _showLeaveSnack(
            'Ảnh nền quá lớn để áp dụng cho tất cả thành viên. Hãy chọn ảnh nhẹ hơn.',
            isError: true,
          );
          return;
        }
      }

      final type = isCustom ? 'CUSTOM' : 'PRESET';
      final idx = isCustom ? 0 : (result.index ?? current);
      final syncRes = await ContactsApiService.instance
          .updateGroupChatBackground(
            conversationId: _group.id,
            type: type,
            index: idx,
            customBase64: isCustom ? result.customBase64 : null,
          );
      if (!mounted) return;
      if (!syncRes.isSuccess) {
        _showLeaveSnack(
          syncRes.error ?? 'Không thể áp dụng hình nền cho tất cả thành viên',
          isError: true,
        );
        return;
      }

      _showLeaveSnack('Đã áp dụng hình nền cho tất cả thành viên');
      return;
    }
    if (result.customBase64 != null) {
      _showLeaveSnack('Đã đặt nền: Ảnh từ thiết bị');
      return;
    }
    final idx = result.index ?? current;
    _showLeaveSnack('Đã đặt nền: ${GroupChatBackgrounds.labels[idx]}');
  }

  Future<void> _onMuteTap() async {
    // Nếu đang mute → bấm là bật lại luôn
    if (_isMuted) {
      setState(() {
        _isMuted = false;
        _muteUntil = null;
      });
      await _persistMute(false);
      if (!mounted) return;
      _showLeaveSnack('Đã bật thông báo cho nhóm này');
      return;
    }

    // Nếu chưa mute → mở sheet chọn thời gian (giống UI ảnh)
    final selected = await _showMuteSheet();
    if (selected == null) return;

    final now = DateTime.now();
    DateTime? until;
    String msg = 'Đã tắt thông báo cho nhóm này';

    switch (selected) {
      case _MuteOption.oneHour:
        until = now.add(const Duration(hours: 1));
        msg = 'Đã tắt thông báo trong 1 giờ';
        break;
      case _MuteOption.fourHours:
        until = now.add(const Duration(hours: 4));
        msg = 'Đã tắt thông báo trong 4 giờ';
        break;
      case _MuteOption.until8am:
        final eight = DateTime(now.year, now.month, now.day, 8);
        // Nếu đã qua 8h sáng hôm nay → lấy 8h sáng ngày mai
        until = now.isBefore(eight)
            ? eight
            : eight.add(const Duration(days: 1));
        msg = 'Đã tắt thông báo đến 8 giờ sáng';
        break;
      case _MuteOption.untilTurnedOn:
        until = null;
        msg = 'Đã tắt thông báo cho đến khi được mở lại';
        break;
    }

    setState(() {
      _isMuted = true;
      _muteUntil = until;
    });
    await _persistMute(true, until: until);
    if (!mounted) return;
    _showLeaveSnack(msg);
  }

  String _muteLabelForAction() {
    if (!_isMuted) return 'Tắt\nthông báo';
    if (_muteUntil == null) return 'Bật\nthông báo';
    return 'Bật\nthông báo';
  }

  Future<_MuteOption?> _showMuteSheet() async {
    return showModalBottomSheet<_MuteOption>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) {
        Widget item(String label, _MuteOption opt) {
          return InkWell(
            onTap: () => Navigator.pop(ctx, opt),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  color: Color(0xFF222222),
                ),
              ),
            ),
          );
        }

        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6E6E6),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: Row(
                  children: const [
                    Expanded(
                      child: Text(
                        'Tắt thông báo tin nhắn',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF222222),
                        ),
                      ),
                    ),
                    // Bỏ icon cài đặt theo yêu cầu
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFEEEEEE)),
              item('Trong 1 giờ', _MuteOption.oneHour),
              const Divider(height: 1, color: Color(0xFFEEEEEE)),
              item('Trong 4 giờ', _MuteOption.fourHours),
              const Divider(height: 1, color: Color(0xFFEEEEEE)),
              item('Đến 8 giờ sáng', _MuteOption.until8am),
              const Divider(height: 1, color: Color(0xFFEEEEEE)),
              item('Cho đến khi được mở lại', _MuteOption.untilTurnedOn),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _changeGroupAvatar() async {
    if (!_isAdmin) {
      _showLeaveSnack('Chỉ quản trị viên mới đổi được ảnh nhóm', isError: true);
      return;
    }

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
              leading: const Icon(
                Icons.camera_alt_outlined,
                color: AppColors.primary,
              ),
              title: const Text(
                'Chụp ảnh',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.textPrimary,
                ),
              ),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: AppColors.primary,
              ),
              title: const Text(
                'Chọn từ thư viện',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.textPrimary,
                ),
              ),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    try {
      final bytes = await file.readAsBytes();
      final ext = file.name.split('.').last.toLowerCase();
      // Đồng bộ với create_group_screen (upload S3 qua conversations/avatar/upload)
      const mimeMap = {
        'png': 'image/png',
        'gif': 'image/gif',
        'webp': 'image/webp',
        'bmp': 'image/bmp',
        'tiff': 'image/tiff',
        'tif': 'image/tiff',
        'svg': 'image/svg+xml',
        'ico': 'image/x-icon',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
      };
      final mime = mimeMap[ext] ?? 'image/jpeg';
      final url = await ContactsApiService.instance.uploadGroupAvatar(
        bytes: bytes,
        fileName: file.name,
        mimeType: mime,
      );
      final result = await ContactsApiService.instance.updateConversationAvatar(
        conversationId: _group.id,
        avatarUrl: url,
      );
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (!mounted) return;
      if (result.isSuccess) {
        setState(() {
          _group = ApiGroupModel(
            id: _group.id,
            name: _group.name,
            avatar: url,
            members: _group.members,
            description: _group.description,
            lastMessageContent: _group.lastMessageContent,
            lastMessageAt: _group.lastMessageAt,
            updatedAt: _group.updatedAt,
          );
        });
        _showLeaveSnack('Đã cập nhật ảnh nhóm');
      } else {
        _showLeaveSnack(
          result.error ?? 'Không thể cập nhật ảnh',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        _showLeaveSnack('Upload thất bại: $e', isError: true);
      }
    }
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
            fontFamily: 'Inter',
            color: AppColors.textPrimary,
          ),
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
            child: const Text(
              'Huỷ',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                setState(
                  () => _group = ApiGroupModel(
                    id: _group.id,
                    name: name,
                    avatar: _group.avatar,
                    members: _group.members,
                    description: _group.description,
                    lastMessageContent: _group.lastMessageContent,
                    lastMessageAt: _group.lastMessageAt,
                    updatedAt: _group.updatedAt,
                  ),
                );
              }
              Navigator.pop(context);
            },
            child: const Text(
              'Lưu',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
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
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Bạn có chắc muốn rời khỏi nhóm "${_group.name}"?',
          style: const TextStyle(
            fontFamily: 'Inter',
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Huỷ',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Rời nhóm',
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
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

  Future<void> _confirmDissolveGroup() async {
    if (!_isAdmin) {
      _showLeaveSnack('Chỉ quản trị viên mới có thể giải tán nhóm', isError: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text(
          'Giải tán nhóm',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Thao tác này sẽ xóa nhóm "${_group.name}" cho tất cả thành viên. Bạn có chắc chắn muốn tiếp tục?',
          style: const TextStyle(
            fontFamily: 'Inter',
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Huỷ',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Giải tán',
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _showLeaveLoading();
    final res = await ContactsApiService.instance.dissolveGroup(
      conversationId: _group.id,
    );
    if (mounted) Navigator.of(context, rootNavigator: true).pop();

    if (!mounted) return;
    if (res.isSuccess) {
      // Trả về true để màn trước refresh / quay về danh sách chat.
      Navigator.pop(context, true);
    } else {
      _showLeaveSnack(res.error ?? 'Không thể giải tán nhóm', isError: true);
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
            color: AppColors.textPrimary,
          ),
        ),
        content: const Text(
          'Toàn bộ tin nhắn sẽ bị xoá khỏi thiết bị của bạn. Thao tác này không thể hoàn tác.',
          style: TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Huỷ',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final myId = authService.userId ?? '';
              if (myId.isEmpty) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Chưa đăng nhập'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Đang xoá lịch sử...'),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 1),
                ),
              );

              final ok = await apiService.deleteConversationHistoryForMe(
                _group.id,
                myId,
              );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok ? 'Đã xoá lịch sử trò chuyện' : 'Xoá thất bại',
                  ),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: const Text(
              'Xoá',
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openStorageSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _ConversationStorageSheet(conversationId: _group.id),
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
          _ChatOptionsSection(children: [
            _buildDescriptionTile(),
            _buildDivider(),
            _buildMediaTile(),
            _buildDivider(),
            _buildNavTile(
              icon: Icons.push_pin_outlined,
              label: 'Tin nhắn đã ghim',
              onTap: () async {
                if (widget.chatController != null) {
                  final msgId = await Navigator.push<String?>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PinnedMessagesScreen(
                        controller: widget.chatController!,
                        chatTitle: _group.name.isEmpty ? 'Nhóm' : _group.name,
                        chatAvatar: _group.avatar,
                        memberNames: widget.memberNames ?? const {},
                        memberAvatars: widget.memberAvatars ?? const {},
                      ),
                    ),
                  );
                  if (msgId != null && mounted) {
                    Navigator.pop(context, msgId);
                  }
                }
              },
            ),
          ]),

          const SizedBox(height: 8),

          // ── Section 2: Thành viên / Link / Ghim CV / Ẩn / Cá nhân
          _ChatOptionsSection(
            children: [
              if (widget.isGroup) ...[
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
              ] else ...[
                _buildNavTile(
                  icon: Icons.group_add_outlined,
                  label: 'Tạo nhóm với $_peerDisplayName',
                  onTap: _createGroupWithPeer,
                ),
                _buildDivider(),
                _buildNavTile(
                  icon: Icons.group_add_outlined,
                  label: 'Thêm $_peerDisplayName vào nhóm',
                  onTap: _addPeerToGroup,
                ),
                _buildDivider(),
              ],
              _buildToggleTile(
                icon: Icons.push_pin_outlined,
                label: 'Ghim trò chuyện',
                value: _isPinned,
                onChanged: (v) => _setPinned(v),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ── Section 3: Báo xấu / Dung lượng
          _ChatOptionsSection(children: [
            _buildNavTile(
              icon: Icons.storage_outlined,
              label: 'Dung lượng trò chuyện',
              onTap: _openStorageSheet,
            ),
          ]),

          const SizedBox(height: 8),

          // ── Section 4: Xoá lịch sử / Rời nhóm (đỏ)
          _ChatOptionsSection(children: [
            _buildNavTile(
              icon: Icons.delete_outline_rounded,
              label: 'Xóa lịch sử trò chuyện',
              labelColor: AppColors.error,
              iconColor: AppColors.error,
              onTap: _confirmDeleteHistory,
            ),
            if (widget.isGroup) ...[
              _buildDivider(),
              _buildNavTile(
                icon: Icons.logout_rounded,
                label: 'Rời nhóm',
                labelColor: AppColors.error,
                iconColor: AppColors.error,
                onTap: _confirmLeave,
              ),
              if (_isAdmin) ...[
                _buildDivider(),
                _buildNavTile(
                  icon: Icons.delete_forever_rounded,
                  label: 'Giải tán nhóm',
                  labelColor: AppColors.error,
                  iconColor: AppColors.error,
                  onTap: _confirmDissolveGroup,
                ),
              ],
            ],
          ]),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────
  Widget _buildHeader() {
    return _ChatOptionsHeader(
      title: _group.name.isEmpty ? 'Nhóm' : _group.name,
      avatarUrl: _group.avatar,
      canEdit: _isAdmin && widget.isGroup,
      onAvatarTap: _changeGroupAvatar,
      onTitleTap: _showRenameDialog,
      defaultAvatarBuilder: _defaultGroupAvatar,
    );
  }

  // ── 4 nút hành động ──────────────────────────────────────────
  Widget _buildActionRow() {
    return _ChatOptionsActionRow(
      isGroup: widget.isGroup,
      isMuted: _isMuted,
      muteLabel: _muteLabelForAction(),
      onSearchTap: _openSearchMessages,
      onSecondaryActionTap: widget.isGroup ? _openAddMembers : _openPeerProfile,
      onWallpaperTap: _showWallpaperPicker,
      onMuteTap: _onMuteTap,
    );
  }

  // ── Mô tả nhóm ───────────────────────────────────────────────
  Widget _buildDescriptionTile() {
    final desc = _group.description?.trim() ?? '';
    final title = desc.isEmpty ? 'Thêm mô tả nhóm' : 'Mô tả nhóm';
    return InkWell(
      onTap: () => _showGroupDescriptionDialog(editable: _isAdmin),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    desc.isEmpty ? 'Chưa có mô tả nhóm' : desc,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: desc.isEmpty
                          ? AppColors.textHint
                          : AppColors.primary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (_isAdmin)
              const Icon(
                Icons.edit_outlined,
                size: 18,
                color: AppColors.textHint,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showGroupDescriptionDialog({required bool editable}) async {
    final initial = _group.description?.trim() ?? '';
    final ctrl = TextEditingController(text: initial);

    await showDialog<void>(
      context: context,
      barrierDismissible: !editable,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text(
          editable ? 'Mô tả nhóm' : 'Mô tả nhóm',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: editable,
          readOnly: !editable,
          minLines: 3,
          maxLines: 6,
          style: const TextStyle(
            fontFamily: 'Inter',
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: 'Nhập mô tả cho nhóm',
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
            child: Text(
              editable ? 'Huỷ' : 'Đóng',
              style: TextStyle(
                color: editable ? AppColors.textSecondary : AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (editable)
            TextButton(
              onPressed: () async {
                final newDesc = ctrl.text.trim();
                Navigator.pop(context);
                await _saveGroupDescription(newDesc);
              },
              child: Text(
                'Lưu',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );

    ctrl.dispose();
  }

  Future<void> _saveGroupDescription(String newDesc) async {
    final desc = newDesc.trim();

    // Cập nhật local trước để UI phản hồi ngay.
    if (!mounted) return;
    setState(() {
      _group = ApiGroupModel(
        id: _group.id,
        name: _group.name,
        avatar: _group.avatar,
        members: _group.members,
        description: desc,
        lastMessageContent: _group.lastMessageContent,
        lastMessageAt: _group.lastMessageAt,
        updatedAt: _group.updatedAt,
      );
    });

    final prefs = await SharedPreferences.getInstance();
    if (desc.isEmpty) {
      await prefs.remove(_descPrefKey);
    } else {
      await prefs.setString(_descPrefKey, desc);
    }

    _showLeaveLoading();
    final result = await ContactsApiService.instance.updateGroupDescription(
      conversationId: _group.id,
      description: desc,
    );

    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    if (!mounted) return;

    if (!result.isSuccess) {
      _showLeaveSnack(
        result.error ?? 'Không thể cập nhật mô tả nhóm',
        isError: true,
      );
      return;
    }

    _showLeaveSnack('Đã cập nhật mô tả nhóm');
  }

  // ── Ảnh, file, link ──────────────────────────────────────────
  Widget _buildMediaTile() {
    return InkWell(
      onTap: () {
        Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => GroupMediaScreen(
              conversationId: _group.id,
              title: _group.name.isEmpty ? 'Ảnh, file, link' : _group.name,
            ),
          ),
        );
      },
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
                  child: const Icon(
                    Icons.folder_outlined,
                    size: 18,
                    color: Color(0xFFFF9800),
                  ),
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
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textHint,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Preview thumbnails placeholder
            SizedBox(
              height: 60,
              child: Row(
                children: [
                  _mediaThumbnail(
                    Icons.image_outlined,
                    const Color(0xFFE8F5E9),
                  ),
                  const SizedBox(width: 6),
                  _mediaThumbnail(Icons.code_rounded, const Color(0xFFE8F5E9)),
                  const SizedBox(width: 6),
                  _mediaThumbnail(Icons.link_rounded, const Color(0xFFF3E5F5)),
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
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
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
    final linkPreview = 'Link mời vào nhóm';
    return InkWell(
      onTap: _openInviteLinkSheet,
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
              child: const Icon(
                Icons.link_rounded,
                size: 18,
                color: AppColors.primary,
              ),
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
                    linkPreview,
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
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openInviteLinkSheet() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      showDragHandle: true,
      builder: (_) {
        return _InviteLinkSheet(conversationId: _group.id);
      },
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
              description: _group.description,
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
            if (trailing != null) ...[trailing, const SizedBox(width: 4)],
            if (trailing == null && labelColor == null)
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.textHint,
              ),
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
      child: Icon(
        Icons.group,
        color: AppColors.textSecondary,
        size: size * 0.5,
      ),
    );
  }
}

class _GroupWallpaperPickerScreen extends StatefulWidget {
  final int initialIndex;
  final String? initialCustomBase64;

  const _GroupWallpaperPickerScreen({
    required this.initialIndex,
    required this.initialCustomBase64,
  });

  @override
  State<_GroupWallpaperPickerScreen> createState() =>
      _GroupWallpaperPickerScreenState();
}

class _GroupWallpaperPickerScreenState
    extends State<_GroupWallpaperPickerScreen> {
  late int _selectedIndex;
  bool _applyForAllMembers = true;
  String? _customBase64;
  bool _selectingCustom = false;
  bool _pickingImage = false;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _customBase64 = widget.initialCustomBase64;
    _selectingCustom = _customBase64 != null;
  }

  Future<void> _pickCustomWallpaper(ImageSource source) async {
    if (_pickingImage) return;
    setState(() => _pickingImage = true);
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1920,
        imageQuality: 80,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);
      if (!mounted) return;
      setState(() {
        _customBase64 = b64;
        _selectingCustom = true;
      });
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _openCameraTile() async {
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
              leading: const Icon(
                Icons.camera_alt_outlined,
                color: AppColors.primary,
              ),
              title: const Text(
                'Chụp ảnh',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.textPrimary,
                ),
              ),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: AppColors.primary,
              ),
              title: const Text(
                'Chọn từ thư viện',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.textPrimary,
                ),
              ),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            if (_customBase64 != null) ...[
              const Divider(height: 1, color: AppColors.divider),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: AppColors.error,
                ),
                title: const Text(
                  'Xóa ảnh nền đã chọn',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: AppColors.textPrimary,
                  ),
                ),
                onTap: () => Navigator.pop(context, null),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted) return;
    if (source == null) {
      if (_customBase64 != null) {
        setState(() {
          _customBase64 = null;
          _selectingCustom = false;
        });
      }
      return;
    }
    await _pickCustomWallpaper(source);
  }

  Widget _previewTile({
    required Widget child,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned.fill(child: child),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: active ? AppColors.primary : const Color(0x33000000),
                    width: active ? 2 : 1,
                  ),
                ),
              ),
            ),
            if (active)
              const Positioned(
                left: 6,
                bottom: 6,
                child: CircleAvatar(
                  radius: 11,
                  backgroundColor: AppColors.primary,
                  child: Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _miniChatPreview({LinearGradient? gradient, ImageProvider? image}) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        image: image != null
            ? DecorationImage(image: image, fit: BoxFit.cover)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeImage = _selectingCustom && _customBase64 != null
        ? MemoryImage(base64Decode(_customBase64!))
        : null;
    final activeGradient = activeImage == null
        ? GroupChatBackgrounds.gradientAt(_selectedIndex)
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFFDDE3EE),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Đổi hình nền',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, (
              index: _selectingCustom ? null : _selectedIndex,
              customBase64: _selectingCustom ? _customBase64 : null,
              applyForAll: _applyForAllMembers,
            )),
            child: const Text(
              'XONG',
              style: TextStyle(
                fontFamily: 'Inter',
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: activeGradient,
                image: activeImage != null
                    ? DecorationImage(image: activeImage, fit: BoxFit.cover)
                    : null,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 78,
            child: const SizedBox.shrink(),
          ),
          Positioned(
            left: 8,
            right: 8,
            top: 10,
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 5,
                            crossAxisSpacing: 3,
                            mainAxisSpacing: 3,
                            childAspectRatio: 1,
                          ),
                      itemCount: GroupChatBackgrounds.count + 1,
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          final active = _selectingCustom;
                          return _previewTile(
                            active: active,
                            onTap: () {
                              if (_customBase64 != null) {
                                setState(() => _selectingCustom = true);
                              } else {
                                _openCameraTile();
                              }
                            },
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: _customBase64 != null
                                      ? _miniChatPreview(
                                          image: MemoryImage(
                                            base64Decode(_customBase64!),
                                          ),
                                        )
                                      : Container(
                                          color: const Color(0xFF1EA5FF),
                                          child: const Icon(
                                            Icons.camera_alt_rounded,
                                            color: Colors.white,
                                            size: 22,
                                          ),
                                        ),
                                ),
                                Positioned(
                                  right: 2,
                                  top: 2,
                                  child: GestureDetector(
                                    onTap: _openCameraTile,
                                    child: Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.95),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _customBase64 == null
                                            ? Icons.add_rounded
                                            : Icons.edit_outlined,
                                        size: 12,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final presetIndex = i - 1;
                        final active =
                            !_selectingCustom && presetIndex == _selectedIndex;
                        return _previewTile(
                          active: active,
                          onTap: () => setState(() {
                            _selectedIndex = presetIndex;
                            _selectingCustom = false;
                          }),
                          child: _miniChatPreview(
                            gradient: GroupChatBackgrounds.gradientAt(
                              presetIndex,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Checkbox(
                          value: _applyForAllMembers,
                          activeColor: AppColors.primary,
                          onChanged: (v) =>
                              setState(() => _applyForAllMembers = v ?? false),
                        ),
                        const Expanded(
                          child: Text(
                            'Đổi hình nền cho tất cả thành viên',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _groupFooterPreview(),
          ),
        ],
      ),
    );
  }

  Widget _groupFooterPreview() {
    const footerBg = AppColors.bgCard;
    const inputBg = AppColors.bgInput;
    const actionColor = AppColors.primary;

    Widget actionIcon(IconData icon) {
      return Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: actionColor, size: 24),
      );
    }

    return Container(
      color: footerBg,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Row(
        children: [
          actionIcon(Icons.add_circle),
          actionIcon(Icons.camera_alt_rounded),
          actionIcon(Icons.image_rounded),
          actionIcon(Icons.mic_none_rounded),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: inputBg,
                borderRadius: BorderRadius.circular(22),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Nhắn tin',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        color: AppColors.textHint,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(
                    Icons.sentiment_satisfied_alt_outlined,
                    color: actionColor,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          actionIcon(Icons.thumb_up),
        ],
      ),
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

// ── Invite link sheet (top-level) ─────────────────────────────────────────────
class _InviteLinkSheet extends StatefulWidget {
  final String conversationId;
  const _InviteLinkSheet({required this.conversationId});

  @override
  State<_InviteLinkSheet> createState() => _InviteLinkSheetState();
}

class _InviteLinkSheetState extends State<_InviteLinkSheet> {
  bool _loading = true;
  bool _enabled = true;
  String _link = '';
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await ContactsApiService.instance.getGroupInviteLink(
      widget.conversationId,
    );
    if (!mounted) return;
    if (!res.isSuccess) {
      setState(() {
        _loading = false;
        _link = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.error ?? 'Không lấy được link nhóm'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final data = res.data ?? const <String, dynamic>{};
    setState(() {
      _enabled = (data['enabled'] as bool?) ?? true;
      _link = (data['link'] ?? '').toString();
      _loading = false;
    });
  }

  Future<void> _toggle(bool v) async {
    setState(() {
      _enabled = v;
      _working = true;
    });
    final res = await ContactsApiService.instance.setGroupInviteLinkEnabled(
      conversationId: widget.conversationId,
      enabled: v,
    );
    if (!mounted) return;
    setState(() => _working = false);
    if (!res.isSuccess) {
      setState(() => _enabled = !v);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.error ?? 'Không cập nhật được'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _copy() async {
    if (_link.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã sao chép link nhóm'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _regenerate() async {
    setState(() => _working = true);
    final res = await ContactsApiService.instance.regenerateGroupInviteLink(
      widget.conversationId,
    );
    if (!mounted) return;
    setState(() => _working = false);
    if (!res.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.error ?? 'Không tạo được link mới'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final data = res.data ?? const <String, dynamic>{};
    setState(() {
      _enabled = (data['enabled'] as bool?) ?? true;
      _link = (data['link'] ?? '').toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Link nhóm',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Cho phép mời bằng link',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Switch(
                value: _enabled,
                onChanged: _working ? null : _toggle,
                activeColor: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bgInput,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Text(
                _enabled
                    ? (_link.isEmpty ? 'Chưa có link' : _link)
                    : 'Link mời đã tắt',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (!_enabled || _link.isEmpty || _working)
                        ? null
                        : _copy,
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: const Text('Sao chép'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      textStyle: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _working ? null : _regenerate,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Tạo mới'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      textStyle: const TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Storage sheet ─────────────────────────────────────────────────────────────
class _ConversationStorageSheet extends StatefulWidget {
  final String conversationId;
  const _ConversationStorageSheet({required this.conversationId});

  @override
  State<_ConversationStorageSheet> createState() =>
      _ConversationStorageSheetState();
}

class _ConversationStorageSheetState extends State<_ConversationStorageSheet> {
  bool _loading = true;
  int _count = 0;
  int _bytesText = 0;
  int _bytesMedia = 0;
  int _bytesVideo = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fmtBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    double v = bytes.toDouble();
    int i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
  }

  Future<void> _load() async {
    final myId = authService.userId ?? '';
    if (myId.isEmpty) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

    setState(() => _loading = true);
    // Lấy tối đa 200 tin gần nhất để tính nhanh (có thể nâng cấp phân trang sau)
    final msgs = await apiService.getMessages(widget.conversationId, myId);
    int textBytes = 0;
    int mediaBytes = 0;
    int videoBytes = 0;

    for (final m in msgs) {
      final fs = m.metadata?.fileSize;
      if (fs != null && fs > 0) {
        mediaBytes += fs;
        if (m.type == 'VIDEO') {
          videoBytes += fs;
        }
      } else {
        textBytes += utf8.encode(m.content).length;
      }
    }

    if (!mounted) return;
    setState(() {
      _count = msgs.length;
      _bytesText = textBytes;
      _bytesMedia = mediaBytes;
      _bytesVideo = videoBytes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = _bytesText + _bytesMedia;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dung lượng trò chuyện',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bgInput,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tổng: ${_fmtBytes(total)}',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Đính kèm: ${_fmtBytes(_bytesMedia)}',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Video: ${_fmtBytes(_bytesVideo)}',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Văn bản: ${_fmtBytes(_bytesText)}',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Số tin đã tính: $_count',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Tính lại'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GroupMembersSheetBodyState extends State<_GroupMembersSheetBody> {
  late List<ApiGroupMember> _members;
  Map<String, UserModel> _userMap = {};
  bool _loading = true;
  String? _error;

  int get _adminCount => _members.where((m) => m.role == 'ADMIN').length;

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
      await Future.wait(
        ids.map((id) async {
          final user = await apiService.getUserById(id);
          if (user != null) map[id] = user;
        }),
      );
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
              style: TextStyle(
                fontFamily: 'Inter',
                color: AppColors.textSecondary,
              ),
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
            .map(
              (m) => m.userId == member.userId
                  ? ApiGroupMember(userId: m.userId, role: newRole)
                  : m,
            )
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
        _members = _members.where((m) => m.userId != member.userId).toList();
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
                      final canTap =
                          widget.canManage &&
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
                                  horizontal: 8,
                                  vertical: 3,
                                ),
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

class _ChatOptionsHeader extends StatelessWidget {
  final String title;
  final String avatarUrl;
  final bool canEdit;
  final VoidCallback onAvatarTap;
  final VoidCallback onTitleTap;
  final Widget Function(double size) defaultAvatarBuilder;

  const _ChatOptionsHeader({
    required this.title,
    required this.avatarUrl,
    required this.canEdit,
    required this.onAvatarTap,
    required this.onTitleTap,
    required this.defaultAvatarBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: canEdit ? onAvatarTap : null,
              borderRadius: BorderRadius.circular(48),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  avatarUrl.isNotEmpty
                      ? ClipOval(
                          child: Image.network(
                            webSafeImageUrl(avatarUrl),
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                defaultAvatarBuilder(80),
                          ),
                        )
                      : defaultAvatarBuilder(80),
                  if (canEdit)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Material(
                        color: AppColors.bgDark,
                        shape: const CircleBorder(
                          side: BorderSide(color: AppColors.bgCard, width: 2),
                        ),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onAvatarTap,
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.camera_alt_outlined,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: canEdit ? onTitleTap : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (canEdit) ...[
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatOptionsActionRow extends StatelessWidget {
  final bool isGroup;
  final bool isMuted;
  final String muteLabel;
  final VoidCallback onSearchTap;
  final VoidCallback onSecondaryActionTap;
  final VoidCallback onWallpaperTap;
  final VoidCallback onMuteTap;

  const _ChatOptionsActionRow({
    required this.isGroup,
    required this.isMuted,
    required this.muteLabel,
    required this.onSearchTap,
    required this.onSecondaryActionTap,
    required this.onWallpaperTap,
    required this.onMuteTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(
            icon: Icons.search_rounded,
            label: 'Tìm\ntin nhắn',
            onTap: onSearchTap,
          ),
          _ActionButton(
            icon: isGroup ? Icons.person_add_alt_1_outlined : Icons.person_outline,
            label: isGroup ? 'Thêm\nthành viên' : 'Trang\ncá nhân',
            onTap: onSecondaryActionTap,
          ),
          _ActionButton(
            icon: Icons.wallpaper_rounded,
            label: 'Đổi\nhình nền',
            onTap: onWallpaperTap,
          ),
          _ActionButton(
            icon: isMuted
                ? Icons.notifications_off_outlined
                : Icons.notifications_outlined,
            label: muteLabel,
            onTap: onMuteTap,
          ),
        ],
      ),
    );
  }
}

class _ChatOptionsSection extends StatelessWidget {
  final List<Widget> children;

  const _ChatOptionsSection({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgCard,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
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

enum _MuteOption { oneHour, fourHours, until8am, untilTurnedOn }
