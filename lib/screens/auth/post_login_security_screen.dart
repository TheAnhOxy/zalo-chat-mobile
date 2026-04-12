import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../navigation/app_router.dart';
import '../../services/auth_service.dart';
import '../../services/fake_auth_flow_service.dart';
import '../../widgets/common/common_widgets.dart';
import '../../widgets/common/top_notice.dart';
import 'otp_verify_screen.dart';

class PostLoginSecurityArguments {
  final LoginResult loginResult;
  final String identifier;

  const PostLoginSecurityArguments({
    required this.loginResult,
    required this.identifier,
  });
}

class PostLoginSecurityScreen extends StatefulWidget {
  final PostLoginSecurityArguments args;

  const PostLoginSecurityScreen({super.key, required this.args});

  @override
  State<PostLoginSecurityScreen> createState() =>
      _PostLoginSecurityScreenState();
}

class _PostLoginSecurityScreenState extends State<PostLoginSecurityScreen> {
  bool _loading = false;
  final _phoneForOtpCtrl = TextEditingController();

  @override
  void dispose() {
    _phoneForOtpCtrl.dispose();
    super.dispose();
  }

  Future<void> _loginDirect() async {
    authService.setUser(
      widget.args.loginResult.user,
      token: widget.args.loginResult.tokens.accessToken,
      refreshToken: widget.args.loginResult.tokens.refreshToken,
    );

    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, AppRouter.main, (r) => false);
  }

  Future<void> _requestOtpFlow() async {
    String phone = widget.args.identifier.trim();

    if (!fakeAuthFlowService.isValidVietnamPhone(phone)) {
      final selected = await _askPhoneDialog();
      if (selected == null) return;
      phone = selected;
    }

    setState(() => _loading = true);
    try {
      final otpSession = await fakeAuthFlowService.requestPhoneLoginOtp(
        phone: phone,
      );
      if (!mounted) return;
      showTopNotice(context, message: 'Da gui OTP dang nhap toi $phone');
      Navigator.pushNamed(
        context,
        AppRouter.otpVerify,
        arguments: OtpVerifyArguments(
          sessionId: otpSession.sessionId,
          email: phone,
          purpose: FakeAuthFlowService.phoneOtpPurposeLogin,
          expiredAt: otpSession.expiredAt,
        ),
      );
    } on FakeAuthException catch (e) {
      if (!mounted) return;
      showTopNotice(context, message: e.message, isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _askPhoneDialog() async {
    _phoneForOtpCtrl.clear();

    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.bgCard,
          title: const Text(
            'Nhap so dien thoai de nhan OTP',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          content: TextField(
            controller: _phoneForOtpCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              hintText: '0901234565',
              filled: true,
              fillColor: AppColors.bgInput,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Huy'),
            ),
            TextButton(
              onPressed: () {
                final phone = _phoneForOtpCtrl.text.trim();
                if (!fakeAuthFlowService.isValidVietnamPhone(phone)) {
                  showTopNotice(
                    context,
                    message: 'So dien thoai OTP khong hop le.',
                    isError: true,
                  );
                  return;
                }
                Navigator.pop(context, phone);
              },
              child: const Text('Gui OTP'),
            ),
          ],
        );
      },
    );
  }

  void _show2faPlan() {
    showTopNotice(
      context,
      message: '2FA se bat buoc sau khi hoan thanh project.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.args.loginResult.user;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgDark,
        elevation: 0,
        title: const Text(
          'Chon cach xac thuc',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                AvatarWidget(url: user.avatar, name: user.fullName, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.fullName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.email ?? user.phone,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _MethodCard(
            index: '1',
            title: 'Dang nhap thang',
            subtitle: 'Nhanh de test hien tai',
            icon: Icons.flash_on_rounded,
            onTap: _loading ? null : _loginDirect,
          ),
          _MethodCard(
            index: '2',
            title: 'Nhan ma OTP',
            subtitle: 'Bat buoc sau khi hoan thanh project',
            icon: Icons.sms_outlined,
            onTap: _loading ? null : _requestOtpFlow,
          ),
          _MethodCard(
            index: '3',
            title: 'Xac thuc 2 lop',
            subtitle: 'Se trien khai tiep theo',
            icon: Icons.admin_panel_settings_outlined,
            onTap: _loading ? null : _show2faPlan,
          ),
          if (_loading) ...[
            const SizedBox(height: 14),
            const Center(child: CircularProgressIndicator()),
          ],
          const SizedBox(height: 10),
          const Text(
            'Note: hien tai cho phep login thang de lam nhanh, sau nay se bat OTP/2FA.',
            style: TextStyle(
              color: AppColors.textHint,
              fontFamily: 'Inter',
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  final String index;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  const _MethodCard({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                index,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Inter',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
            Icon(icon, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}
