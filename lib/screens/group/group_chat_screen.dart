import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'dart:developer';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/date_utils.dart' as du;
import '../../core/utils/image_utils.dart';
import '../../data/models/chat_item.dart';
import '../../data/models/models.dart';
import '../../services/api_service.dart';
import '../../services/contacts_api_service.dart';
import '../../services/auth_service.dart';
import '../../services/socket_service.dart';
import 'group_chat_backgrounds.dart';
import 'group_options_screen.dart';
import '../call/group_voice_call_screen.dart';
import '../call/group_video_call_screen.dart';
import '../ai/ai_screen.dart';
import '../../widgets/chat/conversation_composer_bar.dart';
import '../../widgets/chat/conversation_shared_bubbles.dart';
import '../../widgets/chat/conversation_timeline.dart';
import '../../core/utils/thumbnail_helper.dart';

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
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _voiceRecorder = AudioRecorder();

  late ApiGroupModel _group;
  List<MessageModel> _messages = [];
  List<CallModel> _calls = [];
  List<ChatItem> _chatItems = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isTyping = false;
  bool _selfTypingEmitted = false;
  Timer? _typingPulseTimer;
  Timer? _typingIdleTimer;
  final Map<String, ApiUserModel> _memberProfiles = {};
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

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _textCtrl.addListener(_onTextInputChanged);
    _loadBackgroundPref();
    _loadMemberProfiles();
    _initSocket();
    // ✅ Lắng nghe sự kiện cuộc gọi
    _setupCallListeners();
    _loadConversationData();
  }

  // ✅ Setup listeners cho sự kiện cuộc gọi
  void _setupCallListeners() {
    socketService.on('participant_left', _handleParticipantLeftEvent);
    socketService.on('call_ended', _handleCallEndedEvent);
    socketService.on(
      'conversation_call_updated',
      _handleConversationCallUpdated,
    );
    socketService.on('typing', _handleTypingEvent);
    socketService.on('stop_typing', _handleStopTypingEvent);
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
    final userId = authService.userId;
    if (userId == null || userId.isEmpty) return;

    socketService.emit('typing', {
      'conversationId': _group.id,
      'userId': userId,
    });
    _selfTypingEmitted = true;
  }

  void _emitStopTypingEvent() {
    if (!_selfTypingEmitted) return;
    final userId = authService.userId;
    if (userId == null || userId.isEmpty) return;

    socketService.emit('stop_typing', {
      'conversationId': _group.id,
      'userId': userId,
    });
    _selfTypingEmitted = false;
  }

  void _typingPulse() {
    if (!mounted) return;
    if (_textCtrl.text.trim().isEmpty) {
      _typingPulseTimer = null;
      return;
    }
    _emitTypingEvent();
    _typingPulseTimer = Timer(const Duration(milliseconds: 2500), _typingPulse);
  }

  void _onTextInputChanged() {
    if (!mounted) return;
    setState(() {});

    final text = _textCtrl.text.trim();
    _typingIdleTimer?.cancel();

    if (text.isEmpty) {
      _typingPulseTimer?.cancel();
      _typingPulseTimer = null;
      _emitStopTypingEvent();
      return;
    }

    if (!_selfTypingEmitted) {
      _emitTypingEvent();
    }

    if (_typingPulseTimer == null || !_typingPulseTimer!.isActive) {
      _typingPulseTimer = Timer(
        const Duration(milliseconds: 2500),
        _typingPulse,
      );
    }

    _typingIdleTimer = Timer(const Duration(seconds: 2), () {
      _typingPulseTimer?.cancel();
      _typingPulseTimer = null;
      _emitStopTypingEvent();
    });
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
    _typingPulseTimer?.cancel();
    _typingIdleTimer?.cancel();
    _emitStopTypingEvent();
    _voiceTimer?.cancel();
    _voiceAmplitudeSub?.cancel();
    socketService.off('participant_left', _handleParticipantLeftEvent);
    socketService.off('call_ended', _handleCallEndedEvent);
    socketService.off(
      'conversation_call_updated',
      _handleConversationCallUpdated,
    );
    socketService.off('typing', _handleTypingEvent);
    socketService.off('stop_typing', _handleStopTypingEvent);
    socketService.off('new_message', _handleNewMessageEvent);
    socketService.off('message_edited', _handleMessageUpdatedEvent);
    socketService.off('message_recalled', _handleMessageUpdatedEvent);
    _textCtrl.removeListener(_onTextInputChanged);
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
      ]);
      if (!mounted) return;
      final messages = _normalizeMessages(results[0] as List<MessageModel>);
      final calls = (results[1] as List<Map<String, dynamic>>)
          .map((e) => CallModel.fromJson(e))
          .toList();
      setState(() {
        _messages = messages;
        _calls = calls;
        _rebuildChatItems();
        _isLoading = false;
      });
      _emitSeenForLatest();
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
    setState(() {
      _messages = _upsertMessage(_messages, msg);
      _rebuildChatItems();
    });
    _emitSeenForLatest();
    _scrollToBottom();
  }

  void _handleMessageUpdatedEvent(dynamic data) {
    final map = _tryMap(data);
    if (map == null) return;
    final convId = map['conversationId']?.toString();
    if (convId != null && convId != _group.id) return;
    _loadConversationData();
  }

  void _handleParticipantLeftEvent(dynamic data) {
    final map = _tryMap(data);
    if (map == null) return;
    final callId = map['callId']?.toString() ?? '';
    if (callId.isEmpty) return;

    _activeCallId = callId;
    if (mounted) setState(() {});
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
    if (mounted) setState(() {});
    _syncCallsRealtime();
  }

  void _handleTypingEvent(dynamic data) {
    final map = _tryMap(data);
    if (map == null) return;
    final conversationId = map['conversationId']?.toString() ?? '';
    final userId = map['userId']?.toString() ?? '';
    if (conversationId != _group.id ||
        userId.isEmpty ||
        userId == authService.userId) {
      return;
    }
    if (!mounted) return;
    setState(() => _isTyping = true);
    _scrollToBottom();
  }

  void _handleStopTypingEvent(dynamic data) {
    final map = _tryMap(data);
    if (map == null) return;
    final conversationId = map['conversationId']?.toString() ?? '';
    final userId = map['userId']?.toString() ?? '';
    if (conversationId != _group.id ||
        userId.isEmpty ||
        userId == authService.userId) {
      return;
    }
    if (!mounted) return;
    setState(() => _isTyping = false);
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

  Future<void> _uploadVoiceAndSend(String voicePath, int durationSec) async {
    if (_isUploading) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    try {
      final bytes = await XFile(voicePath).readAsBytes();
      if (bytes.isEmpty) throw Exception('Voice rỗng');

      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final signed = await apiService.getPresignedUrl(fileName, 'audio/mpeg');
      if (signed == null) throw Exception('Không lấy được presigned URL');

      final uploadUrl = signed['uploadUrl']?.toString();
      final fileUrl = signed['fileUrl']?.toString();
      if (uploadUrl == null || uploadUrl.isEmpty) {
        throw Exception('Thiếu uploadUrl');
      }
      if (fileUrl == null || fileUrl.isEmpty) throw Exception('Thiếu fileUrl');

      final uploaded = await apiService.uploadFileToS3(
        uploadUrl,
        bytes,
        'audio/mpeg',
        onSendProgress: (sent, total) {
          if (!mounted || total <= 0) return;
          setState(() => _uploadProgress = sent / total);
        },
      );

      if (!uploaded) throw Exception('Upload voice thất bại');

      socketService.sendMessage({
        'conversationId': _group.id,
        'senderId': authService.userId!,
        'type': 'VOICE',
        'content': fileUrl,
        'metadata': {
          'duration': durationSec,
          'fileName': fileName,
          'fileSize': bytes.length,
        },
      });
    } catch (e) {
      log('❌ Upload voice thất bại: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gửi tin nhắn thoại thất bại, vui lòng thử lại.'),
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _uploadProgress = 0;
      });
    }
  }

  String _detectContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.zip')) return 'application/zip';
    if (lower.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }

  String _detectImageContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }

  String _normalizeImageFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return fileName;

    final dot = fileName.lastIndexOf('.');
    final baseName = dot > 0 ? fileName.substring(0, dot) : fileName;
    return '$baseName.jpg';
  }

  Future<void> _uploadToS3AndSendMessage({
    required Uint8List bytes,
    required String fileName,
    required int fileSize,
    required String type,
    required String contentType,
  }) async {
    if (_isUploading) return;
    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });
    try {
      final fileUrl = await apiService.uploadFileAndGetUrl(
        fileName: fileName,
        bytes: bytes,
        contentType: contentType,
        onSendProgress: (sent, total) {
          if (!mounted || total <= 0) return;
          setState(() => _uploadProgress = sent / total);
        },
      );
      if (fileUrl == null || fileUrl.isEmpty) {
        throw Exception('Upload file thất bại');
      }

      socketService.sendMessage({
        'conversationId': _group.id,
        'senderId': authService.userId!,
        'type': type,
        'content': fileUrl,
        'metadata': {'fileName': fileName, 'fileSize': fileSize},
      });
    } catch (e) {
      log('❌ Upload file thất bại: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tải file lên thất bại, vui lòng thử lại.'),
          ),
        );
      }
    } finally {
      if (mounted)
        setState(() {
          _isUploading = false;
          _uploadProgress = 0;
        });
    }
  }

  Future<void> _pickAndSendImage() async {
    try {
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final rawFileName = picked.name.isNotEmpty
          ? picked.name
          : (picked.path.isNotEmpty
                ? picked.path.split('/').last
                : 'image.jpg');
      final fileName = _normalizeImageFileName(rawFileName);
      final contentType = _detectImageContentType(fileName);
      await _uploadToS3AndSendMessage(
        bytes: bytes,
        fileName: fileName,
        fileSize: bytes.length,
        type: 'IMAGE',
        contentType: contentType,
      );
    } catch (e) {
      log('❌ Chọn ảnh thất bại: $e');
    }
  }

  Future<void> _pickAndSendFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null)
        bytes = await XFile(file.path!).readAsBytes();
      if (bytes == null) throw Exception('Không đọc được dữ liệu file');
      await _uploadToS3AndSendMessage(
        bytes: bytes,
        fileName: file.name,
        fileSize: file.size,
        type: 'FILE',
        contentType: _detectContentType(file.name),
      );
    } catch (e) {
      log('❌ Chọn file thất bại: $e');
    }
  }

  String _safeFileExtension(String fileName, {String fallback = 'bin'}) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return fallback;
    return fileName.substring(dot + 1).toLowerCase();
  }

  Future<Uint8List?> _generateVideoThumbnail(
    String videoPath,
    Uint8List videoBytes,
  ) async {
    log('🎞 [Thumbnail] Generating... path=$videoPath');
    final bytes = await generateVideoThumbnail(videoPath, videoBytes);
    if (bytes != null) {
      log('✅ [Thumbnail] OK (${bytes.length} bytes)');
    } else {
      log('⚠️ [Thumbnail] null');
    }
    return bytes;
  }

  Future<void> _pickAndSendVideo() async {
    if (_isUploading) return;
    try {
      final picked = await _imagePicker.pickVideo(source: ImageSource.gallery);
      if (picked == null) return;
      final videoBytes = await picked.readAsBytes();
      if (videoBytes.isEmpty) throw Exception('Video rỗng');

      setState(() {
        _isUploading = true;
        _uploadProgress = 0;
      });

      final now = DateTime.now().millisecondsSinceEpoch;
      final videoExt = _safeFileExtension(picked.name, fallback: 'mp4');
      final videoFileName = picked.name.isNotEmpty
          ? picked.name
          : 'video_$now.$videoExt';
      final thumbnailBytes = await _generateVideoThumbnail(
        picked.path,
        videoBytes,
      );

      String? thumbnailUrl;
      if (thumbnailBytes != null && thumbnailBytes.isNotEmpty) {
        final thumbnailFileName = 'video_thumb_$now.jpg';
        thumbnailUrl = await apiService.uploadFileAndGetUrl(
          fileName: thumbnailFileName,
          bytes: thumbnailBytes,
          contentType: 'image/jpeg',
          onSendProgress: (sent, total) {
            if (!mounted || total <= 0) return;
            setState(() => _uploadProgress = (sent / total) * 0.3);
          },
        );
      }

      final videoProgressStart = thumbnailUrl != null ? 0.3 : 0.0;
      final videoUrl = await apiService.uploadFileAndGetUrl(
        fileName: videoFileName,
        bytes: videoBytes,
        contentType: 'video/mp4',
        onSendProgress: (sent, total) {
          if (!mounted || total <= 0) return;
          setState(
            () => _uploadProgress =
                videoProgressStart + (sent / total) * (1 - videoProgressStart),
          );
        },
      );
      if (videoUrl == null || videoUrl.isEmpty)
        throw Exception('Upload video thất bại');

      socketService.sendMessage({
        'conversationId': _group.id,
        'senderId': authService.userId!,
        'type': 'VIDEO',
        'content': videoUrl,
        'metadata': {
          'fileName': videoFileName,
          'fileSize': videoBytes.length,
          if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
          if (thumbnailUrl != null) 'thumbnail': thumbnailUrl,
        },
      });

      if (!mounted) return;
      setState(() => _uploadProgress = 1);
    } catch (e) {
      log('❌ Gửi video thất bại: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gửi video thất bại, vui lòng thử lại.'),
          ),
        );
      }
    } finally {
      if (mounted)
        setState(() {
          _isUploading = false;
          _uploadProgress = 0;
        });
    }
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
                        messageBuilder: (msg, _) {
                          final isMe = msg.senderId == authService.userId;
                          return _GroupMessageBubble(
                            msg: msg,
                            isMe: isMe,
                            senderLabel: _resolveMemberName(msg.senderId),
                          );
                        },
                        callBuilder: (call) =>
                            ConversationCallBubble(call: call),
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
                if (_activeCallConversationId != null &&
                    _activeCallId != null) {
                  final group = widget.group;
                  // Build participants từ group members
                  final participants = group.members
                      .map(
                        (m) => GroupCallParticipant(
                          userId: m.userId,
                          name: _memberProfiles[m.userId]?.fullName ?? m.userId,
                          avatar: _memberProfiles[m.userId]?.avatar,
                        ),
                      )
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
    if (_isRecordingVoice) {
      return _buildVoiceRecordingBar();
    }
    return ConversationComposerBar(
      controller: _textCtrl,
      focusNode: _focusNode,
      hintText: 'Nhắn tin',
      actions: [
        ConversationComposerAction(
          icon: Icons.add_circle,
          onTap: () => setState(() => _showEmoji = !_showEmoji),
        ),
        ConversationComposerAction(
          icon: Icons.camera_alt_rounded,
          onTap: _pickAndSendImage,
          enabled: !_isUploading,
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
        ConversationComposerAction(
          icon: Icons.attach_file,
          onTap: _pickAndSendFile,
          enabled: !_isUploading,
        ),
        ConversationComposerAction(
          icon: Icons.videocam_outlined,
          onTap: _pickAndSendVideo,
          enabled: !_isUploading,
        ),
      ],
      onEmojiTap: () => setState(() => _showEmoji = !_showEmoji),
      onSend: _sendMessage,
      onEmptyActionTap: () {},
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet chứa AiScreen (dùng cho menu Quick AI / File trong group chat)
// ─────────────────────────────────────────────────────────────────────────────

class _GroupAiChatSheet extends StatelessWidget {
  const _GroupAiChatSheet();

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
          const Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              child: AiScreen(),
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
