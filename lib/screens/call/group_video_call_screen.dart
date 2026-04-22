import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/constants/app_colors.dart';
import '../../services/call_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/common/common_widgets.dart';
import 'group_voice_call_screen.dart' show GroupCallParticipant;

/// Màn hình gọi video nhóm.
///
/// Kiến trúc hiện tại vẫn dùng mesh P2P đơn giản (1 RTCPeerConnection cho
/// toàn room). Để hỗ trợ video nhiều chiều thực sự cần SFU/MCU — nhưng UI
/// đã chuẩn bị sẵn grid cho từng participant.
class GroupVideoCallScreen extends StatefulWidget {
  final String conversationId;
  final String groupName;
  final String callerId;
  final String? groupAvatar;
  final List<GroupCallParticipant> participants;
  final bool isIncoming;
  final String? callId;
  final Map<String, dynamic>? offer;

  const GroupVideoCallScreen({
    super.key,
    required this.conversationId,
    required this.groupName,
    required this.callerId,
    this.groupAvatar,
    required this.participants,
    this.isIncoming = false,
    this.callId,
    this.offer,
  });

  @override
  State<GroupVideoCallScreen> createState() => _GroupVideoCallScreenState();
}

class _GroupVideoCallScreenState extends State<GroupVideoCallScreen> {
  bool _isMuted = false;
  bool _isCamOff = false;
  bool _showControls = true;
  bool _callWasConnected = false;
  bool _endDialogShown = false;
  int _seconds = 0;
  Timer? _timer;
  Timer? _hideTimer;
  CallState _callState = CallState.idle;

  late RTCVideoRenderer _localRenderer;
  late RTCVideoRenderer _remoteRenderer;
  bool _renderersReady = false;
  MediaStream? _pendingRemoteStream;

