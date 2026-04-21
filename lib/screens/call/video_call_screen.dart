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

class VideoCallScreen extends StatefulWidget {
  final UserModel otherUser;
  final bool isIncoming;
  final String? callId;
  final String? conversationId;
  final Map<String, dynamic>? offer;

  const VideoCallScreen({
    super.key,
    required this.otherUser,
    this.isIncoming = false,
    this.callId,
    this.conversationId,
    this.offer,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  bool _isMuted = false;
  bool _isCamOff = false;
  bool _showControls = true;
  bool _callWasConnected = false;
  int _seconds = 0;
  bool _endDialogShown = false;
  bool _screenClosing = false;
  Timer? _timer;
  Timer? _hideTimer;
  CallState _callState = CallState.idle;

  late RTCVideoRenderer _localRenderer;
  late RTCVideoRenderer _remoteRenderer;
  bool _renderersReady = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) WakelockPlus.enable();
    _initRenderers();
    callService.addStateListener(_onCallStateChanged);
    callService.onRemoteStream = (stream) {
      if (!mounted) return;
      _remoteRenderer.muted = false;
      setState(() => _remoteRenderer.srcObject = stream);
    };
    _init();
  }

  Future<void> _initRenderers() async {
    _localRenderer = RTCVideoRenderer();
    _remoteRenderer = RTCVideoRenderer();
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    if (mounted) setState(() => _renderersReady = true);
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
    if (!kIsWeb) {
      final mic = await Permission.microphone.request();
      final cam = await Permission.camera.request();
      if (mic.isDenied || cam.isDenied) {
        _showError('Cần quyền microphone và camera');
        return;
      }
    }

    if (widget.isIncoming) {
      setState(() => _callState = CallState.incoming);
    } else {
      await callService.startCall(
        conversationId: widget.conversationId ?? '',
        calleeId: widget.otherUser.id,
        isVideo: true,
      );
      // Gán local stream vào renderer
      if (callService.localStream != null) {
        _localRenderer.srcObject = callService.localStream;
      }
      setState(() => _callState = CallState.calling);
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) WakelockPlus.disable();
    _timer?.cancel();
    _hideTimer?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    callService.removeStateListener(_onCallStateChanged);
    callService.onRemoteStream = null;
    // if (_callState == CallState.calling || _callState == CallState.connected) {
    //   callService.endCall();
    // }
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _seconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
    _scheduleHideControls();
  }

