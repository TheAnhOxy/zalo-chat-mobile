import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:developer' as dev;
import '../../core/constants/app_colors.dart';
import '../../core/utils/date_utils.dart' as du;
import '../../core/utils/image_utils.dart';
import '../../data/models/models.dart';
import '../../services/api_service.dart';
import '../../services/contacts_api_service.dart';
import '../../services/auth_service.dart';
import '../../services/socket_service.dart';
import '../../services/call_service.dart';
import 'group_chat_backgrounds.dart';
import 'group_options_screen.dart';
import '../call/group_voice_call_screen.dart';
import '../call/group_video_call_screen.dart';

class GroupChatScreen extends StatefulWidget {
  final ApiGroupModel group;
  const GroupChatScreen({super.key, required this.group});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();

  late ApiGroupModel _group;
  List<MessageModel> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  final Map<String, ApiUserModel> _memberProfiles = {};
  int _bgIndex = 0;
  String? _bgCustomBase64;

  // ✅ Tracking cuộc gọi nhóm đang hoạt động
  String? _activeCallId;
  String? _activeCallConversationId;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _loadBackgroundPref();
    _loadMemberProfiles();
    _loadMessages();
    _initSocket();
    // ✅ Lắng nghe sự kiện cuộc gọi
    _setupCallListeners();
  }

  // ✅ Setup listeners cho sự kiện cuộc gọi
  void _setupCallListeners() {
    socketService.on('participant_left', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      final callId = map['callId']?.toString() ?? '';
      if (callId.isNotEmpty) {
        _activeCallId = callId;
        if (mounted) setState(() {});
      }
    });

    socketService.on('call_ended', (data) {
      // Xoá active call khi call kết thúc
      _activeCallId = null;
      _activeCallConversationId = null;
      if (mounted) setState(() {});
    });

    socketService.on('conversation_call_updated', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      final conversationId = map['conversationId']?.toString() ?? '';
      if (conversationId == _group.id) {
        _activeCallConversationId = conversationId;
        if (mounted) setState(() {});
      }
    });
  }

  // ── Helpers để build GroupCallParticipant từ members ─────────────────────
  List<GroupCallParticipant> _buildParticipants() {
    final myId = authService.userId ?? '';
    return _group.members
        .where((m) => m.userId != myId)
        .map(
          (m) => GroupCallParticipant(
            userId: m.userId,
            name: _memberProfiles[m.userId]?.fullName ?? m.userId,
            avatar: _memberProfiles[m.userId]?.avatar,
          ),
        )
        .toList();
  }

  Future<void> _loadMemberProfiles() async {
    final ids = _group.members.map((m) => m.userId).where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return;
    final profiles = await ContactsApiService.instance.fetchUsersByIds(ids);
    if (!mounted) return;
    setState(() => _memberProfiles.addAll(profiles));
  }

  String _resolveMemberName(String userId) {
    if (userId == authService.userId) return 'Bạn';
    final profile = _memberProfiles[userId];
    if (profile != null && profile.fullName.isNotEmpty) return profile.fullName;
    return userId;
  }

  void _startVoiceCall() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupVoiceCallScreen(
          conversationId: _group.id,
          groupName: _group.name.isNotEmpty ? _group.name : 'Nhóm',
          callerId: authService.userId ?? '',
          groupAvatar: _group.avatar.isNotEmpty ? _group.avatar : null,
          participants: _buildParticipants(),
          isIncoming: false,
        ),
      ),
    );
  }

  void _startVideoCall() {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => GroupVideoCallScreen(
          conversationId: _group.id,
          groupName: _group.name.isNotEmpty ? _group.name : 'Nhóm',
          callerId: authService.userId ?? '',
          groupAvatar: _group.avatar.isNotEmpty ? _group.avatar : null,
          participants: _buildParticipants(),
          isIncoming: false,
        ),
      ),
    );
  }

  // ── Background loading (giữ nguyên) ──────────────────────────────────────
  Future<void> _loadBackgroundPref() async {
    final p = await SharedPreferences.getInstance();
    final idx = p.getInt('group_chat_bg_${_group.id}') ?? 0;
    final custom = p.getString('group_chat_bg_custom_${_group.id}');
    final override = p.getBool('group_chat_bg_override_${_group.id}') ?? false;
    if (!mounted) return;
    setState(() {
      _bgIndex = idx.clamp(0, GroupChatBackgrounds.count - 1);
      _bgCustomBase64 = custom;
    });
    if (!override) await _syncGroupBackgroundFromBackend();
  }

  Future<void> _syncGroupBackgroundFromBackend() async {
    final res = await ContactsApiService.instance.fetchConversationRaw(
      _group.id,
    );
    if (!res.isSuccess) return;
    final map = res.data ?? const <String, dynamic>{};
    final gs = map['groupSettings'];
    if (gs is! Map) return;

    final type = (gs['chatBackgroundType'] ?? 'PRESET').toString();
    final idxRaw = gs['chatBackgroundIndex'];
    final idx = idxRaw is num ? idxRaw.toInt() : int.tryParse('$idxRaw') ?? 0;
    final custom = (gs['chatBackgroundCustomBase64'] ?? '').toString();

    if (!mounted) return;
    setState(() {
      if (type == 'CUSTOM' && custom.isNotEmpty) {
        _bgCustomBase64 = custom;
      } else {
        _bgCustomBase64 = null;
        _bgIndex = idx.clamp(0, GroupChatBackgrounds.count - 1);
      }
    });

    final p = await SharedPreferences.getInstance();
    await p.setBool('group_chat_bg_override_${_group.id}', false);
    if (type == 'CUSTOM' && custom.isNotEmpty) {
      await p.setString('group_chat_bg_custom_${_group.id}', custom);
    } else {
      await p.remove('group_chat_bg_custom_${_group.id}');
      await p.setInt(
        'group_chat_bg_${_group.id}',
        idx.clamp(0, GroupChatBackgrounds.count - 1),
      );
    }
  }

  @override
  void dispose() {
    socketService.off('new_message', _handleNewMessageEvent);
    socketService.off('message_edited', _handleMessageUpdatedEvent);
    socketService.off('message_recalled', _handleMessageUpdatedEvent);
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _initSocket() {
    socketService.joinConversation(_group.id);
    socketService.on('new_message', _handleNewMessageEvent);
    socketService.on('message_edited', _handleMessageUpdatedEvent);
    socketService.on('message_recalled', _handleMessageUpdatedEvent);
  }

  Future<void> _loadMessages() async {
    final myId = authService.userId;
    if (myId == null || myId.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final data = await apiService.getMessages(_group.id, myId);
      if (!mounted) return;
      setState(() {
        _messages = _normalizeMessages(data);
        _isLoading = false;
      });
      _scrollToBottom(animated: false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _handleNewMessageEvent(dynamic data) {
    final map = _tryMap(data);
    if (map == null) return;
    final messageMap = _extractMessageMap(map);
    if (messageMap == null) return;
    final msg = MessageModel.fromJson(messageMap);
    if (msg.conversationId != _group.id) return;
    setState(() => _messages = _upsertMessage(_messages, msg));
    _scrollToBottom();
  }

  void _handleMessageUpdatedEvent(dynamic data) {
    final map = _tryMap(data);
    if (map == null) return;
    final convId = map['conversationId']?.toString();
    if (convId != null && convId != _group.id) return;
    _loadMessages();
  }

  Map<String, dynamic>? _tryMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Map<String, dynamic>? _extractMessageMap(Map<String, dynamic> payload) {
    if (payload.containsKey('conversationId') &&
        (payload.containsKey('_id') || payload.containsKey('id'))) {
      return payload;
    }
    final nested = _tryMap(payload['message']);
    return nested;
  }

  List<MessageModel> _normalizeMessages(List<MessageModel> input) {
    final byId = <String, MessageModel>{};
    for (final m in input) {
      byId[m.id] = m;
    }
    final list = byId.values.toList()
      ..sort((a, b) {
        final c = a.createdAt.compareTo(b.createdAt);
        if (c != 0) return c;
        return a.id.compareTo(b.id);
      });
    return list;
  }

  List<MessageModel> _upsertMessage(List<MessageModel> source, MessageModel next) {
    final idx = source.indexWhere((m) => m.id == next.id);
    if (idx == -1) return _normalizeMessages([...source, next]);
    final updated = [...source];
    updated[idx] = next;
    return _normalizeMessages(updated);
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      if (animated) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _openOptions() async {
    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(builder: (_) => GroupOptionsScreen(group: _group)),
    );
    if (!mounted) return;
    if (result == true) {
      Navigator.pop(context, true);
    } else if (result is ApiGroupModel) {
      setState(() => _group = result);
    }
    await _loadBackgroundPref();
  }

  @override
  Widget build(BuildContext context) {
    final memberCount = _group.members.length;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        children: [
          SafeArea(bottom: false, child: _buildHeader(memberCount)),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: _bgCustomBase64 == null
                    ? GroupChatBackgrounds.gradientAt(_bgIndex)
                    : null,
                image: _bgCustomBase64 != null
                    ? DecorationImage(
                        image: MemoryImage(base64Decode(_bgCustomBase64!)),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: GestureDetector(
                onTap: () => _focusNode.unfocus(),
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      )
                    : _messages.isEmpty
                        ? const _EmptyChat()
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            itemCount: _messages.length,
                            itemBuilder: (_, i) {
                              final msg = _messages[i];
                              final isMe = msg.senderId == authService.userId;
                              return _GroupMessageBubble(
                                msg: msg,
                                isMe: isMe,
                                senderLabel: _resolveMemberName(msg.senderId),
                              );
                            },
                          ),
              ),
            ),
          ),
          SafeArea(top: false, child: _buildInputBar()),
        ],
      ),
    );
  }

  Future<void> _showPlusMenu(Offset globalPosition) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    const menuLift = 140.0;
    final anchor = Offset(globalPosition.dx, globalPosition.dy - menuLift);
    final selected = await showMenu<String>(
      context: context,
      color: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.divider),
      ),
      position: RelativeRect.fromRect(
        Rect.fromPoints(anchor, anchor),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'quick_ai',
          child: Row(
            children: const [
              Icon(Icons.auto_awesome, color: AppColors.primary, size: 20),
              SizedBox(width: 10),
              Text(
                'Quick AI',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Inter',
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'file',
          child: Row(
            children: const [
              Icon(Icons.attach_file, color: AppColors.primary, size: 20),
              SizedBox(width: 10),
              Text(
                'File',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Inter',
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (!mounted || selected == null) return;
  }

  // ── Header (ĐÃ THÊM 2 nút gọi nhóm + REJOIN) ─────────────────────────────────────
  Widget _buildHeader(int memberCount) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back,
              color: AppColors.primary,
              size: 22,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          SizedBox(
            width: 38,
            height: 38,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _GroupAvatar(group: _group, size: 38),
                Positioned(
                  left: -1,
                  bottom: -1,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: AppColors.online,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.bgCard, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _group.name.isEmpty ? 'Nhóm' : _group.name,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$memberCount thành viên',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // ✅ Nút quay lại cuộc gọi (nếu đang có cuộc gọi)
          if (_activeCallId != null && _activeCallId!.isNotEmpty)
            IconButton(
              icon: const Icon(
                Icons.phone_in_talk_outlined,
                color: Colors.green,
                size: 22,
              ),
              tooltip: 'Quay lại cuộc gọi',
              onPressed: () {
                // ✅ Rejoin call: Navigate tới call screen
                if (_activeCallConversationId != null && _activeCallId != null) {
                  final group = widget.group;
                  // Build participants từ group members
                  final participants = group.members
                      .map((m) => GroupCallParticipant(
                            userId: m.userId,
                            name: _memberProfiles[m.userId]?.fullName ?? m.userId,
                            avatar: _memberProfiles[m.userId]?.avatar,
                          ))
                      .toList();

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GroupVideoCallScreen(
                        conversationId: _activeCallConversationId!,
                        groupName: group.name.isNotEmpty ? group.name : 'Nhóm',
                        callerId: authService.userId ?? '',
                        groupAvatar: group.avatar,
                        participants: participants,
                        isIncoming: false,
                        callId: _activeCallId,
                      ),
                    ),
                  );
                }
              },
            ),

          // ── Nút gọi thoại nhóm ──
          IconButton(
            icon: const Icon(
              Icons.phone_outlined,
              color: AppColors.primary,
              size: 22,
            ),
            onPressed: _startVoiceCall,
          ),
          // ── Nút gọi video nhóm ──
          IconButton(
            icon: const Icon(
              Icons.videocam_outlined,
              color: AppColors.primary,
              size: 24,
            ),
            onPressed: _startVideoCall,
          ),
          // ── Nút thông tin nhóm ──
          IconButton(
            icon: const Icon(
              Icons.info_outline,
              color: AppColors.primary,
              size: 22,
            ),
            onPressed: _openOptions,
          ),
        ],
      ),
    );
  }

  // ── Input Bar (giữ nguyên) ────────────────────────────────────────────────
  Widget _buildInputBar() {
    final hasText = _textCtrl.text.trim().isNotEmpty;
    Widget actionIcon(IconData icon, {VoidCallback? onTap}) {
      return InkResponse(
        onTap: onTap,
        radius: 22,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: AppColors.primary, size: 24),
        ),
      );
    }

    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Row(
        children: [
          GestureDetector(
            onTapDown: (d) => _showPlusMenu(d.globalPosition),
            child: actionIcon(Icons.add_circle),
          ),
          actionIcon(Icons.camera_alt_rounded, onTap: () {}),
          actionIcon(Icons.image_rounded, onTap: () {}),
          actionIcon(Icons.mic_none_rounded, onTap: () {}),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 38, maxHeight: 120),
              decoration: BoxDecoration(
                color: AppColors.bgInput,
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _textCtrl,
                focusNode: _focusNode,
                maxLines: null,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Nhắn tin',
                  hintStyle: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: AppColors.textHint,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  suffixIcon: InkResponse(
                    onTap: () {},
                    radius: 22,
                    child: const Icon(
                      Icons.sentiment_satisfied_alt_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          const SizedBox(width: 10),
          InkResponse(
            onTap: hasText ? _sendMessage : () {},
            radius: 24,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                hasText ? Icons.send_rounded : Icons.thumb_up,
                color: AppColors.primary,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _isSending) return;
    final userId = authService.userId;
    if (userId == null || userId.isEmpty) return;
    _isSending = true;
    socketService.sendMessage({
      'conversationId': _group.id,
      'senderId': userId,
      'content': text,
      'type': 'TEXT',
    });
    _textCtrl.clear();
    setState(() {
      _isSending = false;
    });
  }
}

// ── Group avatar widget (giữ nguyên) ─────────────────────────────────────────
class _GroupAvatar extends StatelessWidget {
  final ApiGroupModel group;
  final double size;
  const _GroupAvatar({required this.group, required this.size});

  @override
  Widget build(BuildContext context) {
    if (group.avatar.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          webSafeImageUrl(group.avatar),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      color: AppColors.bgInput,
      shape: BoxShape.circle,
    ),
    child: Icon(Icons.group, color: AppColors.primary, size: size * 0.55),
  );
}

// ── Empty chat placeholder (giữ nguyên) ──────────────────────────────────────
class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: AppColors.primary,
                size: 30,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Chưa có tin nhắn nào\nHãy bắt đầu cuộc trò chuyện!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupMessageBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMe;
  final String senderLabel;

  const _GroupMessageBubble({
    required this.msg,
    required this.isMe,
    required this.senderLabel,
  });

  String _previewContent() {
    final type = msg.type.toUpperCase();
    if (type == 'IMAGE') return '[Ảnh]';
    if (type == 'VIDEO') return '[Video]';
    if (type == 'FILE') return '[File]';
    return msg.content;
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 4,
          bottom: 4,
          left: isMe ? 56 : 0,
          right: isMe ? 0 : 56,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? AppColors.primary : AppColors.bubbleOther,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Text(
                senderLabel,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
            Text(
              _previewContent(),
              style: TextStyle(
                color: isMe ? Colors.white : AppColors.bubbleOtherText,
                fontSize: 14,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 2),
            Text(
              du.DateUtils.formatMessageTime(msg.createdAt),
              style: TextStyle(
                fontSize: 10,
                color: isMe ? Colors.white70 : AppColors.textHint,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
