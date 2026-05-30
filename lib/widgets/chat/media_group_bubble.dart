import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/date_utils.dart' as du;
import '../../data/models/models.dart';
import 'common_message_bubble.dart';

class MediaGroupBubble extends StatelessWidget {
  final List<MessageModel> group;
  final bool isMe;
  final bool isGroup;
  final String? senderLabel;
  final String? senderAvatar;
  final String? senderName;
  final bool showAvatar;
  final bool showSeenLabel;
  final void Function(MessageModel) onImageTap;
  final void Function(MessageModel) onVideoTap;

  const MediaGroupBubble({
    super.key,
    required this.group,
    required this.isMe,
    this.isGroup = false,
    this.senderLabel,
    this.senderAvatar,
    this.senderName,
    this.showAvatar = true,
    this.showSeenLabel = false,
    required this.onImageTap,
    required this.onVideoTap,
  });

  @override
  Widget build(BuildContext context) {
    if (group.isEmpty) return const SizedBox.shrink();

    // If only 1 item, fallback to standard bubble
    if (group.length == 1) {
      return CommonMessageBubble(
        msg: group.first,
        isMe: isMe,
        isGroup: isGroup,
        senderLabel: senderLabel,
        senderAvatar: senderAvatar,
        senderName: senderName,
        showAvatar: showAvatar,
        showSeenLabel: showSeenLabel,
        onImageTap: () => onImageTap(group.first),
        onVideoTap: () => onVideoTap(group.first),
      );
    }

    final lastMsg = group.last;

    return Padding(
      padding: EdgeInsets.only(
        top: !isMe && showAvatar ? 8 : 0,
        bottom: 6,
        left: isMe ? 50 : 8,
        right: isMe ? 8 : 50,
      ),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe)
            (showAvatar && (senderAvatar ?? '').isNotEmpty)
                ? Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 2),
                    child: ClipOval(
                      child: Image.network(
                        senderAvatar!,
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
                              (senderName ?? 'U').isNotEmpty
                                  ? (senderName ?? 'U')[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color.fromARGB(255, 43, 44, 44),
                                fontFamily: 'Inter',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: 40),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.68,
            ),
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (isGroup && !isMe && (senderLabel ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 4),
                    child: Text(
                      senderLabel!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                _buildGrid(context),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      du.DateUtils.formatMessageTime(lastMsg.createdAt),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textHint,
                        fontFamily: 'Inter',
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      _buildStatusIcon(lastMsg),
                    ],
                  ],
                ),
                if (isMe && showSeenLabel)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text(
                      'Đã xem',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.primary,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    const spacing = 2.0;
    const double totalWidth = 240.0;
    final int count = group.length;

    Widget buildMedia(MessageModel msg, double w, double h, {bool isOverlay = false}) {
      final isVideo = msg.type == 'VIDEO';
      final url = isVideo
          ? (msg.metadata?.thumbnailUrl ?? msg.metadata?.thumbnail ?? '')
          : msg.content;

      Widget image = Image.network(
        url,
        width: w,
        height: h,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: w,
          height: h,
          color: AppColors.bgCardLight,
          alignment: Alignment.center,
          child: Icon(
            isVideo ? Icons.videocam : Icons.broken_image_outlined,
            color: AppColors.textHint,
            size: w > 100 ? 32 : 24,
          ),
        ),
      );

      Widget content = isVideo
          ? Stack(
              alignment: Alignment.center,
              children: [
                image,
                Container(
                  width: w > 100 ? 40 : 28,
                  height: w > 100 ? 40 : 28,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.35),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: w > 100 ? 24 : 18,
                  ),
                ),
              ],
            )
          : image;

      if (isOverlay && count > 4) {
        content = Stack(
          fit: StackFit.passthrough,
          children: [
            content,
            Container(
              color: Colors.black.withOpacity(0.5),
              alignment: Alignment.center,
              child: Text(
                '+${count - 4}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ],
        );
      }

      return GestureDetector(
        onTap: () => isVideo ? onVideoTap(msg) : onImageTap(msg),
        child: content,
      );
    }

    Widget gridContent;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMe ? 18 : 4),
      bottomRight: Radius.circular(isMe ? 4 : 18),
    );

    if (count == 2) {
      gridContent = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildMedia(group[0], totalWidth / 2 - spacing / 2, 160),
          const SizedBox(width: spacing),
          buildMedia(group[1], totalWidth / 2 - spacing / 2, 160),
        ],
      );
    } else if (count == 3) {
      gridContent = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildMedia(group[0], totalWidth, 120),
          const SizedBox(height: spacing),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildMedia(group[1], totalWidth / 2 - spacing / 2, 120),
              const SizedBox(width: spacing),
              buildMedia(group[2], totalWidth / 2 - spacing / 2, 120),
            ],
          ),
        ],
      );
    } else {
      // 4 or more items (2x2 grid)
      gridContent = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildMedia(group[0], totalWidth / 2 - spacing / 2, 120),
              const SizedBox(width: spacing),
              buildMedia(group[1], totalWidth / 2 - spacing / 2, 120),
            ],
          ),
          const SizedBox(height: spacing),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildMedia(group[2], totalWidth / 2 - spacing / 2, 120),
              const SizedBox(width: spacing),
              buildMedia(group[3], totalWidth / 2 - spacing / 2, 120, isOverlay: true),
            ],
          ),
        ],
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: gridContent,
    );
  }

  Widget _buildStatusIcon(MessageModel lastMsg) {
    switch (lastMsg.status) {
      case 'SENDING':
        return const Icon(Icons.done, size: 14, color: AppColors.textHint);
      case 'SENT':
        return const Icon(Icons.done, size: 14, color: AppColors.textHint);
      case 'DELIVERED':
        return const Icon(Icons.done_all, size: 14, color: AppColors.textHint);
      case 'SEEN':
        return const Icon(Icons.done_all, size: 14, color: AppColors.primary);
      default:
        return const SizedBox.shrink();
    }
  }
}
