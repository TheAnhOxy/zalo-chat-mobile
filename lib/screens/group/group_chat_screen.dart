import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:developer';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/image_utils.dart';
import '../../data/models/chat_item.dart';
import '../../data/models/models.dart';
import '../../services/api_service.dart';
import '../../services/contacts_api_service.dart';
import '../../services/auth_service.dart';
import '../../controllers/chat_controller.dart';
import '../../services/chat_media_service.dart';
import '../../services/socket_service.dart';
import 'group_chat_backgrounds.dart';
import 'group_options_screen.dart';
import '../call/group_voice_call_screen.dart';
import '../call/group_video_call_screen.dart';
import '../ai/ai_screen.dart';
import '../../widgets/chat/conversation_composer_bar.dart';
import '../../widgets/chat/common_message_bubble.dart';
import '../../widgets/chat/conversation_shared_bubbles.dart';
import '../../widgets/chat/conversation_timeline.dart';
import '../../widgets/chat/media_group_bubble.dart';
import '../chat/video_player_screen.dart';
import '../chat/forward_message_screen.dart';
import '../chat/pinned_messages_screen.dart';

class GroupChatScreen extends StatefulWidget {
  final ApiGroupModel group;
  const GroupChatScreen({super.key, required this.group});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  static const Duration _avatarClusterWindow = Duration(minutes: 30);

  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final AudioRecorder _voiceRecorder = AudioRecorder();
  final ChatMediaService _chatMediaService = ChatMediaService();
  late final ChatController _chatController;

  late ApiGroupModel _group;
  List<CallModel> _calls = [];
  List<ChatItem> _chatItems = [];
  bool _isLoading = true;
  bool _isSending = false;
  final Map<String, ApiUserModel> _memberProfiles = {};
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  int _bgIndex = 0;
  String? _bgCustomBase64;

  // ✅ Tracking cuộc gọi nhóm đang hoạt động
  String? _activeCallId;
  String? _activeCallConversationId;

  // ✅ Media upload & recording
  bool _isUploading = false;
  double _uploadProgress = 0;
  bool _showEmoji = false;
  bool _isRecordingVoice = false;
  bool _voiceCancelHint = false;
  int _voiceDurationSec = 0;
  double _voiceDragDx = 0;
  Timer? _voiceTimer;
  StreamSubscription<Amplitude>? _voiceAmplitudeSub;
  List<double> _voiceWave = List.filled(20, 0.2);
  int _lastKnownMessageCount = 0;
  bool _lastKnownTyping = false;
  String? _highlightedMessageId;
  bool _suppressAutoScroll = false;

