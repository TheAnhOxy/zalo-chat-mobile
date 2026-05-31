import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../navigation/app_router.dart';
import '../../services/auth_service.dart';
import '../../services/contacts_api_service.dart';
import '../../services/api_service.dart';
import '../../data/models/models.dart';

class FoundUserScreen extends StatefulWidget {
  final ApiUserModel user;

  const FoundUserScreen({super.key, required this.user});

  @override
  State<FoundUserScreen> createState() => _FoundUserScreenState();
}

class _FoundUserScreenState extends State<FoundUserScreen> {
  bool _loadingRelation = true;
  String? _friendshipId;
  String? _friendshipStatus; // PENDING | ACCEPTED | BLOCKED

  bool get _isFriend => _friendshipStatus == 'ACCEPTED';

  @override
  void initState() {
    super.initState();
    _loadRelation();
  }

  Future<void> _loadRelation() async {
    final myId = authService.userId ?? '';
    if (myId.isEmpty) {
      if (!mounted) return;
      setState(() => _loadingRelation = false);
      return;
    }

    final res = await ContactsApiService.instance.getFriendshipBetween(
      myUserId: myId,
      otherUserId: widget.user.id,
    );
    if (!mounted) return;
    final data = res.data;
    setState(() {
      _friendshipId = data?['id'];
      _friendshipStatus = data?['status'];
      _loadingRelation = false;
    });
  }

  Future<void> _confirmUnfriend() async {
    final fid = _friendshipId;
    if (fid == null || fid.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text(
          'Hủy kết bạn',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Bạn có chắc muốn hủy kết bạn với ${widget.user.fullName}?',
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
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Hủy kết bạn',
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final ok = await ContactsApiService.instance.rejectFriendRequest(fid);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _friendshipId = null;
        _friendshipStatus = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã hủy kết bạn'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hủy kết bạn thất bại'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openChat() async {
    final currentUserId = authService.userId ?? '';
    if (currentUserId.isEmpty || widget.user.id.isEmpty) return;

    // Hiển thị loading nhẹ
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    final conv = await ApiService().findOrCreateDirectConversation(
      currentUserId: currentUserId,
      targetUserId: widget.user.id,
    );

    if (!mounted) return;
    Navigator.pop(context); // đóng loading

    if (conv == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể mở cuộc trò chuyện')),
      );
      return;
    }

    final otherUser = UserModel(
      id: widget.user.id,
      fullName: widget.user.fullName.isNotEmpty ? widget.user.fullName : 'Người dùng',
      phone: widget.user.phone,
      avatar: widget.user.avatar,
      gender: 'other',
      status: UserStatus(isOnline: widget.user.isOnline, lastSeen: widget.user.lastSeen),
      privacy: const UserPrivacy(),
      isVerified: false,
    );

    Navigator.pushReplacementNamed(
      context,
      AppRouter.chatDetail,
      arguments: {
        'conversationId': conv.id,
        'otherUser': otherUser,
        'conversation': conv,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Stack(
        children: [
          // ── Cover photo / gradient header ──────────────────────────
          SizedBox(
            height: 260,
            width: double.infinity,
            child: user.avatar.isNotEmpty
                ? Image.network(
                    user.avatar,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _defaultCover(),
                  )
                : _defaultCover(),
          ),

          // ── Back & More buttons ────────────────────────────────────
          SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                Row(
                  children: [
                    if (_isFriend)
                      IconButton(
                        icon: const Icon(
                          Icons.person_remove_outlined,
                          color: Colors.white,
                        ),
                        onPressed: _confirmUnfriend,
                      )
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ],
            ),
          ),

          // ── White card content ─────────────────────────────────────
          Align(
            alignment: Alignment.bottomCenter,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 180),
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 50),

                        // Name
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              user.fullName,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Privacy note
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'Bạn chưa thể xem nhật ký của ${user.fullName} khi chưa là bạn bè',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              height: 1.5,
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Action buttons
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            children: [
                              // Nhắn tin
                              Expanded(
                                child: _ActionButton(
                                  icon: Icons.chat_bubble_outline_rounded,
                                  label: 'Nhắn tin',
                                  filled: true,
                                  onTap: _openChat,
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Kết bạn
                              if (_loadingRelation)
                                const SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Center(
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                )
                              else if (!_isFriend)
                                _IconActionButton(
                                  icon: Icons.person_add_alt_1_outlined,
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    AppRouter.sendFriendRequest,
                                    arguments: user,
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Divider
                        const Divider(height: 1, thickness: 1, color: AppColors.divider),

                        const SizedBox(height: 200),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Avatar overlapping cover / card boundary ───────────────
          Positioned(
            top: 180,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  color: const Color(0xFFE5E7EB),
                ),
                child: ClipOval(
                  child: user.avatar.isNotEmpty
                      ? Image.network(
                          user.avatar,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _avatarFallback(),
                        )
                      : _avatarFallback(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _defaultCover() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF388E3C), Color(0xFF66BB6A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );

  Widget _avatarFallback() => Container(
        color: AppColors.primaryLight,
        child: Center(
          child: Text(
            _initials(widget.user.fullName),
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
      );

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

// ── Action Button ─────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.filled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: filled ? AppColors.primaryLight : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: filled ? null : Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: filled ? AppColors.primary : AppColors.textSecondary,
                size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: filled ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconActionButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, color: AppColors.textSecondary, size: 22),
      ),
    );
  }
}