  late List<GroupCallParticipant> _participants;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) WakelockPlus.enable();
    _participants = List.from(widget.participants);
    _initRenderers();
    callService.addStateListener(_onCallStateChanged);
    callService.onRemoteStream = (stream) {
      if (!mounted) return;
      if (!_renderersReady) {
        _pendingRemoteStream = stream;
        return;
      }
      setState(() {
        _remoteRenderer
          ..srcObject = stream
          ..muted = false;
      });
    };
    callService.onParticipantJoined = _onParticipantJoined;
    callService.onParticipantLeft = _onParticipantLeft;
    callService.onCallStarted = _onCallStarted;
    _init();
  }

  Future<void> _initRenderers() async {
    _localRenderer = RTCVideoRenderer();
    _remoteRenderer = RTCVideoRenderer();
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    if (!mounted) return;

    if (callService.localStream != null) {
      _localRenderer.srcObject = callService.localStream;
    }

    final remote = _pendingRemoteStream ?? callService.remoteStream;
    if (remote != null) {
      _remoteRenderer.srcObject = remote;
      _remoteRenderer.muted = false;
      _pendingRemoteStream = null;
    }

    setState(() => _renderersReady = true);
  }

  void _onCallStateChanged(CallState state) {
    if (!mounted) return;
    setState(() => _callState = state);
    if (state == CallState.connected) {
      // ✅ Chỉ start timer lần đầu tiên
      if (!_callWasConnected) {
        _callWasConnected = true;
        _startTimer();
        _scheduleHideControls();
      }
    }
    if (state == CallState.ended) _onCallEnded();
  }

  void _onParticipantJoined(Map<String, dynamic> data) {
    if (!mounted) return;
    final userId = data['userId']?.toString() ?? '';
    if (userId.isEmpty) return;

    final myId = authService.userId;
    if (myId != null && userId == myId) return;

    final idx = _participants.indexWhere((p) => p.userId == userId);
    if (idx >= 0) {
      setState(() {
        _participants[idx].isConnected = true;
      });
    }
  }

  // ✅ Đồng bộ timer từ server
  void _onCallStarted(Map<String, dynamic> data) {
    if (!mounted) return;
    final startedAt = data['startedAt']?.toString() ?? '';
    if (startedAt.isEmpty) return;

    try {
      final startTime = DateTime.parse(startedAt).millisecondsSinceEpoch;
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsedSeconds = ((now - startTime) / 1000).round();

      if (mounted) {
        setState(() {
          _seconds = elapsedSeconds > 0 ? elapsedSeconds : 0;
        });
      }
    } catch (e) {
      dev.log('❌ Error parsing startedAt: $e');
    }
  }

  // ✅ Xử lý khi có người rời khỏi cuộc gọi nhóm
  void _onParticipantLeft(Map<String, dynamic> data) {
    if (!mounted) return;
    final userId = data['userId']?.toString() ?? '';
    final remainingCount = data['activeParticipantsCount'] as int? ?? 0;
    final authService = AuthService();

    // ✅ Không hiển thị thông báo nếu chính BẠN vừa thoát
    if (userId == authService.userId) {
      setState(() {
        _participants.removeWhere((p) => p.userId == userId);
      });
      return;
    }

    setState(() {
      _participants.removeWhere((p) => p.userId == userId);
    });

    final msg = remainingCount >= 2
        ? 'Một thành viên rời cuộc gọi (còn $remainingCount người)'
        : 'Cuộc gọi sắp kết thúc';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.orange.withOpacity(0.8),
      ),
    );
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
      await callService.startGroupCall(
        conversationId: widget.conversationId,
        participantIds: widget.participants.map((p) => p.userId).toList(),
        isVideo: true,
      );
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
    callService.onParticipantJoined = null;
    callService.onParticipantLeft = null;
    callService.onCallStarted = null;
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _seconds = 0;
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
    if (_showControls && _callState == CallState.connected)
      _scheduleHideControls();
  }

  String get _timerLabel {
    final m = _seconds ~/ 60;
    final s = _seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _onCallEnded() {
    if (_endDialogShown) return;
    _endDialogShown = true;
    _timer?.cancel();
    if (!mounted) return;

    if (_callWasConnected) {
      // ✅ Auto-dismiss dialog sau 1.5s thay vì chờ người dùng click OK
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
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
                'Cuộc gọi video nhóm đã kết thúc',
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
                  Navigator.pop(dialogContext); // Đóng dialog
                  Navigator.pop(context); // Quay lại màn hình chat
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
      // ✅ Auto-dismiss sau 1.5s
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context); // Đóng dialog
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted && Navigator.canPop(context)) {
              Navigator.pop(context); // Quay lại màn hình chat
            }
          });
        }
      });
    } else {
      Navigator.pop(context);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    Navigator.pop(context);
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
            // ── Background / remote view ──────────────────────
            _buildBackground(),

            // ── Gradient overlays ─────────────────────────────
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(0.65),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withOpacity(0.75),
                    ],
                    stops: const [0, 0.2, 0.7, 1],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),

            // ── Local preview (bottom-right) ──────────────────
            if (_renderersReady) _buildLocalPreview(),

            // ── Participants strip (bottom of video area) ─────
            if (_callState == CallState.connected) _buildParticipantsStrip(),

            // ── Top bar ───────────────────────────────────────
            _buildTopBar(),

            // ── Bottom controls ───────────────────────────────
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

  Widget _buildBackground() {
    // Hot-reload-safe sync: if callback missed, still bind latest remote stream.
    if (_renderersReady && _remoteRenderer.srcObject == null) {
      final latestRemote = callService.remoteStream;
      if (latestRemote != null) {
        _remoteRenderer.srcObject = latestRemote;
        _remoteRenderer.muted = false;
      }
    }

    if (_callState == CallState.connected &&
        _renderersReady &&
        _remoteRenderer.srcObject != null) {
      return RTCVideoView(
        _remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }
    // Placeholder: tên nhóm + avatar
    return Container(
      color: const Color(0xFF0A1A0A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
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
                child:
                    widget.groupAvatar != null && widget.groupAvatar!.isNotEmpty
                    ? Image.network(
                        widget.groupAvatar!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _defaultGroupAvatar(),
                      )
                    : _defaultGroupAvatar(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.groupName,
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
                  ? 'Đang gọi video nhóm...'
                  : _callState == CallState.incoming
                  ? 'Cuộc gọi video nhóm đến'
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

  Widget _defaultGroupAvatar() => Container(
    color: AppColors.bgInput,
    child: const Icon(Icons.group, color: AppColors.primary, size: 44),
  );

  /// Thumbnail nhỏ của bản thân góc dưới phải.
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

  /// Hàng nhỏ hiển thị avatar của các participant (khi đã connected).
  Widget _buildParticipantsStrip() {
    final connected = _participants.where((p) => p.isConnected).toList();
    if (connected.isEmpty) return const SizedBox.shrink();

    return Positioned(
      bottom: 140,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: SizedBox(
          height: 70,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: connected.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final p = connected[i];
              return Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: p.isConnected
                                ? AppColors.online
                                : Colors.white24,
                            width: 2,
                          ),
                        ),
                        child: ClipOval(
                          child: AvatarWidget(
                            url: p.avatar,
                            name: p.name,
                            size: 44,
                          ),
                        ),
                      ),
                      if (p.isMuted)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.black,
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.mic_off,
                              color: Colors.white,
                              size: 9,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    p.name.split(' ').first,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withOpacity(0.8),
                      fontFamily: 'Inter',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              );
            },
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
              const SizedBox(width: 38, height: 38),
              const Spacer(),
              Column(
                children: [
                  Text(
                    widget.groupName,
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
        GestureDetector(
          // ✅ Sử dụng leaveCall() thay vì endCall() cho cuộc gọi nhóm
          onTap: () {
            callService.leaveCall();
            // ✅ Pop ngay sau khi rời cuộc gọi
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) Navigator.pop(context);
            });
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
        _VideoBtn(
          icon: Icons.people_outline_rounded,
          label: '${_participants.where((p) => p.isConnected).length + 1} người',
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildCallingControls() {
    return Center(
      child: GestureDetector(
        onTap: () {
          callService.endCall();
          Navigator.pop(context);
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
        Column(
          children: [
            GestureDetector(
              onTap: () {
                callService.rejectCall(
                  callId: widget.callId ?? '',
                  conversationId: widget.conversationId,
                );
                Navigator.pop(context);
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
        Column(
          children: [
            GestureDetector(
              onTap: () async {
                await callService.answerCall(
                  conversationId: widget.conversationId,
                  callId: widget.callId ?? '',
                  peerId: widget.callerId,
                  offer: widget.offer ?? {},
                  isVideo: true,
                  isGroup: true,
                );
                if (callService.localStream != null && mounted) {
                  setState(
                    () => _localRenderer.srcObject = callService.localStream,
                  );
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