  List<MessageModel> get _messages => _chatController.messages;
  bool get _isTyping => _chatController.isPeerTyping;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _chatController = ChatController(
      conversationId: _group.id,
      currentUserId: authService.userId ?? '',
      initialPinnedMessageIds: const <String>[],
      scrollController: _scrollCtrl,
      fetchMessagesAround: _fetchMessagesAroundTarget,
      onJumpCompleted: _flashMessageHighlight,
      estimateItemHeight: _estimateMessageItemHeight,
    );
    _chatController.addListener(_onChatControllerChanged);
    _textCtrl.addListener(_onTextInputChanged);
    _chatController.attach();
    _loadBackgroundPref();
    _loadMemberProfiles();
    _initSocket();
    // ✅ Lắng nghe sự kiện cuộc gọi
    _setupCallListeners();
    _loadConversationData();
  }

  // ✅ Setup listeners cho sự kiện cuộc gọi
  void _setupCallListeners() {
    socketService.on('call_started', _handleCallStartedEvent);
    socketService.on('participant_joined', _handleParticipantJoinedEvent);
    socketService.on('participant_left', _handleParticipantLeftEvent);
    socketService.on('call_ended', _handleCallEndedEvent);
    socketService.on(
      'conversation_call_updated',
      _handleConversationCallUpdated,
    );
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
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  void _onConversationUpdated(dynamic data) {
    final map = _tryMap(data);
    if (map == null) return;
    final cid = (map['conversationId'] ?? map['id'] ?? '').toString();
    if (cid != _group.id) return;

    final membersRaw = map['members'];
    List<ApiGroupMember>? members;
    if (membersRaw is List) {
      members = membersRaw
          .whereType<dynamic>()
          .map((e) {
            if (e is Map<String, dynamic>) return e;
            if (e is Map) return Map<String, dynamic>.from(e);
            return null;
          })
          .whereType<Map<String, dynamic>>()
          .map((m) {
            final uid = (m['userId'] ?? '').toString();
            final role = (m['role'] ?? 'MEMBER').toString();
            return ApiGroupMember(userId: uid, role: role);
          })
          .where((m) => m.userId.isNotEmpty)
          .toList();
    }

    setState(() {
      _group = ApiGroupModel(
        id: _group.id,
        name: (map['name']?.toString() ?? _group.name),
        avatar: (map['avatar']?.toString() ?? _group.avatar),
        members: members ?? _group.members,
        description: (map['description']?.toString() ?? _group.description),
        lastMessageContent: _group.lastMessageContent,
        lastMessageAt: _group.lastMessageAt,
        updatedAt: _group.updatedAt,
      );
    });

    _loadMemberProfiles();
  }

  void _onChatControllerChanged() {
    if (!mounted) return;

    final hasNewMessage = _messages.length > _lastKnownMessageCount;
    final typingStarted = _isTyping && !_lastKnownTyping;

    _lastKnownMessageCount = _messages.length;
    _lastKnownTyping = _isTyping;

    _rebuildChatItems();
    setState(() {});

    if (hasNewMessage) {
      _chatController.markLatestSeen();
    }

    // Khi đang jump tới tin nhắn ghim/cũ, việc load thêm message sẽ tăng length
    // nhưng không được auto-scroll xuống cuối (nếu không sẽ bị kéo về như ảnh).
    if (!_suppressAutoScroll && (hasNewMessage || typingStarted)) {
      _scrollToBottomBurst();
    }
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
    final ids = _group.members
        .map((m) => m.userId)
        .where((id) => id.isNotEmpty)
        .toList();
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

  String? _resolveMemberAvatar(String userId) {
    if (userId == authService.userId) return null;
    final profile = _memberProfiles[userId];
    return profile?.avatar;
  }

  String? _resolveMemberFullName(String userId) {
    if (userId == authService.userId) return null;
    final profile = _memberProfiles[userId];
    return profile?.fullName;
  }

  String? _senderIdForChatItem(ChatItem item) {
    if (item.type == ChatItemType.call) {
      return item.call?.callerId.toString();
    }
    return item.message?.senderId.toString();
  }

  GlobalKey _keyForMessage(String messageId) {
    return _messageKeys.putIfAbsent(messageId, () => GlobalKey());
  }

  double _estimateChatItemHeight(ChatItem item) {
    // ConversationTimeline wrap Column + spacing; dùng ước lượng đủ tốt để nhảy tới gần.
    const extra = 10.0;
    if (item.type == ChatItemType.call) return 92 + extra;
    return _estimateMessageItemHeight(item.message!) + extra;
  }

  double _estimateOffsetForChatIndex(int index) {
    if (index <= 0) return 0;
    double sum = 0;
    for (var i = 0; i < index && i < _chatItems.length; i++) {
      sum += _estimateChatItemHeight(_chatItems[i]);
    }
    return sum;
  }

  Future<void> _jumpToMessageExact(String messageId) async {
    _suppressAutoScroll = true;
    final ok = await _chatController.ensureMessageLoaded(messageId);
    if (!ok || !mounted) {
      _suppressAutoScroll = false;
      return;
    }

    // Đợi rebuild `_chatItems` sau khi controller load message.
    int idx = -1;
    for (var t = 0; t < 12; t++) {
      idx = _chatItems.indexWhere(
        (it) => it.type == ChatItemType.message && it.message?.id == messageId,
      );
      if (idx != -1) break;
      await Future.delayed(const Duration(milliseconds: 24));
      if (!mounted) return;
    }

    if (_scrollCtrl.hasClients && idx >= 0) {
      final max = _scrollCtrl.position.maxScrollExtent;
      final rough = _estimateOffsetForChatIndex(idx).clamp(0, max).toDouble();
      await _scrollCtrl.animateTo(
        rough,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }

    // Đợi 1 frame để item được build, rồi ensureVisible "chốt" đúng vị trí.
    await Future.delayed(const Duration(milliseconds: 32));
    if (!mounted) return;
    final ctx = _messageKeys[messageId]?.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 0.22, // đưa message xuống hơi dưới header, đúng “vị trí”
    );

    _flashMessageHighlight(messageId);
    _suppressAutoScroll = false;
  }

  bool _shouldShowAvatarAtIndex(int index) {
    if (index < 0 || index >= _chatItems.length) return false;

    final current = _chatItems[index];
    final currentSender = _senderIdForChatItem(current);
    final currentUserId = authService.userId?.toString() ?? '';
    if (currentSender == null ||
        currentSender.isEmpty ||
        currentSender == currentUserId) {
      return false;
    }

    if (index == _chatItems.length - 1) return true;

    final next = _chatItems[index + 1];
    final nextSender = _senderIdForChatItem(next);
    if (nextSender != currentSender) return true;

    final gap = next.createdAt.difference(current.createdAt).abs();
    return gap > _avatarClusterWindow;
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

  void _emitTypingEvent() {
    _chatController.onTextChanged(_textCtrl.text);
  }

  void _emitStopTypingEvent() {
    _chatController.onTextChanged('');
  }

  void _typingPulse() {
    _chatController.onTextChanged(_textCtrl.text);
  }

  void _onTextInputChanged() {
    _chatController.onTextChanged(_textCtrl.text);
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
    _emitStopTypingEvent();
    _voiceTimer?.cancel();
    _voiceAmplitudeSub?.cancel();
    socketService.off('conversation_updated', _onConversationUpdated);
    socketService.off('conversation_removed', _onConversationRemoved);
    socketService.off(
      'conversation_history_cleared',
      _onConversationHistoryCleared,
    );
    socketService.off('call_started', _handleCallStartedEvent);
    socketService.off('participant_joined', _handleParticipantJoinedEvent);
    socketService.off('participant_left', _handleParticipantLeftEvent);
    socketService.off('call_ended', _handleCallEndedEvent);
    socketService.off(
      'conversation_call_updated',
      _handleConversationCallUpdated,
    );
    socketService.off('message_edited', _handleMessageUpdatedEvent);
    socketService.off('message_recalled', _handleMessageRecalledEvent);
    socketService.off('message_reaction_updated', _handleMessageUpdatedEvent);
    socketService.off('reaction_updated', _handleMessageUpdatedEvent);
    socketService.off('message_reaction', _handleMessageUpdatedEvent);
    socketService.off('message_updated', _handleMessageUpdatedEvent);
    socketService.off('message_deleted_me', _handleMessageRealtimeEvent);
    socketService.off('message_deleted_for_me', _handleMessageRealtimeEvent);
    socketService.off('message_deleted', _handleMessageRealtimeEvent);
    _chatController.removeListener(_onChatControllerChanged);
    _chatController.dispose();
    _textCtrl.removeListener(_onTextInputChanged);
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _initSocket() {
    log('🔌 [SOCKET] Initializing socket listeners for group ${_group.id}');
    socketService.joinConversation(_group.id);
    socketService.on('conversation_updated', _onConversationUpdated);
    socketService.on('conversation_removed', _onConversationRemoved);
    socketService.on(
      'conversation_history_cleared',
      _onConversationHistoryCleared,
    );
    socketService.on('message_edited', _handleMessageUpdatedEvent);
    socketService.on('message_recalled', _handleMessageRecalledEvent);
    socketService.on('message_reaction_updated', _handleMessageUpdatedEvent);
    socketService.on('reaction_updated', _handleMessageUpdatedEvent);
    socketService.on('message_reaction', _handleMessageUpdatedEvent);
    socketService.on('message_updated', _handleMessageUpdatedEvent);
    socketService.on('message_deleted_me', _handleMessageRealtimeEvent);
    socketService.on('message_deleted_for_me', _handleMessageRealtimeEvent);
    socketService.on('message_deleted', _handleMessageRealtimeEvent);
    log('✅ [SOCKET] All listeners registered for group ${_group.id}');
  }

  void _onConversationRemoved(dynamic data) {
    final map = _tryMap(data);
    if (map == null) return;
    final cid = (map['conversationId'] ?? map['id'] ?? '').toString();
    if (cid != _group.id) return;
    if (!mounted) return;

    // Tránh pop sai stack khi đang ở route khác (vd: đang mở Tùy chọn).
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
    if (!isCurrent) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Bạn đã rời khỏi nhóm',
          style: TextStyle(fontFamily: 'Inter', color: Colors.white),
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
    Navigator.of(context).maybePop(true);
  }

  void _onConversationHistoryCleared(dynamic data) {
    final map = _tryMap(data);
    if (map == null) return;
    final cid = (map['conversationId'] ?? map['id'] ?? '').toString();
    if (cid != _group.id) return;
    if (!mounted) return;

    _chatController.setMessages(const <MessageModel>[]);
    setState(() {
      _chatItems = <ChatItem>[];
      _lastKnownMessageCount = 0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Đã xoá lịch sử trò chuyện',
          style: TextStyle(fontFamily: 'Inter', color: Colors.white),
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _emitSeenForLatest() {
    final userId = authService.userId;
    if (userId == null || userId.isEmpty) return;

    socketService.emit('seen_conversation', {
      'conversationId': _group.id,
      'userId': userId,
    });
  }

  Future<void> _loadConversationData() async {
    final myId = authService.userId;
    if (myId == null || myId.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait<dynamic>([
        apiService.getMessages(_group.id, myId),
        apiService.getCalls(_group.id),
        ContactsApiService.instance.fetchConversationRaw(_group.id),
      ]);
      if (!mounted) return;
      final messages = _normalizeMessages(results[0] as List<MessageModel>);
      final calls = (results[1] as List<Map<String, dynamic>>)
          .map((e) => CallModel.fromJson(e))
          .toList();
      final rawConversation =
          results[2] as ContactsResult<Map<String, dynamic>>;
      if (rawConversation.isSuccess) {
        await _syncPinnedStateFromConversationRaw(
          rawConversation.data ?? const <String, dynamic>{},
        );
      }
      _chatController.setMessages(messages);
      _lastKnownMessageCount = messages.length;
      _lastKnownTyping = _isTyping;
      setState(() {
        _calls = calls;
        _rebuildChatItems();
        _isLoading = false;
      });
      _chatController.markLatestSeen();
      _scrollToBottomBurst(animated: false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _syncPinnedStateFromConversationRaw(
    Map<String, dynamic> raw,
  ) async {
    final candidates = <Map<String, dynamic>>[
      raw,
      if (_tryMap(raw['conversation']) != null) _tryMap(raw['conversation'])!,
      if (_tryMap(raw['data']) != null) _tryMap(raw['data'])!,
    ];

    for (final candidate in candidates) {
      final cid = (candidate['_id'] ?? candidate['id'])?.toString() ?? '';
      final hasPinnedFields =
          candidate.containsKey('pinnedMessageIds') ||
          candidate.containsKey('pinnedMessages');
      if (!hasPinnedFields && cid != _group.id) continue;

      try {
        final conversation = ConversationModel.fromJson(candidate);
        await _chatController.initializePinnedState(
          seedPinnedMessageIds: conversation.pinnedMessageIds,
          seedPinnedMessages: conversation.pinnedMessages,
        );
        return;
      } catch (_) {}
    }
  }

  void _handleNewMessageEvent(dynamic data) {
    _chatController.handleNewMessage(data);
    _scrollToBottom();
  }

  void _handleMessageUpdatedEvent(dynamic data) {
    final map = _tryMap(data);
    if (map == null) return;

    final messageMap = _extractMessageMap(map);
    final convId =
        messageMap?['conversationId']?.toString() ??
        map['conversationId']?.toString();
    if (convId != null && convId.isNotEmpty && convId != _group.id) return;

    if (messageMap != null) {
      final messageId =
          messageMap['_id']?.toString() ?? messageMap['id']?.toString();
      if (messageId != null && messageId.isNotEmpty) {
        try {
          final updated = MessageModel.fromJson(messageMap);
          _chatController.updateMessageById(messageId, (_) => updated);
          return;
        } catch (_) {
          // Fall back to lightweight merge below when payload is partial.
        }
      }
    }

    _handleMessageRealtimeEvent(data);
  }

  void _handleMessageRealtimeEvent(dynamic data) {
    log('🔍 [REALTIME] Handling delete/update event');
    final map = _tryMap(data);
    if (map == null) {
      log('🔍 [REALTIME] Map is null, returning');
      return;
    }

    final nestedMessage = _tryMap(map['message']);
    final convId =
        map['conversationId']?.toString() ??
        nestedMessage?['conversationId']?.toString();
    log('🔍 [REALTIME] convId: $convId, _group.id: ${_group.id}');
    if (convId != null && convId.isNotEmpty && convId != _group.id) {
      log('🔍 [REALTIME] Conversation mismatch, returning');
      return;
    }

    final messageId =
        map['messageId']?.toString() ??
        map['id']?.toString() ??
        map['_id']?.toString() ??
        nestedMessage?['id']?.toString() ??
        nestedMessage?['_id']?.toString();
    log('🔍 [REALTIME] messageId: $messageId');
    if (messageId == null || messageId.isEmpty) {
      log('🔍 [REALTIME] messageId is empty, returning');
      return;
    }

    final currentUserId = authService.userId ?? '';
    final deletedByRaw = map['deletedBy'] ?? nestedMessage?['deletedBy'];
    if (deletedByRaw is List &&
        currentUserId.isNotEmpty &&
        deletedByRaw.map((e) => e.toString()).contains(currentUserId)) {
      log('🔍 [REALTIME] Delete-for-me detected, removing message');
      _chatController.removeMessageById(messageId);
      return;
    }

    if (nestedMessage != null) {
      try {
        final updated = MessageModel.fromJson(nestedMessage);
        log('🔍 [REALTIME] Parsed full message');
        _chatController.updateMessageById(messageId, (_) => updated);
        return;
      } catch (e) {
        log(
          '🔍 [REALTIME] Failed to parse full message: $e, using lightweight merge',
        );
      }
    }

    final newContent = map['content']?.toString();
    final newStatus = map['status']?.toString();
    log(
      '🔍 [REALTIME] Lightweight merge: content=$newContent, status=$newStatus',
    );

    _chatController.updateMessageById(messageId, (old) {
      return MessageModel(
        id: old.id,
        conversationId: old.conversationId,
        senderId: old.senderId,
        type: old.type,
        content: newContent ?? old.content,
        metadata: old.metadata,
        replyToId: old.replyToId,
        status: newStatus ?? old.status,
        isRecalled: old.isRecalled,
        deletedBy: old.deletedBy,
        reactions: old.reactions,
        seenBy: old.seenBy,
        createdAt: old.createdAt,
      );
    });
  }

  void _handleMessageRecalledEvent(dynamic data) {
    log('🔍 [RECALL] Handling message_recalled event');
    final map = _tryMap(data);
    if (map == null) {
      log('🔍 [RECALL] Map is null');
      return;
    }

    final convId = map['conversationId']?.toString();
    if (convId != null && convId.isNotEmpty && convId != _group.id) {
      log('🔍 [RECALL] Conversation mismatch: $convId vs ${_group.id}');
      return;
    }

    // Check if message data is nested
    final messageData = _tryMap(map['message']);
    if (messageData != null) {
      try {
        final recalled = MessageModel.fromJson(messageData);
        log(
          '🔍 [RECALL] Parsed full message: isRecalled=${recalled.isRecalled}',
        );
        _chatController.updateMessageById(recalled.id, (_) => recalled);
        return;
      } catch (e) {
        log('🔍 [RECALL] Failed to parse nested message: $e');
      }
    }

    // Extract messageId
    final messageId =
        map['messageId']?.toString() ??
        map['id']?.toString() ??
        map['_id']?.toString();
    if (messageId == null || messageId.isEmpty) {
      log('🔍 [RECALL] No messageId found');
      return;
    }

    log('🔍 [RECALL] Marking message $messageId as recalled');
    _chatController.updateMessageById(messageId, (old) {
      return MessageModel(
        id: old.id,
        conversationId: old.conversationId,
        senderId: old.senderId,
        type: old.type,
        content: old.content,
        metadata: old.metadata,
        replyToId: old.replyToId,
        status: old.status,
        isRecalled: true,
        deletedBy: old.deletedBy,
        reactions: old.reactions,
        seenBy: old.seenBy,
        createdAt: old.createdAt,
      );
    });
  }

  void _handleParticipantLeftEvent(dynamic data) {
    final map = _tryMap(data);
    if (map == null) return;
    final callId = map['callId']?.toString() ?? '';
    if (callId.isEmpty) return;

    final userId = map['userId']?.toString() ?? '';
    if (userId.isEmpty) return;

    setState(() {
      final index = _calls.indexWhere((call) => call.id == callId);
      if (index != -1) {
        final call = _calls[index];
        final updatedActiveParticipants = call.activeParticipants
            .where((id) => id != userId)
            .toList();
        _calls[index] = CallModel(
          id: call.id,
          conversationId: call.conversationId,
          callerId: call.callerId,
          participants: call.participants,
          activeParticipants: updatedActiveParticipants,
          type: call.type,
          status: call.status,
          startedAt: call.startedAt,
          endedAt: call.endedAt,
          duration: call.duration,
          createdAt: call.createdAt,
        );
        _rebuildChatItems();
      }
      _activeCallId = callId;
    });

    _syncCallsRealtime();
  }

  void _handleParticipantJoinedEvent(dynamic data) {
    final map = _tryMap(data);
    if (map == null) return;
    final callId = map['callId']?.toString() ?? '';
    final userId = map['userId']?.toString() ?? '';
    if (callId.isEmpty || userId.isEmpty) return;

    setState(() {
      final index = _calls.indexWhere((call) => call.id == callId);
      if (index != -1) {
        final call = _calls[index];
        final updatedActiveParticipants = <String>{
          ...call.activeParticipants,
          userId,
        }.toList();
        _calls[index] = CallModel(
          id: call.id,
          conversationId: call.conversationId,
          callerId: call.callerId,
          participants: call.participants,
          activeParticipants: updatedActiveParticipants,
          type: call.type,
          status: call.status,
          startedAt: call.startedAt,
          endedAt: call.endedAt,
          duration: call.duration,
          createdAt: call.createdAt,
        );
        _rebuildChatItems();
      }
      _activeCallId = callId;
      _activeCallConversationId = _group.id;
    });

    _syncCallsRealtime();
  }

  void _handleCallStartedEvent(dynamic data) {
    final map = _tryMap(data);
    if (map == null) return;
    final callId = map['callId']?.toString() ?? '';
    if (callId.isEmpty) return;

    setState(() {
      _activeCallId = callId;
      _activeCallConversationId = _group.id;
    });

    _syncCallsRealtime();
  }

  void _handleCallEndedEvent(dynamic data) {
    final map = _tryMap(data);
    if (map != null) {
      final conversationId = map['conversationId']?.toString() ?? '';
      if (conversationId.isNotEmpty && conversationId != _group.id) {
        return;
      }
    }

    _activeCallId = null;
    _activeCallConversationId = null;
    if (mounted) setState(() {});
    _syncCallsRealtime();
  }

  void _handleConversationCallUpdated(dynamic data) {
    final map = _tryMap(data);
    if (map == null) return;
    final conversationId = map['conversationId']?.toString() ?? '';
    if (conversationId != _group.id) return;

    _activeCallConversationId = conversationId;
    final callDataRaw = map['callData'];
    final callData = _tryMap(callDataRaw);
    if (callData != null) {
      try {
        final updatedCall = CallModel.fromJson(callData);
        setState(() {
          _calls = _upsertCall(_calls, updatedCall);
          _rebuildChatItems();
        });
        _syncCallsRealtime();
        return;
      } catch (_) {}
    }
    if (mounted) setState(() {});
    _syncCallsRealtime();
  }

  void _handleTypingEvent(dynamic data) {
    _chatController.handleTypingEvent(data);
    _scrollToBottom();
  }

  void _handleStopTypingEvent(dynamic data) {
    _chatController.handleStopTypingEvent(data);
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

  List<MessageModel> _upsertMessage(
    List<MessageModel> source,
    MessageModel next,
  ) {
    final idx = source.indexWhere((m) => m.id == next.id);
    if (idx == -1) return _normalizeMessages([...source, next]);
    final updated = [...source];
    updated[idx] = next;
    return _normalizeMessages(updated);
  }

  List<CallModel> _upsertCall(List<CallModel> source, CallModel next) {
    final idx = source.indexWhere((c) => c.id == next.id);
    if (idx == -1) {
      return [...source, next]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    final updated = [...source];
    updated[idx] = next;
    updated.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return updated;
  }

  void _rebuildChatItems() {
    final sorted =
        [..._messages.map(ChatItem.message), ..._calls.map(ChatItem.call)]
          ..sort((a, b) {
            final cmp = a.createdAt.compareTo(b.createdAt);
            if (cmp != 0) return cmp;
            final aKey = a.type == ChatItemType.message
                ? 'm_${a.message?.id ?? ''}'
                : 'c_${a.call?.id ?? ''}';
            final bKey = b.type == ChatItemType.message
                ? 'm_${b.message?.id ?? ''}'
                : 'c_${b.call?.id ?? ''}';
            return aKey.compareTo(bKey);
          });

    final clustered = <ChatItem>[];
    for (final item in sorted) {
      if (item.type == ChatItemType.message) {
        final msg = item.message!;
        if (!msg.isRecalled && (msg.type == 'IMAGE' || msg.type == 'VIDEO')) {
          bool addedToExisting = false;
          
          final groupId = msg.metadata?.groupId;
          if (groupId != null && groupId.isNotEmpty) {
            for (int i = clustered.length - 1; i >= 0; i--) {
              if (clustered[i].type == ChatItemType.mediaGroup) {
                final group = clustered[i].mediaGroup!;
                if (group.first.metadata?.groupId == groupId) {
                  group.add(msg);
                  addedToExisting = true;
                  break;
                }
              }
            }
          } else {
            // Logic cũ: Gom nhóm các tin nhắn liên tiếp nếu không có groupId
            if (clustered.isNotEmpty && clustered.last.type == ChatItemType.mediaGroup) {
              final group = clustered.last.mediaGroup!;
              final lastMsg = group.last;
              if (lastMsg.metadata?.groupId == null && 
                  lastMsg.senderId == msg.senderId &&
                  msg.createdAt.difference(lastMsg.createdAt).abs().inMinutes <= 5) {
                group.add(msg);
                addedToExisting = true;
              }
            }
          }

          if (!addedToExisting) {
            clustered.add(ChatItem.mediaGroup([msg]));
          }
          continue;
        }
      }
      clustered.add(item);
    }
    _chatItems = clustered;
  }

  Future<void> _syncCallsRealtime() async {
    try {
      final rawCalls = await apiService.getCalls(_group.id);
      final latestCalls = rawCalls.map((e) => CallModel.fromJson(e)).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (!mounted) return;

      setState(() {
        _calls = latestCalls;
        _rebuildChatItems();
      });
    } catch (_) {}
  }

  void _scrollToBottom({bool animated = true, int retry = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) {
        if (retry < 8) {
          Future.delayed(const Duration(milliseconds: 45), () {
            _scrollToBottom(animated: animated, retry: retry + 1);
          });
        }
        return;
      }
      if (animated) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      } else {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  void _scrollToBottomBurst({bool animated = true}) {
    _scrollToBottom(animated: animated);
    for (final ms in const [90, 180, 320, 520]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (!mounted) return;
        _scrollToBottom(animated: animated);
      });
    }
  }

  double _estimateMessageItemHeight(MessageModel message) {
    if (message.type == 'SYSTEM') return 44;
    if (message.isImage || message.type == 'VIDEO') return 260;
    if (message.type == 'FILE') return 128;
    if (message.type == 'VOICE') return 112;
    final chars = message.content.length;
    if (chars <= 60) return 92;
    if (chars <= 180) return 120;
    return 150;
  }

  Future<List<MessageModel>> _fetchMessagesAroundTarget(
    String messageId,
  ) async {
    final myId = authService.userId;
    if (myId == null || myId.isEmpty) return const [];

    const limit = 50;
    for (var page = 0; page < 12; page++) {
      final chunk = await apiService.getMessages(
        _group.id,
        myId,
        limit: limit,
        skip: page * limit,
      );
      if (chunk.isEmpty) break;
      if (chunk.any((m) => m.id == messageId)) {
        return chunk;
      }
    }
    return const [];
  }

  void _flashMessageHighlight(String messageId) {
    if (!mounted) return;
    setState(() => _highlightedMessageId = messageId);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      if (_highlightedMessageId == messageId) {
        setState(() => _highlightedMessageId = null);
      }
    });
  }

  bool _isPinSystemMessage(MessageModel msg) {
    final content = msg.content.trim();
    if (content.isEmpty) return false;
    if (content.startsWith('PIN_MESSAGE|')) return true;
    if (content.startsWith('UNPIN_MESSAGE|')) return true;
    if (msg.type.toUpperCase() == 'SYSTEM' && content.startsWith('ADD_MEMBER|')) {
      return true;
    }
    if (msg.type.toUpperCase() == 'SYSTEM' &&
        (content.startsWith('REMOVE_MEMBER|') ||
            content.startsWith('KICK_MEMBER|'))) {
      return true;
    }
    if (msg.type.toUpperCase() == 'SYSTEM' && content.startsWith('LEAVE_GROUP|')) {
      return true;
    }
    if (msg.type.toUpperCase() == 'SYSTEM' &&
        (content.startsWith('MAKE_ADMIN|') ||
            content.startsWith('REVOKE_ADMIN|'))) {
      return true;
    }
    if (content.contains('Bạn đã ghim một tin nhắn')) return true;
    if (msg.type.toUpperCase() == 'SYSTEM' && content.contains('ghim')) {
      return true;
    }
    return false;
  }

  String _pinSystemDisplayText(MessageModel msg) {
    final content = msg.content.trim();
    if (content.startsWith('PIN_MESSAGE|')) return 'Đã ghim một tin nhắn';
    if (content.startsWith('UNPIN_MESSAGE|')) {
      return 'Đã bỏ ghim một tin nhắn';
    }
    if (msg.type.toUpperCase() == 'SYSTEM' && content.startsWith('ADD_MEMBER|')) {
      final parts = content.split('|');
      final actor = parts.length > 1 ? parts[1].trim() : '';
      final peer = parts.length > 2 ? parts[2].trim() : '';
      final a = actor.isEmpty ? 'Ai đó' : actor;
      final p = peer.isEmpty ? 'một thành viên' : peer;
      return '$a đã thêm $p vào nhóm';
    }
    if (msg.type.toUpperCase() == 'SYSTEM' &&
        (content.startsWith('REMOVE_MEMBER|') ||
            content.startsWith('KICK_MEMBER|'))) {
      final parts = content.split('|');
      final actor = parts.length > 1 ? parts[1].trim() : '';
      final peer = parts.length > 2 ? parts[2].trim() : '';
      final a = actor.isEmpty ? 'Ai đó' : actor;
      final p = peer.isEmpty ? 'một thành viên' : peer;
      return '$a đã xóa $p khỏi nhóm';
    }
    if (msg.type.toUpperCase() == 'SYSTEM' && content.startsWith('LEAVE_GROUP|')) {
      final parts = content.split('|');
      final actor = parts.length > 1 ? parts[1].trim() : '';
      final a = actor.isEmpty ? 'Ai đó' : actor;
      return '$a đã rời khỏi nhóm';
    }
    if (msg.type.toUpperCase() == 'SYSTEM' && content.startsWith('MAKE_ADMIN|')) {
      final parts = content.split('|');
      final member = parts.length > 1 ? parts[1].trim() : '';
      final by = parts.length > 2 ? parts[2].trim() : '';
      final m = member.isEmpty ? 'một thành viên' : member;
      final b = by.isEmpty ? 'Ai đó' : by;
      return '$b đã đặt $m làm quản trị viên';
    }
    if (msg.type.toUpperCase() == 'SYSTEM' && content.startsWith('REVOKE_ADMIN|')) {
      final parts = content.split('|');
      final member = parts.length > 1 ? parts[1].trim() : '';
      final by = parts.length > 2 ? parts[2].trim() : '';
      final m = member.isEmpty ? 'một thành viên' : member;
      final b = by.isEmpty ? 'Ai đó' : by;
      return '$b đã thu hồi quyền quản trị của $m';
    }
    return content;
  }

  Future<void> _openPinnedMessages() async {
    final selectedMessageId = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) => PinnedMessagesScreen(
          controller: _chatController,
          chatTitle: _group.name.isNotEmpty ? _group.name : 'Nhóm',
          chatAvatar: _group.avatar,
          memberNames: {
            for (final e in _memberProfiles.entries) e.key: e.value.fullName,
            authService.userId ?? '': authService.currentUser?.displayName ?? 'Tôi',
          },
          memberAvatars: {
            for (final e in _memberProfiles.entries) e.key: e.value.avatar,
            authService.userId ?? '': authService.currentUser?.avatar ?? '',
          },
        ),
      ),
    );
    if (selectedMessageId == null || selectedMessageId.isEmpty) return;
    await _jumpToMessageExact(selectedMessageId);
  }

  Widget _buildPinSystemLine(MessageModel msg) {
    final content = msg.content.trim();
    final showPinnedShortcut =
        content.startsWith('PIN_MESSAGE|') || content.startsWith('UNPIN_MESSAGE|');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _pinSystemDisplayText(msg),
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: AppColors.textHint,
            ),
          ),
          if (showPinnedShortcut) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _openPinnedMessages,
              child: const Text(
                'Xem tất cả',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openOptions() async {
    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) => ChatOptionsScreen(
          group: _group, 
          isGroup: true,
          chatController: _chatController,
          memberNames: _memberProfiles.map((k, v) => MapEntry(k, v.fullName)),
          memberAvatars: _memberProfiles.map((k, v) => MapEntry(k, v.avatar)),
        ),
      ),
    );
    if (!mounted) return;
    if (result == true) {
      Navigator.pop(context, true);
    } else if (result is ApiGroupModel) {
      if (mounted) {
        setState(() => _group = result);
      }
    } else if (result is String) {
      _chatController.jumpToMessage(result);
    }
    await _loadBackgroundPref();
  }

  // ── Media & Upload Methods ─────────────────────────────────────────────
  void _sendMessage() {
    if (_isUploading) return;
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    final userId = authService.userId;
    if (userId == null || userId.isEmpty) return;

    socketService.sendMessage({
      'conversationId': _group.id,
      'senderId': userId,
      'content': text,
      'type': 'TEXT',
    });
    setState(() {
      _textCtrl.clear();
      _showEmoji = false;
    });
    _scrollToBottomBurst();
  }

  void _sendQuickLike() {
    if (_isUploading) return;
    final userId = authService.userId;
    if (userId == null || userId.isEmpty) return;

    socketService.sendMessage({
      'conversationId': _group.id,
      'senderId': userId,
      'content': '👍',
      'type': 'TEXT',
    });

    setState(() => _showEmoji = false);
    _scrollToBottomBurst();
  }

  String _formatClock(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(1, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _resetVoiceState() {
    if (!mounted) return;
    setState(() {
      _isRecordingVoice = false;
      _voiceCancelHint = false;
      _voiceDurationSec = 0;
      _voiceDragDx = 0;
      _voiceWave = List.filled(20, 0.2);
    });
  }

  Future<void> _startVoiceRecording() async {
    if (_isUploading || _isRecordingVoice) return;
    bool hasPermission = false;
    try {
      hasPermission = await _voiceRecorder.hasPermission();
    } catch (e, st) {
      log('❌ hasPermission() lỗi: $e', error: e, stackTrace: st);
    }
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ứng dụng chưa có quyền dùng microphone.'),
        ),
      );
      return;
    }

    _focusNode.unfocus();
    setState(() {
      _showEmoji = false;
      _isRecordingVoice = true;
      _voiceCancelHint = false;
      _voiceDurationSec = 0;
      _voiceDragDx = 0;
      _voiceWave = List.filled(20, 0.2);
    });

    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final recordPath = kIsWeb
          ? 'voice_$stamp.webm'
          : '${(await getTemporaryDirectory()).path}/voice_$stamp.m4a';

      final recordConfig = kIsWeb
          ? const RecordConfig(
              encoder: AudioEncoder.opus,
              sampleRate: 48000,
              numChannels: 1,
              bitRate: 128000,
            )
          : const RecordConfig(
              encoder: AudioEncoder.aacLc,
              bitRate: 128000,
              sampleRate: 44100,
              numChannels: 1,
            );

      await _voiceRecorder.start(recordConfig, path: recordPath);

      _voiceTimer?.cancel();
      _voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_isRecordingVoice) return;
        setState(() => _voiceDurationSec += 1);
      });

      _voiceAmplitudeSub?.cancel();
      _voiceAmplitudeSub = _voiceRecorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen((amp) {
            if (!mounted || !_isRecordingVoice) return;
            final normalized = ((amp.current + 60) / 60).clamp(0.12, 1.0);
            final next = [..._voiceWave]..removeAt(0);
            next.add(normalized.toDouble());
            setState(() => _voiceWave = next);
          });
    } catch (e, st) {
      log('❌ Bắt đầu ghi âm thất bại: $e', error: e, stackTrace: st);
      _resetVoiceState();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể bắt đầu ghi âm.')),
        );
      }
    }
  }

  Future<void> _finishVoiceRecording({required bool shouldSend}) async {
    if (!_isRecordingVoice) return;

    _voiceTimer?.cancel();
    _voiceAmplitudeSub?.cancel();

    try {
      if (!shouldSend) {
        await _voiceRecorder.cancel();
        _resetVoiceState();
        return;
      }

      final path = await _voiceRecorder.stop();
      final durationSec = _voiceDurationSec;
      _resetVoiceState();

      if (path == null || path.isEmpty || durationSec <= 0) return;
      await _uploadVoiceAndSend(path, durationSec);
    } catch (e) {
      log('❌ Kết thúc ghi âm thất bại: $e');
      _resetVoiceState();
    }
  }

  Future<T?> _runMediaUpload<T>(Future<T> Function() action) async {
    if (_isUploading) return null;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    try {
      return await action();
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  Future<void> _uploadVoiceAndSend(String voicePath, int durationSec) async {
    await _runMediaUpload(() async {
      final uploaded = await _chatMediaService.uploadVoiceRecording(
        voicePath,
        durationSec,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _uploadProgress = progress);
        },
      );

      socketService.sendMessage({
        'conversationId': _group.id,
        'senderId': authService.userId!,
        'type': 'VOICE',
        'content': uploaded.fileUrl,
        'metadata': {
          'duration': durationSec,
          'fileName': uploaded.fileName,
          'fileSize': uploaded.fileSize,
        },
      });
      _scrollToBottomBurst();
      return null;
    });
  }

  Future<void> _pickAndSendMedia() async {
    try {
      final pickedFiles = await _chatMediaService.pickMultipleMedia();
      if (pickedFiles.isEmpty) return;

      final groupId = const Uuid().v4();
      await _runMediaUpload(() async {
        final total = pickedFiles.length;
        var completed = 0;
        for (final picked in pickedFiles) {
          final isVideo = _chatMediaService.detectContentType(picked.name).startsWith('video');
          ChatMediaUploadResult? uploaded;
          try {
            if (isVideo) {
              uploaded = await _chatMediaService.uploadPickedVideo(
                picked,
                onProgress: (progress) {
                  if (!mounted) return;
                  setState(() => _uploadProgress = (completed + progress) / total);
                },
              );
            } else {
              uploaded = await _chatMediaService.uploadPickedImage(
                picked,
                onProgress: (progress) {
                  if (!mounted) return;
                  setState(() => _uploadProgress = (completed + progress) / total);
                },
              );
            }

            socketService.sendMessage({
              'conversationId': _group.id,
              'senderId': authService.userId!,
              'type': isVideo ? 'VIDEO' : 'IMAGE',
              'content': uploaded.fileUrl,
              'metadata': {
                'fileName': uploaded.fileName,
                'fileSize': uploaded.fileSize,
                'groupId': groupId,
                if (uploaded.thumbnailUrl != null) 'thumbnailUrl': uploaded.thumbnailUrl,
                if (uploaded.thumbnailUrl != null) 'thumbnail': uploaded.thumbnailUrl,
              },
            });
          } catch (e) {
            log('Upload lỗi: $e');
          }
          completed++;
        }
        if (mounted) {
          _scrollToBottomBurst();
        }
        return null;
      });
    } catch (e) {
      log('❌ Chọn media thất bại: $e');
    }
  }

  Future<void> _pickAndSendFile() async {
    await _runMediaUpload(() async {
      final file = await _chatMediaService.pickFile();
      if (file == null) return null;
      final uploaded = await _chatMediaService.uploadPickedFile(
        file,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _uploadProgress = progress);
        },
      );

      socketService.sendMessage({
        'conversationId': _group.id,
        'senderId': authService.userId!,
        'type': 'FILE',
        'content': uploaded.fileUrl,
        'metadata': {
          'fileName': uploaded.fileName,
          'fileSize': uploaded.fileSize,
        },
      });
      _scrollToBottomBurst();
      return null;
    });
  }

  Widget _buildMediaGroupBubble(List<MessageModel> group, int index) {
    if (group.isEmpty) return const SizedBox.shrink();
    final lastMsg = group.last;
    final isMe = lastMsg.senderId == authService.userId;

    return KeyedSubtree(
      key: ValueKey('mg_${lastMsg.id}'),
      child: MediaGroupBubble(
        group: group,
        isMe: isMe,
        isGroup: true,
        senderLabel: isMe ? null : _resolveMemberName(lastMsg.senderId),
        senderAvatar: isMe ? null : _resolveMemberAvatar(lastMsg.senderId),
        senderName: isMe ? null : _resolveMemberFullName(lastMsg.senderId),
        showAvatar: _shouldShowAvatarAtIndex(index),
        showSeenLabel: false,
        onImageTap: _openImageViewer,
        onVideoTap: _openVideoPlayer,
      ),
    );
  }

  void _openImageViewer(MessageModel msg) {
    if (!msg.isImage) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 3,
                child: Image.network(msg.content, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _downloadFile(MessageModel msg) async {
    if (msg.type != 'FILE') return;
    try {
      final uri = Uri.parse(msg.content);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể mở file đính kèm.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lỗi khi mở file đính kèm.')),
      );
    }
  }

  void _openVideoPlayer(MessageModel msg) {
    if (msg.type != 'VIDEO' || msg.content.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          videoUrl: msg.content,
          title: msg.metadata?.fileName ?? 'Video',
        ),
      ),
    );
  }

  void _addReaction(MessageModel msg, String type) {
    final me = authService.userId ?? '';
    if (me.isEmpty) return;

    _chatController.updateMessageById(msg.id, (old) {
      final nextReactions = old.reactions.where((r) => r.userId != me).toList()
        ..add(Reaction(userId: me, type: type));
      return MessageModel(
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
    });

    socketService.sendReaction(msg.id, me, type, _group.id);
  }

  void _deleteMessageForMe(MessageModel msg) {
    socketService.deleteMessageMe(msg.id, authService.userId ?? '');
    _chatController.removeMessageById(msg.id);
    _rebuildChatItems();
    if (mounted) setState(() {});
  }

  void _recallMessage(MessageModel msg) {
    socketService.recallMessage(msg.id, _group.id);
    _chatController.updateMessageById(msg.id, (old) {
      return MessageModel(
        id: old.id,
        conversationId: old.conversationId,
        senderId: old.senderId,
        type: old.type,
        content: old.content,
        metadata: old.metadata,
        replyToId: old.replyToId,
        status: old.status,
        isRecalled: true,
        deletedBy: old.deletedBy,
        reactions: old.reactions,
        seenBy: old.seenBy,
        createdAt: old.createdAt,
      );
    });
  }

  void _showMessageActions(MessageModel msg) {
    final isPinned = _chatController.isMessagePinned(msg.id);
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      showDragHandle: true,
      builder: (sheetContext) {
        const reactions = [
          ('LIKE', '👍'),
          ('LOVE', '❤️'),
          ('HAHA', '😂'),
          ('WOW', '😮'),
          ('SAD', '😢'),
          ('ANGRY', '😠'),
        ];

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: reactions.map((item) {
                  return InkResponse(
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _addReaction(msg, item.$1);
                    },
                    radius: 28,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        item.$2,
                        style: const TextStyle(fontSize: 30),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(
                  Icons.push_pin_outlined,
                  color: AppColors.textPrimary,
                  size: 22,
                ),
                title: Text(
                  isPinned ? 'Bỏ ghim' : 'Ghim',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final nowPinned = await _chatController.togglePinMessage(
                    msg.id,
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        nowPinned ? 'Đã ghim tin nhắn' : 'Đã bỏ ghim tin nhắn',
                      ),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.forward_to_inbox_outlined,
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
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ForwardMessageScreen(message: msg),
                    ),
                  );
                },
              ),
              if (msg.senderId == authService.userId && !msg.isRecalled)
                ListTile(
                  leading: const Icon(
                    Icons.undo,
                    color: AppColors.error,
                    size: 22,
                  ),
                  title: const Text(
                    'Thu hồi',
                    style: TextStyle(
                      color: AppColors.error,
                      fontFamily: 'Inter',
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
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
                  'Xóa phía tôi',
                  style: TextStyle(color: AppColors.error, fontFamily: 'Inter'),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _deleteMessageForMe(msg);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showComposerActionsSheet() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      showDragHandle: true,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.auto_awesome,
                  color: AppColors.primary,
                ),
                title: const Text('Trợ lý AI'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    useSafeArea: false,
                    builder: (_) => _GroupAiChatSheet(
                      conversationId: _group.id,
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_rounded,
                  color: AppColors.textPrimary,
                ),
                title: const Text('Chụp ảnh'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndSendMedia();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.image_rounded,
                  color: AppColors.textPrimary,
                ),
                title: const Text('Chọn ảnh/video'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndSendMedia();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.attach_file,
                  color: AppColors.textPrimary,
                ),
                title: const Text('Đính kèm file'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndSendFile();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVoiceRecordingBar() {
    final waveColor = _voiceCancelHint ? AppColors.error : AppColors.primary;

    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _voiceCancelHint
                ? 'Thả tay để hủy'
                : 'Vuốt sang trái để hủy, hoặc bấm gửi để gửi',
            style: TextStyle(
              fontSize: 13,
              color: _voiceCancelHint
                  ? AppColors.error
                  : AppColors.textSecondary,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              InkResponse(
                onTap: () => _finishVoiceRecording(shouldSend: false),
                radius: 24,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.delete_outline,
                    color: AppColors.error,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    final shouldCancel = details.primaryDelta != null
                        ? (_voiceDragDx + details.primaryDelta!) < -100
                        : false;
                    setState(() {
                      _voiceDragDx += details.primaryDelta ?? 0;
                      _voiceCancelHint = shouldCancel;
                    });
                  },
                  onHorizontalDragEnd: (_) {
                    final shouldCancel =
                        _voiceCancelHint || _voiceDragDx < -100;
                    if (shouldCancel) {
                      _finishVoiceRecording(shouldSend: false);
                      return;
                    }
                    setState(() {
                      _voiceDragDx = 0;
                      _voiceCancelHint = false;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    transform: Matrix4.translationValues(
                      _voiceDragDx.clamp(-60, 0).toDouble(),
                      0,
                      0,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.bgInput,
                      borderRadius: BorderRadius.circular(36),
                      border: Border.all(
                        color: _voiceCancelHint
                            ? AppColors.error.withOpacity(0.45)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(
                            color: AppColors.bgCardLight,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _voiceCancelHint
                                ? Icons.close_rounded
                                : Icons.mic_rounded,
                            color: _voiceCancelHint
                                ? AppColors.error
                                : AppColors.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: _voiceWave
                                .map(
                                  (v) => Container(
                                    width: 3,
                                    height: 8 + (v * 20),
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 1.2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: waveColor.withOpacity(0.9),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatClock(_voiceDurationSec),
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              InkResponse(
                onTap: () => _finishVoiceRecording(shouldSend: true),
                radius: 24,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
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
                onTap: () {
                  _focusNode.unfocus();
                  setState(() => _showEmoji = false);
                },
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      )
                    : _chatItems.isEmpty
                    ? const _EmptyChat()
                    : ConversationTimeline(
                        controller: _scrollCtrl,
                        items: _chatItems,
                        showTypingIndicator: _isTyping,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        mediaGroupBuilder: _buildMediaGroupBubble,
                        messageBuilder: (msg, index) {
                          if (_isPinSystemMessage(msg)) {
                            return _buildPinSystemLine(msg);
                          }
                          final isMe = msg.senderId == authService.userId;
                          return KeyedSubtree(
                            key: _keyForMessage(msg.id),
                            child: CommonMessageBubble(
                              msg: msg,
                              isMe: isMe,
                              isGroup: true,
                              senderLabel: isMe
                                  ? null
                                  : _resolveMemberName(msg.senderId),
                              senderAvatar: isMe
                                  ? null
                                  : _resolveMemberAvatar(msg.senderId),
                              senderName: isMe
                                  ? null
                                  : _resolveMemberFullName(msg.senderId),
                              showAvatar: _shouldShowAvatarAtIndex(index),
                              onLongPress: () {
                                _showMessageActions(msg);
                              },
                              onDoubleTap: () {
                                _addReaction(msg, 'LIKE');
                              },
                              onImageTap: () => _openImageViewer(msg),
                              onFileTap: () => _downloadFile(msg),
                              onVideoTap: () => _openVideoPlayer(msg),
                              isPinned:
                                  _chatController.isPinnedStateReady &&
                                  _chatController.isMessagePinned(msg.id),
                              isHighlighted: _highlightedMessageId == msg.id,
                            ),
                          );
                        },
                        callBuilder: (call, index) => ConversationCallBubble(
                          call: call,
                          callerAvatar: _resolveMemberAvatar(call.callerId),
                          callerName: _resolveMemberFullName(call.callerId),
                          senderLabel: _resolveMemberName(call.callerId),
                          showAvatar: _shouldShowAvatarAtIndex(index),
                        ),
                      ),
              ),
            ),
          ),
          if (_isUploading)
            LinearProgressIndicator(
              value: _uploadProgress > 0 ? _uploadProgress : null,
              minHeight: 3,
              color: AppColors.primary,
              backgroundColor: AppColors.bgInput,
            ),
          SafeArea(top: false, child: _buildInputBar()),
          if (_showEmoji) _buildEmojiPanel(),
        ],
      ),
    );
  }

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

          IconButton(
            icon: const Icon(
              Icons.phone_outlined,
              color: AppColors.primary,
              size: 22,
            ),
            onPressed: _startVoiceCall,
          ),
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
    if (_isRecordingVoice) {
      return _buildVoiceRecordingBar();
    }
    return ConversationComposerBar(
      controller: _textCtrl,
      focusNode: _focusNode,
      hintText: 'Nhắn tin',
      actions: [
        ConversationComposerAction(
          icon: Icons.add_circle_outline,
          onTap: _showComposerActionsSheet,
        ),
        ConversationComposerAction(
          icon: Icons.image_rounded,
          onTap: _pickAndSendMedia,
          enabled: !_isUploading,
        ),
        ConversationComposerAction(
          icon: Icons.mic_none_rounded,
          onLongPressStart: _isUploading ? null : (_) => _startVoiceRecording(),
          enabled: !_isUploading,
        ),
      ],
      onEmojiTap: () => setState(() => _showEmoji = !_showEmoji),
      onSend: _sendMessage,
      onEmptyActionTap: _sendQuickLike,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet chứa AiScreen (dùng cho menu Quick AI / File trong group chat)
// ─────────────────────────────────────────────────────────────────────────────

class _GroupAiChatSheet extends StatelessWidget {
  final String conversationId;

  const _GroupAiChatSheet({required this.conversationId});

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    return Container(
      height: screenH * 0.92,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: AiScreen(
                targetConversationId: conversationId,
                autoSummarizeOnOpen: true,
              ),
            ),
          ),
        ],
      ),
    );
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
