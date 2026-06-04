import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/date_utils.dart' as du;
import '../../data/models/models.dart';

class MediaClusterBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMe;
  final bool isGroup;
  final String? senderLabel;
  final String? senderAvatar;
  final String? senderName;
  final bool showAvatar;
  final bool showSeenLabel;
  final bool isHighlighted;
  final bool isPinned;
  final MessageModel? replyToMsg;
  final void Function(MessageModel)? onReplyTap;
  final void Function(MediaItem)? onMediaTap;
  final void Function(MessageModel)? onLongPress;
  final void Function(MessageModel, String)? onReactionTap;

  const MediaClusterBubble({
    super.key,
    required this.msg,
    required this.isMe,
    this.isGroup = false,
    this.senderLabel,
    this.senderAvatar,
    this.senderName,
    this.showAvatar = true,
    this.showSeenLabel = false,
    this.isHighlighted = false,
    this.isPinned = false,
    this.replyToMsg,
    this.onReplyTap,
    this.onMediaTap,
    this.onLongPress,
    this.onReactionTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!msg.isMediaCluster) return const SizedBox.shrink();

    final items = msg.clusterItems;
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(
        top: !isMe && showAvatar ? 8 : 0,
        bottom: 6,
        left: isMe ? 50 : 8,
        right: isMe ? 8 : 50,
      ),
      child: GestureDetector(
        onLongPress: () => onLongPress?.call(msg),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe) _buildAvatar(),
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
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          border: isHighlighted
                              ? Border.all(color: const Color(0xFFFFD54F), width: 1.4)
                              : null,
                          borderRadius: _getBubbleBorder(),
                        ),
                        child: _buildGrid(context, items),
                      ),
                      if (isPinned)
                        Positioned(
                          top: -6,
                          right: -6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.push_pin,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                        ),
                      if (msg.reactions.isNotEmpty)
                        Positioned(
                          bottom: -10,
                          right: isMe ? 8 : null,
                          left: isMe ? null : 8,
                          child: _buildReactions(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        du.DateUtils.formatMessageTime(msg.createdAt),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textHint,
                          fontFamily: 'Inter',
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        _buildStatusIcon(),
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
      ),
    );
  }

  Widget _buildAvatar() {
    if (showAvatar && (senderAvatar ?? '').isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 2),
        child: ClipOval(
          child: Image.network(
            senderAvatar!,
            width: 32,
            height: 32,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildFallbackAvatar(),
          ),
        ),
      );
    } else if (showAvatar) {
      return Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 2),
        child: _buildFallbackAvatar(),
      );
    }
    return const SizedBox(width: 40);
  }

  Widget _buildFallbackAvatar() {
    return Container(
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
    );
  }

  Widget _buildGrid(BuildContext context, List<MediaItem> items) {
    const spacing = 2.0;
    const double totalWidth = 240.0;
    final int count = items.length;

    Widget buildMedia(MediaItem item, double w, double h, {bool isOverlay = false}) {
      final isVideo = item.type == 'VIDEO';
      final url = isVideo
          ? (item.thumbnail ?? item.url)
          : item.url;

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
        onTap: () => onMediaTap?.call(item),
        child: content,
      );
    }

    Widget gridContent;

    if (count == 1) {
      gridContent = buildMedia(items[0], 200, 160);
    } else if (count == 2) {
      gridContent = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildMedia(items[0], totalWidth / 2 - spacing / 2, 160),
          const SizedBox(width: spacing),
          buildMedia(items[1], totalWidth / 2 - spacing / 2, 160),
        ],
      );
    } else if (count == 3) {
      gridContent = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildMedia(items[0], totalWidth, 120),
          const SizedBox(height: spacing),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildMedia(items[1], totalWidth / 2 - spacing / 2, 120),
              const SizedBox(width: spacing),
              buildMedia(items[2], totalWidth / 2 - spacing / 2, 120),
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
              buildMedia(items[0], totalWidth / 2 - spacing / 2, 120),
              const SizedBox(width: spacing),
              buildMedia(items[1], totalWidth / 2 - spacing / 2, 120),
            ],
          ),
          const SizedBox(height: spacing),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildMedia(items[2], totalWidth / 2 - spacing / 2, 120),
              const SizedBox(width: spacing),
              buildMedia(items[3], totalWidth / 2 - spacing / 2, 120, isOverlay: true),
            ],
          ),
        ],
      );
    }

    return ClipRRect(
      borderRadius: _getBubbleBorder(),
      child: gridContent,
    );
  }

  BorderRadius _getBubbleBorder() {
    return BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMe ? 18 : 4),
      bottomRight: Radius.circular(isMe ? 4 : 18),
    );
  }

  Widget _buildStatusIcon() {
    switch (msg.status) {
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

  Widget _buildReactions() {
    final Map<String, int> counts = {};
    for (final r in msg.reactions) {
      counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
    }

    return GestureDetector(
      onTap: () {
        // Do something on reaction tap if needed
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.bgCardLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...counts.keys.map((e) => Text(e, style: const TextStyle(fontSize: 12))),
            if (msg.reactions.length > 1) ...[
              const SizedBox(width: 4),
              Text(
                '${msg.reactions.length}',
                style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
