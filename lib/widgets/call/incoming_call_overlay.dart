import 'package:flutter/material.dart';
import '../../data/models/models.dart';
import '../../screens/call/voice_call_screen.dart';
import '../../screens/call/video_call_screen.dart';
import '../../services/call_service.dart';

class IncomingCallListener extends StatefulWidget {
  final Widget child;
  const IncomingCallListener({super.key, required this.child});

  @override
  State<IncomingCallListener> createState() => _IncomingCallListenerState();
}

class _IncomingCallListenerState extends State<IncomingCallListener> {
  @override
  void initState() {
    super.initState();
    callService.onIncomingCall = (data) {
      if (!mounted) return;
      _showIncomingCallDialog(data);
    };
  }

  @override
  void dispose() {
    callService.onIncomingCall = null;
    super.dispose();
  }

  void _showIncomingCallDialog(Map<String, dynamic> data) {
    final callerId = data['callerId']?.toString() ?? '';
    final callId = data['callId']?.toString() ?? '';
    final conversationId = data['conversationId']?.toString() ?? '';
    final offer = data['offer'] as Map<String, dynamic>?;
    final type = data['type']?.toString() ?? 'VOICE';
    final isVideo = type == 'VIDEO';

    final callerName = data['callerName']?.toString() ?? 'Người dùng';
    final callerAvatar = data['callerAvatar']?.toString() ?? '';

    final callerUser = UserModel(
      id: callerId,
      fullName: callerName,
      phone: '',
      avatar: callerAvatar,
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon loại cuộc gọi
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: isVideo
                    ? Colors.blue.withOpacity(0.15)
                    : Colors.green.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                color: isVideo ? Colors.blue : Colors.green,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isVideo ? 'Cuộc gọi video đến' : 'Cuộc gọi thoại đến',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              callerName,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
                fontFamily: 'Inter',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
          ],
        ),
        actions: [
          Row(
            children: [
              // Từ chối
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    callService.rejectCall(
                      callId: callId,
                      conversationId: conversationId,
                    );
                  },
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.call_end_rounded,
                          color: Colors.red,
                          size: 18,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Từ chối',
                          style: TextStyle(
                            color: Colors.red,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Chấp nhận
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    if (isVideo) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          fullscreenDialog: true,
                          builder: (_) => VideoCallScreen(
                            otherUser: callerUser,
                            isIncoming: true,
                            callId: callId,
                            conversationId: conversationId,
                            offer: offer,
                          ),
                        ),
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          fullscreenDialog: true,
                          builder: (_) => VoiceCallScreen(
                            otherUser: callerUser,
                            isIncoming: true,
                            callId: callId,
                            conversationId: conversationId,
                            offer: offer,
                          ),
                        ),
                      );
                    }
                  },
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                          color: Colors.green,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Nghe',
                          style: TextStyle(
                            color: Colors.green,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
