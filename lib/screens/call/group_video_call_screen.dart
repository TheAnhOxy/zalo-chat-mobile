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
  /// true = vào thẳng cuộc gọi đang có, không tạo call mới.
  final bool joinExistingCall;
  /// true = nhận cuộc gọi ngay khi màn hình mở.
  final bool autoAnswer;

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
    this.joinExistingCall = false,
    this.autoAnswer = false,
  });

  @override
  State<GroupVideoCallScreen> createState() => _GroupVideoCallScreenState();
}

class _GroupVideoCallScreenState extends State<GroupVideoCallScreen> {
  bool _isMuted = false;
  bool _isCamOff = false;
  bool _isSpeakerOn = true;
  bool _showControls = true;
  bool _callWasConnected = false;
  bool _endDialogShown = false;
  int _seconds = 0;
  Timer? _timer;
  Timer? _hideTimer;
  CallState _callState = CallState.idle;

  late RTCVideoRenderer _localRenderer;
  late RTCVideoRenderer _remoteRenderer;
  final Map<String, RTCVideoRenderer> _peerRenderers = {};
  final Map<String, MediaStream> _peerStreams = {};
  bool _renderersReady = false;
  MediaStream? _pendingRemoteStream;
  MediaStream? _pendingLocalStream;

  late List<GroupCallParticipant> _participants;

  String _peerKey(String? id) => (id ?? '').trim();

