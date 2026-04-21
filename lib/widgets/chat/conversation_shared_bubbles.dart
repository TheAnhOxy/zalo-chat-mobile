import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/date_utils.dart' as du;
import '../../data/models/models.dart';
import '../../services/auth_service.dart';

class ConversationTypingIndicator extends StatelessWidget {
  const ConversationTypingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 0, bottom: 8, top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: AppColors.bubbleOther,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            3,
            (index) => _DotAnimation(delay: index * 200),
          ),
        ),
      ),
    );
  }
}

class ConversationCallBubble extends StatelessWidget {
  final CallModel call;
  final String? callerAvatar;
  final String? callerName;
  final bool showAvatar;

  const ConversationCallBubble({
    super.key,
    required this.call,
    this.callerAvatar,
    this.callerName,
    this.showAvatar = true,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = call.callerId == authService.userId;
    final isVideo = call.isVideo;
    final isMissed = call.isMissed;
    Color iconColor;
    Color bgColor;
    String label;
    IconData icon;

    if (isMissed) {
      iconColor = Colors.red;
      bgColor = Colors.red.withOpacity(0.1);
      label = isMe ? 'Người nhận không bắt máy' : 'Cuộc gọi nhỡ';
      icon = isVideo ? Icons.videocam_off : Icons.phone_missed;
    } else {
      iconColor = AppColors.primary;
      bgColor = isMe
          ? AppColors.primary.withOpacity(0.15)
          : Colors.grey.withOpacity(0.15);
      label = isVideo ? 'Cuộc gọi video' : 'Cuộc gọi thoại';
      icon = isVideo ? Icons.videocam : Icons.phone;
    }

    return Padding(
      padding: EdgeInsets.only(
        top: 6,
        bottom: 6,
        left: isMe ? 60 : 8,
        right: isMe ? 8 : 60,
      ),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar for non-me calls
          if (!isMe)
            (showAvatar && (callerAvatar ?? '').isNotEmpty)
                ? Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 2),
                    child: ClipOval(
                      child: Image.network(
                        callerAvatar!,
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            color: AppColors.bgCardLight,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              (callerName ?? 'U').isNotEmpty
                                  ? (callerName ?? 'U')[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: 40),
          Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 260),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: isMe ? const Radius.circular(18) : Radius.zero,
                      bottomRight: isMe ? Radius.zero : const Radius.circular(18),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: iconColor, size: 16),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 13,
                              color: isMissed ? Colors.red : AppColors.textPrimary,
                            ),
                          ),
                          if (call.isEnded && call.duration > 0)
                            Text(
                              call.durationLabel,
                              style: const TextStyle(fontSize: 11),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  du.DateUtils.formatMessageTime(call.createdAt),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textHint,
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
}

class _DotAnimation extends StatefulWidget {
  final int delay;

  const _DotAnimation({required this.delay});

  @override
  State<_DotAnimation> createState() => _DotAnimationState();
}

class _DotAnimationState extends State<_DotAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _value;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _value = Tween<double>(begin: 0.35, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (!mounted) return;
      _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: AnimatedBuilder(
        animation: _value,
        builder: (context, child) {
          final value = _value.value;
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, (1 - value) * -4),
              child: child,
            ),
          );
        },
        child: Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
