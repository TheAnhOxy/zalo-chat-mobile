import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/models.dart';
import '../../widgets/common/common_widgets.dart';

class VideoCallScreen extends StatefulWidget {
  final UserModel otherUser;
  final bool isIncoming;
  const VideoCallScreen({super.key, required this.otherUser, this.isIncoming = false});

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  bool _isConnected = false;
  bool _isMuted     = false;
  bool _isCamOff    = false;
  bool _isFrontCam  = true;
  bool _showControls = true;
  int  _seconds     = 0;
  Timer? _timer;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    if (!widget.isIncoming) {
      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() => _isConnected = true);
        _startTimer();
        _scheduleHideControls();
      });
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  void _scheduleHideControls() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHideControls();
  }

  String get _timerLabel {
    final m = _seconds ~/ 60;
    final s = _seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            // ── Remote Video (full screen — fake) ────────────────
            Container(
              color: AppColors.callBg,
              child: Center(
                child: _isCamOff
                    ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        AvatarWidget(url: widget.otherUser.avatar, name: widget.otherUser.fullName, size: 100),
                        const SizedBox(height: 16),
                        const Text('Camera đã tắt', style: TextStyle(color: AppColors.textSecondary, fontFamily: 'Inter')),
                      ])
                    : ClipRRect(
                        child: Image.network(
                          'https://picsum.photos/400/800?random=99',
                          fit: BoxFit.cover,
                          width: double.infinity, height: double.infinity,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
              ),
            ),

            // ── Gradient Overlays ─────────────────────────────────
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black.withOpacity(0.6), Colors.transparent, Colors.black.withOpacity(0.6)],
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    stops: const [0, 0.4, 1],
                  ),
                ),
              ),
            ),

            // ── Self preview (corner) ─────────────────────────────
            Positioned(
              top: 80, right: 16,
              child: AnimatedOpacity(
                opacity: _showControls || !_isConnected ? 1 : 0.3,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  width: 90, height: 130,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12)],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _isCamOff
                        ? Center(child: AvatarWidget(url: null, name: 'Me', size: 40))
                        : Container(color: AppColors.bgCardLight,
                            child: const Center(child: Icon(Icons.person, color: AppColors.textSecondary, size: 40))),
                  ),
                ),
              ),
            ),

            // ── Top Bar ───────────────────────────────────────────
            AnimatedSlide(
              offset: _showControls || !_isConnected ? Offset.zero : const Offset(0, -1),
              duration: const Duration(milliseconds: 300),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), shape: BoxShape.circle),
                          child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                        ),
                      ),
                      const Spacer(),
                      Column(children: [
                        Text(widget.otherUser.fullName,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white, fontFamily: 'Inter')),
                        Text(
                          _isConnected ? _timerLabel : widget.isIncoming ? 'Cuộc gọi video đến' : 'Đang kết nối...',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontFamily: 'Inter'),
                        ),
                      ]),
                      const Spacer(),
                      const SizedBox(width: 36),
                    ],
                  ),
                ),
              ),
            ),

            // ── Bottom Controls ───────────────────────────────────
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: AnimatedSlide(
                offset: _showControls || !_isConnected ? Offset.zero : const Offset(0, 1),
                duration: const Duration(milliseconds: 300),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    ),
                  ),
                  child: _isConnected
                      ? _buildConnectedControls()
                      : widget.isIncoming
                          ? _buildIncomingControls()
                          : _buildCallingControls(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _VideoCallBtn(
          icon: _isMuted ? Icons.mic_off : Icons.mic,
          label: _isMuted ? 'Bật mic' : 'Mic',
          color: _isMuted ? AppColors.callReject.withOpacity(0.8) : Colors.white.withOpacity(0.2),
          onTap: () => setState(() => _isMuted = !_isMuted),
        ),
        _VideoCallBtn(
          icon: _isCamOff ? Icons.videocam_off : Icons.videocam,
          label: _isCamOff ? 'Bật cam' : 'Camera',
          color: _isCamOff ? AppColors.callReject.withOpacity(0.8) : Colors.white.withOpacity(0.2),
          onTap: () => setState(() => _isCamOff = !_isCamOff),
        ),
        // End call (center, bigger)
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 64, height: 64,
            decoration: BoxDecoration(color: AppColors.callReject, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.callReject.withOpacity(0.5), blurRadius: 16)]),
            child: const Icon(Icons.call_end, color: Colors.white, size: 30),
          ),
        ),
        _VideoCallBtn(
          icon: Icons.flip_camera_ios,
          label: 'Đổi cam',
          color: Colors.white.withOpacity(0.2),
          onTap: () => setState(() => _isFrontCam = !_isFrontCam),
        ),
        _VideoCallBtn(
          icon: Icons.more_horiz,
          label: 'Thêm',
          color: Colors.white.withOpacity(0.2),
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildCallingControls() => Center(
    child: GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 64, height: 64,
        decoration: BoxDecoration(color: AppColors.callReject, shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: AppColors.callReject.withOpacity(0.5), blurRadius: 16)]),
        child: const Icon(Icons.call_end, color: Colors.white, size: 30),
      ),
    ),
  );

  Widget _buildIncomingControls() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      Column(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(width: 64, height: 64,
              decoration: BoxDecoration(color: AppColors.callReject, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.callReject.withOpacity(0.4), blurRadius: 16)]),
              child: const Icon(Icons.call_end, color: Colors.white, size: 30)),
        ),
        const SizedBox(height: 8),
        const Text('Từ chối', style: TextStyle(color: Colors.white70, fontFamily: 'Inter', fontSize: 13)),
      ]),
      Column(children: [
        GestureDetector(
          onTap: () => setState(() { _isConnected = true; _startTimer(); _scheduleHideControls(); }),
          child: Container(width: 64, height: 64,
              decoration: BoxDecoration(color: AppColors.callAccept, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.callAccept.withOpacity(0.4), blurRadius: 16)]),
              child: const Icon(Icons.videocam, color: Colors.white, size: 30)),
        ),
        const SizedBox(height: 8),
        const Text('Chấp nhận', style: TextStyle(color: Colors.white70, fontFamily: 'Inter', fontSize: 13)),
      ]),
    ],
  );
}

class _VideoCallBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _VideoCallBtn({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 48, height: 48,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 22)),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70, fontFamily: 'Inter')),
    ]),
  );
}
