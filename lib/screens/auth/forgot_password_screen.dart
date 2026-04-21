import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../navigation/app_router.dart';
import '../../services/fake_auth_flow_service.dart';
import '../../widgets/common/common_widgets.dart';
import '../../widgets/common/top_notice.dart';
import 'otp_verify_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    if (_loading) return;

    final email = _emailCtrl.text.trim();
    final newPassword = _newPassCtrl.text;
    final confirm = _confirmPassCtrl.text;

    if (!fakeAuthFlowService.isValidEmail(email)) {
      _showError('Email không hợp lệ.');
      return;
    }
    if (!fakeAuthFlowService.isStrongPassword(newPassword)) {
      _showError('Mật khẩu mới phải >= 8 ký tự, gồm chữ hoa, chữ thường và số.');
      return;
    }
    if (newPassword != confirm) {
      _showError('Mật khẩu xác nhận không khớp.');
      return;
    }

    setState(() => _loading = true);
    try {
      final otpSession = await fakeAuthFlowService.requestForgotPasswordOtp(
        email: email,
        newPassword: newPassword,
      );

      if (!mounted) return;
      showTopNotice(context, message: 'Da gui OTP toi ${otpSession.email}.');

      Navigator.pushNamed(
        context,
        AppRouter.otpVerify,
        arguments: OtpVerifyArguments(
          sessionId: otpSession.sessionId,
          email: otpSession.email,
          purpose: FakeAuthFlowService.emailOtpPurposeForgotPassword,
          expiredAt: otpSession.expiredAt,
        ),
      );
    } on FakeAuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Không thể gửi OTP, vui lòng thử lại.');
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
          'Quên mật khẩu',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: const [
                    Icon(Icons.lock_reset_rounded, color: Colors.white, size: 42),
                    SizedBox(height: 8),
                    Text(
                      'Khôi phục tài khoản',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        fontFamily: 'Inter',
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Xác thực OTP qua email để đổi mật khẩu',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'Inter',
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _buildInput(
                      controller: _emailCtrl,
                      hint: 'name@gmail.com',
                      label: 'Email tài khoản',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 14),
                    _buildInput(
                      controller: _newPassCtrl,
                      hint: 'NewPass@123',
                      label: 'Mật khẩu mới',
                      icon: Icons.lock_outline,
                      obscure: _obscureNew,
                      suffix: IconButton(
                        onPressed: () {
                          setState(() => _obscureNew = !_obscureNew);
                        },
                        icon: Icon(
                          _obscureNew
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildInput(
                      controller: _confirmPassCtrl,
                      hint: 'Nhập lại mật khẩu mới',
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
                    const SizedBox(height: 18),
                    GradientButton(
                      label: 'Gửi OTP qua email',
                      loading: _loading,
                      onTap: _requestOtp,
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