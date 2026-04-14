import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/date_utils.dart' as du;
import '../../data/models/models.dart';
import '../../services/auth_service.dart';
import '../../services/api_service.dart'; // Import ApiService
import '../../services/socket_service.dart'; // Import SocketService
import '../../widgets/common/common_widgets.dart';
import '../call/voice_call_screen.dart';
import '../call/video_call_screen.dart';
import 'package:uuid/uuid.dart';
import 'dart:developer';
import '../../data/models/chat_item.dart';

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
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();

  // 1. Thay đổi List messages khởi tạo rỗng và thêm biến loading
  List<MessageModel> _messages = [];
  bool _isLoading = true;
  bool _showEmoji = false;
  bool _showExtra = false;
  MessageModel? _replyTo;
  bool _isTyping = false;
  int _selectedBackgroundIndex = 0;
  List<ChatItem> _chatItems = [];

  static const List<_ChatBackgroundOption> _backgroundOptions = [
    _ChatBackgroundOption(
      label: 'Mặc định',
      gradient: LinearGradient(
        colors: [Color(0xFFEEF1F6), Color(0xFFE3E8EF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    _ChatBackgroundOption(
      label: 'Sky',
      gradient: LinearGradient(
        colors: [Color(0xFFEAF6FF), Color(0xFFD4ECFF)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    ),
    _ChatBackgroundOption(
      label: 'Mint',
      gradient: LinearGradient(
        colors: [Color(0xFFE9FFF6), Color(0xFFD4F5E8)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    _ChatBackgroundOption(
      label: 'Sunset',
      gradient: LinearGradient(
        colors: [Color(0xFFFFF1E6), Color(0xFFFFDCC6)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
  ];

  final _uuid = const Uuid();

  String get _backgroundPrefKey => 'chat_bg_${widget.conversationId}';

  @override
  void initState() {
    super.initState();
    _restoreBackground();
    _loadMessages(); // Lấy lịch sử từ MongoDB
    _initSocket(); // Kết nối real-time
  }

  // 2. Lấy lịch sử tin nhắn từ API
  Future<void> _loadMessages() async {
    try {
      final results = await Future.wait([
        apiService.getMessages(widget.conversationId),
        apiService.getCalls(widget.conversationId),
      ]);

      final msgs = _normalizeMessages(results[0] as List<MessageModel>);
      final calls = (results[1] as List<Map<String, dynamic>>)
          .map((e) => CallModel.fromJson(e))
          .toList();

      // Merge và sort theo thời gian tăng dần
      final items = <ChatItem>[
        ...msgs.map((m) => ChatItem.message(m)),
        ...calls.map((c) => ChatItem.call(c)),
      ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      setState(() {
        _messages = msgs;
        _chatItems = items;
        _isLoading = false;
      });
      _emitSeenForLatest();
      _scrollToBottom(animated: false);
    } catch (e) {
      log('❌ Lỗi tải: $e');
      setState(() => _isLoading = false);
    }
  }

  // 3. Khởi tạo Socket và các sự kiện lắng nghe
  void _initSocket() {
    // Tham gia phòng chat
    socketService.emit('join_conversation', {
      'conversationId': widget.conversationId,
    });

    // Lắng nghe tin nhắn mới
    socketService.on('new_message', (data) {
      try {
        final map = data is Map<String, dynamic>
            ? data
            : Map<String, dynamic>.from(data as Map);
        final newMessage = _normalizeMessage(MessageModel.fromJson(map));
        if (newMessage.conversationId == widget.conversationId) {
          setState(() {
            _messages = _upsertMessage(_messages, newMessage);
            // Thêm vào chatItems nếu chưa có
            final exists = _chatItems.any(
              (i) =>
                  i.type == ChatItemType.message &&
                  i.message?.id == newMessage.id,
            );
            if (!exists) {
              _chatItems = [..._chatItems, ChatItem.message(newMessage)]
                ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
            }
          });
          _emitSeenForLatest();
          _scrollToBottom();
        }
      } catch (e) {
        log('❌ Lỗi parse new_message: $e');
      }
    });

    socketService.on('message_seen', (data) {
      try {
        if (data['conversationId'] != widget.conversationId) return;
        final messageId = data['messageId']?.toString();
        if (messageId == null || messageId.isEmpty) return;
        final status = data['status']?.toString();
        final rawSeenBy = (data['seenBy'] as List?) ?? const [];
        final seenBy = rawSeenBy
            .whereType<Map>()
            .map((s) => SeenBy.fromJson(Map<String, dynamic>.from(s)))
            .toList();

        setState(() {
          final idx = _messages.indexWhere((m) => m.id == messageId);
          if (idx == -1) return;
          final old = _messages[idx];
          _messages[idx] = MessageModel(
            id: old.id,
            conversationId: old.conversationId,
            senderId: old.senderId,
            type: old.type,
            content: old.content,
            metadata: old.metadata,
            replyToId: old.replyToId,
            status: status ?? old.status,
            isRecalled: old.isRecalled,
            deletedBy: old.deletedBy,
            reactions: old.reactions,
            seenBy: seenBy.isNotEmpty ? seenBy : old.seenBy,
            createdAt: old.createdAt,
          );
          _messages = _normalizeMessages(_messages);
        });
      } catch (_) {}
    });

    for (final event in const [
      'message_reaction_updated',
      'reaction_updated',
      'message_reaction',
    ]) {
      socketService.on(event, _handleReactionEvent);
    }

    for (final event in const ['conversation_theme_changed', 'theme_changed']) {
      socketService.on(event, _handleThemeEvent);
    }

    // Lắng nghe sự kiện typing (Nếu backend có phát)
    socketService.on('typing', (data) {
      if (data['conversationId'] == widget.conversationId &&
          data['userId'] != authService.userId) {
        setState(() => _isTyping = true);
      }
    });

    socketService.on('stop_typing', (data) {
      if (data['conversationId'] == widget.conversationId) {
        setState(() => _isTyping = false);
      }
    });
  }

  @override
  void dispose() {
    // 4. Hủy lắng nghe để tránh trùng lặp tin nhắn khi quay lại
    socketService.off('new_message');
    socketService.off('typing');
    socketService.off('stop_typing');
    socketService.off('message_seen');
    socketService.off('message_reaction_updated');
    socketService.off('reaction_updated');
    socketService.off('message_reaction');
    socketService.off('conversation_theme_changed');
    socketService.off('theme_changed');
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<MessageModel> _normalizeMessages(List<MessageModel> input) {
    final byId = <String, MessageModel>{};
    for (final m in input) {
      byId[m.id] = _normalizeMessage(m);
    }
    final list = byId.values.toList()
      ..sort((a, b) {
        final c = a.createdAt.compareTo(b.createdAt);
        if (c != 0) return c;
        return a.id.compareTo(b.id);
      });
    return list;
  }

  MessageModel _normalizeMessage(MessageModel m) {
    return MessageModel(
      id: m.id,
      conversationId: m.conversationId,
      senderId: m.senderId,
      type: m.type,
      content: m.content,
      metadata: m.metadata,
      replyToId: m.replyToId,
      status: m.status,
      isRecalled: m.isRecalled,
      deletedBy: m.deletedBy,
      reactions: m.reactions,
      seenBy: m.seenBy,
      createdAt: m.createdAt.toLocal(),
    );
  }

  List<MessageModel> _upsertMessage(
    List<MessageModel> source,
    MessageModel next,
  ) {
    final idx = source.indexWhere((m) => m.id == next.id);
    if (idx == -1) {
      return _normalizeMessages([...source, next]);
    }
    final copied = [...source];
    copied[idx] = next;
    return _normalizeMessages(copied);
  }

  Map<String, dynamic>? _tryMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      try {
        return Map<String, dynamic>.from(data);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  void _handleReactionEvent(dynamic data) {
    final map = _tryMap(data);
    if (map == null) return;
    final convId = map['conversationId']?.toString();
    if (convId != null && convId != widget.conversationId) return;

    final messageData = _tryMap(map['message']);
    if (messageData != null) {
      final next = _normalizeMessage(MessageModel.fromJson(messageData));
      if (next.conversationId != widget.conversationId) return;
      setState(() {
        _messages = _upsertMessage(_messages, next);
      });
      return;
    }

    final messageId = map['messageId']?.toString();
    if (messageId == null || messageId.isEmpty) return;
    final raw = map['reactions'];
    if (raw is! List) return;
    final nextReactions = raw
        .whereType<Map>()
        .map((r) => Reaction.fromJson(Map<String, dynamic>.from(r)))
        .toList();

    setState(() {
      final idx = _messages.indexWhere((m) => m.id == messageId);
      if (idx == -1) return;
      final old = _messages[idx];
      _messages[idx] = MessageModel(
        id: old.id,
        conversationId: old.conversationId,
        senderId: old.senderId,
        type: old.type,
        content: old.content,
        metadata: old.metadata,
        replyToId: old.replyToId,
        status: old.status,
        isRecalled: old.isRecalled,
        deletedBy: old.deletedBy,
        reactions: nextReactions,
        seenBy: old.seenBy,
        createdAt: old.createdAt,
      );
      _messages = _normalizeMessages(_messages);
    });
  }

  Future<void> _restoreBackground() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_backgroundPrefKey);
    if (!mounted || idx == null) return;
    if (idx < 0 || idx >= _backgroundOptions.length) return;
    setState(() => _selectedBackgroundIndex = idx);
  }

  Future<void> _setBackground(int index, {bool emitSync = false}) async {
    setState(() => _selectedBackgroundIndex = index);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_backgroundPrefKey, index);

    if (emitSync) {
      socketService.emit('change_conversation_theme', {
        'conversationId': widget.conversationId,
        'backgroundIndex': index,
      });
    }
  }

  void _handleThemeEvent(dynamic data) {
    final map = _tryMap(data);
    if (map == null) return;
    if (map['conversationId']?.toString() != widget.conversationId) return;
    final index = map['backgroundIndex'];
    if (index is! int) return;
    if (index < 0 || index >= _backgroundOptions.length) return;
    _setBackground(index);
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

  // 5. Gửi tin nhắn thật qua Socket
  void _sendMessage() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    final msgData = {
      'conversationId': widget.conversationId,
      'senderId': authService.userId!,
      'content': text,
      'type': 'TEXT',
      if (_replyTo != null) 'replyToId': _replyTo!.id,
    };

    socketService.sendMessage(msgData);

    setState(() {
      _textCtrl.clear();
      _replyTo = null;
      _showEmoji = false;
    });
  }

  void _emitSeenForLatest() {
    final unread = _messages.where(
      (m) =>
          m.senderId != authService.userId &&
          !m.isRecalled &&
          !_isSeenByCurrentUser(m),
    );
    if (unread.isEmpty) return;
    final latest = unread.last;
    socketService.emit('seen_message', {
      'conversationId': widget.conversationId,
      'messageId': latest.id,
      'userId': authService.userId,
    });
  }

  bool _isSeenByCurrentUser(MessageModel msg) {
    if (msg.senderId == authService.userId) return false;
    return msg.seenBy.any((s) => s.userId == authService.userId);
  }

  bool _isSeenByPeer(MessageModel msg) {
    if (msg.status == 'SEEN') return true;
    final peerId = widget.otherUser?.id;
    if (peerId != null && peerId.isNotEmpty) {
      return msg.seenBy.any((s) => s.userId == peerId);
    }
    return msg.seenBy.isNotEmpty;
  }

  String? _lastOutgoingMessageId() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].senderId == authService.userId) {
        return _messages[i].id;
      }
    }
    return null;
  }

  void _showAppearanceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Đổi nền đoạn chat',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: List.generate(_backgroundOptions.length, (i) {
                  final item = _backgroundOptions[i];
                  final active = i == _selectedBackgroundIndex;
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _setBackground(i, emitSync: true);
                    },
                    child: Container(
                      width: 76,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.bgCardLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: active ? AppColors.primary : AppColors.border,
                          width: active ? 1.6 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: item.gradient,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.label,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textPrimary,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  // Các hàm reaction và thu hồi tin nhắn sẽ gọi API/Socket ở đây (nâng cấp sau)
  void _addReaction(MessageModel msg, String type) {
    setState(() {
      final idx = _messages.indexWhere((m) => m.id == msg.id);
      if (idx == -1) return;
      final old = _messages[idx];
      final me = authService.userId ?? '';
      final nextReactions = old.reactions.where((r) => r.userId != me).toList()
        ..add(Reaction(userId: me, type: type));

      _messages[idx] = MessageModel(
        id: old.id,
        conversationId: old.conversationId,
        senderId: old.senderId,
        type: old.type,
        content: old.content,
        metadata: old.metadata,
        replyToId: old.replyToId,
        status: old.status,
        isRecalled: old.isRecalled,
        deletedBy: old.deletedBy,
        reactions: nextReactions,
        seenBy: old.seenBy,
        createdAt: old.createdAt,
      );
      _messages = _normalizeMessages(_messages);
    });

    socketService.emit('add_reaction', {
      'messageId': msg.id,
      'reactionType': type,
      'userId': authService.userId,
    });
    // UI sẽ cập nhật khi nhận lại event từ socket hoặc tối ưu hóa local tại đây
  }

  ConversationMember? _getMemberInfo(String userId) {
    try {
      return widget.conversation.members.firstWhere((m) => m.userId == userId);
    } catch (e) {
      return null;
    }
  }

  void _recallMessage(MessageModel msg) {
    // Gửi sự kiện thu hồi tin nhắn lên Server NestJS
    socketService.emit('recall_message', {
      'messageId': msg.id,
      'conversationId': widget.conversationId,
    });

    // Thông báo cho UI local (tùy chọn, vì socket sẽ trả về event cho cả 2)
    setState(() {
      final idx = _messages.indexWhere((m) => m.id == msg.id);
      if (idx != -1) {
        _messages[idx] = MessageModel(
          id: msg.id,
          conversationId: msg.conversationId,
          senderId: msg.senderId,
          content: msg.content,
          isRecalled: true,
          createdAt: msg.createdAt,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isGroup = widget.conversation.isGroup;
    final lastOutgoingMessageId = _lastOutgoingMessageId();
    final title = isGroup
        ? widget.conversation.name ?? 'Nhóm'
        : widget.otherUser?.fullName ?? 'Chat';

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(title, isGroup),
            const Divider(color: AppColors.divider, height: 1),

            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        gradient: _backgroundOptions[_selectedBackgroundIndex]
                            .gradient,
                      ),
                      child: GestureDetector(
                        onTap: () {
                          _focusNode.unfocus();
                          setState(() {
                            _showEmoji = false;
                            _showExtra = false;
                          });
                        },
                        child: ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          itemCount: _chatItems.length + (_isTyping ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i == _chatItems.length)
                              return _buildTypingIndicator();

                            final item = _chatItems[i];
                            final prevItem = i > 0 ? _chatItems[i - 1] : null;
                            final showDate =
                                prevItem == null ||
                                !du.DateUtils.isSameDay(
                                  prevItem.createdAt,
                                  item.createdAt,
                                );

                            return Column(
                              children: [
                                if (showDate)
                                  ChatDateDivider(
                                    label: du.DateUtils.formatDateSeparator(
                                      item.createdAt,
                                    ),
                                  ),
                                if (item.type == ChatItemType.call)
                                  _buildCallBubble(item.call!)
                                else
                                  _buildMessageBubble(item.message!, i),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
            ),

            if (_replyTo != null) _buildReplyPreview(),
            _buildInputBar(),
            if (_showEmoji) _buildEmojiPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(MessageModel msg, int i) {
    final lastOutgoingMessageId = _lastOutgoingMessageId();
    final isGroup = widget.conversation.isGroup;
    final senderMember = _getMemberInfo(msg.senderId);

    return _MessageBubble(
      msg: msg,
      isMe: msg.senderId.toString() == authService.userId.toString(),
      senderUser: isGroup ? null : widget.otherUser,
      senderMember: senderMember,
      showSenderName: isGroup && msg.senderId != authService.userId,
      showSeenLabel:
          !isGroup && msg.id == lastOutgoingMessageId && _isSeenByPeer(msg),
      replyToMsg: msg.replyToId != null
          ? _messages.firstWhere(
              (m) => m.id == msg.replyToId,
              orElse: () => msg,
            )
          : null,
      onLongPress: () => _showMessageActions(msg),
      onDoubleTap: () => _addReaction(msg, 'LIKE'),
      onReply: () => setState(() => _replyTo = msg),
    );
  }

  Widget _buildCallBubble(CallModel call) {
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
      label = isMe ? 'Bạn đã gọi nhưng không nghe' : 'Cuộc gọi nhỡ';
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
        left: isMe ? 60 : 34, // 👈 tăng số này
        right: isMe ? 6 : 60, // 👈 giữ khoảng cách bên phải
      ),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            /// 🔹 Bubble
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

            /// 🔹 Time (đưa ra ngoài giống message)
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
                  avatarUrls: widget.conversation.members
                      .take(3)
                      .map((m) => (_getMemberInfo(m.userId))?.userId)
                      .toList(), // Hoặc .avatar tùy model
                  names: widget.conversation.members
                      .take(3)
                      .map(
                        (m) => (_getMemberInfo(m.userId))?.nickname ?? m.userId,
                      )
                      .toList(),
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
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  isGroup
                      ? '${widget.conversation.members.length} thành viên'
                      : online
                      ? 'Đang hoạt động'
                      : 'Ngoại tuyến',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'Inter',
                    color: online ? AppColors.online : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Voice call
          if (!isGroup && widget.conversation.id != 'CONV_AI')
            IconButton(
              icon: const Icon(
                Icons.phone_outlined,
                color: AppColors.textPrimary,
                size: 24,
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VoiceCallScreen(
                    otherUser: widget.otherUser!,
                    isIncoming: false,
                    conversationId: widget.conversationId,
                  ),
                ),
              ),
            ),
          // Video call
          if (!isGroup && widget.conversation.id != 'CONV_AI')
            IconButton(
              icon: const Icon(
                Icons.videocam_outlined,
                color: AppColors.textPrimary,
                size: 24,
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => VideoCallScreen(
                    otherUser: widget.otherUser!,
                    isIncoming: false,
                    conversationId: widget.conversationId,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(
              Icons.wallpaper_outlined,
              color: AppColors.textPrimary,
              size: 22,
            ),
            onPressed: _showAppearanceSheet,
          ),
          IconButton(
            icon: const Icon(
              Icons.info_outline,
              color: AppColors.textPrimary,
              size: 22,
            ),
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
            topLeft: Radius.circular(4),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
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
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Trả lời',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Inter',
                  ),
                ),
                Text(
                  _replyTo!.content,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.close,
              color: AppColors.textSecondary,
              size: 18,
            ),
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
            onTap: () => setState(() {
              _showEmoji = !_showEmoji;
              _showExtra = false;
            }),
            child: Icon(
              _showEmoji ? Icons.keyboard : Icons.emoji_emotions_outlined,
              color: _showEmoji ? AppColors.primary : AppColors.textSecondary,
              size: 26,
            ),
          ),
          const SizedBox(width: 6),
          // Image
          GestureDetector(
            onTap: () {},
            child: const Icon(
              Icons.image_outlined,
              color: AppColors.textSecondary,
              size: 26,
            ),
          ),
          const SizedBox(width: 6),
          // Voice
          GestureDetector(
            onTap: () {},
            child: const Icon(
              Icons.mic_outlined,
              color: AppColors.textSecondary,
              size: 26,
            ),
          ),
          const SizedBox(width: 8),

          // TextField
          Expanded(
            child: TextField(
              controller: _textCtrl,
              focusNode: _focusNode,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontFamily: 'Inter',
                fontSize: 14,
              ),
              maxLines: 4,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Nhập tin nhắn...',
                hintStyle: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 14,
                  fontFamily: 'Inter',
                ),
                filled: true,
                fillColor: AppColors.bgInput,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),

          // Send / Voice record
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _textCtrl,
            builder: (_, val, _) {
              final hasText = val.text.trim().isNotEmpty;
              return GestureDetector(
                onTap: hasText ? _sendMessage : () {},
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: hasText ? AppColors.primaryGradient : null,
                    color: hasText ? null : AppColors.bgInput,
                    shape: BoxShape.circle,
                    boxShadow: hasText
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.4),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    hasText ? Icons.send_rounded : Icons.thumb_up_outlined,
                    color: hasText ? Colors.white : AppColors.textSecondary,
                    size: 20,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiPanel() {
    const emojis = [
      '😀',
      '😂',
      '😍',
      '😎',
      '😭',
      '🥺',
      '😡',
      '😱',
      '👍',
      '❤️',
      '🔥',
      '✨',
      '🎉',
      '💯',
      '👏',
      '🙏',
    ];
    return Container(
      height: 220,
      color: AppColors.bgCard,
      child: GridView.count(
        crossAxisCount: 8,
        padding: const EdgeInsets.all(12),
        children: emojis
            .map(
              (e) => GestureDetector(
                onTap: () {
                  _textCtrl.text += e;
                  setState(() {});
                },
                child: Center(
                  child: Text(e, style: const TextStyle(fontSize: 26)),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  void _showMessageActions(MessageModel msg) {
    final isMe = msg.senderId == authService.userId;
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Reaction row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ['LIKE', 'LOVE', 'HAHA', 'WOW', 'SAD', 'ANGRY'].map((
                  type,
                ) {
                  final r = Reaction(userId: '', type: type);
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _addReaction(msg, type);
                    },
                    child: Text(r.emoji, style: const TextStyle(fontSize: 30)),
                  );
                }).toList(),
              ),
            ),
            const Divider(color: AppColors.divider),

            ListTile(
              leading: const Icon(
                Icons.reply,
                color: AppColors.textPrimary,
                size: 22,
              ),
              title: const Text(
                'Trả lời',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Inter',
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                setState(() => _replyTo = msg);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.copy,
                color: AppColors.textPrimary,
                size: 22,
              ),
              title: const Text(
                'Sao chép',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Inter',
                ),
              ),
              onTap: () {
                Clipboard.setData(ClipboardData(text: msg.content));
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.forward,
                color: AppColors.textPrimary,
                size: 22,
              ),
              title: const Text(
                'Chuyển tiếp',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Inter',
                ),
              ),
              onTap: () => Navigator.pop(context),
            ),
            if (isMe && !msg.isRecalled)
              ListTile(
                leading: const Icon(
                  Icons.undo,
                  color: AppColors.error,
                  size: 22,
                ),
                title: const Text(
                  'Thu hồi',
                  style: TextStyle(color: AppColors.error, fontFamily: 'Inter'),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _recallMessage(msg);
                },
              ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: AppColors.error,
                size: 22,
              ),
              title: const Text(
                'Xoá (phía tôi)',
                style: TextStyle(color: AppColors.error, fontFamily: 'Inter'),
              ),
              onTap: () {
                Navigator.pop(context);
                setState(() => _messages.removeWhere((m) => m.id == msg.id));
              },
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
  final ConversationMember? senderMember;
  final bool showSenderName;
  final bool showSeenLabel;
  final MessageModel? replyToMsg;
  final VoidCallback onLongPress;
  final VoidCallback onDoubleTap;
  final VoidCallback onReply;

  const _MessageBubble({
    required this.msg,
    required this.isMe,
    this.senderUser,
    this.senderMember,
    this.showSenderName = false,
    this.showSeenLabel = false,
    this.replyToMsg,
    required this.onLongPress,
    required this.onDoubleTap,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    if (msg.isRecalled) return _buildRecalled();
    final senderDisplayName =
        senderMember?.nickname ??
        senderMember?.userId ??
        senderUser?.fullName ??
        'User';

    return GestureDetector(
      onLongPress: onLongPress,
      onDoubleTap: onDoubleTap,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: 6,
          left: isMe ? 50 : 3,
          right: isMe ? 3 : 50,
        ),
        child: Row(
          mainAxisAlignment: isMe
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe && (senderUser != null || senderMember != null)) ...[
              AvatarWidget(
                url: senderUser?.avatar,
                name: senderDisplayName,
                size: 28,
              ),
              const SizedBox(width: 6),
            ],
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.68,
              ),
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (showSenderName &&
                      (senderUser != null || senderMember != null))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2, left: 4),
                      child: Text(
                        senderDisplayName,
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
      content = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          msg.content,
          width: 200,
          height: 150,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox(
            width: 200,
            height: 100,
            child: Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                color: AppColors.textHint,
              ),
            ),
          ),
        ),
      );
    } else if (msg.type == 'FILE') {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.insert_drive_file_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg.content,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Inter',
                  ),
                  maxLines: 2,
                ),
                if (msg.metadata?.fileSize != null)
                  Text(
                    '${(msg.metadata!.fileSize! / 1024 / 1024).toStringAsFixed(1)} MB',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.bubbleMeText,
                      fontFamily: 'Inter',
                    ),
                  ),
              ],
            ),
          ),
        ],
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
      padding: msg.isImage
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
}

// ── Dot Animation (typing indicator) ─────────────────────────────────────────
class _DotAnimation extends StatefulWidget {
  final int delay;
  const _DotAnimation({required this.delay});

  @override
  State<_DotAnimation> createState() => _DotAnimationState();
}

class _DotAnimationState extends State<_DotAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _anim = Tween<double>(
      begin: 0,
      end: -5,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, _) => Transform.translate(
      offset: Offset(0, _anim.value),
      child: Container(
        width: 7,
        height: 7,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: const BoxDecoration(
          color: AppColors.textSecondary,
          shape: BoxShape.circle,
        ),
      ),
    ),
  );
}

class _ChatBackgroundOption {
  final String label;
  final Gradient gradient;

  const _ChatBackgroundOption({required this.label, required this.gradient});
}
