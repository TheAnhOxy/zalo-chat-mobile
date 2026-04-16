import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../core/constants/app_colors.dart';
import '../../core/utils/image_utils.dart';
import '../../services/contacts_api_service.dart';
import 'group_chat_backgrounds.dart';
import 'group_options_screen.dart';

class GroupChatScreen extends StatefulWidget {
  final ApiGroupModel group;

  const GroupChatScreen({super.key, required this.group});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();

  late ApiGroupModel _group;
  int _bgIndex = 0;
  String? _bgCustomBase64;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _loadBackgroundPref();
  }

  Future<void> _loadBackgroundPref() async {
    final p = await SharedPreferences.getInstance();
    final idx = p.getInt('group_chat_bg_${_group.id}') ?? 0;
    final custom = p.getString('group_chat_bg_custom_${_group.id}');
    final override = p.getBool('group_chat_bg_override_${_group.id}') ?? false;
    if (!mounted) return;
    setState(() {
      _bgIndex = idx.clamp(0, GroupChatBackgrounds.count - 1);
      _bgCustomBase64 = custom;
    });

    // Nếu không override cá nhân → lấy nền toàn nhóm từ backend.
    if (!override) {
      await _syncGroupBackgroundFromBackend();
    }
  }

  Future<void> _syncGroupBackgroundFromBackend() async {
    final res =
        await ContactsApiService.instance.fetchConversationRaw(_group.id);
    if (!res.isSuccess) return;
    final map = res.data ?? const <String, dynamic>{};
    final gs = map['groupSettings'];
    if (gs is! Map) return;

    final type = (gs['chatBackgroundType'] ?? 'PRESET').toString();
    final idxRaw = gs['chatBackgroundIndex'];
    final idx = idxRaw is num ? idxRaw.toInt() : int.tryParse('$idxRaw') ?? 0;
    final custom = (gs['chatBackgroundCustomBase64'] ?? '').toString();

    if (!mounted) return;
    setState(() {
      if (type == 'CUSTOM' && custom.isNotEmpty) {
        _bgCustomBase64 = custom;
      } else {
        _bgCustomBase64 = null;
        _bgIndex = idx.clamp(0, GroupChatBackgrounds.count - 1);
      }
    });

    // Cache local để mở lại nhanh.
    final p = await SharedPreferences.getInstance();
    await p.setBool('group_chat_bg_override_${_group.id}', false);
    if (type == 'CUSTOM' && custom.isNotEmpty) {
      await p.setString('group_chat_bg_custom_${_group.id}', custom);
    } else {
      await p.remove('group_chat_bg_custom_${_group.id}');
      await p.setInt('group_chat_bg_${_group.id}',
          idx.clamp(0, GroupChatBackgrounds.count - 1));
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // Mở GroupOptionsScreen: cập nhật nhóm hoặc rời nhóm (pop về danh sách)
  Future<void> _openOptions() async {
    // `true` = đã rời nhóm; [ApiGroupModel] = nhóm đã chỉnh từ tùy chọn
    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(builder: (_) => GroupOptionsScreen(group: _group)),
    );
    if (!mounted) return;
    if (result == true) {
      Navigator.pop(context, true);
    } else if (result is ApiGroupModel) {
      setState(() => _group = result);
    }
    await _loadBackgroundPref();
  }

  @override
  Widget build(BuildContext context) {
    final memberCount = _group.members.length;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        children: [
          // ── Header ──────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: _buildHeader(memberCount),
          ),

          // ── Messages area (nền gradient theo Tùy chọn) ─────
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: _bgCustomBase64 == null
                    ? GroupChatBackgrounds.gradientAt(_bgIndex)
                    : null,
                image: _bgCustomBase64 != null
                    ? DecorationImage(
                        image: MemoryImage(base64Decode(_bgCustomBase64!)),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: GestureDetector(
                onTap: () {
                  _focusNode.unfocus();
                },
                child: ListView(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  children: const [
                    _EmptyChat(),
                  ],
                ),
              ),
            ),
          ),

          // ── Input Bar ───────────────────────────────────────
          SafeArea(
            top: false,
            child: _buildInputBar(),
          ),
        ],
      ),
    );
  }

  Future<void> _showPlusMenu(Offset globalPosition) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    // Đẩy menu lên cao để không che hàng icon ở footer.
    const menuLift = 140.0;
    final anchor = Offset(globalPosition.dx, globalPosition.dy - menuLift);

    final selected = await showMenu<String>(
      context: context,
      color: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.divider),
      ),
      position: RelativeRect.fromRect(
        Rect.fromPoints(anchor, anchor),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'quick_ai',
          child: Row(
            children: const [
              Icon(Icons.auto_awesome, color: AppColors.primary, size: 20),
              SizedBox(width: 10),
              Text(
                'Quick AI',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Inter',
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'file',
          child: Row(
            children: const [
              Icon(Icons.attach_file, color: AppColors.primary, size: 20),
              SizedBox(width: 10),
              Text(
                'File',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Inter',
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (!mounted || selected == null) return;
    switch (selected) {
      case 'quick_ai':
        // TODO: gắn flow AI sau (hiện tại chỉ UI menu)
        break;
      case 'file':
        // TODO: gắn flow chọn/gửi file sau (hiện tại chỉ UI menu)
        break;
    }
  }

  // ── Header ────────────────────────────────────────────────────
  Widget _buildHeader(int memberCount) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back,
              color: AppColors.primary,
              size: 22,
            ),
            onPressed: () => Navigator.pop(context),
          ),

          // Avatar + online dot (giống kiểu Messenger)
          SizedBox(
            width: 38,
            height: 38,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _GroupAvatar(group: _group, size: 38),
                Positioned(
                  left: -1,
                  bottom: -1,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: AppColors.online,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.bgCard, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _group.name.isEmpty ? 'Nhóm' : _group.name,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$memberCount thành viên',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          IconButton(
            icon: const Icon(
              Icons.phone_outlined,
              color: AppColors.primary,
              size: 22,
            ),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(
              Icons.videocam_outlined,
              color: AppColors.primary,
              size: 24,
            ),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(
              Icons.info_outline,
              color: AppColors.primary,
              size: 22,
            ),
            onPressed: _openOptions,
          ),
        ],
      ),
    );
  }

  // ── Input Bar ─────────────────────────────────────────────────
  Widget _buildInputBar() {
    const footerBg = AppColors.bgCard;
    const inputBg = AppColors.bgInput;
    const actionColor = AppColors.primary;

    final hasText = _textCtrl.text.trim().isNotEmpty;

    Widget actionIcon(IconData icon, {VoidCallback? onTap}) {
      return InkResponse(
        onTap: onTap,
        radius: 22,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: actionColor, size: 24),
        ),
      );
    }

    return Container(
      color: footerBg,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Row(
        children: [
          GestureDetector(
            onTapDown: (d) => _showPlusMenu(d.globalPosition),
            child: actionIcon(Icons.add_circle),
          ),
          actionIcon(Icons.camera_alt_rounded, onTap: () {}),
          actionIcon(Icons.image_rounded, onTap: () {}),
          actionIcon(Icons.mic_none_rounded, onTap: () {}),
          const SizedBox(width: 6),

          // Text field
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 38, maxHeight: 120),
              decoration: BoxDecoration(
                color: inputBg,
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _textCtrl,
                focusNode: _focusNode,
                maxLines: null,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Nhắn tin',
                  hintStyle: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: AppColors.textHint,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  suffixIcon: InkResponse(
                    onTap: () {},
                    radius: 22,
                    child: Icon(
                      Icons.sentiment_satisfied_alt_outlined,
                      color: actionColor,
                      size: 22,
                    ),
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),

          const SizedBox(width: 10),

          InkResponse(
            onTap: hasText ? _sendMessage : () {},
            radius: 24,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                hasText ? Icons.send_rounded : Icons.thumb_up,
                color: actionColor,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    setState(() {});
  }
}

// ── Group avatar widget ───────────────────────────────────────────────────────
class _GroupAvatar extends StatelessWidget {
  final ApiGroupModel group;
  final double size;

  const _GroupAvatar({required this.group, required this.size});

  @override
  Widget build(BuildContext context) {
    if (group.avatar.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          webSafeImageUrl(group.avatar),
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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.bgInput,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.group, color: AppColors.primary, size: size * 0.55),
    );
  }
}

// ── Empty chat placeholder ────────────────────────────────────────────────────
class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: AppColors.primary,
                size: 30,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Chưa có tin nhắn nào\nHãy bắt đầu cuộc trò chuyện!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
