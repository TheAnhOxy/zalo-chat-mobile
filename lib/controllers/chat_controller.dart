import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/models.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

class ChatController extends ChangeNotifier {
  ChatController({
    required this.conversationId,
    required this.currentUserId,
    this.initialPinnedMessageIds = const <String>[],
    this.initialPinnedMessages = const <MessageModel>[],
    this.scrollController,
    this.fetchMessagesAround,
    this.onJumpCompleted,
    this.estimateItemHeight,
  });

  static const double _defaultItemHeight = 92;
  static const String _pinSignalPrefix = 'PIN_MESSAGE|';
  static const String _unpinSignalPrefix = 'UNPIN_MESSAGE|';

  final String conversationId;
  final String currentUserId;
  final List<String> initialPinnedMessageIds;
  final List<MessageModel> initialPinnedMessages;
  final ScrollController? scrollController;
  final Future<List<MessageModel>> Function(String messageId)?
  fetchMessagesAround;
  final void Function(String messageId)? onJumpCompleted;
  final double Function(MessageModel message)? estimateItemHeight;

  final List<MessageModel> _messages = [];
  final List<MessageModel> _pinnedMessageObjects = [];
  final Set<String> _pinnedMessageIds = <String>{};
  bool _isPeerTyping = false;
  bool _isPinnedStateReady = false;
  bool _isInitializingPinned = false;
  bool _selfTypingEmitted = false;
  Timer? _typingPulseTimer;
  Timer? _typingIdleTimer;
  bool _isAttached = false;

  List<MessageModel> get messages => List.unmodifiable(_messages);
  List<MessageModel> get pinnedMessages =>
      List.unmodifiable(_pinnedMessageObjects);
  bool get isPeerTyping => _isPeerTyping;
  bool get isPinnedStateReady => _isPinnedStateReady;
  Set<String> get pinnedMessageIds => Set.unmodifiable(_pinnedMessageIds);

  String get _pinnedPrefKey =>
      'message_pins_${currentUserId.isEmpty ? 'me' : currentUserId}_$conversationId';

  void attach() {
    if (_isAttached) return;
    _isAttached = true;

    socketService.joinConversation(conversationId);
    socketService.on('new_message', _handleNewMessage);
    socketService.on('message_seen', _handleMessageSeen);
    socketService.on('typing', _handleTypingEvent);
    socketService.on('stop_typing', _handleStopTypingEvent);
    socketService.on('message_pinned_update', _handleMessagePinnedUpdate);

    unawaited(
      initializePinnedState(
        seedPinnedMessageIds: initialPinnedMessageIds,
        seedPinnedMessages: initialPinnedMessages,
      ),
    );
  }

  Future<void> initializePinnedState({
    List<String> seedPinnedMessageIds = const <String>[],
    List<MessageModel> seedPinnedMessages = const <MessageModel>[],
  }) async {
    if (_isInitializingPinned) {
      _pinnedMessageIds.addAll(
        seedPinnedMessageIds.where((id) => id.isNotEmpty),
      );
      if (seedPinnedMessages.isNotEmpty) {
        _upsertPinnedMessageObjects(seedPinnedMessages);
        _pinnedMessageIds.addAll(
          seedPinnedMessages.map((m) => m.id).where((id) => id.isNotEmpty),
        );
      }
      _syncPinnedObjectsWithMessages(_messages);
      notifyListeners();
      return;
    }
    _isInitializingPinned = true;

    final wasReady = _isPinnedStateReady;
    final beforeCount = _pinnedMessageIds.length;

    _pinnedMessageIds.addAll(seedPinnedMessageIds.where((id) => id.isNotEmpty));
    if (seedPinnedMessages.isNotEmpty) {
      _upsertPinnedMessageObjects(seedPinnedMessages);
      _pinnedMessageIds.addAll(
        seedPinnedMessages.map((m) => m.id).where((id) => id.isNotEmpty),
      );
    }

    if (currentUserId.isNotEmpty) {
      await loadPinnedMessages(notify: false, replaceExisting: true);
    }

    if (_pinnedMessageIds.isEmpty) {
      final localIds = await _readPinnedPrefs();
      if (localIds.isNotEmpty) {
        _pinnedMessageIds.addAll(localIds);
      }
    }

    if (_pinnedMessageIds.isNotEmpty || _pinnedMessageObjects.isNotEmpty) {
      _syncPinnedObjectsWithMessages(_messages);
    }

    _isPinnedStateReady = true;
    _isInitializingPinned = false;

    if (_pinnedMessageIds.length != beforeCount) {
      await _persistPinnedPrefs();
    }

    if (!wasReady || _pinnedMessageIds.length != beforeCount) {
      notifyListeners();
    }
  }

