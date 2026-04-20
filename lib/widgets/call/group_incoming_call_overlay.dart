import 'package:flutter/material.dart';
import '../../screens/call/group_video_call_screen.dart';
import '../../screens/call/group_voice_call_screen.dart';
import '../../services/call_service.dart';

class GroupIncomingCallDialog extends StatelessWidget {
  final String conversationId;
  final String callId;
  final bool isVideo;
  final String groupName;
  final String callerId;
  final String? groupAvatar;
  final List<GroupCallParticipant> participants;
  final Map<String, dynamic>? offer;

  const GroupIncomingCallDialog({
    super.key,
    required this.conversationId,
    required this.callId,
    required this.isVideo,
    required this.groupName,
    required this.callerId,
    this.groupAvatar,
    required this.participants,
    this.offer,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = groupName.isNotEmpty ? groupName : 'Nhóm';
    final avatarUrl = groupAvatar?.trim();

    return AlertDialog(
      backgroundColor: const Color(0xFF1A3A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.08),
              shape: BoxShape.circle,
              image: avatarUrl != null && avatarUrl.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(avatarUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: avatarUrl == null || avatarUrl.isEmpty
                ? Icon(
                    isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                    color: Colors.green,
                    size: 36,
                  )
                : null,
          ),
          const SizedBox(height: 16),
          Text(
            isVideo ? 'Cuộc gọi video nhóm đến' : 'Cuộc gọi thoại nhóm đến',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            displayName,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontFamily: 'Inter',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            'Có ${participants.length} người mời',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 12,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
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
                      Icon(Icons.call_end_rounded, color: Colors.red, size: 18),
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
            Expanded(
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  if (isVideo) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (_) => GroupVideoCallScreen(
                          conversationId: conversationId,
                          groupName: displayName,
                          callerId: callerId,
                          groupAvatar: avatarUrl,
                          participants: participants,
                          isIncoming: true,
                          callId: callId,
                          offer: offer,
                        ),
                      ),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (_) => GroupVoiceCallScreen(
                          conversationId: conversationId,
                          groupName: displayName,
                          callerId: callerId,
                          groupAvatar: avatarUrl,
                          participants: participants,
                          isIncoming: true,
                          callId: callId,
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
                        'Chấp nhận',
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
    );
  }
}
