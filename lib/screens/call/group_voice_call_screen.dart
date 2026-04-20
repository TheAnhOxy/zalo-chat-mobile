import 'dart:async';
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
    _init();
  }

  void _onCallStateChanged(CallState state) {
    if (!mounted) return;
    setState(() => _callState = state);
    if (state == CallState.connected) {
      _callWasConnected = true;
      _startTimer();
      // Đánh dấu tất cả participants là đã kết nối (đơn giản hoá — backend
      // có thể push event chi tiết hơn nếu cần).
      setState(() {
        for (final p in _participants) {
          p.isConnected = true;
        }
      });
    }
    if (state == CallState.ended) _onCallEnded();
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
      setState(() => _callState = CallState.incoming);
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
                  Navigator.pop(context);
                  Navigator.pop(context);
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
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.keyboard_arrow_down,
                color: Colors.white.withOpacity(0.8),
              ),
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
    // Thêm bản thân vào đầu danh sách hiển thị.
    final me = GroupCallParticipant(
      userId: authService.userId ?? '',
      name: authService.currentUser?.fullName ?? 'Bạn',
      avatar: authService.currentUser?.avatar,
      isConnected: true,
      isMuted: _isMuted,
    );
    final all = [me, ..._participants];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        alignment: WrapAlignment.center,
        children: all.map((p) => _ParticipantTile(participant: p)).toList(),
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
              _ControlBtn(
                icon: Icons.dialpad_rounded,
                label: 'Bàn phím',
                onTap: () {},
              ),
            ],
          ),
        ),
        const SizedBox(height: 36),
        _EndCallButton(onTap: () => callService.endCall()),
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