  void setMessages(List<MessageModel> input) {
    final normalized = _normalizeMessages(input);
    _messages
      ..clear()
      ..addAll(normalized);
    _syncPinnedStateFromHistory(normalized);
    _syncPinnedObjectsWithMessages(normalized);
    notifyListeners();
  }

  bool isMessagePinned(String messageId) {
    if (messageId.isEmpty) return false;
    return _pinnedMessageIds.contains(messageId);
  }

  Future<void> pinMessage(String messageId) async {
    if (messageId.isEmpty) return;
    socketService.pinMessage(messageId, conversationId, currentUserId);
    if (_pinnedMessageIds.add(messageId)) {
      final fromLoaded = _messages.where((m) => m.id == messageId).toList();
      if (fromLoaded.isNotEmpty) {
        _upsertPinnedMessageObjects(fromLoaded);
      }
      await _persistPinnedPrefs();
      notifyListeners();
    }
  }

  Future<void> unpinMessage(String messageId) async {
    if (messageId.isEmpty) return;
    socketService.unpinMessage(messageId, conversationId, currentUserId);
    if (_pinnedMessageIds.remove(messageId)) {
      _pinnedMessageObjects.removeWhere((m) => m.id == messageId);
      await _persistPinnedPrefs();
      notifyListeners();
    }
  }

  Future<bool> togglePinMessage(String messageId) async {
    if (messageId.isEmpty) return false;
    if (isMessagePinned(messageId)) {
      await unpinMessage(messageId);
      return false;
    }
    await pinMessage(messageId);
    return true;
  }

  Future<void> loadPinnedMessages({
    bool notify = true,
    bool replaceExisting = false,
  }) async {
    if (currentUserId.isEmpty) {
      _isPinnedStateReady = true;
      if (notify) notifyListeners();
      return;
    }
    final pinned = await apiService.getPinnedMessages(
      conversationId,
      currentUserId,
    );
    final before = _pinnedMessageIds.length;
    final loadedIds = pinned
        .map((m) => m.id)
        .where((id) => id.isNotEmpty)
        .toSet();
    if (replaceExisting) {
      _pinnedMessageIds
        ..clear()
        ..addAll(loadedIds);
      _pinnedMessageObjects
        ..clear()
        ..addAll(pinned);
    } else if (loadedIds.isNotEmpty) {
      _pinnedMessageIds.addAll(loadedIds);
      if (pinned.isNotEmpty) {
        _upsertPinnedMessageObjects(pinned);
      }
    }
    _isPinnedStateReady = true;
    if (_pinnedMessageIds.length != before) {
      await _persistPinnedPrefs();
      if (notify) notifyListeners();
      return;
    }
    if (notify) notifyListeners();
  }

  Future<void> jumpToMessage(String messageId) async {
    if (messageId.isEmpty) return;

    var index = _messages.indexWhere((m) => m.id == messageId);

    if (index == -1 && fetchMessagesAround != null) {
      final around = await fetchMessagesAround!(messageId);
      if (around.isNotEmpty) {
        _messages
          ..clear()
          ..addAll(_normalizeMessages(around));
        _syncPinnedObjectsWithMessages(_messages);
        notifyListeners();
      }
      index = _messages.indexWhere((m) => m.id == messageId);
    }

    if (index == -1) return;

    final sc = scrollController;
    if (sc == null || !sc.hasClients) {
      onJumpCompleted?.call(messageId);
      return;
    }

    final offset = _estimateOffsetForIndex(index, sc.position.maxScrollExtent);
    await sc.animateTo(
      offset,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );

    onJumpCompleted?.call(messageId);
  }

  void handleNewMessage(dynamic data) => _handleNewMessage(data);

  void handleMessageSeen(dynamic data) => _handleMessageSeen(data);

  void handleTypingEvent(dynamic data) => _handleTypingEvent(data);

  void handleStopTypingEvent(dynamic data) => _handleStopTypingEvent(data);

  void _handleMessagePinnedUpdate(dynamic data) {
    try {
      final map = _tryMap(data);
      if (map == null) return;
      if (map['conversationId']?.toString() != conversationId) return;

      final messageId = map['messageId']?.toString();
      if (messageId == null || messageId.isEmpty) return;

      final action = map['action']?.toString();
      if (action == 'PINNED') {
        if (_pinnedMessageIds.add(messageId)) {
          final match = _messages.where((m) => m.id == messageId).toList();
          if (match.isNotEmpty) {
            _upsertPinnedMessageObjects(match);
          } else {
            unawaited(_fetchPinnedMessageObjectById(messageId));
          }
          unawaited(_persistPinnedPrefs());
          notifyListeners();
        }
      } else if (action == 'UNPINNED') {
        if (_pinnedMessageIds.remove(messageId)) {
          _pinnedMessageObjects.removeWhere((m) => m.id == messageId);
          unawaited(_persistPinnedPrefs());
          notifyListeners();
        }
      }
    } catch (e) {
      log('❌ ChatController message_pinned_update error: $e');
    }
  }

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
      (m) =>
          m.senderId != currentUserId &&
          !m.isRecalled &&
          !_isSeenByCurrentUser(m),
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

