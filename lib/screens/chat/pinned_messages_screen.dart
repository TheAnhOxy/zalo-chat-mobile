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
  bool _actionBusy = false;

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

  String _senderName(MessageModel msg) {
    final name = widget.memberNames[msg.senderId]?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return 'Người dùng';
  }

  Future<void> _openPinnedActions(MessageModel msg) async {
    if (_actionBusy) return;
    final sender = _senderName(msg);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Text(
                    'Tin nhắn của $sender',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFEEEEEE)),
                _ActionTile(
                  label: 'Xóa khỏi bảng tin nhắn ghim',
                  onTap: () async {
                    if (_actionBusy) return;
                    setState(() => _actionBusy = true);
                    Navigator.pop(ctx);
                    try {
                      await widget.controller.unpinMessage(msg.id);
                      await widget.controller.loadPinnedMessages(
                        replaceExisting: true,
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Đã bỏ ghim tin nhắn',
                            style: TextStyle(fontFamily: 'Inter', color: Colors.white),
                          ),
                          backgroundColor: AppColors.primary,
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    } finally {
                      if (mounted) setState(() => _actionBusy = false);
                    }
                  },
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
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
                                        _senderName(msg),
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
                          const SizedBox(width: 6),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: IconButton(
                              onPressed: _actionBusy ? null : () => _openPinnedActions(msg),
                              icon: const Icon(
                                Icons.more_horiz_rounded,
                                color: AppColors.textHint,
                              ),
                              tooltip: 'Tùy chọn',
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

class _ActionTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ActionTile({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}
