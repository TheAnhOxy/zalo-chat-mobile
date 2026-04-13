import 'package:flutter/material.dart';
import '../../data/models/models.dart';
import '../../screens/call/voice_call_screen.dart';
import '../../services/call_service.dart';
import '../../services/socket_service.dart';

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

  void _showIncomingCallDialog(Map<String, dynamic> data) {
    final callerId = data['callerId']?.toString() ?? '';
    final callId = data['callId']?.toString() ?? '';
    final conversationId = data['conversationId']?.toString() ?? '';
    final offer = data['offer'] as Map<String, dynamic>?;

    // Tạm dùng UserModel đơn giản từ callerId
    // Thực tế nên fetch user info từ API
    final callerUser = UserModel(
      id: callerId,
      fullName: 'Đang gọi...',
      phone: '',
      avatar: '',
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cuộc gọi đến', style: TextStyle(color: Colors.white)),
        content: Text('ID: $callerId', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              callService.rejectCall(callId: callId, conversationId: conversationId);
            },
            child: const Text('Từ chối', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VoiceCallScreen(
                    otherUser: callerUser,
                    isIncoming: true,
                    callId: callId,
                    conversationId: conversationId,
                    offer: offer,
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Nghe'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}