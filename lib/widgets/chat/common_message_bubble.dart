import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/date_utils.dart' as du;
import '../../data/models/models.dart';

class CommonMessageBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMe;
  final bool isGroup;
  final String? senderLabel;
  final String? senderAvatar;
  final String? senderName;
  final bool showAvatar;
  final bool showSeenLabel;
  final MessageModel? replyToMsg;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onReply;
  final VoidCallback? onImageTap;
  final VoidCallback? onFileTap;
  final VoidCallback? onVideoTap;

  const CommonMessageBubble({
    super.key,
    required this.msg,
    required this.isMe,
    this.isGroup = false,
    this.senderLabel,
    this.senderAvatar,
    this.senderName,
    this.showAvatar = true,
    this.showSeenLabel = false,
    this.replyToMsg,
    this.onLongPress,
    this.onDoubleTap,
    this.onReply,
    this.onImageTap,
    this.onFileTap,
    this.onVideoTap,
  });

  @override
  Widget build(BuildContext context) {
    if (msg.isRecalled) return _buildRecalled();

    return GestureDetector(
      onLongPress: onLongPress,
      onDoubleTap: onDoubleTap,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: 6,
          left: isMe ? 50 : 8,
          right: isMe ? 8 : 50,
        ),
        child: Row(
          mainAxisAlignment: isMe
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
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
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (isGroup && !isMe && showAvatar && (senderLabel ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2, left: 4),
                      child: Text(
                        senderLabel!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                  if (replyToMsg != null) _buildReplyQuote(),
                  _buildBubble(context),
                  const SizedBox(height: 2),
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
                  if (msg.reactions.isNotEmpty) _buildReactions(),
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

  Widget _buildBubble(BuildContext context) {
    Widget content;
    if (msg.isImage) {
      final imageContent = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          msg.content,
          width: 220,
          height: 160,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return SizedBox(
              width: 220,
              height: 160,
              child: Container(
                color: AppColors.bgCardLight,
                child: Center(
                  child: CircularProgressIndicator(
                    value:
                        progress.cumulativeBytesLoaded /
                        (progress.expectedTotalBytes ?? 1),
                    strokeWidth: 2,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) => SizedBox(
            width: 220,
            height: 160,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.bgCardLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.textHint,
                      size: 32,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Không tải được ảnh',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textHint,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      content = GestureDetector(
        onTap: onImageTap,
        child: Hero(tag: 'image_${msg.id}', child: imageContent),
      );
    } else if (msg.type == 'VIDEO') {
      final thumbnailUrl = msg.metadata?.thumbnailUrl ?? msg.metadata?.thumbnail;
      final title = msg.metadata?.fileName ?? 'Video';
      content = GestureDetector(
        onTap: onVideoTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: thumbnailUrl != null && thumbnailUrl.isNotEmpty
                  ? Image.network(
                      thumbnailUrl,
                      width: 220,
                      height: 160,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 220,
                        height: 160,
                        color: AppColors.bgCardLight,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.videocam,
                          color: AppColors.textHint,
                          size: 34,
                        ),
                      ),
                    )
                  : Container(
                      width: 220,
                      height: 160,
                      color: AppColors.bgCardLight,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.videocam,
                        color: AppColors.textHint,
                        size: 34,
                      ),
                    ),
            ),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Inter',
                  shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    } else if (msg.type == 'FILE') {
      final fileName = msg.metadata?.fileName ?? _extractFileNameFromUrl(msg.content);
      content = GestureDetector(
        onTap: onFileTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: (isMe ? Colors.white : AppColors.primary).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.insert_drive_file_outlined,
                color: isMe ? Colors.white : AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: TextStyle(
                      fontSize: 13,
                      color: isMe ? Colors.white : AppColors.bubbleOtherText,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Inter',
                    ),
                    maxLines: 2,
                  ),
                  if (msg.metadata?.fileSize != null)
                    Text(
                      _formatFileSize(msg.metadata!.fileSize!),
                      style: TextStyle(
                        fontSize: 11,
                        color: isMe ? AppColors.bubbleMeText : AppColors.textSecondary,
                        fontFamily: 'Inter',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    } else if (msg.type == 'VOICE') {
      content = _VoiceMessagePlayer(
        audioUrl: msg.content,
        initialDurationSeconds: msg.metadata?.duration ?? 0,
        isMe: isMe,
      );
    } else {
      content = Text(
        msg.content,
        style: TextStyle(
          fontSize: 14,
          fontFamily: 'Inter',
          color: isMe ? AppColors.bubbleMeText : AppColors.bubbleOtherText,
          height: 1.4,
        ),
      );
    }

    return Container(
      padding: msg.isImage || msg.type == 'VIDEO'
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? null : AppColors.bubbleOther,
        gradient: isMe ? AppColors.primaryGradient : null,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMe ? 18 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: content,
    );
  }

  Widget _buildReplyQuote() {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bgCardLight,
        borderRadius: BorderRadius.circular(10),
        border: const Border(
          left: BorderSide(color: AppColors.primary, width: 3),
        ),
      ),
      child: Text(
        replyToMsg!.content,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
          fontFamily: 'Inter',
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildRecalled() => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bgCardLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: const Text(
          'Tin nhắn đã bị thu hồi',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textHint,
            fontStyle: FontStyle.italic,
            fontFamily: 'Inter',
          ),
        ),
      ),
    ),
  );

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
    final grouped = <String, int>{};
    for (final r in msg.reactions) {
      final e = r.emoji;
      grouped[e] = (grouped[e] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: grouped.entries
            .map(
              (e) => Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.bgCardLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  '${e.key} ${e.value}',
                  style: const TextStyle(fontSize: 11, fontFamily: 'Inter'),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  String _extractFileNameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      if (path.isNotEmpty) return path;
      return url.split('/').last;
    } catch (_) {
      return url.split('/').last;
    }
  }

  String _formatFileSize(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class _VoiceMessagePlayer extends StatefulWidget {
  final String audioUrl;
  final int initialDurationSeconds;
  final bool isMe;

  const _VoiceMessagePlayer({
    required this.audioUrl,
    required this.initialDurationSeconds,
    required this.isMe,
  });

  @override
  State<_VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<_VoiceMessagePlayer> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<PlayerState>? _playerStateSub;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isPrepared = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialDurationSeconds > 0) {
      _duration = Duration(seconds: widget.initialDurationSeconds);
    }

    _positionSub = _player.onPositionChanged.listen((value) {
      if (!mounted) return;
      setState(() => _position = value);
    });

    _durationSub = _player.onDurationChanged.listen((value) {
      if (!mounted) return;
      setState(() => _duration = value);
    });

    _playerStateSub = _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _isPlaying = state == PlayerState.playing);
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playerStateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final total = d.inSeconds;
    final m = (total ~/ 60).toString().padLeft(1, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _toggle() async {
    try {
      if (_isPlaying) {
        await _player.pause();
        return;
      }

      if (!_isPrepared) {
        await _player.setSourceUrl(widget.audioUrl);
        _isPrepared = true;
      }
      await _player.resume();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không phát được audio.')),
      );
    }
  }

  Future<void> _seek(double value) async {
    final target = Duration(milliseconds: value.round());
    await _player.seek(target);
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = (_duration.inMilliseconds <= 0)
        ? 1.0
        : _duration.inMilliseconds.toDouble();
    final valueMs = _position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();

    final fg = widget.isMe ? Colors.white : AppColors.bubbleOtherText;
    final dim = widget.isMe
        ? Colors.white.withOpacity(0.8)
        : AppColors.textSecondary;

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          InkResponse(
            onTap: _toggle,
            radius: 20,
            child: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
              size: 30,
              color: fg,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 10,
                    ),
                    activeTrackColor: fg,
                    inactiveTrackColor: dim.withOpacity(0.35),
                    thumbColor: fg,
                  ),
                  child: Slider(
                    value: valueMs,
                    min: 0,
                    max: maxMs,
                    onChanged: (v) => _seek(v),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _fmt(_position),
                      style: TextStyle(
                        fontSize: 11,
                        color: dim,
                        fontFamily: 'Inter',
                      ),
                    ),
                    Text(
                      _fmt(_duration),
                      style: TextStyle(
                        fontSize: 11,
                        color: dim,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