  List<GroupCallParticipant> get _remoteParticipants {
    final myId = _peerKey(authService.userId);
    final seen = <String>{};
    final result = <GroupCallParticipant>[];

    for (final p in _participants) {
      final id = _peerKey(p.userId);
      if (id.isEmpty || id == myId || !seen.add(id)) continue;
      if (p.isConnected ||
          _peerStreams.containsKey(id) ||
          _peerRenderers.containsKey(id)) {
        result.add(p);
      }
    }

    for (final id in _peerStreams.keys) {
      if (id == myId || !seen.add(id)) continue;
      final ref = _participants.firstWhere(
        (p) => _peerKey(p.userId) == id,
        orElse: () => GroupCallParticipant(
          userId: id,
          name: 'Thành viên',
          avatar: '',
          isConnected: true,
        ),
      );
      result.add(ref);
    }

    return result;
  }

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) WakelockPlus.enable();
    _participants = List.from(widget.participants);
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
    callService.onLocalStream = _bindLocalToRenderer;
    callService.onPeerRemoteStream = _onPeerRemoteStream;
    callService.onParticipantJoined = _onParticipantJoined;
    callService.onParticipantLeft = _onParticipantLeft;
    callService.onCallStarted = _onCallStarted;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _initRenderers();
    if (!mounted) return;
    await _init();
  }

  void _bindLocalToRenderer(MediaStream stream) {
    if (!mounted) return;
    if (!_renderersReady) {
      _pendingLocalStream = stream;
      return;
    }
    if (_localRenderer.srcObject?.id != stream.id) {
      _localRenderer.srcObject = null;
      _localRenderer.srcObject = stream;
    }
    setState(() {});
  }

  void _bindLocalFromCallService() {
    final stream = callService.localStream;
    if (stream != null) _bindLocalToRenderer(stream);
  }

  bool get _hasLocalVideo {
    if (_isCamOff) return false;
    final stream = _localRenderer.srcObject ?? callService.localStream;
    return stream?.getVideoTracks().any((t) => t.enabled) ?? false;
  }

  Future<void> _onPeerRemoteStream(String peerId, MediaStream stream) async {
    final key = _peerKey(peerId);
    if (!mounted || key.isEmpty) return;

    dev.log('[GroupVideo] remote stream from $key tracks=${stream.getTracks().map((t) => t.kind).toList()}');

    RTCVideoRenderer renderer;
    if (_peerRenderers.containsKey(key)) {
      renderer = _peerRenderers[key]!;
    } else {
      renderer = RTCVideoRenderer();
      await renderer.initialize();
      _peerRenderers[key] = renderer;
    }

    final mergedStream = _peerStreams.putIfAbsent(key, () => stream);
    if (!identical(mergedStream, stream)) {
      for (final track in stream.getTracks()) {
        final sameKind =
            mergedStream.getTracks().where((t) => t.kind == track.kind).toList();
        for (final old in sameKind) {
          await mergedStream.removeTrack(old);
        }
        if (!mergedStream.getTracks().any((t) => t.id == track.id)) {
          await mergedStream.addTrack(track);
        }
      }
    }

    renderer
      ..srcObject = null
      ..srcObject = mergedStream
      ..muted = false;

    if (!kIsWeb) {
      callService.toggleSpeaker(_isSpeakerOn);
    }

    final idx = _participants.indexWhere((p) => _peerKey(p.userId) == key);
    if (idx >= 0) {
      _participants[idx].isConnected = true;
    } else {
      _participants.add(GroupCallParticipant(
        userId: key,
        name: 'Thành viên',
        avatar: '',
        isConnected: true,
      ));
    }

    if (!_callWasConnected) {
      _callWasConnected = true;
      _startTimer();
    }
    if (_callState != CallState.connected && mounted) {
      setState(() => _callState = CallState.connected);
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _initRenderers() async {
    _localRenderer = RTCVideoRenderer();
    _remoteRenderer = RTCVideoRenderer();
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    if (!mounted) return;

    final local = _pendingLocalStream ?? callService.localStream;
    if (local != null) {
      _localRenderer.srcObject = local;
      _pendingLocalStream = null;
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
    if (state == CallState.calling || state == CallState.connected) {
      _bindLocalFromCallService();
    }
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
    final userId = _peerKey(data['userId']?.toString());
    if (userId.isEmpty) return;

    final myId = _peerKey(authService.userId);
    if (myId.isNotEmpty && userId == myId) return;

    final idx = _participants.indexWhere((p) => _peerKey(p.userId) == userId);
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

    final key = _peerKey(userId);
    setState(() {
      final renderer = _peerRenderers.remove(key);
      renderer?.srcObject = null;
      renderer?.dispose();
      _peerStreams.remove(key);
      _participants.removeWhere((p) => _peerKey(p.userId) == key);
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
      callService.toggleSpeaker(_isSpeakerOn);
    }

    if (widget.isIncoming) {
      if (widget.autoAnswer) {
        setState(() => _callState = CallState.calling);
        await callService.answerCall(
          conversationId: widget.conversationId,
          callId: widget.callId ?? '',
          peerId: widget.callerId,
          offer: widget.offer ?? const {},
          isVideo: true,
          isGroup: true,
        );
        _bindLocalFromCallService();
      } else {
        setState(() => _callState = CallState.incoming);
      }
    } else if (widget.joinExistingCall) {
      await callService.joinGroupCall(
        conversationId: widget.conversationId,
        callId: widget.callId ?? '',
        isVideo: true,
      );
      _bindLocalFromCallService();
      setState(() => _callState = CallState.calling);
    } else {
      final callId = await callService.startGroupCall(
        conversationId: widget.conversationId,
        participantIds: widget.participants.map((p) => p.userId).toList(),
        isVideo: true,
      );
      if (callId == null) {
        _showError('Không thể bắt đầu cuộc gọi nhóm');
        return;
      }
      _bindLocalFromCallService();
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
    for (final r in _peerRenderers.values) {
      r.srcObject = null;
      r.dispose();
    }
    _peerRenderers.clear();
    _peerStreams.clear();
    callService.removeStateListener(_onCallStateChanged);
    callService.onRemoteStream = null;
    callService.onLocalStream = null;
    callService.onPeerRemoteStream = null;
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
    setState(() => _showControls = true);
    if (_callState == CallState.connected) {
      _scheduleHideControls();
    }
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

  bool _peerHasVideo(String userId) {
    final key = _peerKey(userId);
    final stream = _peerStreams[key] ?? _peerRenderers[key]?.srcObject;
    return stream?.getVideoTracks().any((t) => t.enabled) ?? false;
  }

  bool _remoteHasVideo() {
    final stream = _remoteRenderer.srcObject;
    return stream?.getVideoTracks().isNotEmpty ?? false;
  }

  void _leaveCall() {
    callService.leaveCall();
    if (mounted) Navigator.pop(context);
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
            // Remote participants — chiếm toàn màn hình
            Positioned.fill(child: _buildRemoteMainArea()),

            // Gradient nhẹ phía dưới (controls)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withOpacity(0.75),
                      ],
                      stops: const [0, 0.65, 1],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
            ),

            // Local PiP nhỏ góc phải
            if (_renderersReady) _buildLocalPip(),

            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(),
            ),

            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: _buildBottomControls(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Vùng chính: video/avatar của mọi người khác (ưu tiên diện tích lớn).
  Widget _buildRemoteMainArea() {
    final remotes = _remoteParticipants;
    if (remotes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.group_outlined,
              size: 56,
              color: Colors.white.withOpacity(0.35),
            ),
            const SizedBox(height: 12),
            Text(
              _callState == CallState.calling
                  ? 'Đang chờ thành viên tham gia...'
                  : 'Chờ thành viên tham gia...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      );
    }

    if (remotes.length == 1) {
      return _buildParticipantCard(remotes.first, fillParent: true);
    }
    if (remotes.length == 2) {
      return Column(
        children: [
          Expanded(child: _buildParticipantCard(remotes[0], fillParent: true)),
          const SizedBox(height: 2),
          Expanded(child: _buildParticipantCard(remotes[1], fillParent: true)),
        ],
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(4, 72, 4, 120),
      physics: const BouncingScrollPhysics(),
      itemCount: remotes.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: remotes.length <= 4 ? 2 : 2,
        childAspectRatio: remotes.length <= 4 ? 0.85 : 0.78,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemBuilder: (_, i) =>
          _buildParticipantCard(remotes[i], fillParent: true),
    );
  }

  /// PiP local — nhỏ, không chiếm 60% màn hình.
  Widget _buildLocalPip() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 56,
      right: 12,
      child: AnimatedOpacity(
        opacity: _showControls || _callState != CallState.connected ? 1.0 : 0.85,
        duration: const Duration(milliseconds: 250),
        child: Container(
          width: 96,
          height: 132,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.35)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.45),
                blurRadius: 10,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_isCamOff)
                  const Center(
                    child: Icon(
                      Icons.videocam_off_rounded,
                      color: Colors.white54,
                      size: 28,
                    ),
                  )
                else if (!_hasLocalVideo)
                  Center(
                    child: AvatarWidget(
                      url: authService.currentUser?.avatar,
                      name: authService.currentUser?.fullName ?? 'You',
                      size: 40,
                    ),
                  )
                else
                  RTCVideoView(
                    _localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                Positioned(
                  left: 4,
                  right: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Bạn',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Grid hiển thị participant cards (avatar + name + status)
  Widget _buildParticipantsGridView() {
    final connected = _remoteParticipants;
    if (connected.isEmpty) {
      return Center(
        child: Text(
          'Chờ thành viên tham gia...',
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontFamily: 'Inter',
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      itemCount: connected.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        return _buildParticipantCard(connected[index]);
      },
    );
  }

  /// Card hiển thị participant (avatar + name + status)
  Widget _buildParticipantCard(
    GroupCallParticipant participant, {
    bool fillParent = false,
  }) {
    final key = _peerKey(participant.userId);
    final renderer = _peerRenderers[key];
    final stream = _peerStreams[key] ?? renderer?.srcObject;
    final hasVideoTrack =
        stream?.getVideoTracks().any((t) => t.enabled) ?? false;
    final hasAudioOnly =
        !hasVideoTrack &&
        (stream?.getAudioTracks().any((t) => t.enabled) ?? false);

    return GestureDetector(
      onTap: () {
        // Optional: tap để xem full video của người này
      },
      child: Container(
        width: fillParent ? double.infinity : null,
        height: fillParent ? double.infinity : null,
        decoration: BoxDecoration(
          color: const Color(0xFF1A3A1A),
          borderRadius: fillParent ? BorderRadius.zero : BorderRadius.circular(12),
          border: Border.all(
            color: participant.isConnected 
                ? AppColors.primary.withOpacity(0.3)
                : Colors.white10,
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius:
              fillParent ? BorderRadius.zero : BorderRadius.circular(11),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasVideoTrack && renderer != null)
                RTCVideoView(
                  renderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              else if (hasAudioOnly && renderer != null)
                SizedBox(
                  width: 1,
                  height: 1,
                  child: RTCVideoView(
                    renderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                )
              else
                // Avatar + name nếu không có video
                Container(
                  color: const Color(0xFF0D240D),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
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
                              size: 64,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            participant.name,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          participant.isConnected ? 'Đã vào' : 'Chưa tham gia',
                          style: TextStyle(
                            color: participant.isConnected
                                ? AppColors.online
                                : Colors.white.withOpacity(0.5),
                            fontSize: 10,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Name pill ở dưới
              if (hasVideoTrack && renderer != null)
                Positioned(
                  left: 8,
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      participant.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                ),

              // Mic indicator
              if (participant.isMuted)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.4),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.mic_off,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),

              // Online indicator
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: participant.isConnected 
                        ? AppColors.online
                        : Colors.grey,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                ),
              ),
            ],
          ),
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

    if (_callState == CallState.connected && _renderersReady) {
      final connectedPeers = _participants.where((p) => p.isConnected).toList();
      final anyPeerVideo = connectedPeers.any((p) => _peerHasVideo(p.userId));

      if (connectedPeers.isNotEmpty && !anyPeerVideo && _remoteHasVideo()) {
        return RTCVideoView(
          _remoteRenderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        );
      }

      if (connectedPeers.length == 2) {
        return _buildTwoUpLayout(connectedPeers);
      }

      if (connectedPeers.length == 3) {
        return _buildThreeUpLayout(connectedPeers);
      }

      if (connectedPeers.length >= 4) {
        return _buildVideoGridBackground(connectedPeers);
      }

      if (connectedPeers.length == 1) {
        return _buildParticipantFullView(connectedPeers.first);
      }

      if (_remoteRenderer.srcObject != null) {
        return RTCVideoView(
          _remoteRenderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        );
      }
    }

    return Center(
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
              child: widget.groupAvatar != null && widget.groupAvatar!.isNotEmpty
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
    );
  }

  Widget _buildVideoGridBackground(List<GroupCallParticipant> activePeers) {
    final count = activePeers.length;
    // For 4+ participants we show 2 columns. For more than 4 allow vertical
    // scrolling (5-6 etc.). Keep tiles ~portrait for mobile.
    final crossAxisCount = 2;
    final childAspectRatio = 0.78;
    final scrollable = count > 4;

    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: scrollable
          ? const BouncingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemCount: count,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: childAspectRatio,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemBuilder: (_, index) => _buildParticipantVideoTile(activePeers[index]),
    );
  }

  Widget _buildTwoUpLayout(List<GroupCallParticipant> peers) {
    // Top/bottom split (each takes 50% height, full width)
    return SizedBox.expand(
      child: Column(
        children: [
          Expanded(child: _buildParticipantVideoTile(peers[0])),
          const SizedBox(height: 2),
          Expanded(child: _buildParticipantVideoTile(peers[1])),
        ],
      ),
    );
  }

  Widget _buildThreeUpLayout(List<GroupCallParticipant> peers) {
    // Layout: first participant full-width on top, two others split below
    return SizedBox.expand(
      child: Column(
        children: [
          Expanded(child: _buildParticipantVideoTile(peers[0])),
          const SizedBox(height: 2),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildParticipantVideoTile(peers[1])),
                const SizedBox(width: 2),
                Expanded(child: _buildParticipantVideoTile(peers[2])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantFullView(GroupCallParticipant participant) {
    final renderer = _peerRenderers[participant.userId];
    final hasVideoTrack =
        _peerStreams[participant.userId]?.getVideoTracks().isNotEmpty ??
        renderer?.srcObject?.getVideoTracks().isNotEmpty ?? false;

    if (hasVideoTrack && renderer != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          RTCVideoView(
            renderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
          Positioned(
            left: 16,
            bottom: 16,
            child: _buildNamePill(participant.name),
          ),
          // mic indicator
          if (participant.isMuted)
            Positioned(
              right: 12,
              bottom: 12,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1.2),
                ),
                child: const Icon(Icons.mic_off, color: Colors.white, size: 12),
              ),
            ),
        ],
      );
    }

    return Container(
      color: const Color(0xFF172017),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: participant.isConnected ? AppColors.online : Colors.white24,
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: AvatarWidget(
                  url: participant.avatar,
                  name: participant.name,
                  size: 108,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              participant.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              participant.isConnected ? 'Đang ở trong cuộc gọi' : 'Chưa tham gia',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 13,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParticipantVideoTile(GroupCallParticipant participant) {
    final renderer = _peerRenderers[participant.userId];
    final hasVideoTrack =
        _peerStreams[participant.userId]?.getVideoTracks().isNotEmpty ??
        renderer?.srcObject?.getVideoTracks().isNotEmpty ?? false;
    final isConnected = participant.isConnected;

    if (hasVideoTrack && renderer != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          RTCVideoView(
            renderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
          Positioned(
            left: 8,
            bottom: 8,
            child: _buildNamePill(participant.name),
          ),
          if (participant.isMuted)
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1),
                ),
                child: const Icon(Icons.mic_off, color: Colors.white, size: 10),
              ),
            ),
        ],
      );
    }

    return Container(
      color: const Color(0xFF172017),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isConnected ? AppColors.online : Colors.white24,
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: AvatarWidget(
                      url: participant.avatar,
                      name: participant.name,
                      size: 84,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  participant.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isConnected ? 'Đã vào cuộc gọi' : 'Chưa tham gia',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 11,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 8,
            top: 8,
            child: _buildNamePill(participant.name),
          ),
          if (participant.isMuted)
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1),
                ),
                child: const Icon(Icons.mic_off, color: Colors.white, size: 10),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNamePill(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        name,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontFamily: 'Inter',
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
              IconButton(
                onPressed: _leaveCall,
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                tooltip: 'Rời cuộc gọi',
              ),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, Colors.black.withOpacity(0.92)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: _callState == CallState.incoming
          ? _buildIncomingControls()
          : _callState == CallState.calling
          ? _buildCallingControlsRow()
          : _buildConnectedControls(),
    );
  }

  /// Mic + kết thúc + loa khi đang chờ/ghép mesh (không chỉ nút huỷ).
  Widget _buildCallingControlsRow() {
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
        GestureDetector(
          onTap: _leaveCall,
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
          icon: _isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          label: _isSpeakerOn ? 'Loa' : 'Tắt loa',
          isActive: !_isSpeakerOn,
          activeColor: Colors.orange,
          onTap: () {
            setState(() => _isSpeakerOn = !_isSpeakerOn);
            callService.toggleSpeaker(_isSpeakerOn);
          },
        ),
      ],
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
          onTap: _leaveCall,
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
          icon: _isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          label: _isSpeakerOn ? 'Loa' : 'Tắt loa',
          isActive: !_isSpeakerOn,
          activeColor: Colors.orange,
          onTap: () {
            setState(() => _isSpeakerOn = !_isSpeakerOn);
            callService.toggleSpeaker(_isSpeakerOn);
          },
        ),
      ],
    );
  }

  Widget _buildCallingControls() {
    return Center(
      child: GestureDetector(
        onTap: _leaveCall,
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
                _bindLocalFromCallService();
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
