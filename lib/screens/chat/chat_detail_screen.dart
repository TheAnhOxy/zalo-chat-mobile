import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/models.dart';
import '../../services/auth_service.dart';
import '../../services/api_service.dart';
import '../../services/contacts_api_service.dart';
import '../../controllers/chat_controller.dart';
import '../../services/chat_media_service.dart';
import '../../services/socket_service.dart';
import '../call/voice_call_screen.dart';
import '../call/video_call_screen.dart';
import 'video_player_screen.dart';
import 'forward_message_screen.dart';
import 'dart:developer';
import 'package:url_launcher/url_launcher.dart';
import 'package:photo_view/photo_view.dart';
import '../../data/models/chat_item.dart';
import '../../widgets/chat/conversation_composer_bar.dart';
import '../../widgets/chat/common_message_bubble.dart';
import '../../widgets/chat/conversation_header.dart';
import '../../widgets/chat/conversation_shared_bubbles.dart';
import '../../widgets/chat/conversation_timeline.dart';
import '../../widgets/chat/conversation_voice_recording_bar.dart';
import '../ai/ai_screen.dart';
import 'pinned_messages_screen.dart';
import '../group/group_options_screen.dart';
import '../group/group_chat_screen.dart';
import '../../navigation/app_navigator.dart';

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
  static const Duration _avatarClusterWindow = Duration(minutes: 30);

  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  final _voiceRecorder = AudioRecorder();
  final _chatMediaService = ChatMediaService();
  late final ChatController _chatController;

  bool _isLoading = true;
  bool _showEmoji = false;
  MessageModel? _replyTo;
  MessageModel? _editingMessage;
  bool _isUploading = false;
  double _uploadProgress = 0;
  bool _isRecordingVoice = false;
  bool _voiceCancelHint = false;
  int _voiceDurationSec = 0;
  double _voiceDragDx = 0;
  Timer? _voiceTimer;
  StreamSubscription<Amplitude>? _voiceAmplitudeSub;
  List<double> _voiceWave = List.filled(20, 0.2);
  bool _peerOnline = false;
  DateTime? _peerLastSeen;
  int _selectedBackgroundIndex = 0;
  List<CallModel> _calls = [];
  List<ChatItem> _chatItems = [];
  int _lastKnownMessageCount = 0;
  bool _lastKnownTyping = false;
  String? _lastEmittedSeenMessageId;
  String? _highlightedMessageId;
  bool _suppressAutoScroll = false;
  bool _backInProgress = false;
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};

  List<MessageModel> get _messages => _chatController.messages;
  bool get _isTyping => _chatController.isPeerTyping;

  static const List<_ChatBackgroundOption> _backgroundOptions = [
    _ChatBackgroundOption(
      label: 'Mặc định',
      gradient: LinearGradient(
        colors: [Color(0xFFEDF2ED), Color(0xFFE3EBE3)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    _ChatBackgroundOption(
      label: 'Sky',
      gradient: LinearGradient(
        colors: [Color(0xFFE8F5E9), Color(0xFFC8E6C9)],
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

  String get _backgroundPrefKey => 'chat_bg_${widget.conversationId}';

  @override
  void initState() {
    super.initState();
    _peerOnline = widget.otherUser?.isOnline ?? false;
    _peerLastSeen = widget.otherUser?.status.lastSeen;
    _chatController = ChatController(
      conversationId: widget.conversationId,
      currentUserId: authService.userId ?? '',
      initialPinnedMessageIds: widget.conversation.pinnedMessageIds,
      initialPinnedMessages: widget.conversation.pinnedMessages,
      scrollController: _scrollCtrl,
      fetchMessagesAround: _fetchMessagesAroundTarget,
      onJumpCompleted: _flashMessageHighlight,
      estimateItemHeight: _estimateMessageItemHeight,
    );
    _chatController.addListener(_onChatControllerChanged);
    _textCtrl.addListener(_onTextInputChanged);
    _chatController.attach();
    _restoreBackground();
    _loadData();
    _initSocket();
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
      _emitSeenForLatest();
    }

    if (!_suppressAutoScroll && (hasNewMessage || typingStarted)) {
      _scrollToBottomBurst();
    }
  }

  void _onTextInputChanged() {
    _chatController.onTextChanged(_textCtrl.text);
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

  GlobalKey _keyForMessage(String messageId) {
    return _messageKeys.putIfAbsent(messageId, () => GlobalKey());
  }

  double _estimateChatItemHeight(ChatItem item) {
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

    await Future.delayed(const Duration(milliseconds: 32));
    if (!mounted) return;
    final ctx = _messageKeys[messageId]?.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 0.22,
    );

    _flashMessageHighlight(messageId);
    _suppressAutoScroll = false;
  }

  Future<List<MessageModel>> _fetchMessagesAroundTarget(
    String messageId,
  ) async {
    final uid = authService.userId;
    if (uid == null || uid.isEmpty) return const [];

    const limit = 50;
    for (var page = 0; page < 12; page++) {
      final skip = page * limit;
      final chunk = await apiService.getMessages(
        widget.conversationId,
        uid,
        limit: limit,
        skip: skip,
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

  Future<void> _loadData() async {
    try {
      final results = await Future.wait<dynamic>([
        apiService.getMessages(widget.conversationId, authService.userId!),
        apiService.getCalls(widget.conversationId),
        ContactsApiService.instance.fetchConversationRaw(widget.conversationId),
      ]);

      final msgs = _normalizeMessages(results[0] as List<MessageModel>);
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
      final items =
          <ChatItem>[...msgs.map(ChatItem.message), ...calls.map(ChatItem.call)]
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

      _chatController.setMessages(msgs);
      _lastKnownMessageCount = msgs.length;
      _lastKnownTyping = _isTyping;
      setState(() {
        _calls = calls;
        _chatItems = items;
        _isLoading = false;
      });
      _emitSeenForLatest();
      _scrollToBottomBurst(animated: false);
    } catch (e) {
      log('❌ Lỗi tải: $e');
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
      if (!hasPinnedFields && cid != widget.conversationId) continue;

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

  void _rebuildChatItems() {
    _chatItems =
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
  }

  void _initSocket() {
    socketService.joinConversation(widget.conversationId);

    socketService.on(
      'conversation_call_updated',
      _handleConversationCallUpdated,
    );
    socketService.on('call_ended', _handleCallTerminalEvent);
    socketService.on('call_rejected', _handleCallTerminalEvent);

    for (final event in const [
      'message_reaction_updated',
      'reaction_updated',
      'message_reaction',
      'message_updated',
    ]) {
      socketService.on(event, _handleMessageUpdated);
    }

    socketService.on('message_edited', _handleMessageEdited);
    socketService.on('message_recalled', _handleMessageRecalled);
    socketService.on('message_deleted_me', _handleMessageDeletedForMe);
    socketService.on('message_deleted_for_me', _handleMessageDeletedForMe);
    socketService.on('message_deleted', _handleMessageDeletedForMe);

    for (final event in const ['conversation_theme_changed', 'theme_changed']) {
      socketService.on(event, _handleThemeEvent);
    }

    socketService.on('user_status_changed', _handlePeerStatusChanged);

    socketService.on(
      'conversation_history_cleared',
      _handleConversationHistoryCleared,
    );
  }

  void _handleConversationHistoryCleared(dynamic data) {
    try {
      final map = data is Map<String, dynamic>
          ? data
          : (data is String
              ? (jsonDecode(data) as Map<String, dynamic>)
              : Map<String, dynamic>.from(data as Map));
      final cid = (map['conversationId'] ?? map['id'] ?? '').toString();
      if (cid != widget.conversationId) return;
    } catch (_) {
      return;
    }

    if (!mounted) return;
    _chatController.setMessages(const <MessageModel>[]);
    setState(() {
      _calls = [];
      _chatItems = [];
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

  void _handleConversationCallUpdated(dynamic data) {
    try {
      final map = data is Map<String, dynamic>
          ? data
          : Map<String, dynamic>.from(data as Map);

      if (map['conversationId']?.toString() != widget.conversationId) return;

      final callDataRaw = map['callData'];
      if (callDataRaw != null) {
        final callMap = callDataRaw is Map<String, dynamic>
            ? callDataRaw
            : Map<String, dynamic>.from(callDataRaw as Map);
        final newCall = CallModel.fromJson(callMap);

        setState(() {
          _calls = _upsertCall(_calls, newCall);
          _rebuildChatItems();
        });
        _scrollToBottom();
      } else {
        _syncCallsRealtime();
      }
    } catch (e) {
      log('❌ conversation_call_updated error: $e');
    }
  }

  void _handleCallTerminalEvent(dynamic data) {
    final map = _tryMap(data);
    if (map != null) {
      final convId = map['conversationId']?.toString();
      if (convId != null &&
          convId.isNotEmpty &&
          convId != widget.conversationId) {
        return;
      }
    }
    _syncCallsRealtime();
  }

  Future<void> _syncCallsRealtime() async {
    try {
      final rawCalls = await apiService.getCalls(widget.conversationId);
      final latestCalls = rawCalls.map((e) => CallModel.fromJson(e)).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (!mounted) return;

      final oldIds = _calls.map((c) => c.id).toSet();
      final newIds = latestCalls.map((c) => c.id).toSet();
      final hasNewCall =
          newIds.length > oldIds.length || !newIds.containsAll(oldIds);

      setState(() {
        _calls = latestCalls;
        _rebuildChatItems();
      });

      if (hasNewCall) {
        _scrollToBottom();
      }
    } catch (e) {
      log('❌ sync call realtime error: $e');
    }
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

  void _handleMessageSeen(dynamic data) {
    _chatController.handleMessageSeen(data);
  }

  void _handleTypingEvent(dynamic data) {
    _chatController.handleTypingEvent(data);
    _scrollToBottom();
  }

  void _handleStopTypingEvent(dynamic data) {
    _chatController.handleStopTypingEvent(data);
  }

  @override
  void dispose() {
    socketService.off('message_reaction_updated', _handleMessageUpdated);
    socketService.off('reaction_updated', _handleMessageUpdated);
    socketService.off('message_reaction', _handleMessageUpdated);
    socketService.off('message_updated', _handleMessageUpdated);
    socketService.off('message_edited', _handleMessageEdited);
    socketService.off('message_recalled', _handleMessageRecalled);
    socketService.off('message_deleted_me', _handleMessageDeletedForMe);
    socketService.off('message_deleted_for_me', _handleMessageDeletedForMe);
    socketService.off('message_deleted', _handleMessageDeletedForMe);
    socketService.off('conversation_theme_changed', _handleThemeEvent);
    socketService.off('theme_changed', _handleThemeEvent);
    socketService.off(
      'conversation_call_updated',
      _handleConversationCallUpdated,
    );
    socketService.off('call_ended', _handleCallTerminalEvent);
    socketService.off('call_rejected', _handleCallTerminalEvent);
    socketService.off('user_status_changed', _handlePeerStatusChanged);
    socketService.off(
      'conversation_history_cleared',
      _handleConversationHistoryCleared,
    );
    _chatController.removeListener(_onChatControllerChanged);
    _chatController.dispose();
    _voiceTimer?.cancel();
    _voiceAmplitudeSub?.cancel();
    _voiceRecorder.dispose();
    _textCtrl.removeListener(_onTextInputChanged);
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  DateTime? _parseDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
    return null;
  }

  void _handlePeerStatusChanged(dynamic data) {
    if (widget.otherUser == null || widget.conversation.isGroup) return;
    final map = _tryMap(data);
    if (map == null) return;
    final userId = map['userId']?.toString() ?? '';
    if (userId.isEmpty || userId != widget.otherUser!.id) return;

    final isOnline = map['isOnline'] == true;
    final lastSeen = _parseDateTime(map['lastSeen']);

    setState(() {
      _peerOnline = isOnline;
      if (isOnline) {
        _peerLastSeen = null;
      } else if (lastSeen != null) {
        _peerLastSeen = lastSeen;
      } else {
        _peerLastSeen ??= widget.otherUser?.status.lastSeen;
      }
    });
  }

  String _presenceText() {
    if (_peerOnline) return 'Đang hoạt động';
    final lastSeen = _peerLastSeen;
    if (lastSeen == null) return 'Ngoại tuyến';
    final diff = DateTime.now().difference(lastSeen.toLocal());
    if (diff.inMinutes < 1) return 'Hoạt động vừa xong';
    if (diff.inHours < 1) return 'Hoạt động ${diff.inMinutes} phút trước';
    if (diff.inDays < 1) return 'Hoạt động ${diff.inHours} giờ trước';
    return 'Hoạt động ${diff.inDays} ngày trước';
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
    if (idx == -1) return _normalizeMessages([...source, next]);
    final copied = [...source];
    copied[idx] = next;
    return _normalizeMessages(copied);
  }

  void _updateMessageById(
    String messageId,
    MessageModel Function(MessageModel old) updater,
  ) {
    _chatController.updateMessageById(messageId, updater);
  }

  List<Reaction> _parseReactions(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((r) => Reaction.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  List<SeenBy> _parseSeenBy(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((s) => SeenBy.fromJson(Map<String, dynamic>.from(s)))
        .toList();
  }

  MessageModel _mergeMessageData(
    MessageModel old,
    Map<String, dynamic> data, {
    List<Reaction>? reactions,
    bool? isRecalled,
  }) {
    final metadata = data['metadata'] is Map
        ? MessageMetadata.fromJson(Map<String, dynamic>.from(data['metadata']))
        : old.metadata;
    final seenBy = _parseSeenBy(data['seenBy']);
    return MessageModel(
      id: old.id,
      conversationId: data['conversationId']?.toString() ?? old.conversationId,
      senderId: data['senderId']?.toString() ?? old.senderId,
      type:
          data['messageType']?.toString() ??
          data['type']?.toString() ??
          old.type,
      content: data['content']?.toString() ?? old.content,
      metadata: metadata,
      replyToId: data.containsKey('replyTo')
          ? data['replyTo']?.toString()
          : old.replyToId,
      status: data['status']?.toString() ?? old.status,
      isRecalled: isRecalled ?? (data['isRecalled'] as bool? ?? old.isRecalled),
      deletedBy: data['deletedBy'] is List
          ? List<String>.from(data['deletedBy'] as List)
          : old.deletedBy,
      reactions:
          reactions ??
          () {
            final parsedReactions = _parseReactions(data['reactions']);
            return parsedReactions.isNotEmpty ? parsedReactions : old.reactions;
          }(),
      seenBy: seenBy.isNotEmpty ? seenBy : old.seenBy,
      createdAt: old.createdAt,
    );
  }

  void _handleMessageUpdated(dynamic data) {
    final map = _tryMap(data);
    if (map == null) return;

    final String? messageId =
        map['id']?.toString() ??
        map['_id']?.toString() ??
        map['messageId']?.toString();
    final String? convId = map['conversationId']?.toString();

    if (convId != null && convId != widget.conversationId) return;
    if (messageId == null || messageId.isEmpty) return;

    final currentIndex = _messages.indexWhere((m) => m.id == messageId);
    if (currentIndex == -1) return;
    final current = _messages[currentIndex];

    final merged = (map.containsKey('senderId') || map.containsKey('content'))
        ? _normalizeMessage(MessageModel.fromJson(map))
        : _mergeMessageData(current, map);

    final currentUserId = authService.userId;
    if (currentUserId != null && merged.deletedBy.contains(currentUserId)) {
      _chatController.removeMessageById(messageId);
      return;
    }

    _chatController.updateMessageById(messageId, (_) => merged);

    if (_editingMessage?.id == messageId) {
      setState(() {
        _editingMessage = null;
        _textCtrl.clear();
      });
    }
  }

  void _handleMessageEdited(dynamic data) => _handleMessageUpdated(data);

  void _handleMessageRecalled(dynamic data) {
    final map = _tryMap(data);
    if (map == null) return;
    final convId = map['conversationId']?.toString();
    if (convId != null && convId != widget.conversationId) return;

    final messageData = _tryMap(map['message']);
    if (messageData != null) {
      final recalled = _normalizeMessage(MessageModel.fromJson(messageData));
      if (recalled.conversationId != widget.conversationId) return;
      _updateMessageById(recalled.id, (_) => recalled);
      if (_editingMessage?.id == recalled.id)
        setState(() => _editingMessage = null);
      return;
    }

    final messageId = map['messageId']?.toString();
    if (messageId == null || messageId.isEmpty) return;
    _updateMessageById(
      messageId,
      (old) => MessageModel(
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
      ),
    );
    if (_editingMessage?.id == messageId)
      setState(() => _editingMessage = null);
  }

  void _handleMessageDeletedForMe(dynamic data) {
    final map = _tryMap(data);
    if (map == null) return;
    final convId = map['conversationId']?.toString();
    if (convId != null && convId != widget.conversationId) return;

    final messageId =
        map['messageId']?.toString() ??
        map['id']?.toString() ??
        map['_id']?.toString();
    if (messageId == null || messageId.isEmpty) return;

    _chatController.removeMessageById(messageId);
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

  void _scrollToBottom({bool animated = true, int retry = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollCtrl.hasClients) {
        if (retry < 8) {
          Future.delayed(const Duration(milliseconds: 45), () {
            _scrollToBottom(animated: animated, retry: retry + 1);
          });
        }
        return;
      }

      final target = _scrollCtrl.position.maxScrollExtent;
      if (!target.isFinite) return;

      if (animated) {
        _scrollCtrl.animateTo(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      } else {
        _scrollCtrl.jumpTo(target);
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

  void _startEditing(MessageModel msg) {
    if (msg.senderId != authService.userId) return;
    setState(() {
      _editingMessage = msg;
      _replyTo = null;
      _showEmoji = false;
    });
    _textCtrl.text = msg.content;
    _textCtrl.selection = TextSelection.collapsed(offset: msg.content.length);
    _focusNode.requestFocus();
  }

  void _cancelEditing() {
    if (_editingMessage == null) return;
    setState(() => _editingMessage = null);
    _textCtrl.clear();
  }

  void _sendMessage() {
    if (_isUploading) return;
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    final editingMessage = _editingMessage;
    if (editingMessage != null) {
      socketService.editMessage(editingMessage.id, text, widget.conversationId);
      _updateMessageById(
        editingMessage.id,
        (old) => MessageModel(
          id: old.id,
          conversationId: old.conversationId,
          senderId: old.senderId,
          type: old.type,
          content: text,
          metadata: old.metadata,
          replyToId: old.replyToId,
          status: old.status,
          isRecalled: old.isRecalled,
          deletedBy: old.deletedBy,
          reactions: old.reactions,
          seenBy: old.seenBy,
          createdAt: old.createdAt,
        ),
      );
      setState(() {
        _editingMessage = null;
        _textCtrl.clear();
        _showEmoji = false;
      });
      _scrollToBottomBurst();
      return;
    }

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
    _scrollToBottomBurst();
  }

  void _sendQuickLike() {
    if (_isUploading) return;
    final userId = authService.userId;
    if (userId == null || userId.isEmpty) return;

    socketService.sendMessage({
      'conversationId': widget.conversationId,
      'senderId': userId,
      'content': '👍',
      'type': 'TEXT',
    });

    setState(() {
      _replyTo = null;
      _showEmoji = false;
    });
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
        'conversationId': widget.conversationId,
        'senderId': authService.userId!,
        'type': 'VOICE',
        'content': uploaded.fileUrl,
        if (_replyTo != null) 'replyToId': _replyTo!.id,
        'metadata': {
          'duration': durationSec,
          'fileName': uploaded.fileName,
          'fileSize': uploaded.fileSize,
        },
      });
      if (mounted) {
        setState(() => _replyTo = null);
        _scrollToBottomBurst();
      }
      return null;
    });
  }

  Future<void> _pickAndSendImage() async {
    try {
      await _runMediaUpload(() async {
        final picked = await _chatMediaService.pickImage();
        if (picked == null) return null;
        final uploaded = await _chatMediaService.uploadPickedImage(
          picked,
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => _uploadProgress = progress);
          },
        );

        socketService.sendMessage({
          'conversationId': widget.conversationId,
          'senderId': authService.userId!,
          'type': 'IMAGE',
          'content': uploaded.fileUrl,
          if (_replyTo != null) 'replyToId': _replyTo!.id,
          'metadata': {
            'fileName': uploaded.fileName,
            'fileSize': uploaded.fileSize,
          },
        });
        if (mounted) {
          setState(() => _replyTo = null);
          _scrollToBottomBurst();
        }
        return null;
      });
    } catch (e) {
      log('❌ Chọn ảnh thất bại: $e');
    }
  }

  Future<void> _pickAndSendFile() async {
    try {
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
          'conversationId': widget.conversationId,
          'senderId': authService.userId!,
          'type': 'FILE',
          'content': uploaded.fileUrl,
          if (_replyTo != null) 'replyToId': _replyTo!.id,
          'metadata': {
            'fileName': uploaded.fileName,
            'fileSize': uploaded.fileSize,
          },
        });

        if (mounted) {
          setState(() => _replyTo = null);
          _scrollToBottomBurst();
        }
        return null;
      });
    } catch (e) {
      log('❌ Chọn file thất bại: $e');
    }
  }

  Future<void> _pickAndSendVideo() async {
    try {
      await _runMediaUpload(() async {
        final picked = await _chatMediaService.pickVideo();
        if (picked == null) return null;
        final uploaded = await _chatMediaService.uploadPickedVideo(
          picked,
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => _uploadProgress = progress);
          },
        );

        socketService.sendMessage({
          'conversationId': widget.conversationId,
          'senderId': authService.userId!,
          'type': 'VIDEO',
          'content': uploaded.fileUrl,
          if (_replyTo != null) 'replyToId': _replyTo!.id,
          'metadata': {
            'fileName': uploaded.fileName,
            'fileSize': uploaded.fileSize,
            if (uploaded.thumbnailUrl != null)
              'thumbnailUrl': uploaded.thumbnailUrl,
            if (uploaded.thumbnailUrl != null)
              'thumbnail': uploaded.thumbnailUrl,
          },
        });

        if (!mounted) return null;
        setState(() {
          _replyTo = null;
          _uploadProgress = 1;
        });
        _scrollToBottomBurst();
        return null;
      });
    } catch (e) {
      log('❌ Gửi video thất bại: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gửi video thất bại, vui lòng thử lại.'),
          ),
        );
      }
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

  void _emitSeenForLatest() {
    _chatController.markLatestSeen();
  }

  bool _isSeenByCurrentUser(MessageModel msg) {
    if (msg.senderId == authService.userId) return false;
    return msg.seenBy.any((s) => s.userId == authService.userId);
  }

  bool _isSeenByPeer(MessageModel msg) {
    if (msg.status == 'SEEN') return true;
    final peerId = widget.otherUser?.id;
    if (peerId != null && peerId.isNotEmpty)
      return msg.seenBy.any((s) => s.userId == peerId);
    return msg.seenBy.isNotEmpty;
  }

  String? _lastOutgoingMessageId() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].senderId == authService.userId) return _messages[i].id;
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
                    builder: (_) => Container(
                      height: MediaQuery.of(context).size.height * 0.92,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                        child: AiScreen(
                          targetConversationId: widget.conversationId,
                          autoSummarizeOnOpen: true,
                        ),
                      ),
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
                  _pickAndSendImage();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.image_rounded,
                  color: AppColors.textPrimary,
                ),
                title: const Text('Chọn ảnh'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndSendImage();
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
              ListTile(
                leading: const Icon(
                  Icons.videocam_outlined,
                  color: AppColors.textPrimary,
                ),
                title: const Text('Gửi video'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndSendVideo();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _addReaction(MessageModel msg, String type) {
    final me = authService.userId ?? '';
    _updateMessageById(msg.id, (old) {
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
    socketService.sendReaction(
      msg.id,
      authService.userId ?? '',
      type,
      widget.conversationId,
    );
  }

  void _recallMessage(MessageModel msg) {
    socketService.recallMessage(msg.id, widget.conversationId);
    _updateMessageById(
      msg.id,
      (old) => MessageModel(
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
      ),
    );
    if (_editingMessage?.id == msg.id) setState(() => _editingMessage = null);
  }

  void _deleteMessageForMe(MessageModel msg) {
    socketService.deleteMessageMe(msg.id, authService.userId ?? '');
    setState(() {
      _chatController.removeMessageById(msg.id);
      _rebuildChatItems();
      if (_replyTo?.id == msg.id) _replyTo = null;
      if (_editingMessage?.id == msg.id) {
        _editingMessage = null;
        _textCtrl.clear();
        _focusNode.unfocus();
      }
    });
  }

  void _openImageViewer(MessageModel msg) {
    if (!msg.isImage) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(
          imageUrl: msg.content,
          heroTag: 'image_${msg.id}',
        ),
      ),
    );
  }

  void _startVoiceCall() {
    final otherUser = widget.otherUser;
    if (otherUser == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VoiceCallScreen(
          otherUser: otherUser,
          isIncoming: false,
          conversationId: widget.conversationId,
        ),
      ),
    );
  }

  void _startVideoCall() {
    final otherUser = widget.otherUser;
    if (otherUser == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => VideoCallScreen(
          otherUser: otherUser,
          isIncoming: false,
          conversationId: widget.conversationId,
        ),
      ),
    );
  }

  Future<void> _downloadFile(MessageModel msg) async {
    if (msg.type != 'FILE') return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đang bắt đầu tải xuống...'),
        duration: Duration(seconds: 2),
      ),
    );
    try {
      final url = msg.content;
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể tải xuống file')),
          );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Lỗi khi tải xuống file')));
    }
  }

  String _peerNameForOptions() {
    final peerName = widget.otherUser?.fullName.trim() ?? '';
    if (peerName.isNotEmpty) return peerName;
    final convName = widget.conversation.name?.trim() ?? '';
    if (convName.isNotEmpty) return convName;
    return 'Người dùng';
  }

  ApiGroupModel _buildOptionsGroupModel() {
    return ApiGroupModel(
      id: widget.conversationId,
      name: _peerNameForOptions(),
      avatar: widget.otherUser?.avatar ?? (widget.conversation.avatar ?? ''),
      members: widget.conversation.members
          .map((m) => ApiGroupMember(userId: m.userId, role: m.role))
          .toList(),
      description: null,
      lastMessageContent: widget.conversation.lastMessage?.content,
      lastMessageAt: widget.conversation.lastMessage?.createdAt,
      updatedAt: widget.conversation.updatedAt,
    );
  }

  Future<void> _openOptions() async {
    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) => ChatOptionsScreen(
          group: _buildOptionsGroupModel(),
          isGroup: false,
          peerName: _peerNameForOptions(),
          chatController: _chatController,
          memberNames: {
            authService.userId ?? '': authService.currentUser?.displayName ?? 'Tôi',
            widget.otherUser?.id ?? '': _peerNameForOptions(),
          },
          memberAvatars: {
            authService.userId ?? '': authService.currentUser?.avatar ?? '',
            widget.otherUser?.id ?? '': widget.conversation.avatar ?? '',
          },
        ),
      ),
    );
    if (!mounted) return;
    if (result is String && result.isNotEmpty) {
      _chatController.jumpToMessage(result);
      return;
    }
    if (result is ApiGroupModel) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => GroupChatScreen(group: result)),
      );
    }
  }

  bool _isPinSystemMessage(MessageModel msg) {
    final content = msg.content.trim();
    if (content.isEmpty) return false;
    if (content.startsWith('PIN_MESSAGE|')) return true;
    if (content.startsWith('UNPIN_MESSAGE|')) return true;
    if (content.contains('Bạn đã ghim một tin nhắn')) return true;
    if (msg.type.toUpperCase() == 'SYSTEM' && content.contains('ghim')) {
      return true;
    }
    return false;
  }

  String _pinSystemDisplayText(MessageModel msg) {
    final content = msg.content.trim();
    if (content.startsWith('PIN_MESSAGE|')) return 'Đã ghim một tin nhắn';
    if (content.startsWith('UNPIN_MESSAGE|')) return 'Đã bỏ ghim một tin nhắn';
    return content;
  }

  Future<void> _openPinnedMessages() async {
    final selectedMessageId = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) => PinnedMessagesScreen(
          controller: _chatController,
          chatTitle: _peerNameForOptions(),
          chatAvatar: widget.conversation.avatar,
          memberNames: {
            authService.userId ?? '': authService.currentUser?.displayName ?? 'Tôi',
            widget.otherUser?.id ?? '': _peerNameForOptions(),
          },
          memberAvatars: {
            authService.userId ?? '': authService.currentUser?.avatar ?? '',
            widget.otherUser?.id ?? '': widget.conversation.avatar ?? '',
          },
        ),
      ),
    );
    if (selectedMessageId == null || selectedMessageId.isEmpty) return;
    await _jumpToMessageExact(selectedMessageId);
  }

  Widget _buildPinSystemLine(MessageModel msg) {
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _peerNameForOptions();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        children: [
          // ── Header (phong cách mới giống GroupChatScreen) ──
          SafeArea(
            bottom: false,
            child: ConversationHeader(
              title: title,
              avatarName: title,
              avatarUrl: widget.otherUser?.avatar,
              isOnline: _peerOnline,
              presenceText: _presenceText(),
              onBackTap: _handleBack,
              onVoiceCallTap: _startVoiceCall,
              onVideoCallTap: _startVideoCall,
              onAppearanceTap: _showAppearanceSheet,
              onInfoTap: _openOptions,
            ),
          ),

          // ── Messages ──
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : Container(
                    decoration: BoxDecoration(
                      gradient:
                          _backgroundOptions[_selectedBackgroundIndex].gradient,
                    ),
                    child: GestureDetector(
                      onTap: () {
                        _focusNode.unfocus();
                        setState(() => _showEmoji = false);
                      },
                      child: ConversationTimeline(
                        controller: _scrollCtrl,
                        items: _chatItems,
                        showTypingIndicator: _isTyping,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        messageBuilder: _buildMessageBubble,
                        callBuilder: (call, index) {
                          final isMe =
                              call.callerId.toString() ==
                              authService.userId.toString();
                          return ConversationCallBubble(
                            call: call,
                            callerAvatar: !isMe
                                ? widget.otherUser?.avatar
                                : null,
                            callerName: !isMe
                                ? widget.otherUser?.fullName
                                : null,
                            showAvatar: _shouldShowAvatarAtIndex(index),
                          );
                        },
                      ),
                    ),
                  ),
          ),

          if (_replyTo != null) _buildReplyPreview(),
          if (_editingMessage != null) _buildEditPreview(),
          if (_isUploading)
            LinearProgressIndicator(
              value: _uploadProgress > 0 ? _uploadProgress : null,
              minHeight: 3,
              color: AppColors.primary,
              backgroundColor: AppColors.bgInput,
            ),

          // ── Input Bar (phong cách mới giống GroupChatScreen) ──
          SafeArea(top: false, child: _buildInputBar()),

          if (_showEmoji) _buildEmojiPanel(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(MessageModel msg, int i) {
    if (_isPinSystemMessage(msg)) {
      return _buildPinSystemLine(msg);
    }

    final lastOutgoingMessageId = _lastOutgoingMessageId();
    final isCurrentUserMessage =
        msg.senderId.toString() == authService.userId.toString();
    final showAvatar = _shouldShowAvatarAtIndex(i);

    return KeyedSubtree(
      key: _keyForMessage(msg.id),
      child: CommonMessageBubble(
        msg: msg,
        isMe: isCurrentUserMessage,
        isGroup: false,
        senderAvatar: !isCurrentUserMessage ? widget.otherUser?.avatar : null,
        senderName: !isCurrentUserMessage ? widget.otherUser?.fullName : null,
        showAvatar: showAvatar,
        showSeenLabel: msg.id == lastOutgoingMessageId && _isSeenByPeer(msg),
        replyToMsg: msg.replyToId != null
            ? _messages.firstWhere(
                (m) => m.id == msg.replyToId,
                orElse: () => msg,
              )
            : null,
        onLongPress: () {
          _showMessageActions(msg);
        },
        onDoubleTap: () {
          _addReaction(msg, 'LIKE');
        },
        onReply: () {
          setState(() => _replyTo = msg);
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
  }

  void _handleBack() {
    // Trên web dễ bị assert navigator.dart:5591 khi pop trong lúc Navigator đang "locked"
    // (do double-tap hoặc đang có transition). Debounce + pop qua root navigator.
    if (_backInProgress) return;
    _backInProgress = true;

    Future.microtask(() async {
      try {
        final root = AppNavigator.navigatorKey.currentState;
        if (root != null) {
          final didPop = await root.maybePop();
          if (didPop) return;
        }

        if (!mounted) return;
        final nav = Navigator.of(context);
        if (nav.canPop()) nav.pop();
      } finally {
        if (mounted) {
          // Nhả khóa sau 1 tick để tránh click liên tiếp
          Future.delayed(const Duration(milliseconds: 150), () {
            if (mounted) _backInProgress = false;
          });
        }
      }
    });
  }

  String? _senderIdForChatItem(ChatItem item) {
    if (item.type == ChatItemType.call) {
      return item.call?.callerId.toString();
    }
    return item.message?.senderId.toString();
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

  Widget _buildCallBubble(CallModel call) {
    final isMe = call.callerId.toString() == authService.userId.toString();
    return ConversationCallBubble(
      call: call,
      callerAvatar: !isMe ? widget.otherUser?.avatar : null,
      callerName: !isMe ? widget.otherUser?.fullName : null,
    );
  }

  Widget _buildTypingIndicator() {
    return const ConversationTypingIndicator();
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

  Widget _buildEditPreview() {
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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Đang sửa tin nhắn',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Inter',
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Nội dung sẽ được cập nhật khi bấm gửi',
                  style: TextStyle(
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
            onPressed: _cancelEditing,
          ),
        ],
      ),
    );
  }

  // ── Input Bar mới: style giống GroupChatScreen ───────────────────────────
  Widget _buildInputBar() {
    final isEditing = _editingMessage != null;

    if (_isRecordingVoice) {
      return ConversationVoiceRecordingBar(
        isCancelHint: _voiceCancelHint,
        dragOffset: _voiceDragDx,
        waveValues: _voiceWave,
        durationText: _formatClock(_voiceDurationSec),
        onCancelTap: () => _finishVoiceRecording(shouldSend: false),
        onDragUpdate: (details) {
          final shouldCancel = details.primaryDelta != null
              ? (_voiceDragDx + details.primaryDelta!) < -100
              : false;
          setState(() {
            _voiceDragDx += details.primaryDelta ?? 0;
            _voiceCancelHint = shouldCancel;
          });
        },
        onDragEnd: (_) {
          final shouldCancel = _voiceCancelHint || _voiceDragDx < -100;
          if (shouldCancel) {
            _finishVoiceRecording(shouldSend: false);
            return;
          }
          setState(() {
            _voiceDragDx = 0;
            _voiceCancelHint = false;
          });
        },
        onSendTap: () => _finishVoiceRecording(shouldSend: true),
      );
    }
    return ConversationComposerBar(
      controller: _textCtrl,
      focusNode: _focusNode,
      hintText: isEditing ? 'Sửa tin nhắn...' : 'Nhắn tin',
      actions: [
        ConversationComposerAction(
          icon: Icons.add_circle_outline,
          onTap: _showComposerActionsSheet,
        ),
        ConversationComposerAction(
          icon: Icons.image_rounded,
          onTap: _pickAndSendImage,
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
              if (isMe)
                ListTile(
                  leading: const Icon(
                    Icons.edit_outlined,
                    color: AppColors.textPrimary,
                    size: 22,
                  ),
                  title: const Text(
                    'Sửa',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontFamily: 'Inter',
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _startEditing(msg);
                  },
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
}

class _ChatBackgroundOption {
  final String label;
  final Gradient gradient;
  const _ChatBackgroundOption({required this.label, required this.gradient});
}

// ── Full-Screen Image Viewer ──────────────────────────────────────────────────
class ImageViewerScreen extends StatelessWidget {
  final String imageUrl;
  final String heroTag;
  const ImageViewerScreen({
    super.key,
    required this.imageUrl,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: CloseButton(
          color: Colors.white,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Hero(
        tag: heroTag,
        child: PhotoView(
          imageProvider: NetworkImage(imageUrl),
          loadingBuilder: (context, event) => Center(
            child: CircularProgressIndicator(
              value: event == null
                  ? 0
                  : event.cumulativeBytesLoaded /
                        (event.expectedTotalBytes ?? 1),
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            ),
          ),
          errorBuilder: (context, error, stackTrace) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Không thể tải ảnh',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          minScale: PhotoViewComputedScale.contained * 0.8,
          maxScale: PhotoViewComputedScale.covered * 2,
          initialScale: PhotoViewComputedScale.contained,
        ),
      ),
    );
  }
}