      _applyPinSignalFromMessage(message);

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

  void _emitPinSignal(String messageId, {required bool isPinned}) {
    final signal = isPinned
        ? '$_pinSignalPrefix$messageId'
        : '$_unpinSignalPrefix$messageId';
    socketService.sendMessage({
      'conversationId': conversationId,
      'senderId': currentUserId,
      'type': 'SYSTEM',
      'content': signal,
    });
  }

  void _applyPinSignalFromMessage(MessageModel message) {
    if (message.type.toUpperCase() != 'SYSTEM') return;
    final content = message.content.trim();

    if (content.startsWith(_pinSignalPrefix)) {
      final id = content.substring(_pinSignalPrefix.length).trim();
      if (id.isEmpty) return;
      _pinnedMessageIds.add(id);
      final match = _messages.where((m) => m.id == id).toList();
      if (match.isNotEmpty) {
        _upsertPinnedMessageObjects(match);
      } else {
        unawaited(_fetchPinnedMessageObjectById(id));
      }
      unawaited(_persistPinnedPrefs());
      return;
    }

    if (content.startsWith(_unpinSignalPrefix)) {
      final id = content.substring(_unpinSignalPrefix.length).trim();
      if (id.isEmpty) return;
      _pinnedMessageIds.remove(id);
      _pinnedMessageObjects.removeWhere((m) => m.id == id);
      unawaited(_persistPinnedPrefs());
    }
  }

  Future<void> _fetchPinnedMessageObjectById(String messageId) async {
    final found = await apiService.getMessageById(messageId, currentUserId);
    if (found == null) return;
    if (found.conversationId != conversationId) return;
    _upsertPinnedMessageObjects([found]);
    notifyListeners();
  }

  void _syncPinnedStateFromHistory(List<MessageModel> messages) {
    var changed = false;
    for (final message in messages) {
      if (message.type.toUpperCase() != 'SYSTEM') continue;
      final content = message.content.trim();
      if (content.startsWith(_pinSignalPrefix)) {
        final id = content.substring(_pinSignalPrefix.length).trim();
        if (id.isEmpty) continue;
        changed = _pinnedMessageIds.add(id) || changed;
        continue;
      }
      if (content.startsWith(_unpinSignalPrefix)) {
        final id = content.substring(_unpinSignalPrefix.length).trim();
        if (id.isEmpty) continue;
        changed = _pinnedMessageIds.remove(id) || changed;
      }
    }

    if (changed) {
      _syncPinnedObjectsWithMessages(messages);
      unawaited(_persistPinnedPrefs());
    }
  }

  void _syncPinnedObjectsWithMessages(List<MessageModel> source) {
    final byId = <String, MessageModel>{
      for (final m in _pinnedMessageObjects) m.id: m,
    };

    for (final msg in source) {
      if (_pinnedMessageIds.contains(msg.id)) {
        byId[msg.id] = msg;
      }
    }

    byId.removeWhere((id, _) => !_pinnedMessageIds.contains(id));

    _pinnedMessageObjects
      ..clear()
      ..addAll(
        byId.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );
  }

  void _upsertPinnedMessageObjects(List<MessageModel> incoming) {
    final byId = <String, MessageModel>{
      for (final m in _pinnedMessageObjects) m.id: m,
    };

    for (final msg in incoming) {
      if (msg.id.isEmpty) continue;
      byId[msg.id] = msg;
    }

    _pinnedMessageObjects
      ..clear()
      ..addAll(
        byId.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );
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
    final byUser = <String, SeenBy>{for (final s in oldSeenBy) s.userId: s};

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

  double _estimateOffsetForIndex(int index, double maxExtent) {
    if (index <= 0) return 0;
    double sum = 0;
    for (var i = 0; i < index && i < _messages.length; i++) {
      final item = _messages[i];
      sum += estimateItemHeight?.call(item) ?? _defaultItemHeight;
    }
    return sum.clamp(0, maxExtent);
  }

  Future<void> _persistPinnedPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pinnedPrefKey, _pinnedMessageIds.toList());
  }

  Future<Set<String>> _readPinnedPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_pinnedPrefKey) ?? const [];
    return raw.where((e) => e.isNotEmpty).toSet();
  }
}
