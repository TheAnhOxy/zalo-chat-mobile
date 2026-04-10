import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/date_utils.dart' as du;
import '../../data/mock/mock_data.dart';
import '../../data/models/models.dart';
import '../../services/auth_service.dart';
import '../../widgets/common/common_widgets.dart';
import '../call/voice_call_screen.dart';
import '../call/video_call_screen.dart';
import 'package:uuid/uuid.dart';

class ChatDetailScreen extends StatefulWidget {
  final String conversationId;
  final UserModel? otherUser;
  final ConversationModel conversation;

  const ChatDetailScreen({
    super.key,
    required this.conversationId,
    required this.otherUser,
    required this.conversation,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _textCtrl    = TextEditingController();
  final _scrollCtrl  = ScrollController();
  final _focusNode   = FocusNode();

  late List<MessageModel> _messages;
  bool _showEmoji    = false;
  bool _showExtra    = false;
  MessageModel? _replyTo;
  bool _isTyping     = false; // fake typing indicator

  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _messages = List.from(getMessages(widget.conversationId));
    _startFakeTyping();
  }

  void _startFakeTyping() {
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _isTyping = true);
      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() => _isTyping = false);
      });
    });
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        if (animated) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        }
      }
    });
  }

  void _sendMessage() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    final msg = MessageModel(
      id: _uuid.v4(),
      conversationId: widget.conversationId,
      senderId: authService.userId!,
      content: text,
      replyToId: _replyTo?.id,
      status: 'SENDING',
      createdAt: DateTime.now(),
    );
    setState(() {
      _messages.add(msg);
      _textCtrl.clear();
      _replyTo = null;
    });
    _scrollToBottom();
    // Fake: SENDING → SENT after 500ms
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final idx = _messages.indexWhere((m) => m.id == msg.id);
      if (idx < 0) return;
      setState(() {
        _messages[idx] = MessageModel(
          id: msg.id, conversationId: msg.conversationId,
          senderId: msg.senderId, content: msg.content,
          status: 'SENT', createdAt: msg.createdAt,
        );
      });
    });
  }

  void _recallMessage(MessageModel msg) {
    final idx = _messages.indexWhere((m) => m.id == msg.id);
    if (idx < 0) return;
    setState(() {
      _messages[idx] = MessageModel(
        id: msg.id, conversationId: msg.conversationId,
        senderId: msg.senderId, content: msg.content,
        isRecalled: true, status: msg.status, createdAt: msg.createdAt,
      );
    });
  }

  void _addReaction(MessageModel msg, String type) {
    final idx = _messages.indexWhere((m) => m.id == msg.id);
    if (idx < 0) return;
    final uid = authService.userId!;
    final reactions = List<Reaction>.from(msg.reactions)
      ..removeWhere((r) => r.userId == uid)
      ..add(Reaction(userId: uid, type: type));
    setState(() {
      _messages[idx] = MessageModel(
        id: msg.id, conversationId: msg.conversationId,
        senderId: msg.senderId, content: msg.content,
        type: msg.type, status: msg.status, replyToId: msg.replyToId,
        isRecalled: msg.isRecalled, reactions: reactions,
        seenBy: msg.seenBy, createdAt: msg.createdAt,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isGroup = widget.conversation.isGroup;
    final title = isGroup ? widget.conversation.name ?? 'Nhóm'
                          : widget.otherUser?.fullName ?? 'Chat';

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────
            _buildHeader(title, isGroup),
            const Divider(color: AppColors.divider, height: 1),

            // ── Messages ───────────────────────────────────────
            Expanded(
              child: GestureDetector(
                onTap: () {
                  _focusNode.unfocus();
                  setState(() { _showEmoji = false; _showExtra = false; });
                },
                child: ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _messages.length + (_isTyping ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _messages.length) return _buildTypingIndicator();
                    final msg = _messages[i];
                    final prev = i > 0 ? _messages[i - 1] : null;
                    final showDate = prev == null ||
                        !du.DateUtils.isSameDay(prev.createdAt, msg.createdAt);
                    return Column(
                      children: [
                        if (showDate) ChatDateDivider(label: du.DateUtils.formatDateSeparator(msg.createdAt)),
                        _MessageBubble(
                          msg: msg,
                          isMe: msg.senderId == authService.userId,
                          senderUser: isGroup ? getUser(msg.senderId) : null,
                          showSenderName: isGroup && msg.senderId != authService.userId,
                          replyToMsg: msg.replyToId != null
                              ? _messages.firstWhere((m) => m.id == msg.replyToId, orElse: () => msg)
                              : null,
                          onLongPress: () => _showMessageActions(msg),
                          onReply: () => setState(() => _replyTo = msg),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

            // ── Reply Preview ──────────────────────────────────
            if (_replyTo != null) _buildReplyPreview(),

            // ── Input Bar ──────────────────────────────────────
            _buildInputBar(),

            // ── Emoji (toggle) ─────────────────────────────────
            if (_showEmoji) _buildEmojiPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String title, bool isGroup) {
    final online = widget.otherUser?.isOnline ?? false;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      color: AppColors.bgDark,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          isGroup
              ? GroupAvatarWidget(
                  avatarUrls: widget.conversation.members.take(3).map((m) => getUser(m.userId)?.avatar).toList(),
                  names: widget.conversation.members.take(3).map((m) => getUser(m.userId)?.fullName ?? '').toList(),
                  size: 38,
                )
              : AvatarWidget(
                  url: widget.otherUser?.avatar,
                  name: title,
                  size: 38,
                  showOnline: true,
                  isOnline: online,
                ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontFamily: 'Inter'),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  isGroup
                      ? '${widget.conversation.members.length} thành viên · ${widget.conversation.members.where((m) => getUser(m.userId)?.isOnline ?? false).length} đang hoạt động'
                      : online ? 'Đang hoạt động' : 'Ngoại tuyến',
                  style: TextStyle(
                    fontSize: 12, fontFamily: 'Inter',
                    color: online ? AppColors.online : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Voice call
          if (!isGroup && widget.conversation.id != 'CONV_AI')
            IconButton(
              icon: const Icon(Icons.phone_outlined, color: AppColors.textPrimary, size: 22),
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => VoiceCallScreen(otherUser: widget.otherUser!, isIncoming: false))),
            ),
          // Video call
          if (!isGroup && widget.conversation.id != 'CONV_AI')
            IconButton(
              icon: const Icon(Icons.videocam_outlined, color: AppColors.textPrimary, size: 24),
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => VideoCallScreen(otherUser: widget.otherUser!, isIncoming: false))),
            ),
          IconButton(
            icon: const Icon(Icons.info_outline, color: AppColors.textPrimary, size: 22),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 0, bottom: 8, top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bubbleOther,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4), topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) => _DotAnimation(delay: i * 200)),
        ),
      ),
    );
  }

  Widget _buildReplyPreview() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.bgCardLight,
      child: Row(
        children: [
          Container(width: 3, height: 36, decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Trả lời', style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
                Text(_replyTo!.content, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontFamily: 'Inter'), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 18),
            onPressed: () => setState(() => _replyTo = null),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          // Emoji
          GestureDetector(
            onTap: () => setState(() { _showEmoji = !_showEmoji; _showExtra = false; }),
            child: Icon(_showEmoji ? Icons.keyboard : Icons.emoji_emotions_outlined,
                color: _showEmoji ? AppColors.primary : AppColors.textSecondary, size: 26),
          ),
          const SizedBox(width: 6),
          // Image
          GestureDetector(
            onTap: () {},
            child: const Icon(Icons.image_outlined, color: AppColors.textSecondary, size: 26),
          ),
          const SizedBox(width: 6),
          // Voice
          GestureDetector(
            onTap: () {},
            child: const Icon(Icons.mic_outlined, color: AppColors.textSecondary, size: 26),
          ),
          const SizedBox(width: 8),

          // TextField
          Expanded(
            child: TextField(
              controller: _textCtrl,
              focusNode: _focusNode,
              style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Inter', fontSize: 14),
              maxLines: 4, minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Nhập tin nhắn...',
                hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14, fontFamily: 'Inter'),
                filled: true,
                fillColor: AppColors.bgInput,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),

          // Send / Voice record
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _textCtrl,
            builder: (_, val, __) {
              final hasText = val.text.trim().isNotEmpty;
              return GestureDetector(
                onTap: hasText ? _sendMessage : () {},
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: hasText ? AppColors.primaryGradient : null,
                    color: hasText ? null : AppColors.bgInput,
                    shape: BoxShape.circle,
                    boxShadow: hasText ? [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 8)] : null,
                  ),
                  child: Icon(hasText ? Icons.send_rounded : Icons.thumb_up_outlined,
                      color: hasText ? Colors.white : AppColors.textSecondary, size: 20),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiPanel() {
    const emojis = ['😀', '😂', '😍', '😎', '😭', '🥺', '😡', '😱',
                    '👍', '❤️', '🔥', '✨', '🎉', '💯', '👏', '🙏'];
    return Container(
      height: 220,
      color: AppColors.bgCard,
      child: GridView.count(
        crossAxisCount: 8,
        padding: const EdgeInsets.all(12),
        children: emojis.map((e) => GestureDetector(
          onTap: () { _textCtrl.text += e; setState(() {}); },
          child: Center(child: Text(e, style: const TextStyle(fontSize: 26))),
        )).toList(),
      ),
    );
  }

  void _showMessageActions(MessageModel msg) {
    final isMe = msg.senderId == authService.userId;
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),

            // Reaction row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ['LIKE', 'LOVE', 'HAHA', 'WOW', 'SAD', 'ANGRY'].map((type) {
                  final r = Reaction(userId: '', type: type);
                  return GestureDetector(
                    onTap: () { Navigator.pop(context); _addReaction(msg, type); },
                    child: Text(r.emoji, style: const TextStyle(fontSize: 30)),
                  );
                }).toList(),
              ),
            ),
            const Divider(color: AppColors.divider),

            ListTile(
              leading: const Icon(Icons.reply, color: AppColors.textPrimary, size: 22),
              title: const Text('Trả lời', style: TextStyle(color: AppColors.textPrimary, fontFamily: 'Inter')),
              onTap: () { Navigator.pop(context); setState(() => _replyTo = msg); },
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: AppColors.textPrimary, size: 22),
              title: const Text('Sao chép', style: TextStyle(color: AppColors.textPrimary, fontFamily: 'Inter')),
              onTap: () { Clipboard.setData(ClipboardData(text: msg.content)); Navigator.pop(context); },
            ),
            ListTile(
              leading: const Icon(Icons.forward, color: AppColors.textPrimary, size: 22),
              title: const Text('Chuyển tiếp', style: TextStyle(color: AppColors.textPrimary, fontFamily: 'Inter')),
              onTap: () => Navigator.pop(context),
            ),
            if (isMe && !msg.isRecalled)
              ListTile(
                leading: const Icon(Icons.undo, color: AppColors.error, size: 22),
                title: const Text('Thu hồi', style: TextStyle(color: AppColors.error, fontFamily: 'Inter')),
                onTap: () { Navigator.pop(context); _recallMessage(msg); },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error, size: 22),
              title: const Text('Xoá (phía tôi)', style: TextStyle(color: AppColors.error, fontFamily: 'Inter')),
              onTap: () { Navigator.pop(context); setState(() => _messages.removeWhere((m) => m.id == msg.id)); },
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}

