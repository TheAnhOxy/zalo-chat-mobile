import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../navigation/app_router.dart';
import '../../services/fake_auth_flow_service.dart';
import '../../widgets/common/common_widgets.dart';
import '../../widgets/common/top_notice.dart';
import 'otp_verify_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _agreeTerms = true;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _loading = false;

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_loading) return;
    final fullName = _fullNameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;
    final confirm = _confirmCtrl.text;

    if (fullName.length < 2) {
      _showError('Họ tên cần ít nhất 2 ký tự.');
      return;
    }
    if (!fakeAuthFlowService.isValidVietnamPhone(phone)) {
      _showError('Số điện thoại chưa đúng định dạng Việt Nam.');
      return;
    }
    if (!fakeAuthFlowService.isValidEmail(email)) {
      _showError('Email không hợp lệ.');
      return;
    }
    if (!fakeAuthFlowService.isStrongPassword(password)) {
      _showError('Mật khẩu tối thiểu 8 ký tự, gồm chữ hoa, chữ thường và số.');
      return;
    }
    if (password != confirm) {
      _showError('Mật khẩu xác nhận chưa khớp.');
      return;
    }
    if (!_agreeTerms) {
      _showError('Bạn cần đồng ý điều khoản để tiếp tục.');
      return;
    }

    setState(() => _loading = true);
    try {
      final otpSession = await fakeAuthFlowService.register(
        fullName: fullName,
        phone: phone,
        email: email,
        password: password,
      );

      if (!mounted) return;
      showTopNotice(context, message: 'Da gui OTP toi ${otpSession.email}.');

      Navigator.pushNamed(
        context,
        AppRouter.otpVerify,
        arguments: OtpVerifyArguments(
          sessionId: otpSession.sessionId,
          email: otpSession.email,
          purpose: FakeAuthFlowService.emailOtpPurposeRegister,
          expiredAt: otpSession.expiredAt,
        ),
      );
    } on FakeAuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Đăng ký thất bại. Vui lòng thử lại.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    showTopNotice(context, message: message, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text(
          'Tạo tài khoản mới',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontFamily: 'Inter',
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 700),
                tween: Tween(begin: 0.8, end: 1),
                curve: Curves.easeOutBack,
                builder: (context, value, child) {
                  return Transform.scale(scale: value, child: child);
                },
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person_add_alt_1_rounded,
                    color: Colors.white,
                    size: 42,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Đăng ký tài khoản mới QuickChat',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Kết nối mọi lúc mọi nơi với mọi người',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _buildInput(
                      controller: _fullNameCtrl,
                      hint: 'Nguyễn Văn A',
                      label: 'Họ và tên',
                      icon: Icons.badge_outlined,
                    ),
                    const SizedBox(height: 14),
                    _buildInput(
                      controller: _phoneCtrl,
                      hint: '0000000',
                      label: 'Số điện thoại ',
                      icon: Icons.phone_iphone_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 14),
                    _buildInput(
                      controller: _emailCtrl,
                      hint: 'you@gmail.com',
                      label: 'Email',
                      icon: Icons.alternate_email_rounded,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 14),
                    _buildInput(
                      controller: _passCtrl,
                      hint: 'password',
                      label: 'Mật khẩu',
                      icon: Icons.lock_outline,
                      obscure: _obscurePass,
                      suffix: IconButton(
                        onPressed: () {
                          setState(() => _obscurePass = !_obscurePass);
                        },
                        icon: Icon(
                          _obscurePass
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildInput(
                      controller: _confirmCtrl,
                      hint: 'Nhập lại mật khẩu',
                      label: 'Xác nhận mật khẩu',
                      icon: Icons.verified_user_outlined,
                      obscure: _obscureConfirm,
                      suffix: IconButton(
                        onPressed: () {
                          setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          );
                        },
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      value: _agreeTerms,
                      onChanged: (value) {
                        setState(() => _agreeTerms = value ?? false);
                      },
                      title: const Text(
                        'Tôi đồng ý điều khoản sử dụng và chính sách riêng tư',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      activeColor: AppColors.primary,
                    ),
                    const SizedBox(height: 6),
                    GradientButton(
                      label: 'Đăng ký và gửi OTP email',
                      loading: _loading,
                      onTap: _register,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
    Widget? suffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscure,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontFamily: 'Inter',
          ),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: AppColors.textHint, size: 20),
            suffixIcon: suffix,
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
          ),
        ),
      ],
    );
  }
}