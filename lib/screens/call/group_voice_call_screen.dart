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

/// Model nhỏ đại diện cho 1 participant đang trong cuộc gọi nhóm.
class GroupCallParticipant {
  final String userId;
  final String name;
  final String? avatar;
  bool isMuted;
  bool isConnected;

  GroupCallParticipant({
    required this.userId,
    required this.name,
    this.avatar,
    this.isMuted = false,
    this.isConnected = false,
  });
}

/// Màn hình gọi thoại nhóm.
///
/// Khác gọi 1-1:
/// - [participants] là danh sách tất cả thành viên (trừ bản thân).
/// - Backend nhận `start_call` với `participants` là list nhiều userId.
/// - ICE candidates & offer/answer vẫn broadcast qua conversationId room —
///   phù hợp với gateway hiện tại (client.to(conversationId)).
class GroupVoiceCallScreen extends StatefulWidget {
  /// Id của conversation nhóm.
  final String conversationId;

  /// Tên nhóm hiển thị trên header.
  final String groupName;

  /// Id của người gọi cuộc gọi nhóm.
  final String callerId;

  /// Avatar nhóm (URL).
  final String? groupAvatar;

  /// Danh sách thành viên trong nhóm (trừ bản thân).
  final List<GroupCallParticipant> participants;

  /// true = đang nhận cuộc gọi đến, false = người gọi.
  final bool isIncoming;

  /// callId từ server (chỉ có khi isIncoming == true).
  final String? callId;

  /// offer SDP (chỉ có khi isIncoming == true).
  final Map<String, dynamic>? offer;

  /// true = vào thẳng cuộc gọi đang có, không tạo call mới.
  final bool joinExistingCall;

  /// true = nhận cuộc gọi ngay khi màn hình mở.
  final bool autoAnswer;

  const GroupVoiceCallScreen({
    super.key,
    required this.conversationId,
    required this.groupName,
    required this.callerId,
    this.groupAvatar,
    required this.participants,
    this.isIncoming = false,
    this.callId,
    this.offer,
    this.joinExistingCall = false,
    this.autoAnswer = false,
  });

  @override
  State<GroupVoiceCallScreen> createState() => _GroupVoiceCallScreenState();
}

