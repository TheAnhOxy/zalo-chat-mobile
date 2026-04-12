import 'package:flutter/material.dart';
import 'package:ott_chat_app/navigation/app_router.dart';
import '../../core/constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/fake_auth_flow_service.dart';
import '../../widgets/common/common_widgets.dart';

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});

  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  bool _logoutLoading = false;

  Future<void> _logoutCurrentDevice() async {
    if (_logoutLoading) return;

    setState(() => _logoutLoading = true);
    try {
      final refresh = authService.refreshToken;
      if (refresh != null && refresh.isNotEmpty) {
        await fakeAuthFlowService.logout(refresh);
      }
    } catch (_) {
      // Keep UX smooth: still allow local logout when API call fails.
    }

    if (!mounted) return;
    authService.logout();
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRouter.login,
      (route) => false,
    );
    setState(() => _logoutLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final user = authService.currentUser;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgDark,
        elevation: 0,
        title: const Text(
          'Cài đặt',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 16, bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Stack(
                    children: [
                      AvatarWidget(
                        url: user?.avatar,
                        name: user?.fullName ?? 'User',
                        size: 82,
                        showOnline: true,
                        isOnline: true,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.bgDark, width: 2),
                          ),
                          child: const Icon(
                            Icons.edit,
                            size: 18,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    user?.fullName ?? 'Minh Anh Lê',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    user?.email ?? 'minhanh.le@azureconnect.com',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'Chỉnh sửa hồ sơ',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Inter',
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _SettingsGroup(
            items: [
              _SettingsItemData(
                icon: Icons.lock_outline,
                title: 'Tài khoản & Bảo mật',
                subtitle: 'Mật khẩu, xác thực 2 lớp',
                onTap: () {
                  Navigator.pushNamed(context, AppRouter.accountSecurity);
                },
              ),
              _SettingsItemData(
                icon: Icons.devices_outlined,
                title: 'Thiết bị & Phiên đăng nhập',
                subtitle: 'Quản lý các thiết bị đang kết nối',
                onTap: () {
                  Navigator.pushNamed(context, AppRouter.deviceSessions);
                },
              ),
              _SettingsItemData(
                icon: Icons.notifications_outlined,
                title: 'Thông báo',
                subtitle: 'Âm thanh, rung, cảnh báo',
              ),
              _SettingsItemData(
                icon: Icons.privacy_tip_outlined,
                title: 'Quyền riêng tư',
                subtitle: 'Ai có thể nhìn tin, trạng thái',
              ),
              _SettingsItemData(
                icon: Icons.chat_bubble_outline,
                title: 'Tin nhắn & Cuộc gọi',
                subtitle: 'Cài đặt trò chuyện, media',
              ),
              _SettingsItemData(
                icon: Icons.palette_outlined,
                title: 'Giao diện & Chủ đề',
                subtitle: 'Đổi chủ đề, hình nền',
              ),
              _SettingsItemData(
                icon: Icons.language_outlined,
                title: 'Ngôn ngữ & Phông chữ',
                subtitle: 'Tiếng Việt, cỡ chữ hệ thống',
              ),
              _SettingsItemData(
                icon: Icons.sd_storage_outlined,
                title: 'Dữ liệu & Bộ nhớ',
                subtitle: 'Bộ nhớ đệm, tự động tải',
              ),
              _SettingsItemData(
                icon: Icons.backup_outlined,
                title: 'Sao lưu & Khôi phục',
                subtitle: 'Sao lưu lên Google Drive',
              ),
              _SettingsItemData(
                icon: Icons.support_agent_outlined,
                title: 'Trung tâm trợ giúp',
                subtitle: 'Câu hỏi thường gặp, hướng dẫn',
              ),
              _SettingsItemData(
                icon: Icons.description_outlined,
                title: 'Điều khoản & Chính sách',
                subtitle: 'Quy định sử dụng, bảo mật dữ liệu',
              ),
            ],
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              icon: _logoutLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.error,
                      ),
                    )
                  : const Icon(Icons.logout, color: AppColors.error),
              label: Text(
                _logoutLoading ? 'Dang dang xuat...' : 'Dang xuat',
                style: const TextStyle(
                  color: AppColors.error,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.error),
                backgroundColor: AppColors.bgCard,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _logoutLoading ? null : _logoutCurrentDevice,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final List<_SettingsItemData> items;
  const _SettingsGroup({required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: List.generate(
            items.length,
            (index) {
              final item = items[index];
              return Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.bgDark,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(item.icon, color: AppColors.primary, size: 22),
                    ),
                    title: Text(
                      item.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Inter',
                      ),
                    ),
                    subtitle: Text(
                      item.subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontFamily: 'Inter',
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: AppColors.textHint,
                      size: 22,
                    ),
                    onTap: item.onTap,
                  ),
                  if (index < items.length - 1)
                    const Divider(color: AppColors.divider, height: 1, indent: 20, endIndent: 20),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SettingsItemData {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsItemData({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap = _defaultAction,
  });

  static void _defaultAction() {}
}
