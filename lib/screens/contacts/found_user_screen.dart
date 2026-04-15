import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/contacts_api_service.dart';
import '../../services/social_api_service.dart';

class FoundUserScreen extends StatefulWidget {
  final ApiUserModel user;

  const FoundUserScreen({super.key, required this.user});

  @override
  State<FoundUserScreen> createState() => _FoundUserScreenState();
}

class _FoundUserScreenState extends State<FoundUserScreen> {
  bool _loadingRelationship = true;
  bool _processing = false;
  String _status = 'none';
  String? _friendshipId;

  @override
  void initState() {
    super.initState();
    _loadRelationship();
  }

  Future<void> _loadRelationship() async {
    setState(() => _loadingRelationship = true);
    try {
      final rel = await SocialApiService.instance.getRelationship(widget.user.id);
      if (!mounted) return;
      setState(() {
        _status = rel['status']?.toString() ?? 'none';
        _friendshipId = rel['friendshipId']?.toString();
        _loadingRelationship = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = 'none';
        _friendshipId = null;
        _loadingRelationship = false;
      });
    }
  }

  Future<void> _sendRequest() async {
    if (widget.user.id == authService.userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể gửi lời mời cho chính bạn'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() => _processing = true);
    final ok = await SocialApiService.instance.sendFriendRequest(widget.user.id);
    if (!mounted) return;
    setState(() => _processing = false);
    if (ok) {
      await _loadRelationship();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã gửi lời mời kết bạn'), duration: Duration(seconds: 2)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            SocialApiService.instance.lastError ?? 'Không thể gửi lời mời',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _cancelRequest() async {
    final id = _friendshipId;
    if (id == null || id.isEmpty) return;
    setState(() => _processing = true);
    final ok = await SocialApiService.instance.cancelRequest(id);
    if (!mounted) return;
    setState(() => _processing = false);
    if (ok) {
      await _loadRelationship();
    }
  }

  Future<void> _acceptRequest() async {
    final id = _friendshipId;
    if (id == null || id.isEmpty) return;
    setState(() => _processing = true);
    final ok = await SocialApiService.instance.acceptRequest(id);
    if (!mounted) return;
    setState(() => _processing = false);
    if (ok) {
      await _loadRelationship();
    }
  }

  Future<void> _declineRequest() async {
    final id = _friendshipId;
    if (id == null || id.isEmpty) return;
    setState(() => _processing = true);
    final ok = await SocialApiService.instance.declineRequest(id);
    if (!mounted) return;
    setState(() => _processing = false);
    if (ok) {
      await _loadRelationship();
    }
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
                    IconButton(
                      icon: const Icon(Icons.phone_outlined, color: Colors.white),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_horiz, color: Colors.white),
                      onPressed: () {},
                    ),
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
                                  onTap: () {},
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Kết bạn
                              _buildRightAction(),
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
            colors: [Color(0xFF0068FF), Color(0xFF42A5F5)],
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

  Widget _buildRightAction() {
    if (_loadingRelationship || _processing) {
      return const SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_status == 'friends') {
      return _IconActionButton(
        icon: Icons.check_circle_outline,
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hai bạn đã là bạn bè'), duration: Duration(seconds: 2)),
          );
        },
      );
    }

    if (_status == 'pending_out') {
      return _IconActionButton(
        icon: Icons.hourglass_top_rounded,
        onTap: _cancelRequest,
      );
    }

    if (_status == 'pending_in') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _IconActionButton(icon: Icons.close_rounded, onTap: _declineRequest),
          const SizedBox(width: 8),
          _IconActionButton(icon: Icons.check_rounded, onTap: _acceptRequest),
        ],
      );
    }

    if (_status == 'blocked' || _status == 'blocked_by_other') {
      return _IconActionButton(
        icon: Icons.block,
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể kết bạn do bị chặn'), duration: Duration(seconds: 2)),
          );
        },
      );
    }

    return _IconActionButton(icon: Icons.person_add_alt_1_outlined, onTap: _sendRequest);
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
