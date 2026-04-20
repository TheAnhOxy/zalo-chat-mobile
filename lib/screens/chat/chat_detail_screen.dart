import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/utils/thumbnail_helper.dart';
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
import 'video_player_screen.dart';
import 'forward_message_screen.dart';
import 'dart:developer';
import 'dart:typed_data';
import 'package:url_launcher/url_launcher.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
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
  final _imagePicker = ImagePicker();

  // 1. Thay đổi List messages khởi tạo rỗng và thêm biến loading
  List<MessageModel> _messages = [];
  bool _isLoading = true;
  bool _showEmoji = false;
  MessageModel? _replyTo;
  MessageModel? _editingMessage;
  bool _isTyping = false;
  bool _isUploading = false;
  double _uploadProgress = 0;
  bool _peerOnline = false;
  DateTime? _peerLastSeen;
  int _selectedBackgroundIndex = 0;
  List<CallModel> _calls = [];
  List<ChatItem> _chatItems = [];

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
    _restoreBackground();
    _loadData(); // Lấy lịch sử từ MongoDB
    _initSocket(); // Kết nối real-time
  }

  // 2. Lấy lịch sử tin nhắn từ API
  Future<void> _loadData() async {
    try {
      final results = await Future.wait<dynamic>([
        apiService.getMessages(widget.conversationId, authService.userId!),
        apiService.getCalls(widget.conversationId),
      ]);

      final msgs = _normalizeMessages(results[0] as List<MessageModel>);
      final calls = (results[1] as List<Map<String, dynamic>>)
          .map((e) => CallModel.fromJson(e))
          .toList();
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

      setState(() {
        _messages = msgs;
        _calls = calls;
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

  // 3. Khởi tạo Socket và các sự kiện lắng nghe
  void _initSocket() {
    // Tham gia phòng chat
    socketService.joinConversation(widget.conversationId);

    // ✅ Tự động đánh dấu đã đọc tất cả messages khi vào chat
    socketService.emit('seen_conversation', {
      'conversationId': widget.conversationId,
      'userId': authService.userId,
    });

    // Thêm vào _initSocket():
    socketService.on('conversation_call_updated', (data) {
      try {
        final map = data is Map<String, dynamic>
            ? data
            : Map<String, dynamic>.from(data as Map);

        if (map['conversationId']?.toString() != widget.conversationId) return;

        // Nếu có callData thì thêm call bubble vào chatItems
        final callDataRaw = map['callData'];
        if (callDataRaw != null) {
          final callMap = callDataRaw is Map<String, dynamic>
              ? callDataRaw
              : Map<String, dynamic>.from(callDataRaw as Map);
          final newCall = CallModel.fromJson(callMap);

          setState(() {
            // Kiểm tra trùng trước khi thêm
            final exists = _chatItems.any(
              (i) => i.type == ChatItemType.call && i.call?.id == newCall.id,
            );
            if (!exists) {
              _chatItems = [..._chatItems, ChatItem.call(newCall)]
                ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
            }
          });
          _scrollToBottom();
        }
      } catch (e) {
        log('❌ conversation_call_updated error: $e');
      }
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
            _rebuildChatItems();
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
          _rebuildChatItems();
        });
      } catch (_) {}
    });

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

    socketService.on('user_status_changed', _handlePeerStatusChanged);
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
    socketService.off('message_updated');
    socketService.off('message_edited');
    socketService.off('message_recalled');
    socketService.off('conversation_theme_changed');
    socketService.off('theme_changed');
    socketService.off('user_status_changed');
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  DateTime? _parseDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw);
    }
    return null;
  }

  void _handlePeerStatusChanged(dynamic data) {
    if (widget.otherUser == null || widget.conversation.isGroup) return;
    final map = _tryMap(data);
    if (map == null) return;
    final userId = map['userId']?.toString();
    if (userId == null || userId != widget.otherUser!.id) return;

    final isOnline = map['isOnline'] == true;
    final lastSeen = _parseDateTime(map['lastSeen'] ?? map['lastActiveAt']);

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

  String _presenceText(bool isGroup) {
    if (isGroup) return '${widget.conversation.members.length} thành viên';
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
    if (idx == -1) {
      return _normalizeMessages([...source, next]);
    }
    final copied = [...source];
    copied[idx] = next;
    return _normalizeMessages(copied);
  }

  void _updateMessageById(
    String messageId,
    MessageModel Function(MessageModel old) updater,
  ) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    setState(() {
      _messages[idx] = updater(_messages[idx]);
      _messages = _normalizeMessages(_messages);
      _rebuildChatItems();
    });
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

    // Kiểm tra nếu dữ liệu là nguyên object tin nhắn (thường xảy ra khi dùng toPlainDoc từ NestJS)
    final String? messageId =
        map['id']?.toString() ??
        map['_id']?.toString() ??
        map['messageId']?.toString();
    final String? convId = map['conversationId']?.toString();

    if (convId != null && convId != widget.conversationId) return;
    if (messageId == null || messageId.isEmpty) return;

    setState(() {
      final idx = _messages.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        // TRƯỜNG HỢP 1: Dữ liệu trả về là object tin nhắn đầy đủ (ưu tiên)
        // Kiểm tra các trường bắt buộc để xác định đây là full object
        if (map.containsKey('senderId') || map.containsKey('content')) {
          _messages[idx] = _normalizeMessage(MessageModel.fromJson(map));
        }
        // TRƯỜNG HỢP 2: Dữ liệu chỉ là phần update (dùng hàm merge có sẵn của bạn)
        else {
          _messages[idx] = _mergeMessageData(_messages[idx], map);
        }

        // Xóa trạng thái đang sửa nếu tin nhắn đó vừa được cập nhật thành công
        if (_editingMessage?.id == messageId) {
          _editingMessage = null;
          _textCtrl.clear(); // Xóa text trên input sau khi sửa xong
        }

        // Sắp xếp và chuẩn hóa lại list
        _messages = _normalizeMessages(_messages);
        _rebuildChatItems();
      }
    });
  }

  void _handleMessageEdited(dynamic data) {
    _handleMessageUpdated(data);
  }

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
      if (_editingMessage?.id == recalled.id) {
        setState(() => _editingMessage = null);
      }
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
    if (_editingMessage?.id == messageId) {
      setState(() => _editingMessage = null);
    }
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

  // 5. Gửi tin nhắn thật qua Socket
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
  }

  String _detectContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
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
      final signed = await apiService.getPresignedUrl(fileName, contentType);
      if (signed == null) {
        throw Exception('Không lấy được presigned URL');
      }
      final uploadUrl = signed['uploadUrl']?.toString();
      final fileUrl = signed['fileUrl']?.toString();
      if (uploadUrl == null || uploadUrl.isEmpty) {
        throw Exception('Thiếu uploadUrl từ API presigned URL');
      }
      if (fileUrl == null || fileUrl.isEmpty) {
        throw Exception('Thiếu fileUrl từ API presigned URL');
      }

      final uploaded = await apiService.uploadFileToS3(
        uploadUrl,
        bytes,
        contentType,
        onSendProgress: (sent, total) {
          if (!mounted) return;
          if (total <= 0) return;
          setState(() => _uploadProgress = sent / total);
        },
      );
      if (!uploaded) {
        throw Exception('Upload S3 thất bại');
      }

      socketService.sendMessage({
        'conversationId': widget.conversationId,
        'senderId': authService.userId!,
        'type': type,
        'content': fileUrl,
        if (_replyTo != null) 'replyToId': _replyTo!.id,
        'metadata': {'fileName': fileName, 'fileSize': fileSize},
      });

      setState(() {
        _replyTo = null;
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
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    try {
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      await _uploadToS3AndSendMessage(
        bytes: bytes,
        fileName: picked.name,
        fileSize: bytes.length,
        type: 'IMAGE',
        contentType: _detectContentType(picked.name),
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

      // Ưu tiên bytes có sẵn (web), fallback đọc lại từ path cho mobile/desktop.
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await XFile(file.path!).readAsBytes();
      }
      if (bytes == null) {
        throw Exception('Không đọc được dữ liệu file');
      }

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

  /// Tạo thumbnail từ video thực.
  /// Web  → dart:html canvas (thumbnail_helper_web.dart)
  /// Mobile → video_thumbnail package (thumbnail_helper_io.dart)
  Future<Uint8List?> _generateVideoThumbnail(
    String videoPath,
    Uint8List videoBytes,
  ) async {
    log('🎞 [Thumbnail] Generating... path=$videoPath');
    final bytes = await generateVideoThumbnail(videoPath, videoBytes);
    if (bytes != null) {
      log('✅ [Thumbnail] OK (${bytes.length} bytes)');
    } else {
      log('⚠️ [Thumbnail] null – sẽ gửi video không có thumbnail');
    }
    return bytes;
  }

  Future<void> _pickAndSendVideo() async {
    if (_isUploading) return;
    try {
      final picked = await _imagePicker.pickVideo(source: ImageSource.gallery);
      if (picked == null) return;

      final videoBytes = await picked.readAsBytes();
      if (videoBytes.isEmpty) {
        throw Exception('Video rỗng hoặc không đọc được dữ liệu');
      }

      setState(() {
        _isUploading = true;
        _uploadProgress = 0;
      });

      final now = DateTime.now().millisecondsSinceEpoch;
      final videoExt = _safeFileExtension(picked.name, fallback: 'mp4');
      final videoFileName = picked.name.isNotEmpty
          ? picked.name
          : 'video_$now.$videoExt';

      // Tạo thumbnail từ video thực (web dùng canvas, mobile dùng video_thumbnail)
      final thumbnailBytes = await _generateVideoThumbnail(
        picked.path,
        videoBytes,
      );

      // Upload thumbnail nếu có
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
        log('📸 Thumbnail URL: $thumbnailUrl');
      } else {
        log('ℹ️ Không có thumbnail, tiếp tục upload video...');
      }

      // Upload video (chiếm 70% progress nếu có thumbnail, 100% nếu không)
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
      if (videoUrl == null || videoUrl.isEmpty) {
        throw Exception('Upload video thất bại');
      }

      socketService.sendMessage({
        'conversationId': widget.conversationId,
        'senderId': authService.userId!,
        'type': 'VIDEO',
        'content': videoUrl,
        if (_replyTo != null) 'replyToId': _replyTo!.id,
        'metadata': {
          'fileName': videoFileName,
          'fileSize': videoBytes.length,
          if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
          if (thumbnailUrl != null) 'thumbnail': thumbnailUrl,
        },
      });

      if (!mounted) return;
      setState(() {
        _replyTo = null;
        _uploadProgress = 1;
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
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0;
        });
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

  ConversationMember? _getMemberInfo(String userId) {
    try {
      return widget.conversation.members.firstWhere((m) => m.userId == userId);
    } catch (e) {
      return null;
    }
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
    if (_editingMessage?.id == msg.id) {
      setState(() => _editingMessage = null);
    }
  }

  void _deleteMessageForMe(MessageModel msg) {
    // 1. Gửi lệnh xóa lên server để lưu vào Database (Tránh hiện lại khi load lại chat)
    socketService.deleteMessageMe(msg.id, authService.userId ?? '');

    log(
      '🗑️ Requesting delete message ${msg.id} for user ${authService.userId}',
    );

    setState(() {
      // 2. Xóa ngay lập tức khỏi danh sách đang hiển thị
      _messages.removeWhere((m) => m.id == msg.id);
      _rebuildChatItems();

      // 3. Reset các trạng thái liên quan
      if (_replyTo?.id == msg.id) {
        _replyTo = null;
      }
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
        log('✅ Tải file thành công: $url');
      } else {
        log('❌ Không thể mở URL: $url');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể tải xuống file')),
          );
        }
      }
    } catch (e) {
      log('❌ Lỗi tải file: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Lỗi khi tải xuống file')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGroup = widget.conversation.isGroup;
    final lastOutgoingMessageId = _lastOutgoingMessageId();
    final String title;
    if (isGroup) {
      final n = widget.conversation.name;
      title = (n != null && n.isNotEmpty) ? n : 'Nhóm';
    } else {
      final n = widget.otherUser?.fullName;
      title = (n != null && n.isNotEmpty) ? n : 'Người dùng';
    }

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
                            if (i == _chatItems.length) {
                              return _buildTypingIndicator();
                            }

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
            if (_editingMessage != null) _buildEditPreview(),
            if (_isUploading)
              LinearProgressIndicator(
                value: _uploadProgress > 0 ? _uploadProgress : null,
                minHeight: 3,
                color: AppColors.primary,
                backgroundColor: AppColors.bgInput,
              ),
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
      onImageTap: () => _openImageViewer(msg),
      onFileTap: () => _downloadFile(msg),
      onVideoTap: () => _openVideoPlayer(msg),
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
    final online = _peerOnline;
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
                  _presenceText(isGroup),
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

  Widget _buildInputBar() {
    final isEditing = _editingMessage != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => setState(() {
              _showEmoji = !_showEmoji;
            }),
            child: Icon(
              _showEmoji ? Icons.keyboard : Icons.emoji_emotions_outlined,
              color: _showEmoji ? AppColors.primary : AppColors.textSecondary,
              size: 26,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _isUploading ? null : _pickAndSendImage,
            child: const Icon(
              Icons.image_outlined,
              color: AppColors.textSecondary,
              size: 26,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _isUploading ? null : _pickAndSendFile,
            child: const Icon(
              Icons.attach_file,
              color: AppColors.textSecondary,
              size: 26,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _isUploading ? null : _pickAndSendVideo,
            child: const Icon(
              Icons.videocam_outlined,
              color: AppColors.textSecondary,
              size: 26,
            ),
          ),
          const SizedBox(width: 8),
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
                    hasText
                        ? (isEditing ? Icons.check_rounded : Icons.send_rounded)
                        : Icons.thumb_up_outlined,
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
                  final type = item.$1;
                  final emoji = item.$2;
                  return InkResponse(
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _addReaction(msg, type);
                    },
                    radius: 28,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(emoji, style: const TextStyle(fontSize: 30)),
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
  final VoidCallback? onImageTap;
  final VoidCallback? onFileTap;
  final VoidCallback? onVideoTap;

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
    this.onImageTap,
    this.onFileTap,
    this.onVideoTap,
  });

  String _extractFileNameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.pathSegments.isNotEmpty) {
        return Uri.decodeComponent(uri.pathSegments.last);
      }
    } catch (_) {}
    return url;
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(1)} GB';
  }

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
      log(
        '🖼️ IMAGE MESSAGE: type=${msg.type}, content=${msg.content.substring(0, msg.content.length > 50 ? 50 : msg.content.length)}..., isImage=${msg.isImage}',
      );
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
          errorBuilder: (context, error, stackTrace) {
            log('❌ IMAGE LOAD ERROR: $error');
            return SizedBox(
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
            );
          },
        ),
      );
      content = GestureDetector(
        onTap: onImageTap,
        child: Hero(tag: 'image_${msg.id}', child: imageContent),
      );
    } else if (msg.type == 'VIDEO') {
      final thumbnailUrl =
          msg.metadata?.thumbnailUrl ?? msg.metadata?.thumbnail;
      final title = msg.metadata?.fileName ?? 'Video';
      final videoContent = Stack(
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
      );
      content = GestureDetector(onTap: onVideoTap, child: videoContent);
    } else if (msg.type == 'FILE') {
      final fileName =
          msg.metadata?.fileName ?? _extractFileNameFromUrl(msg.content);
      final fileContent = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: (isMe ? Colors.white : AppColors.primary).withOpacity(
                0.15,
              ),
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
                      color: isMe
                          ? AppColors.bubbleMeText
                          : AppColors.textSecondary,
                      fontFamily: 'Inter',
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
      content = GestureDetector(onTap: onFileTap, child: fileContent);
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

// ── Full-Screen Image Viewer with Hero Animation ────────────────────────────
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
          loadingBuilder: (context, event) {
            return Center(
              child: CircularProgressIndicator(
                value: event == null
                    ? 0
                    : event.cumulativeBytesLoaded /
                          (event.expectedTotalBytes ?? 1),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.primary,
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Center(
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
            );
          },
          minScale: PhotoViewComputedScale.contained * 0.8,
          maxScale: PhotoViewComputedScale.covered * 2,
          initialScale: PhotoViewComputedScale.contained,
        ),
      ),
    );
  }
}
