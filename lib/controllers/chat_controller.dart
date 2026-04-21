import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';

import '../data/models/models.dart';
import '../services/socket_service.dart';

class ChatController extends ChangeNotifier {
  ChatController({
    required this.conversationId,
    required this.currentUserId,
  });

  final String conversationId;
  final String currentUserId;

  final List<MessageModel> _messages = [];
  bool _isPeerTyping = false;
  bool _selfTypingEmitted = false;
  Timer? _typingPulseTimer;
  Timer? _typingIdleTimer;
  bool _isAttached = false;

  List<MessageModel> get messages => List.unmodifiable(_messages);
  bool get isPeerTyping => _isPeerTyping;

  void attach() {
    if (_isAttached) return;
    _isAttached = true;

    socketService.joinConversation(conversationId);
    socketService.on('new_message', _handleNewMessage);
    socketService.on('message_seen', _handleMessageSeen);
    socketService.on('typing', _handleTypingEvent);
    socketService.on('stop_typing', _handleStopTypingEvent);
  }

  void setMessages(List<MessageModel> input) {
    _messages
      ..clear()
      ..addAll(_normalizeMessages(input));
    notifyListeners();
  }

  void handleNewMessage(dynamic data) => _handleNewMessage(data);

  void handleMessageSeen(dynamic data) => _handleMessageSeen(data);

  void handleTypingEvent(dynamic data) => _handleTypingEvent(data);

  void handleStopTypingEvent(dynamic data) => _handleStopTypingEvent(data);

  void upsertMessage(MessageModel next) {
    final idx = _messages.indexWhere((m) => m.id == next.id);
    if (idx == -1) {
      _messages.add(_normalizeMessage(next));
    } else {
      _messages[idx] = _normalizeMessage(next);
    }
    _messages.sort(_compareMessages);
    notifyListeners();
  }

