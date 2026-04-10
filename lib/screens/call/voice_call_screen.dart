import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/models.dart';
import '../../widgets/common/common_widgets.dart';

class VoiceCallScreen extends StatefulWidget {
  final UserModel otherUser;
  final bool isIncoming;

  const VoiceCallScreen({super.key, required this.otherUser, this.isIncoming = false});

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> with SingleTickerProviderStateMixin {
  bool _isConnected = false;
  bool _isMuted     = false;
  bool _isSpeaker   = false;
  int  _seconds     = 0;
  Timer? _timer;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    if (!widget.isIncoming) {
      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() => _isConnected = true);
        _startTimer();
      });
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  String get _timerLabel {
    final m = _seconds ~/ 60;
    final s = _seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A0A18), Color(0xFF0D1B35), Color(0xFF0A0A18)],
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 48),
              // Status
              Text(
                _isConnected ? _timerLabel : widget.isIncoming ? 'Cuộc gọi đến...' : 'Đang gọi...',
                style: TextStyle(
                  fontSize: 18, fontFamily: 'Inter',
                  color: _isConnected ? AppColors.online : AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 40),

              // Pulsing Avatar
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, child) => Transform.scale(
                  scale: _isConnected ? 1.0 : _pulseAnim.value,
                  child: child,
                ),
                child: Container(
                  width: 110, height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary.withOpacity(0.5), width: 3),
                    boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.25), blurRadius: 30, spreadRadius: 8)],
                  ),
                  child: AvatarWidget(url: widget.otherUser.avatar, name: widget.otherUser.fullName, size: 110),
                ),
              ),

              const SizedBox(height: 24),
              Text(widget.otherUser.fullName,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontFamily: 'Inter')),
              const SizedBox(height: 6),
              Text(widget.otherUser.phone,
                  style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, fontFamily: 'Inter')),

              const Spacer(),

              // Controls
              if (_isConnected) _buildConnectedControls(),
              if (!_isConnected && widget.isIncoming) _buildIncomingControls(),
              if (!_isConnected && !widget.isIncoming) _buildCallingControls(),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectedControls() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CallBtn(
              icon: _isMuted ? Icons.mic_off : Icons.mic,
              label: _isMuted ? 'Bật mic' : 'Tắt mic',
              color: _isMuted ? AppColors.callMuted : AppColors.callMuted,
              onTap: () => setState(() => _isMuted = !_isMuted),
            ),
            const SizedBox(width: 24),
            _CallBtn(
              icon: _isSpeaker ? Icons.volume_up : Icons.volume_down,
              label: 'Loa ngoài',
              color: _isSpeaker ? AppColors.primary : AppColors.callMuted,
              onTap: () => setState(() => _isSpeaker = !_isSpeaker),
            ),
            const SizedBox(width: 24),
            _CallBtn(
              icon: Icons.keyboard,
              label: 'Bàn phím',
              color: AppColors.callMuted,
              onTap: () {},
            ),
          ],
        ),
        const SizedBox(height: 40),
        _EndCallBtn(onTap: () => Navigator.pop(context)),
      ],
    );
  }

  Widget _buildCallingControls() {
    return Column(
      children: [
        _CallBtn(icon: Icons.mic_off, label: 'Tắt mic', color: AppColors.callMuted, onTap: () => setState(() => _isMuted = !_isMuted)),
        const SizedBox(height: 40),
        _EndCallBtn(onTap: () => Navigator.pop(context)),
      ],
    );
  }

  Widget _buildIncomingControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(children: [
            _RoundCallBtn(icon: Icons.call_end, color: AppColors.callReject, size: 70,
                onTap: () => Navigator.pop(context)),
            const SizedBox(height: 8),
            const Text('Từ chối', style: TextStyle(color: AppColors.textSecondary, fontFamily: 'Inter', fontSize: 13)),
          ]),
          Column(children: [
            _RoundCallBtn(icon: Icons.call, color: AppColors.callAccept, size: 70,
                onTap: () => setState(() { _isConnected = true; _startTimer(); })),
            const SizedBox(height: 8),
            const Text('Chấp nhận', style: TextStyle(color: AppColors.textSecondary, fontFamily: 'Inter', fontSize: 13)),
          ]),
        ],
      ),
    );
  }
}

class _CallBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _CallBtn({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(children: [
      Container(
        width: 54, height: 54,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontFamily: 'Inter')),
    ]),
  );
}

class _EndCallBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _EndCallBtn({required this.onTap});

  @override
  Widget build(BuildContext context) => Column(children: [
    GestureDetector(
      onTap: onTap,
      child: Container(
        width: 70, height: 70,
        decoration: BoxDecoration(
          color: AppColors.callReject,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: AppColors.callReject.withOpacity(0.4), blurRadius: 16)],
        ),
        child: const Icon(Icons.call_end, color: Colors.white, size: 32),
      ),
    ),
    const SizedBox(height: 8),
    const Text('Kết thúc', style: TextStyle(color: AppColors.textSecondary, fontFamily: 'Inter', fontSize: 13)),
  ]);
}

class _RoundCallBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onTap;
  const _RoundCallBtn({required this.icon, required this.color, required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: size, height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 16)]),
      child: Icon(icon, color: Colors.white, size: size * 0.45),
    ),
  );
}