  void _scheduleHideControls() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls && _callState == CallState.connected) {
      _scheduleHideControls();
    }
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
                  Icons.videocam_off_rounded,
                  color: Colors.red,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Cuộc gọi video đã kết thúc',
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
                  Navigator.pop(context);
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
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Remote Video / Placeholder ────────────────────────
            _buildRemoteView(),

            // ── Gradient overlays ─────────────────────────────────
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(0.6),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withOpacity(0.7),
                    ],
                    stops: const [0, 0.2, 0.7, 1],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),

            // ── Local preview (góc phải) ──────────────────────────
            if (_renderersReady) _buildLocalPreview(),

            // ── Top bar ───────────────────────────────────────────
            _buildTopBar(),

            // ── Bottom controls ───────────────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedSlide(
                offset: _showControls || _callState != CallState.connected
                    ? Offset.zero
                    : const Offset(0, 1),
                duration: const Duration(milliseconds: 250),
                child: _buildBottomControls(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteView() {
    if (_callState == CallState.connected &&
        _renderersReady &&
        _remoteRenderer.srcObject != null) {
      return RTCVideoView(
        _remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }

    // Placeholder khi chưa kết nối
    return Container(
      color: const Color(0xFF0A1A0A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.4),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.2),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: ClipOval(
                child: AvatarWidget(
                  url: widget.otherUser.avatar,
                  name: widget.otherUser.fullName,
                  size: 110,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.otherUser.fullName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _callState == CallState.calling
                  ? 'Đang gọi video...'
                  : _callState == CallState.incoming
                  ? 'Cuộc gọi video đến'
                  : 'Đang kết nối...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalPreview() {
    return Positioned(
      top: 100,
      right: 16,
      child: AnimatedOpacity(
        opacity: _showControls || _callState != CallState.connected ? 1.0 : 0.4,
        duration: const Duration(milliseconds: 300),
        child: Container(
          width: 90,
          height: 130,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 12),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: _isCamOff || _localRenderer.srcObject == null
                ? Container(
                    color: const Color(0xFF1A3A1A),
                    child: const Center(
                      child: Icon(
                        Icons.videocam_off_rounded,
                        color: Colors.white54,
                        size: 28,
                      ),
                    ),
                  )
                : RTCVideoView(
                    _localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final showBar = _showControls || _callState != CallState.connected;
    return AnimatedSlide(
      offset: showBar ? Offset.zero : const Offset(0, -1),
      duration: const Duration(milliseconds: 250),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Column(
                children: [
                  Text(
                    widget.otherUser.fullName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _callState == CallState.connected
                        ? _timerLabel
                        : _callState == CallState.calling
                        ? 'Đang gọi...'
                        : _callState == CallState.incoming
                        ? 'Cuộc gọi đến'
                        : 'Đang kết nối...',
                    style: TextStyle(
                      fontSize: 12,
                      color: _callState == CallState.connected
                          ? AppColors.online
                          : Colors.white54,
                      fontFamily: 'Inter',
                      fontWeight: _callState == CallState.connected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Mã hoá badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 10,
                      color: Colors.white.withOpacity(0.7),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'E2E',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withOpacity(0.7),
                        fontFamily: 'Inter',
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

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, Colors.black.withOpacity(0.85)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: _callState == CallState.incoming
          ? _buildIncomingControls()
          : _callState == CallState.connected
          ? _buildConnectedControls()
          : _buildCallingControls(),
    );
  }

  Widget _buildConnectedControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _VideoBtn(
          icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
          label: _isMuted ? 'Bật mic' : 'Tắt mic',
          isActive: _isMuted,
          activeColor: Colors.red,
          onTap: () {
            setState(() => _isMuted = !_isMuted);
            callService.toggleMute(_isMuted);
          },
        ),
        _VideoBtn(
          icon: _isCamOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
          label: _isCamOff ? 'Bật cam' : 'Tắt cam',
          isActive: _isCamOff,
          activeColor: Colors.red,
          onTap: () {
            setState(() => _isCamOff = !_isCamOff);
            callService.localStream?.getVideoTracks().forEach(
              (t) => t.enabled = !_isCamOff,
            );
          },
        ),
        // End call — lớn hơn
        GestureDetector(
          onTap: () {
            callService.endCall();
          },
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.5),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.call_end_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Kết thúc',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white70,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
        _VideoBtn(
          icon: Icons.flip_camera_ios_rounded,
          label: 'Đổi cam',
          onTap: () {
            callService.localStream?.getVideoTracks().forEach((t) {
              // ignore: invalid_use_of_protected_member
              Helper.switchCamera(t);
            });
          },
        ),
        _VideoBtn(icon: Icons.speaker_rounded, label: 'Loa', onTap: () {}),
      ],
    );
  }

  Widget _buildCallingControls() {
    return Center(
      child: GestureDetector(
        onTap: () {
          callService.endCall();
        },
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.red.withOpacity(0.5), blurRadius: 20),
                ],
              ),
              child: const Icon(
                Icons.call_end_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Huỷ',
              style: TextStyle(
                color: Colors.white70,
                fontFamily: 'Inter',
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomingControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Từ chối
        Column(
          children: [
            GestureDetector(
              onTap: () {
                callService.rejectCall(
                  callId: widget.callId ?? '',
                  conversationId: widget.conversationId ?? '',
                );
              },
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.5),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.call_end_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Từ chối',
              style: TextStyle(
                color: Colors.white70,
                fontFamily: 'Inter',
                fontSize: 13,
              ),
            ),
          ],
        ),
        // Chấp nhận
        Column(
          children: [
            GestureDetector(
              onTap: () async {
                await callService.answerCall(
                  conversationId: widget.conversationId ?? '',
                  callId: widget.callId ?? '',
                  peerId: widget.otherUser.id,
                  offer: widget.offer ?? {},
                  isVideo: true,
                );
                // Gán local stream sau khi answer
                if (callService.localStream != null && mounted) {
                  setState(() {
                    _localRenderer.srcObject = callService.localStream;
                  });
                }
              },
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.5),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.videocam_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Chấp nhận',
              style: TextStyle(
                color: Colors.white70,
                fontFamily: 'Inter',
                fontSize: 13,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Video Button ──────────────────────────────────────────────────────────────
class _VideoBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final Color activeColor;

  const _VideoBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.activeColor = Colors.red,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isActive
                  ? activeColor.withOpacity(0.25)
                  : Colors.white.withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive
                    ? activeColor.withOpacity(0.5)
                    : Colors.white.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              color: isActive ? activeColor : Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withOpacity(0.7),
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}
