import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/date_utils.dart' as du;
import '../../controllers/chat_controller.dart';
import '../../data/models/models.dart';

class PinnedMessagesScreen extends StatefulWidget {
  final ChatController controller;
  final String title;
  final String chatTitle;
  final String? chatAvatar;
  final Map<String, String> memberNames;
  final Map<String, String> memberAvatars;

  const PinnedMessagesScreen({
    super.key,
    required this.controller,
    this.title = 'Tin nhắn đã ghim',
    required this.chatTitle,
    this.chatAvatar,
    this.memberNames = const {},
    this.memberAvatars = const {},
  });

  @override
  State<PinnedMessagesScreen> createState() => _PinnedMessagesScreenState();
}

class _PinnedMessagesScreenState extends State<PinnedMessagesScreen> {
  List<MessageModel> _items = const [];

  @override
  void initState() {
    super.initState();
    _items = widget.controller.pinnedMessages;
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {
      _items = widget.controller.pinnedMessages;
    });
  }

  bool _canShowImagePreview(MessageModel msg) {
    return msg.isImage || msg.type == 'VIDEO';
  }

  String _contentPreview(MessageModel msg) {
    if (msg.content.trim().isNotEmpty) return msg.content.trim();
    switch (msg.type) {
      case 'IMAGE':
        return '[Hình ảnh]';
      case 'VIDEO':
        return '[Video]';
      case 'FILE':
        return '[Tệp đính kèm]';
      case 'VOICE':
        return '[Tin nhắn thoại]';
      default:
        return '[Tin nhắn]';
    }
  }

  Widget _buildAvatar(MessageModel msg) {
    final url = widget.memberAvatars[msg.senderId]?.trim() ?? widget.chatAvatar?.trim() ?? '';
    if (url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: 42,
          height: 42,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackAvatar(msg),
        ),
      );
    }
    return _fallbackAvatar(msg);
  }

  Widget _fallbackAvatar(MessageModel msg) {
    final name = widget.memberNames[msg.senderId] ?? widget.chatTitle;
    final first = name.isNotEmpty ? name[0] : 'U';
    return Container(
      width: 42,
      height: 42,
      decoration: const BoxDecoration(
        color: AppColors.bgCardLight,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        first.toUpperCase(),
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: _items.isEmpty
          ? const Center(
              child: Text(
                'Chưa có tin nhắn nào được ghim.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
            )
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () async {
                await widget.controller.loadPinnedMessages();
              },
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(
                  height: 1,
                  thickness: 0.8,
                  color: AppColors.divider,
                ),
                itemBuilder: (_, i) {
                  final msg = _items[i];
                  return InkWell(
                    onTap: () => Navigator.pop(context, msg.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildAvatar(msg),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        widget.memberNames[msg.senderId] ?? 'Người dùng',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      du.DateUtils.formatMessageTime(
                                        msg.createdAt,
                                      ),
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 12,
                                        color: AppColors.textHint,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                if (_canShowImagePreview(msg))
                                  Container(
                                    width: double.infinity,
                                    height: 140,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: AppColors.bgCard,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.network(
                                        msg.type == 'VIDEO'
                                            ? (msg.metadata?.thumbnailUrl ??
                                                  msg.metadata?.thumbnail ??
                                                  '')
                                            : msg.content,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Center(
                                              child: Icon(
                                                Icons
                                                    .image_not_supported_outlined,
                                                color: AppColors.textHint,
                                              ),
                                            ),
                                      ),
                                    ),
                                  )
                                else
                                  Text(
                                    _contentPreview(msg),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 14,
                                      color: AppColors.textPrimary,
                                      height: 1.35,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.textHint,
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
