import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../navigation/app_router.dart';
import '../../services/auth_service.dart';
import '../../services/fake_auth_flow_service.dart';
import '../../widgets/common/top_notice.dart';

class LoginChallengeWaitingArguments {
  final String challengeId;
  final String email;
  final DateTime challengeExpiredAt;

  const LoginChallengeWaitingArguments({
    required this.challengeId,
    required this.email,
    required this.challengeExpiredAt,
  });
}

class LoginChallengeWaitingScreen extends StatefulWidget {
  final LoginChallengeWaitingArguments args;

  const LoginChallengeWaitingScreen({super.key, required this.args});

  @override
  State<LoginChallengeWaitingScreen> createState() =>
      _LoginChallengeWaitingScreenState();
}

class _LoginChallengeWaitingScreenState
    extends State<LoginChallengeWaitingScreen> {
  Timer? _pollTimer;
  bool _polling = true;
  bool _checking = false;
  String _statusText = 'Đang chờ bạn xác nhận trong email...';

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  void _startPolling() {
    _checkStatus();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkStatus();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _polling = false;
  }

  Future<void> _checkStatus() async {
    if (!_polling || _checking) return;

    if (DateTime.now().isAfter(widget.args.challengeExpiredAt)) {
      _setExpired();
      return;
    }

    _checking = true;
    try {
      final result = await fakeAuthFlowService.getLoginChallengeStatus(
        widget.args.challengeId,
      );

      if (!mounted || !_polling) return;

      if (result.isPending) {
        setState(() {
          _statusText = 'Đang chờ bạn xác nhận trong email...';
        });
        return;
      }

      if (result.isConsumed && result.loginResult != null) {
        setState(() {
          _statusText = 'Đăng nhập đã được xác nhận, đang vào hệ thống...';
        });

        final login = result.loginResult!;
        authService.setUser(
          login.user,
          token: login.tokens.accessToken,
          refreshToken: login.tokens.refreshToken,
          accessExpiredAt: login.tokens.accessExpiredAt,
        );

        _stopPolling();
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, AppRouter.main, (_) => false);
        return;
      }

      setState(() {
        _statusText = 'Đang kiểm tra xác nhận đăng nhập...';
      });
    } on FakeAuthException catch (e) {
      if (!mounted || !_polling) return;
      final upper = e.message.toUpperCase();
      if (upper.contains('LOGIN_CHALLENGE_REJECTED') ||
          upper.contains('REJECTED')) {
        _setRejected();
      } else if (upper.contains('LOGIN_CHALLENGE_INVALID_OR_EXPIRED') ||
          upper.contains('EXPIRED') ||
          e.message.toLowerCase().contains('het han')) {
        _setExpired();
      } else {
        setState(() {
          _statusText = 'Không thể kiểm tra xác nhận, đang thử lại...';
        });
      }
    } finally {
      _checking = false;
    }
  }

  void _setRejected() {
    _stopPolling();
    setState(() {
      _statusText = 'Yêu cầu đăng nhập bị từ chối.';
    });
    showTopNotice(context, message: _statusText, isError: true);
  }

  void _setExpired() {
    _stopPolling();
    setState(() {
      _statusText = 'Yêu cầu đã hết hạn.';
    });
    showTopNotice(context, message: _statusText, isError: true);
  }

  void _cancelAndBack() {
    _stopPolling();
    Navigator.pushNamedAndRemoveUntil(context, AppRouter.login, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final left = widget.args.challengeExpiredAt.difference(now).inSeconds;
    final leftSec = left < 0 ? 0 : left;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgDark,
        elevation: 0,
        title: const Text('Xác nhận đăng nhập qua email'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.mark_email_unread_outlined,
                  color: AppColors.primary, size: 34),
              const SizedBox(height: 12),
              const Text(
                'Đang chờ bạn xác nhận trong email',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Email nhận xác nhận: ${widget.args.email}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Thời gian còn lại: ${leftSec}s',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _statusText,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _cancelAndBack,
                  child: const Text('Hủy và quay lại đăng nhập'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
