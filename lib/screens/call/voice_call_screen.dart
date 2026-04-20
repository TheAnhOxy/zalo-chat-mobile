import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/models.dart';
import '../../services/call_service.dart';
import '../../widgets/common/common_widgets.dart';

class VoiceCallScreen extends StatefulWidget {
  final UserModel otherUser;
  final bool isIncoming;
  final String? callId;
  final String? conversationId;
  final Map<String, dynamic>? offer;

  const VoiceCallScreen({
    super.key,
    required this.otherUser,
    this.isIncoming = false,
    this.callId,
    this.conversationId,
    this.offer,
  });

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with SingleTickerProviderStateMixin {
  bool _isMuted = false;
  bool _isSpeaker = false;
  bool _callWasConnected = false;
  bool _endDialogShown = false;
  bool _screenClosing = false;
  int _seconds = 0;
  Timer? _timer;
  CallState _callState = CallState.idle;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late RTCVideoRenderer _remoteRenderer;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) WakelockPlus.enable();

    _remoteRenderer = RTCVideoRenderer();
    _remoteRenderer.initialize();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    callService.onRemoteStream = _onRemoteStream;
    callService.addStateListener(_onCallStateChanged);
    _init();
  }

  void _onRemoteStream(MediaStream stream) {
    print('🎵 VoiceCallScreen received remote stream');
    _remoteRenderer.srcObject = stream;
    _remoteRenderer.muted = false;
  }

  void _onCallStateChanged(CallState state) {
    if (!mounted) return;
    setState(() => _callState = state);
    if (state == CallState.connected) {
      _callWasConnected = true;
      _startTimer();
    }
    if (state == CallState.ended) _onCallEnded();
  }

  Future<void> _init() async {
    print('🎯 VoiceCallScreen _init called, isIncoming: ${widget.isIncoming}');
    if (!kIsWeb) {
      final status = await Permission.microphone.request();
      if (status.isDenied) {
        print('❌ Microphone permission denied');
        _showError('Cần quyền microphone để gọi');
        return;
      }
    }
    if (widget.isIncoming) {
      print('📞 Incoming call, setting state to incoming');
      setState(() => _callState = CallState.incoming);
    } else {
      print('📞 Outgoing call, starting call');
      await callService.startCall(
        conversationId: widget.conversationId ?? '',
        calleeId: widget.otherUser.id,
        isVideo: false,
      );
      print('📞 Outgoing call initiated, setting state to calling');
      setState(() => _callState = CallState.calling);
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) WakelockPlus.disable();
    _pulseCtrl.dispose();
    _remoteRenderer.dispose();
    _timer?.cancel();
    callService.removeStateListener(_onCallStateChanged);
    // if (_callState == CallState.calling || _callState == CallState.connected) {
    //   callService.endCall();
    // }
    super.dispose();
  }

  void _startTimer() {
    print('⏱️ Starting timer');
    _timer?.cancel();
    _seconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _seconds++);
        print('⏱️ Timer tick: $_seconds seconds');
      }
    });
  }

  String get _timerLabel {
    final m = _seconds ~/ 60;
    final s = _seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _closeCallScreen() {
    if (_screenClosing || !mounted) return;
    _screenClosing = true;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _onCallEnded() {
    if (_endDialogShown) return;
    _endDialogShown = true;

    _timer?.cancel();
    if (!mounted) return;

    // ✅ Chỉ hiện dialog nếu đã từng kết nối
    if (_callWasConnected) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A3A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.call_end_rounded,
                  color: Colors.red,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Cuộc gọi đã kết thúc',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Thời lượng: $_timerLabel',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 14,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  Navigator.pop(context); // đóng dialog
                  _closeCallScreen();
                },
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(color: Colors.white, fontFamily: 'Inter'),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      _closeCallScreen();
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    _closeCallScreen();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C1A),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.3),
            radius: 1.2,
            colors: [Color(0xFF1A3A1A), Color(0xFF0A1A0A)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              const Spacer(flex: 2),
              _buildAvatar(),
              const SizedBox(height: 20),
              _buildNameAndStatus(),
              const Spacer(flex: 3),
              _buildControls(),
              const SizedBox(height: 48),
              SizedBox(
                width: 1,
                height: 1,
                child: RTCVideoView(_remoteRenderer),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          // Mã hóa badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 12,
                  color: Colors.white.withOpacity(0.7),
                ),
                const SizedBox(width: 4),
                Text(
                  'Mã hoá đầu cuối',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.7),
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final isConnected = _callState == CallState.connected;
    final isPulsing =
        _callState == CallState.calling || _callState == CallState.incoming;

    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer glow ring (pulsing)
            if (isPulsing)
              Transform.scale(
                scale: _pulseAnim.value * 1.3,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.15),
                      width: 1,
                    ),
                  ),
                ),
              ),
            // Middle ring
            if (isPulsing)
              Transform.scale(
                scale: _pulseAnim.value * 1.15,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.25),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            // Avatar
            Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isConnected
                      ? AppColors.online.withOpacity(0.6)
                      : AppColors.primary.withOpacity(0.5),
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isConnected ? AppColors.online : AppColors.primary)
                        .withOpacity(0.3),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: ClipOval(
                child: AvatarWidget(
                  url: widget.otherUser.avatar,
                  name: widget.otherUser.fullName,
                  size: 130,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNameAndStatus() {
    String statusText;
    Color statusColor;
    IconData? statusIcon;

    switch (_callState) {
      case CallState.calling:
        statusText = 'Đang gọi...';
        statusColor = Colors.white54;
        statusIcon = null;
        break;
      case CallState.incoming:
        statusText = 'Cuộc gọi thoại';
        statusColor = Colors.white54;
        statusIcon = Icons.call_outlined;
        break;
      case CallState.connected:
        statusText = _timerLabel;
        statusColor = AppColors.online;
        statusIcon = Icons.call_outlined;
        break;
      case CallState.ended:
        statusText = 'Đã kết thúc';
        statusColor = AppColors.error;
        statusIcon = null;
        break;
      default:
        statusText = 'Đang kết nối...';
        statusColor = Colors.white54;
        statusIcon = null;
    }

    return Column(
      children: [
        Text(
          widget.otherUser.fullName,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            fontFamily: 'Inter',
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (statusIcon != null) ...[
              Icon(statusIcon, size: 14, color: statusColor),
              const SizedBox(width: 4),
            ],
            Text(
              statusText,
              style: TextStyle(
                fontSize: 15,
                color: statusColor,
                fontFamily: 'Inter',
                fontWeight: _callState == CallState.connected
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildControls() {
    switch (_callState) {
      case CallState.connected:
        return _buildConnectedControls();
      case CallState.incoming:
        return _buildIncomingControls();
      default:
        return _buildCallingControls();
    }
  }

  Widget _buildConnectedControls() {
    return Column(
      children: [
        // Control buttons row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ControlBtn(
                icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                label: _isMuted ? 'Bật mic' : 'Tắt mic',
                isActive: _isMuted,
                activeColor: AppColors.error,
                onTap: () {
                  setState(() => _isMuted = !_isMuted);
                  callService.toggleMute(_isMuted);
                },
              ),
              _ControlBtn(
                icon: _isSpeaker
                    ? Icons.volume_up_rounded
                    : Icons.volume_down_rounded,
                label: 'Loa ngoài',
                isActive: _isSpeaker,
                activeColor: AppColors.primary,
                onTap: () {
                  setState(() => _isSpeaker = !_isSpeaker);
                  callService.toggleSpeaker(_isSpeaker);
                },
              ),
              _ControlBtn(
                icon: Icons.dialpad_rounded,
                label: 'Bàn phím',
                onTap: () {},
              ),
            ],
          ),
        ),
        const SizedBox(height: 36),
        _EndCallButton(
          onTap: () {
            callService.endCall();
          },
        ),
      ],
    );
  }

  Widget _buildCallingControls() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ControlBtn(
                icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                label: _isMuted ? 'Bật mic' : 'Tắt mic',
                isActive: _isMuted,
                activeColor: AppColors.error,
                onTap: () {
                  setState(() => _isMuted = !_isMuted);
                  callService.toggleMute(_isMuted);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 36),
        _EndCallButton(
          onTap: () {
            callService.endCall();
          },
        ),
      ],
    );
  }

  Widget _buildIncomingControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 60),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Reject
          Column(
            children: [
              _ActionButton(
                icon: Icons.call_end_rounded,
                color: AppColors.callReject,
                size: 68,
                onTap: () {
                  callService.rejectCall(
                    callId: widget.callId ?? '',
                    conversationId: widget.conversationId ?? '',
                  );
                },
              ),
              const SizedBox(height: 10),
              Text(
                'Từ chối',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          // Accept
          Column(
            children: [
              _ActionButton(
                icon: Icons.call_rounded,
                color: AppColors.callAccept,
                size: 68,
                onTap: () async {
                  await callService.answerCall(
                    conversationId: widget.conversationId ?? '',
                    callId: widget.callId ?? '',
                    peerId: widget.otherUser.id,
                    offer: widget.offer ?? {},
                    isVideo: false,
                  );
                },
              ),
              const SizedBox(height: 10),
              Text(
                'Chấp nhận',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Control Button (tròn nhỏ có label) ───────────────────────────────────────
class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final Color activeColor;

  const _ControlBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.activeColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: isActive
                  ? activeColor.withOpacity(0.2)
                  : Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive
                    ? activeColor.withOpacity(0.5)
                    : Colors.white.withOpacity(0.15),
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              color: isActive ? activeColor : Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.7),
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

// ── End Call Button ───────────────────────────────────────────────────────────
class _EndCallButton extends StatelessWidget {
  final VoidCallback onTap;
  const _EndCallButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: AppColors.callReject,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.callReject.withOpacity(0.5),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.call_end_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Kết thúc',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ── Action Button (incoming call) ─────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.42),
      ),
    );
  }
}
