import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../core/constants/app_colors.dart';
import '../../navigation/app_router.dart';
import '../../services/fake_auth_flow_service.dart';
import '../../services/device_info_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/common/common_widgets.dart';
import '../../widgets/common/top_notice.dart';
import 'login_challenge_waiting_screen.dart';
import 'post_login_security_screen.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback? onLoginSuccess;
  const LoginScreen({super.key, this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading) return;
    final identifier = _phoneCtrl.text.trim();
    final password = _passCtrl.text;

    if (identifier.isEmpty) {
      _showError('Vui lòng nhập số điện thoại hoặc email.');
      return;
    }
    if (password.length < 8) {
      _showError('Mật khẩu cần từ 8 ký tự trở lên.');
      return;
    }

    setState(() => _loading = true);
    try {
      final deviceFingerprint = await deviceInfoService.getDeviceFingerprint();
      final result = await fakeAuthFlowService.login(
        identifier: identifier,
        password: password,
        device: deviceInfoService.deviceType,
        deviceName: deviceInfoService.deviceName,
        deviceFingerprint: deviceFingerprint,
      );
      if (!mounted) return;

      if (result.requiresEmailConfirmation && result.challenge != null) {
        final challenge = result.challenge!;
        Navigator.pushNamed(
          context,
          AppRouter.loginChallengeWaiting,
          arguments: LoginChallengeWaitingArguments(
            challengeId: challenge.challengeId,
            email: challenge.email,
            challengeExpiredAt: challenge.challengeExpiredAt,
            reason: challenge.reason,
          ),
        );
        return;
      }

      if (result.loginResult == null) {
        _showError('Không nhận được dữ liệu đăng nhập từ backend.');
        return;
      }

      final login = result.loginResult!;
      final isTrusted = await authService.isDeviceTrusted();
      if (!mounted) return;

      if (isTrusted) {
        authService.setUser(
          login.user,
          token: login.tokens.accessToken,
          refreshToken: login.tokens.refreshToken,
          accessExpiredAt: login.tokens.accessExpiredAt,
        );
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRouter.main,
          (route) => false,
        );
        return;
      }

      Navigator.pushNamed(
        context,
        AppRouter.postLoginSecurity,
        arguments: PostLoginSecurityArguments(
          loginResult: login,
          identifier: identifier,
        ),
      );
    } on FakeAuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Đăng nhập thất bại: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    showTopNotice(context, message: message, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 48),

              // Logo
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.chat_bubble_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'QuickChat',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Chào mừng bạn quay trở lại',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 40),

              // Form card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Số điện thoại hoặc Email',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _phoneCtrl,
                      hint: 'Nhập SĐT hoặc Email',
                      icon: Icons.person_outline,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Mật khẩu',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontFamily: 'Inter',
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pushNamed(
                              context,
                              AppRouter.forgotPassword,
                            );
                          },
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                          ),
                          child: const Text(
                            'Quên mật khẩu?',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.primary,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _passCtrl,
                      hint: 'Nhập mật khẩu',
                      icon: Icons.lock_outline,
                      obscure: _obscure,
                      suffix: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: AppColors.textHint,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      onSubmit: (_) => _login(),
                    ),
                    const SizedBox(height: 24),
                    GradientButton(
                      label: 'Đăng nhập',
                      onTap: _login,
                      loading: _loading,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              RichText(
                text: TextSpan(
                  text: 'Bạn chưa có tài khoản? ',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                  children: [
                    TextSpan(
                      text: 'Đăng ký ngay',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Inter',
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          Navigator.pushNamed(context, AppRouter.register);
                        },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                '© 2026 Chat app team 2. All rights reserved.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textDisabled,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType keyboardType = TextInputType.text,
    ValueChanged<String>? onSubmit,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Inter'),
      onSubmitted: onSubmit,
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
    );
  }
}


