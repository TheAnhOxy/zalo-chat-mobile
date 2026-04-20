import 'package:flutter/material.dart';
import '../../data/models/models.dart';
import '../../screens/call/voice_call_screen.dart';
import '../../screens/call/video_call_screen.dart';
import '../../screens/call/group_voice_call_screen.dart';
import '../../screens/call/group_video_call_screen.dart';
import '../../services/auth_service.dart';
import '../../services/call_service.dart';
import '../../services/contacts_api_service.dart';

class IncomingCallListener extends StatefulWidget {
  final Widget child;
  const IncomingCallListener({super.key, required this.child});

  @override
  State<IncomingCallListener> createState() => _IncomingCallListenerState();
}

class _IncomingCallListenerState extends State<IncomingCallListener> {
  BuildContext? _dialogContext;
  bool _isIncomingDialogVisible = false;

  @override
  void initState() {
    super.initState();
    callService.addStateListener(_onCallStateChanged);
    callService.onIncomingCall = (data) {
      if (!mounted) return;
      _showIncomingCallDialog(data);
    };
  }

  @override
  void dispose() {
    callService.onIncomingCall = null;
    callService.removeStateListener(_onCallStateChanged);
    super.dispose();
  }

  void _onCallStateChanged(CallState state) {
    if (state == CallState.ended) {
      _dismissIncomingDialog();
    }
  }

  void _dismissIncomingDialog() {
    if (!_isIncomingDialogVisible) return;
    final ctx = _dialogContext;
    if (ctx != null && Navigator.of(ctx).canPop()) {
      Navigator.of(ctx).pop();
    }
    _dialogContext = null;
    _isIncomingDialogVisible = false;
  }

  Future<void> _showIncomingCallDialog(Map<String, dynamic> data) async {
    if (_isIncomingDialogVisible) return;

    final callerId = data['callerId']?.toString() ?? '';
    final callId = data['callId']?.toString() ?? '';
    final conversationId = data['conversationId']?.toString() ?? '';
    final offer = data['offer'] as Map<String, dynamic>?;
    final type = data['type']?.toString() ?? 'VOICE';
    final isVideo = type == 'VIDEO';
    final rawParticipants = (data['participants'] as List?) ?? const [];
    final participantIds = rawParticipants
        .map((e) {
          if (e is Map) {
            return (e['userId'] ?? e['_id'] ?? e['id'] ?? '').toString();
          }
          return e.toString();
        })
        .where((id) => id.isNotEmpty)
        .toList();
    final explicitGroup = data['isGroup'] == true ||
        data['conversationType']?.toString().toUpperCase() == 'GROUP';
    final isGroupCall = explicitGroup || participantIds.length > 1;
    String groupName = data['groupName']?.toString() ?? '';
    String? groupAvatar = data['groupAvatar']?.toString();
    final memberNameById = <String, String>{};

    final callerName = data['callerName']?.toString() ?? 'Người dùng';
    final callerAvatar = data['callerAvatar']?.toString() ?? '';
    final myUserId = authService.userId ?? '';

    if (isGroupCall && conversationId.isNotEmpty) {
      final conversationRes = await ContactsApiService.instance.fetchConversationRaw(
        conversationId,
      );
      if (conversationRes.isSuccess) {
        final map = conversationRes.data ?? const <String, dynamic>{};
        final resolvedName = map['name']?.toString() ?? '';
        if (resolvedName.isNotEmpty) {
          groupName = resolvedName;
        }
        final resolvedAvatar = map['avatar']?.toString();
        if (resolvedAvatar != null && resolvedAvatar.isNotEmpty) {
          groupAvatar = resolvedAvatar;
        }

        final members = (map['members'] as List?) ?? const [];
        for (final raw in members) {
          if (raw is! Map) continue;
          final userId = (raw['userId'] ?? raw['_id'] ?? '').toString();
          if (userId.isEmpty) continue;
          final name =
              raw['nickname']?.toString() ??
              raw['name']?.toString() ??
              raw['fullName']?.toString() ??
              userId;
          memberNameById[userId] = name;
        }
      }
    }

    if (groupName.isEmpty) {
      groupName = 'Nhóm';
    }

    final groupParticipants = participantIds
        .where((id) => id != callerId && id != myUserId)
        .map(
          (id) => GroupCallParticipant(
            userId: id,
            name: memberNameById[id] ?? id,
            avatar: null,
          ),
        )
        .toList();

    final callerUser = UserModel(
      id: callerId,
      fullName: callerName,
      phone: '',
      avatar: callerAvatar,
    );
    _isIncomingDialogVisible = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        _dialogContext = dialogCtx;
        return AlertDialog(
        backgroundColor: const Color(0xFF1A3A1A),
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
                    ? const Color(0xFF388E3C).withOpacity(0.15)
                    : Colors.green.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                color: isVideo ? const Color(0xFF388E3C) : Colors.green,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isGroupCall
                  ? (isVideo ? 'Cuộc gọi video nhóm đến' : 'Cuộc gọi thoại nhóm đến')
                  : (isVideo ? 'Cuộc gọi video đến' : 'Cuộc gọi thoại đến'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isGroupCall ? '$callerName từ $groupName' : callerName,
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
                    _dismissIncomingDialog();
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
                    _dismissIncomingDialog();
                    if (isVideo) {
                      if (isGroupCall) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            fullscreenDialog: true,
                            builder: (_) => GroupVideoCallScreen(
                              conversationId: conversationId,
                              groupName: groupName,
                              groupAvatar: groupAvatar,
                              participants: groupParticipants,
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
                            builder: (_) => VideoCallScreen(
                              otherUser: callerUser,
                              isIncoming: true,
                              callId: callId,
                              conversationId: conversationId,
                              offer: offer,
                            ),
                          ),
                        );
                      }
                    } else {
                      if (isGroupCall) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            fullscreenDialog: true,
                            builder: (_) => GroupVoiceCallScreen(
                              conversationId: conversationId,
                              groupName: groupName,
                              groupAvatar: groupAvatar,
                              participants: groupParticipants,
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
      );
      },
    ).whenComplete(() {
      _dialogContext = null;
      _isIncomingDialogVisible = false;
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