  void updateMessageById(
    String messageId,
    MessageModel Function(MessageModel old) updater,
  ) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    _messages[idx] = _normalizeMessage(updater(_messages[idx]));
    _messages.sort(_compareMessages);
    notifyListeners();
  }

  void removeMessageById(String messageId) {
    final before = _messages.length;
    _messages.removeWhere((m) => m.id == messageId);
    if (_messages.length != before) notifyListeners();
  }

  void markLatestSeen() {
    final unread = _messages.where(
      (m) => m.senderId != currentUserId && !m.isRecalled && !_isSeenByCurrentUser(m),
    );
    if (unread.isEmpty) return;

    socketService.emit('seen_conversation', {
      'conversationId': conversationId,
      'userId': currentUserId,
    });
  }

  void onTextChanged(String text) {
    _typingIdleTimer?.cancel();

    if (text.trim().isEmpty) {
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

  @override
  void dispose() {
    _typingPulseTimer?.cancel();
    _typingIdleTimer?.cancel();
    _emitStopTypingEvent();

    if (_isAttached) {
      socketService.off('new_message', _handleNewMessage);
      socketService.off('message_seen', _handleMessageSeen);
      socketService.off('typing', _handleTypingEvent);
      socketService.off('stop_typing', _handleStopTypingEvent);
      _isAttached = false;
    }

    super.dispose();
  }

  void _handleNewMessage(dynamic data) {
    try {
      final map = _tryMap(data);
      if (map == null) return;

      final messageMap = _extractMessageMap(map);
      if (messageMap == null) return;

      final message = _normalizeMessage(MessageModel.fromJson(messageMap));
      if (message.conversationId != conversationId) return;

      upsertMessage(message);
    } catch (e) {
      log('❌ ChatController new_message error: $e');
    }
  }

  void _handleMessageSeen(dynamic data) {
    try {
      final map = _tryMap(data);
      if (map == null) return;
      if (map['conversationId']?.toString() != conversationId) return;

      final messageId = map['messageId']?.toString();
      if (messageId == null || messageId.isEmpty) return;
      final status = map['status']?.toString();
      final seenByFromPayload = _parseSeenBy(map['seenBy']);
      final seenUserId = map['userId']?.toString();
      final seenAt = _parseDateTime(map['seenAt']) ?? DateTime.now();

      updateMessageById(messageId, (old) {
        final mergedSeenBy = _mergeSeenBy(
          oldSeenBy: old.seenBy,
          seenByFromPayload: seenByFromPayload,
          seenUserId: seenUserId,
          seenAt: seenAt,
        );

        final nextStatus =
            status ??
            ((old.senderId == currentUserId &&
                    mergedSeenBy.any((s) => s.userId != currentUserId))
                ? 'SEEN'
                : old.status);

        return MessageModel(
          id: old.id,
          conversationId: old.conversationId,
          senderId: old.senderId,
          type: old.type,
          content: old.content,
          metadata: old.metadata,
          replyToId: old.replyToId,
          status: nextStatus,
          isRecalled: old.isRecalled,
          deletedBy: old.deletedBy,
          reactions: old.reactions,
          seenBy: mergedSeenBy,
          createdAt: old.createdAt,
        );
      });
    } catch (e) {
      log('❌ ChatController message_seen error: $e');
    }
  }

  void _handleTypingEvent(dynamic data) {
    final map = _tryMap(data);
    if (map == null) return;
    if (map['conversationId']?.toString() != conversationId) return;
    final userId = map['userId']?.toString() ?? '';
    if (userId.isEmpty || userId == currentUserId) return;

    if (_isPeerTyping) return;
    _isPeerTyping = true;
    notifyListeners();
  }

  void _handleStopTypingEvent(dynamic data) {
    final map = _tryMap(data);
    if (map == null) return;
    if (map['conversationId']?.toString() != conversationId) return;
    final userId = map['userId']?.toString() ?? '';
    if (userId.isEmpty || userId == currentUserId) return;

    if (!_isPeerTyping) return;
    _isPeerTyping = false;
    notifyListeners();
  }

  void _typingPulse() {
    _emitTypingEvent();
    _typingPulseTimer = Timer(const Duration(milliseconds: 2500), _typingPulse);
  }

  void _emitTypingEvent() {
    socketService.emit('typing', {
      'conversationId': conversationId,
      'userId': currentUserId,
    });
    _selfTypingEmitted = true;
  }

  void _emitStopTypingEvent() {
    if (!_selfTypingEmitted) return;
    socketService.emit('stop_typing', {
      'conversationId': conversationId,
      'userId': currentUserId,
    });
    _selfTypingEmitted = false;
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

  Map<String, dynamic>? _extractMessageMap(Map<String, dynamic> payload) {
    if (payload.containsKey('conversationId') &&
        (payload.containsKey('_id') || payload.containsKey('id'))) {
      return payload;
    }
    return _tryMap(payload['message']);
  }

  List<MessageModel> _normalizeMessages(List<MessageModel> input) {
    final byId = <String, MessageModel>{};
    for (final m in input) {
      byId[m.id] = _normalizeMessage(m);
    }
    final list = byId.values.toList()..sort(_compareMessages);
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

  DateTime? _parseDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return null;
  }

  List<SeenBy> _mergeSeenBy({
    required List<SeenBy> oldSeenBy,
    required List<SeenBy> seenByFromPayload,
    required String? seenUserId,
    required DateTime seenAt,
  }) {
    final byUser = <String, SeenBy>{
      for (final s in oldSeenBy) s.userId: s,
    };

    for (final s in seenByFromPayload) {
      if (s.userId.isEmpty) continue;
      byUser[s.userId] = s;
    }

    if (seenByFromPayload.isEmpty &&
        seenUserId != null &&
        seenUserId.isNotEmpty) {
      byUser[seenUserId] = SeenBy(userId: seenUserId, seenAt: seenAt);
    }

    return byUser.values.toList();
  }

  bool _isSeenByCurrentUser(MessageModel msg) {
    if (msg.senderId == currentUserId) return false;
    return msg.seenBy.any((s) => s.userId == currentUserId);
  }

  int _compareMessages(MessageModel a, MessageModel b) {
    final cmp = a.createdAt.compareTo(b.createdAt);
    if (cmp != 0) return cmp;
    return a.id.compareTo(b.id);
  }
}