// ── MessageBubble Widget ──────────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMe;
  final UserModel? senderUser;
  final bool showSenderName;
  final MessageModel? replyToMsg;
  final VoidCallback onLongPress;
  final VoidCallback onReply;

  const _MessageBubble({
    required this.msg,
    required this.isMe,
    this.senderUser,
    this.showSenderName = false,
    this.replyToMsg,
    required this.onLongPress,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    if (msg.isRecalled) return _buildRecalled();

    return GestureDetector(
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe && senderUser != null) ...[
              AvatarWidget(url: senderUser!.avatar, name: senderUser!.fullName, size: 28),
              const SizedBox(width: 6),
            ],
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.68),
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (showSenderName && senderUser != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2, left: 4),
                      child: Text(senderUser!.fullName,
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontFamily: 'Inter')),
                    ),
                  if (replyToMsg != null) _buildReplyQuote(),
                  _buildBubble(context),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(du.DateUtils.formatMessageTime(msg.createdAt),
                          style: const TextStyle(fontSize: 10, color: AppColors.textHint, fontFamily: 'Inter')),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        _buildStatusIcon(),
                      ],
                    ],
                  ),
                  if (msg.reactions.isNotEmpty) _buildReactions(),
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
      content = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(msg.content, width: 200, height: 150, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox(width: 200, height: 100,
                child: Center(child: Icon(Icons.image_not_supported_outlined, color: AppColors.textHint)))),
      );
    } else if (msg.type == 'FILE') {
      content = Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 38, height: 38, decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.insert_drive_file_outlined, color: Colors.white, size: 20)),
        const SizedBox(width: 10),
        Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(msg.content, style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500, fontFamily: 'Inter'), maxLines: 2),
          if (msg.metadata?.fileSize != null)
            Text('${(msg.metadata!.fileSize! / 1024 / 1024).toStringAsFixed(1)} MB',
                style: const TextStyle(fontSize: 11, color: AppColors.bubbleMeText, fontFamily: 'Inter')),
        ])),
      ]);
    } else {
      content = Text(msg.content,
          style: TextStyle(
            fontSize: 14, fontFamily: 'Inter',
            color: isMe ? AppColors.bubbleMeText : AppColors.bubbleOtherText,
            height: 1.4,
          ));
    }

    return Container(
      padding: msg.isImage ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? null : AppColors.bubbleOther,
        gradient: isMe ? AppColors.primaryGradient : null,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMe ? 18 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 18),
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))],
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
        border: const Border(left: BorderSide(color: AppColors.primary, width: 3)),
      ),
      child: Text(replyToMsg!.content,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontFamily: 'Inter'),
          maxLines: 2, overflow: TextOverflow.ellipsis),
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
        child: const Text('Tin nhắn đã bị thu hồi',
            style: TextStyle(fontSize: 13, color: AppColors.textHint, fontStyle: FontStyle.italic, fontFamily: 'Inter')),
      ),
    ),
  );

  Widget _buildStatusIcon() {
    switch (msg.status) {
      case 'SENDING': return const SizedBox(width: 12, height: 12,
          child: CircularProgressIndicator(color: AppColors.textHint, strokeWidth: 1.5));
      case 'SENT': return const Icon(Icons.done, size: 14, color: AppColors.textHint);
      case 'DELIVERED': return const Icon(Icons.done_all, size: 14, color: AppColors.textHint);
      case 'SEEN': return const Icon(Icons.done_all, size: 14, color: AppColors.primary);
      default: return const SizedBox.shrink();
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
        children: grouped.entries.map((e) => Container(
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.bgCardLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Text('${e.key} ${e.value}', style: const TextStyle(fontSize: 11, fontFamily: 'Inter')),
        )).toList(),
      ),
    );
  }
}

// ── Dot Animation (typing indicator) ─────────────────────────────────────────
class _DotAnimation extends StatefulWidget {
  final int delay;
  const _DotAnimation({required this.delay});

  @override
  State<_DotAnimation> createState() => _DotAnimationState();
}

class _DotAnimationState extends State<_DotAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0, end: -5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Transform.translate(
      offset: Offset(0, _anim.value),
      child: Container(
        width: 7, height: 7, margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: const BoxDecoration(color: AppColors.textSecondary, shape: BoxShape.circle),
      ),
    ),
  );
}