class _GroupVoiceCallScreenState extends State<GroupVoiceCallScreen>
    with SingleTickerProviderStateMixin {
  bool _isMuted = false;
  bool _isSpeaker = false;
  bool _callWasConnected = false;
  bool _endDialogShown = false;
  int _seconds = 0;
  Timer? _timer;
  CallState _callState = CallState.idle;

  late AnimationController _pulseCtrl;
  late RTCVideoRenderer _remoteRenderer;

  // Danh sách participants (reactive — sẽ cập nhật khi có người join/leave)
  late List<GroupCallParticipant> _participants;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) WakelockPlus.enable();

    _participants = List.from(widget.participants);

    _remoteRenderer = RTCVideoRenderer();
    _remoteRenderer.initialize();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    callService.onRemoteStream = (stream) {
      _remoteRenderer.srcObject = stream;
      _remoteRenderer.muted = false;
    };
    callService.addStateListener(_onCallStateChanged);
    callService.onParticipantJoined = _onParticipantJoined;
    callService.onParticipantLeft = _onParticipantLeft;
    callService.onCallStarted = _onCallStarted;
    _init();
  }

  void _onCallStateChanged(CallState state) {
    if (!mounted) return;
    setState(() => _callState = state);
    if (state == CallState.connected) {
      // ✅ Chỉ start timer lần đầu tiên
      if (!_callWasConnected) {
        _callWasConnected = true;
        _startTimer();
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

    // Lấy tên participant TRƯỚC khi xoá
    final participant = _participants.firstWhere(
      (p) => p.userId == userId,
      orElse: () => GroupCallParticipant(
        userId: '',
        name: 'Một thành viên',
        avatar: null,
      ),
    );
    final participantName = participant.name;

    // Xoá participant khỏi danh sách
    setState(() {
      _participants.removeWhere((p) => p.userId == userId);
    });

    // Hiển thị thông báo
    final msg = remainingCount >= 2
        ? '$participantName rời cuộc gọi (còn $remainingCount người)'
        : 'Cuộc gọi sắp kết thúc';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.orange.withOpacity(0.8),
      ),
    );
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
      dev.log('⏱️ Timer synced: $_seconds seconds');
    } catch (e) {
      dev.log('❌ Error parsing startedAt: $e');
    }
  }

  Future<void> _init() async {
    if (!kIsWeb) {
      final status = await Permission.microphone.request();
      if (status.isDenied) {
        _showError('Cần quyền microphone để gọi');
        return;
      }
    }

    if (widget.isIncoming) {
      if (widget.autoAnswer) {
        setState(() => _callState = CallState.calling);
        await callService.answerCall(
          conversationId: widget.conversationId,
          callId: widget.callId ?? '',
          peerId: widget.callerId,
          offer: widget.offer ?? const {},
          isVideo: false,
          isGroup: true,
        );
      } else {
        setState(() => _callState = CallState.incoming);
      }
    } else if (widget.joinExistingCall) {
      await callService.joinGroupCall(
        conversationId: widget.conversationId,
        callId: widget.callId ?? '',
        isVideo: false,
      );
      setState(() => _callState = CallState.calling);
    } else {
      // Gọi nhóm: participants là danh sách userId của tất cả thành viên.
      await callService.startGroupCall(
        conversationId: widget.conversationId,
        participantIds: widget.participants.map((p) => p.userId).toList(),
        isVideo: false,
      );
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
                  Icons.call_end_rounded,
                  color: Colors.red,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Cuộc gọi nhóm đã kết thúc',
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
              const SizedBox(height: 16),
              _buildGroupInfo(),
              const SizedBox(height: 20),
              _buildParticipantsGrid(),
              const Spacer(),
              _buildStatusLabel(),
              const SizedBox(height: 24),
              _buildControls(),
              const SizedBox(height: 48),
              // Hidden renderer để audio remote vẫn phát
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
        ],
      ),
    );
  }

  Widget _buildGroupInfo() {
    return Column(
      children: [
        // Group avatar
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.primary.withOpacity(0.5),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 3,
              ),
            ],
          ),
          child: ClipOval(
            child: widget.groupAvatar != null && widget.groupAvatar!.isNotEmpty
                ? Image.network(
                    widget.groupAvatar!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _defaultGroupAvatar(),
                  )
                : _defaultGroupAvatar(),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          widget.groupName,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            fontFamily: 'Inter',
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_participants.length + 1} người tham gia',
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withOpacity(0.6),
            fontFamily: 'Inter',
          ),
        ),
      ],
    );
  }

  Widget _defaultGroupAvatar() => Container(
    color: AppColors.bgInput,
    child: const Icon(Icons.group, color: AppColors.primary, size: 36),
  );

  /// Grid hiển thị avatar của từng participant.
  Widget _buildParticipantsGrid() {
    final connected = _participants.where((p) => p.isConnected).toList();

    if (connected.isEmpty) {
      return Text(
        'Đang chờ thành viên tham gia...',
        style: TextStyle(
          color: Colors.white.withOpacity(0.65),
          fontSize: 13,
          fontFamily: 'Inter',
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        alignment: WrapAlignment.center,
        children: connected.map((p) => _ParticipantTile(participant: p)).toList(),
      ),
    );
  }

  Widget _buildStatusLabel() {
    String text;
    Color color;
    switch (_callState) {
      case CallState.calling:
        text = 'Đang gọi nhóm...';
        color = Colors.white54;
        break;
      case CallState.incoming:
        text = 'Cuộc gọi nhóm đến';
        color = Colors.white54;
        break;
      case CallState.connected:
        text = _timerLabel;
        color = AppColors.online;
        break;
      case CallState.ended:
        text = 'Đã kết thúc';
        color = AppColors.error;
        break;
      default:
        text = 'Đang kết nối...';
        color = Colors.white54;
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_callState == CallState.connected) ...[
          Icon(Icons.call_outlined, size: 14, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          text,
          style: TextStyle(
            fontSize: 15,
            color: color,
            fontFamily: 'Inter',
            fontWeight: _callState == CallState.connected
                ? FontWeight.w600
                : FontWeight.w400,
          ),
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
            ],
          ),
        ),
        const SizedBox(height: 36),
        // ✅ Sử dụng leaveCall() thay vì endCall() cho cuộc gọi nhóm
        _EndCallButton(onTap: () {
          callService.leaveCall();
          // ✅ Pop ngay sau khi rời cuộc gọi
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) Navigator.pop(context);
          });
        }),
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
            Navigator.pop(context);
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
          Column(
            children: [
              _ActionButton(
                icon: Icons.call_end_rounded,
                color: AppColors.callReject,
                size: 68,
                onTap: () {
                  callService.rejectCall(
                    callId: widget.callId ?? '',
                    conversationId: widget.conversationId,
                  );
                  Navigator.pop(context);
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
          Column(
            children: [
              _ActionButton(
                icon: Icons.call_rounded,
                color: AppColors.callAccept,
                size: 68,
                onTap: () async {
                  await callService.answerCall(
                    conversationId: widget.conversationId,
                    callId: widget.callId ?? '',
                    peerId: widget.callerId,
                    offer: widget.offer ?? {},
                    isVideo: false,
                    isGroup: true,
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

// ── Participant tile ──────────────────────────────────────────────────────────
class _ParticipantTile extends StatelessWidget {
  final GroupCallParticipant participant;
  const _ParticipantTile({required this.participant});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: participant.isConnected
                        ? AppColors.online
                        : Colors.white24,
                    width: 2,
                  ),
                ),
                child: ClipOval(
                  child: AvatarWidget(
                    url: participant.avatar,
                    name: participant.name,
                    size: 56,
                  ),
                ),
              ),
              if (participant.isMuted)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0A1A0A),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.mic_off,
                      color: Colors.white,
                      size: 10,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            participant.name,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withOpacity(0.8),
              fontFamily: 'Inter',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────
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
            ),
          ),
        ],
      ),
    );
  }
}

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
