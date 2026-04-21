import 'dart:async';

import 'package:another_flushbar/flushbar.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../navigation/app_router.dart';
import '../../services/auth_service.dart';
import '../../services/fake_auth_flow_service.dart';
import '../../widgets/common/common_widgets.dart';
import '../../widgets/common/top_notice.dart';

class OtpVerifyArguments {
  final String sessionId;
  final String email;
  final String purpose;
  final DateTime? expiredAt;

  const OtpVerifyArguments({
    required this.sessionId,
    required this.email,
    required this.purpose,
    this.expiredAt,
  });
}

class OtpVerifyScreen extends StatefulWidget {
  final OtpVerifyArguments args;
  const OtpVerifyScreen({super.key, required this.args});

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  final _otpCtrl = TextEditingController();

  bool _loading = false;
  int _remainingSeconds = 120;
  Timer? _timer;
  late String _sessionId;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.args.sessionId;
    _startCountdown(from: widget.args.expiredAt);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpCtrl.dispose();
    super.dispose();
  }

  void _startCountdown({DateTime? from}) {
    _timer?.cancel();
    final seconds = from == null
        ? 120
        : from.difference(DateTime.now()).inSeconds.clamp(0, 120);
    setState(() => _remainingSeconds = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remainingSeconds <= 1) {
        timer.cancel();
        setState(() => _remainingSeconds = 0);
        return;
      }
      setState(() => _remainingSeconds -= 1);
    });
  }

  Future<void> _verifyOtp() async {
    if (_loading) return;

    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) {
      _showError('Vui lòng nhập đúng 6 số OTP.');
      return;
    }

    setState(() => _loading = true);
    try {
      if (widget.args.purpose == FakeAuthFlowService.emailOtpPurposeRegister) {
        await fakeAuthFlowService.verifyRegisterOtp(
          sessionId: _sessionId,
          otp: otp,
        );
        if (!mounted) return;
        await _showRegisterSuccessAndGoLogin();
        return;
      }

      if (widget.args.purpose == FakeAuthFlowService.phoneOtpPurposeLogin) {
        final result = await fakeAuthFlowService.verifyPhoneLoginOtp(
          sessionId: _sessionId,
          otp: otp,
        );
        authService.setUser(
          result.user,
          token: result.tokens.accessToken,
          refreshToken: result.tokens.refreshToken,
          accessExpiredAt: result.tokens.accessExpiredAt,
        );
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRouter.main,
          (route) => false,
        );
        return;
      }

      await fakeAuthFlowService.verifyForgotPasswordOtp(
        sessionId: _sessionId,
        otp: otp,
      );

      if (!mounted) return;
      showTopNotice(
        context,
        message: 'Đổi mật khẩu thành công. Vui lòng đăng nhập lại.',
      );
      Navigator.pushNamedAndRemoveUntil(context, AppRouter.login, (r) => false);
    } on FakeAuthException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Không thể xác thực OTP, vui lòng thử lại.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendOtp() async {
    if (_remainingSeconds > 0 || _loading) return;

    setState(() => _loading = true);
    try {
      final next = await fakeAuthFlowService.resendOtp(_sessionId);
      _sessionId = next.sessionId;
      _startCountdown(from: next.expiredAt);

      if (!mounted) return;
      showTopNotice(context, message: 'Đã gửi lại mã OTP.');
    } on FakeAuthException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showRegisterSuccessAndGoLogin() async {
    await Flushbar<void>(
      messageText: const Text(
        'Đăng ký thành công. Mời bạn đăng nhập để tiếp tục.',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
      icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
      duration: const Duration(seconds: 2),
      margin: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(14),
      backgroundGradient: const LinearGradient(
        colors: [Color(0xFF66BB6A), Color(0xFF22C55E)],
      ),
      flushbarPosition: FlushbarPosition.TOP,
    ).show(context);

    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, AppRouter.login, (r) => false);
  }

  void _showError(String message) {
    if (!mounted) return;
    showTopNotice(context, message: message, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    final isRegister =
        widget.args.purpose == FakeAuthFlowService.emailOtpPurposeRegister;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(isRegister ? 'Xác thực OTP Email' : 'OTP quên mật khẩu'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 120,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Center(
                  child: Icon(
                    Icons.mark_email_unread_outlined,
                    size: 58,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                isRegister
                  ? 'Nhập mã OTP đã gửi đến email của bạn'
                  : 'Xác minh OTP để đặt lại mật khẩu',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 8),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Mã OTP (6 số)',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _otpCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Inter',
                        letterSpacing: 5,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '------',
                        hintStyle: const TextStyle(letterSpacing: 5),
                        prefixIcon: const Icon(Icons.shield_outlined),
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
                          borderSide:
                              const BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                      ),
                      onSubmitted: (_) => _verifyOtp(),
                    ),
                    const SizedBox(height: 10),
                    const SizedBox(height: 16),
                    GradientButton(
                      label: isRegister ? 'Xác thực và tạo tài khoản' : 'Xác thực OTP',
                      loading: _loading,
                      onTap: _verifyOtp,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: (_remainingSeconds == 0 && !_loading)
                          ? _resendOtp
                          : null,
                      child: Text(
                        _remainingSeconds == 0
                            ? 'Gửi lại OTP'
                            : 'Gửi lại sau $_remainingSeconds s',
                        style: const TextStyle(fontFamily: 'Inter'),
                      ),
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
}
