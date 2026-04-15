import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/image_utils.dart';
import '../../services/contacts_api_service.dart';
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
  bool _showExtra = false;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // Mở GroupOptionsScreen và nhận lại group đã cập nhật
  Future<void> _openOptions() async {
    final updated = await Navigator.push<ApiGroupModel>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupOptionsScreen(group: _group),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _group = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final memberCount = _group.members.length;

    return Scaffold(
      backgroundColor: const Color(0xFFDDE8F0),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────
            _buildHeader(memberCount),

            // ── Messages area ────────────────────────────────────
            Expanded(
              child: GestureDetector(
                onTap: () {
                  _focusNode.unfocus();
                  setState(() => _showExtra = false);
                },
                child: ListView(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  children: const [
                    // Placeholder — tích hợp socket/API ở đây
                    _EmptyChat(),
                  ],
                ),
              ),
            ),

            // ── Input Bar ───────────────────────────────────────
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────
  Widget _buildHeader(int memberCount) {
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          // Back
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
            onPressed: () => Navigator.pop(context),
          ),

          // Avatar
          _GroupAvatar(group: _group, size: 38),
          const SizedBox(width: 10),

          // Title + sub
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _group.name.isEmpty ? 'Nhóm' : _group.name,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
          ),

          // Video call
          IconButton(
            icon: const Icon(Icons.videocam_outlined,
                color: Colors.white, size: 24),
            onPressed: () {},
          ),
          // Search
          IconButton(
            icon: const Icon(Icons.search_rounded,
                color: Colors.white, size: 22),
            onPressed: () {},
          ),
          // Menu → GroupOptionsScreen
          IconButton(
            icon: const Icon(Icons.format_list_bulleted_rounded,
                color: Colors.white, size: 22),
            onPressed: _openOptions,
          ),
        ],
      ),
    );
  }

  // ── Input Bar ─────────────────────────────────────────────────
  Widget _buildInputBar() {
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Row(
        children: [
          // Extra actions
          IconButton(
            icon: Icon(
              _showExtra ? Icons.close_rounded : Icons.add_circle_outline,
              color: AppColors.textSecondary,
              size: 24,
            ),
            onPressed: () => setState(() => _showExtra = !_showExtra),
          ),

          // Text field
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 38, maxHeight: 120),
              decoration: BoxDecoration(
                color: AppColors.bgDark,
                borderRadius: BorderRadius.circular(20),
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
                decoration: const InputDecoration(
                  hintText: 'Tin nhắn',
                  hintStyle: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: AppColors.textHint,
                  ),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),

          const SizedBox(width: 6),

          // More / emoji
          if (_textCtrl.text.isEmpty) ...[
            IconButton(
              icon: const Icon(Icons.more_horiz_rounded,
                  color: AppColors.textSecondary, size: 22),
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.mic_none_rounded,
                  color: AppColors.textSecondary, size: 24),
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.sentiment_satisfied_alt_outlined,
                  color: AppColors.textSecondary, size: 24),
              onPressed: () {},
            ),
          ] else
            GestureDetector(
              onTap: _sendMessage,
              child: Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send_rounded,
                    color: Colors.white, size: 18),
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
        color: Colors.white.withOpacity(0.3),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.group, color: Colors.white, size: size * 0.55),
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
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  color: AppColors.primary, size: 30),
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
