import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/models.dart';
import '../../services/auth_service.dart';
import '../../services/fake_auth_flow_service.dart';
import '../../widgets/common/common_widgets.dart';
import '../../widgets/common/top_notice.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  String _showPhone = 'FRIEND';
  bool _showOnline = true;
  bool _allowStrangerMessage = false;
  bool _findByPhone = true;
  bool _isOnline = true;

  bool _isVerified = false;
  bool _isBlocked = false;
  int _fcmTokenCount = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _hydrateFromCurrentUser();
    _loadServerProfile();
  }

  void _hydrateFromCurrentUser() {
    final user = authService.currentUser;
    if (user == null) return;

    _showPhone = user.privacy.showPhone;
    _showOnline = user.privacy.showOnline;
    _allowStrangerMessage = user.privacy.allowStrangerMessage;
    _isOnline = user.status.isOnline;
    _isVerified = user.isVerified;
  }

  Future<void> _loadServerProfile() async {
    final userId = authService.userId;
    if (userId == null || userId.isEmpty) return;

    try {
      final map = await fakeAuthFlowService.getUserProfile(userId);
      if (!mounted || map.isEmpty) return;

      final privacy = map['privacy'] is Map<String, dynamic>
          ? map['privacy'] as Map<String, dynamic>
          : <String, dynamic>{};
      final status = map['status'] is Map<String, dynamic>
          ? map['status'] as Map<String, dynamic>
          : <String, dynamic>{};
      final fcmTokens = map['fcmTokens'];

      setState(() {
        _showPhone = (privacy['showPhone'] ?? _showPhone).toString();
        _showOnline = privacy['showOnline'] == true;
        _allowStrangerMessage = privacy['allowStrangerMessage'] == true;
        _findByPhone = privacy['findByPhone'] != false;
        _isOnline = status['isOnline'] != false;
        _isVerified = map['isVerified'] == true;
        _isBlocked = map['isBlocked'] == true;
        _fcmTokenCount = fcmTokens is List ? fcmTokens.length : 0;
      });
    } catch (_) {
      // Keep local values if server mapping is not ready.
    }
  }

  Future<void> _savePrivacy() async {
    final userId = authService.userId;
    if (userId == null || userId.isEmpty) return;

    setState(() => _loading = true);
    try {
      await fakeAuthFlowService.updatePrivacy(
        userId: userId,
        showPhone: _showPhone,
        showOnline: _showOnline,
        allowStrangerMessage: _allowStrangerMessage,
        findByPhone: _findByPhone,
      );
      await fakeAuthFlowService.updateOnlineStatus(
        userId: userId,
        isOnline: _isOnline,
      );

      final old = authService.currentUser;
      if (old != null) {
        authService.updateCurrentUser(
          UserModel(
            id: old.id,
            fullName: old.fullName,
            phone: old.phone,
            email: old.email,
            avatar: old.avatar,
            coverImage: old.coverImage,
            bio: old.bio,
            gender: old.gender,
            status: UserStatus(
              isOnline: _isOnline,
              lastSeen: old.status.lastSeen,
            ),
            privacy: UserPrivacy(
              showPhone: _showPhone,
              showOnline: _showOnline,
              allowStrangerMessage: _allowStrangerMessage,
            ),
            isVerified: old.isVerified,
          ),
        );
      }

      if (!mounted) return;
      showTopNotice(context, message: 'Đã cập nhật quyền riêng tư.');
    } on FakeAuthException catch (e) {
      if (!mounted) return;
      showTopNotice(context, message: e.message, isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgDark,
        elevation: 0,
        title: const Text(
          'Quyền riêng tư',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        children: [
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Quyền riêng tư',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _showPhone,
                  decoration: _decoration('Ai xem được số điện thoại'),
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('Mọi người')),
                    DropdownMenuItem(value: 'FRIEND', child: Text('Bạn bè')),
                    DropdownMenuItem(value: 'PRIVATE', child: Text('Chỉ mình tôi')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _showPhone = v);
                  },
                ),
                const SizedBox(height: 6),
                SwitchListTile.adaptive(
                  value: _showOnline,
                  onChanged: (v) => setState(() => _showOnline = v),
                  title: const Text('Ai thấy trạng thái online'),
                  subtitle: const Text('Bật/tắt hiển thị trạng thái online'),
                  activeThumbColor: AppColors.primary,
                ),
                SwitchListTile.adaptive(
                  value: _isOnline,
                  onChanged: (v) => setState(() => _isOnline = v),
                  title: const Text('Trạng thái hoạt động'),
                  subtitle: const Text('Tắt trạng thái hoạt động như Zalo'),
                  activeThumbColor: AppColors.primary,
                ),
                SwitchListTile.adaptive(
                  value: _findByPhone,
                  onChanged: (v) => setState(() => _findByPhone = v),
                  title: const Text('Cho phép tìm bằng số điện thoại'),
                  activeThumbColor: AppColors.primary,
                ),
                SwitchListTile.adaptive(
                  value: _allowStrangerMessage,
                  onChanged: (v) => setState(() => _allowStrangerMessage = v),
                  title: const Text('Cho người lạ nhắn tin'),
                  activeThumbColor: AppColors.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Thông tin bảo mật',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 10),
                _kv('fcmTokens', 'Array ($_fcmTokenCount)'),
                _kv('isVerified', _isVerified ? 'true' : 'false'),
                _kv('isBlocked', _isBlocked ? 'true' : 'false'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GradientButton(
            label: 'Lưu quyền riêng tư',
            loading: _loading,
            onTap: _savePrivacy,
          ),
        ],
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            key,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Inter',
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(Widget child) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: AppColors.bgInput,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }
}
