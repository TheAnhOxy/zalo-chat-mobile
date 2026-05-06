import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../services/chatbot_service.dart';
import '../../services/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AiScreen — Tab AI Assistant — Chat thực sự với Gemini AI
// ─────────────────────────────────────────────────────────────────────────────

class AiScreen extends StatefulWidget {
  final String? targetConversationId;
  final int targetConversationLimit;
  final bool autoSummarizeOnOpen;

  const AiScreen({
    super.key,
    this.targetConversationId,
    this.targetConversationLimit = 60,
    this.autoSummarizeOnOpen = false,
  });

  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> with TickerProviderStateMixin {
  final _messages = <ChatMessage>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _isSending = false;
  final List<PlatformFile> _selectedFiles = [];
  String? _conversationId;
  late final AnimationController _typingController;

  // Gợi ý câu hỏi nhanh
  static const _quickReplies = [
    '🤝 Tôi có bao nhiêu bạn?',
    '🆕 Tôi vừa kết bạn với ai?',
    '⏳ Ai đang chờ tôi chấp nhận?',
    '📦 Hướng dẫn gửi file',
    '🔍 Tìm bạn theo tên',
  ];

  @override
  void initState() {
    super.initState();
    _typingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    // Tin nhắn chào mừng
    _messages.add(ChatMessage(
      id: 'welcome',
      content:
          'Xin chào! Tôi là trợ lý AI của QuickChat 🤖\n\nTôi có thể giúp bạn:\n• Xem danh sách bạn bè & lời mời kết bạn\n• Đọc và phân tích file bạn gửi\n• Trả lời câu hỏi về tính năng ứng dụng\n\nHãy hỏi tôi bất cứ điều gì!',
      isUser: false,
      createdAt: DateTime.now(),
    ));

    _loadOrCreateConversation();
  }

  Future<void> _loadOrCreateConversation() async {
    final userId = authService.userId;
    if (userId == null) return;
    try {
      final list = await chatbotService.listConversations(userId: userId);
      if (list.isEmpty) {
        final id = await chatbotService.createConversation(userId: userId);
        setState(() => _conversationId = id);
        return;
      }
      final id = list.first['id']?.toString();
      if (id == null || id.isEmpty) return;
      await _loadConversationById(id);
    } catch (_) {
      // ignore - fallback to local-only
    }

    if (widget.autoSummarizeOnOpen &&
        widget.targetConversationId != null &&
        widget.targetConversationId!.isNotEmpty) {
      // Gửi yêu cầu tóm tắt ngay khi mở AI từ 1 cuộc trò chuyện cụ thể.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      await _sendMessage(
        'Tóm tắt cuộc trò chuyện này (nêu ý chính, quyết định/việc cần làm, mốc thời gian nếu có).',
        targetConversationId: widget.targetConversationId,
      );
    }
  }

  Future<void> _loadConversationById(String id) async {
    final userId = authService.userId;
    if (userId == null) return;
    setState(() => _conversationId = id);

    final msgs = await chatbotService.getConversationMessages(
      userId: userId,
      conversationId: id,
    );
    final mapped = msgs.map((m) {
      final role = m['role']?.toString() ?? 'assistant';
      final content = m['content']?.toString() ?? '';
      final atts = (m['attachments'] as List<dynamic>? ?? [])
          .map((a) => a as Map<String, dynamic>)
          .map(
            (a) => ChatAttachment(
              name: a['name']?.toString() ?? 'file',
              url: a['url']?.toString() ?? '',
              mimeType: a['mimeType']?.toString() ?? 'application/octet-stream',
            ),
          )
          .where((a) => a.url.isNotEmpty)
          .toList();
      return ChatMessage(
        id: m['id']?.toString() ?? 'm_${DateTime.now().millisecondsSinceEpoch}',
        content: content,
        isUser: role == 'user',
        createdAt: DateTime.now(),
        attachments: atts,
        toolsUsed:
            (m['toolsUsed'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      );
    }).toList();

    setState(() {
      _messages
        ..clear()
        ..addAll(mapped);
    });
    _scrollToBottom();
  }

  @override
  void dispose() {
    _typingController.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Send message ──────────────────────────────────────────────────────────

  Future<void> _sendMessage(
    String text, {
    String? targetConversationId,
  }) async {
    final trimmed = text.trim();
    if ((trimmed.isEmpty && _selectedFiles.isEmpty) || _isSending) return;

    final userId = authService.userId;
    if (userId == null) {
      _showSnack('Bạn chưa đăng nhập');
      return;
    }

    _controller.clear();
    _focusNode.unfocus();

    // Thêm tin nhắn user (attachments sẽ được fill sau khi upload xong)
    final userMsgId = 'u_${DateTime.now().millisecondsSinceEpoch}';
    final userMsg = ChatMessage(
      id: userMsgId,
      content: trimmed,
      isUser: true,
      createdAt: DateTime.now(),
      attachments: const [],
    );

    // Thêm placeholder AI đang gõ
    final loadingId = 'ai_${DateTime.now().millisecondsSinceEpoch}';
    final loadingMsg = ChatMessage(
      id: loadingId,
      content: '',
      isUser: false,
      createdAt: DateTime.now(),
      isLoading: true,
    );

    setState(() {
      _messages.add(userMsg);
      _messages.add(loadingMsg);
      _isSending = true;
    });
    _scrollToBottom();

    try {
      // Lấy history (tối đa 10 tin gần nhất, không tính loading)
      final history = _messages
          .where((m) => !m.isLoading && m.id != 'welcome')
          .take(10)
          .toList();

      final uploads = _selectedFiles.isNotEmpty
          ? await chatbotService.uploadChatbotFiles(files: _selectedFiles)
          : <({String fileUrl, String mimeType, String name})>[];

      // Update user message to show downloadable attachments
      final idxUser = _messages.indexWhere((m) => m.id == userMsgId);
      if (idxUser != -1 && uploads.isNotEmpty) {
        setState(() {
          _messages[idxUser] = _messages[idxUser].copyWith(
            attachments: uploads
                .map(
                  (u) => ChatAttachment(
                    name: u.name,
                    url: u.fileUrl,
                    mimeType: u.mimeType,
                  ),
                )
                .toList(),
          );
        });
      }

      final result = await chatbotService.sendMessage(
        userId: userId,
        message: trimmed.isEmpty ? '(Người dùng gửi file đính kèm)' : trimmed,
        files: uploads
            .map((u) => {
                  'url': u.fileUrl,
                  'mimeType': u.mimeType,
                  'name': u.name,
                })
            .toList(),
        conversationId: _conversationId,
        targetConversationId: targetConversationId,
        targetConversationLimit: widget.targetConversationLimit,
        history: history,
      );

      // Cập nhật id Mongo cho tin nhắn user vừa gửi để thu hồi ngay
      if (result.userMessageId != null && result.userMessageId!.isNotEmpty) {
        final idxUser = _messages.indexWhere((m) => m.id == userMsgId);
        if (idxUser != -1) {
          setState(() {
            _messages[idxUser] = _messages[idxUser].copyWith(
              attachments: _messages[idxUser].attachments,
            );
            // ignore: invalid_use_of_protected_member
            _messages[idxUser] = ChatMessage(
              id: result.userMessageId!,
              content: _messages[idxUser].content,
              isUser: _messages[idxUser].isUser,
              createdAt: _messages[idxUser].createdAt,
              toolsUsed: _messages[idxUser].toolsUsed,
              isLoading: _messages[idxUser].isLoading,
              attachments: _messages[idxUser].attachments,
            );
          });
        }
      }

      if (result.conversationId != null &&
          result.conversationId!.isNotEmpty &&
          result.conversationId != _conversationId) {
        setState(() => _conversationId = result.conversationId);
      }

      // Thay loading bằng câu trả lời thực
      final idx = _messages.indexWhere((m) => m.id == loadingId);
      if (idx != -1) {
        setState(() {
          _messages[idx] = _messages[idx].copyWith(
            content: result.reply,
            isLoading: false,
            toolsUsed: result.toolsUsed,
          );
        });
      }
    } catch (e) {
      final idx = _messages.indexWhere((m) => m.id == loadingId);
      if (idx != -1) {
        setState(() {
          _messages[idx] = _messages[idx].copyWith(
            content: 'Đã có lỗi xảy ra. Vui lòng thử lại.',
            isLoading: false,
          );
        });
      }
    } finally {
      setState(() {
        _isSending = false;
        _selectedFiles.clear();
      });
      _scrollToBottom();
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        withData: true, // cần cho Flutter Web
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'png',
          'jpg',
          'jpeg',
          'webp',
          'txt',
          'csv',
          'json',
          'docx',
          'doc',
        ],
      );
      if (result == null || result.files.isEmpty) return;
      setState(() {
        _selectedFiles
          ..clear()
          ..addAll(result.files);
      });
    } catch (e) {
      _showSnack('Không thể chọn file: $e');
    }
  }

  Widget _buildSelectedFilesChips() {
    if (_selectedFiles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: _selectedFiles
            .map(
              (f) => Chip(
                label: Text(
                  f.name,
                  overflow: TextOverflow.ellipsis,
                ),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: _isSending
                    ? null
                    : () {
                        setState(() => _selectedFiles.remove(f));
                      },
              ),
            )
            .toList(),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _newConversation() async {
    final userId = authService.userId;
    if (userId == null) return;
    final id = await chatbotService.createConversation(userId: userId);
    setState(() {
      _conversationId = id;
      _messages
        ..clear()
        ..add(ChatMessage(
          id: 'welcome',
          content: 'Bắt đầu cuộc trò chuyện mới. Bạn muốn hỏi gì?',
          isUser: false,
          createdAt: DateTime.now(),
        ));
    });
  }

  Future<void> _showConversationsSheet() async {
    final userId = authService.userId;
    if (userId == null) return;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        Future<List<Map<String, dynamic>>> future =
            chatbotService.listConversations(userId: userId);

        return StatefulBuilder(
          builder: (context, modalSetState) {
            Future<void> reload() async {
              modalSetState(() {
                future = chatbotService.listConversations(userId: userId);
              });
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: future,
                  builder: (context, snap) {
                    final list = snap.data ?? [];
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Cuộc trò chuyện',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                Navigator.of(ctx).pop();
                                await _newConversation();
                              },
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Mới'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (snap.connectionState == ConnectionState.waiting)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: CircularProgressIndicator(),
                          )
                        else if (list.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text('Chưa có cuộc trò chuyện nào'),
                          )
                        else
                          Flexible(
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: list.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final c = list[i];
                                final id = c['id']?.toString() ?? '';
                                final rawTitle = c['title']?.toString() ?? '';
                                final title = rawTitle.trim().isEmpty
                                    ? 'Cuộc trò chuyện'
                                    : rawTitle;
                                final isActive =
                                    id.isNotEmpty && id == _conversationId;

                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight: isActive
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                    ),
                                  ),
                                  leading: Icon(
                                    Icons.forum_outlined,
                                    color: isActive
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Đổi tên',
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () async {
                                          if (id.isEmpty) return;
                                          final controller =
                                              TextEditingController(text: title);
                                          final next = await showDialog<String>(
                                            context: ctx,
                                            builder: (dialogCtx) {
                                              return AlertDialog(
                                                title: const Text(
                                                  'Đổi tên cuộc trò chuyện',
                                                ),
                                                content: TextField(
                                                  controller: controller,
                                                  autofocus: true,
                                                  decoration: const InputDecoration(
                                                    hintText: 'Nhập tên mới...',
                                                  ),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.of(dialogCtx)
                                                            .pop(),
                                                    child: const Text('Hủy'),
                                                  ),
                                                  FilledButton(
                                                    onPressed: () =>
                                                        Navigator.of(dialogCtx).pop(
                                                      controller.text.trim(),
                                                    ),
                                                    child: const Text('Lưu'),
                                                  ),
                                                ],
                                              );
                                            },
                                          );
                                          final newTitle = (next ?? '').trim();
                                          if (newTitle.isEmpty) return;
                                          await chatbotService.renameConversation(
                                            userId: userId,
                                            conversationId: id,
                                            title: newTitle,
                                          );
                                          await reload();
                                        },
                                      ),
                                      IconButton(
                                        tooltip: 'Xóa',
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                        ),
                                        onPressed: () async {
                                          if (id.isEmpty) return;
                                          await chatbotService.deleteConversation(
                                            userId: userId,
                                            conversationId: id,
                                          );
                                          if (id == _conversationId) {
                                            setState(() => _conversationId = null);
                                          }
                                          await reload();
                                        },
                                      ),
                                    ],
                                  ),
                                  onTap: () async {
                                    if (id.isEmpty) return;
                                    Navigator.of(ctx).pop();
                                    await _loadConversationById(id);
                                  },
                                );
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteConversation() async {
    final userId = authService.userId;
    final cid = _conversationId;
    if (userId == null || cid == null || cid.isEmpty) return;
    await chatbotService.deleteConversation(userId: userId, conversationId: cid);
    setState(() {
      _conversationId = null;
    });
    await _loadOrCreateConversation();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  bool _looksLikeObjectId(String id) {
    final s = id.trim();
    final okLen = s.length == 24;
    if (!okLen) return false;
    return RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(s);
  }

  Future<void> _onMessageTap(ChatMessage msg) async {
    if (msg.isLoading) return;
    final userId = authService.userId;
    final cid = _conversationId;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final canRecall =
            msg.isUser && userId != null && cid != null && _looksLikeObjectId(msg.id);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('Sao chép'),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: msg.content));
                    if (mounted) {
                      Navigator.of(ctx).pop();
                    }
                  },
                ),
                ListTile(
                  enabled: canRecall,
                  leading: const Icon(Icons.undo_rounded),
                  title: const Text('Thu hồi'),
                  subtitle: canRecall
                      ? const Text('Xóa tin nhắn khỏi lịch sử chatbot')
                      : const Text('Chỉ thu hồi được tin nhắn đã lưu lịch sử'),
                  onTap: !canRecall
                      ? null
                      : () async {
                          await chatbotService.deleteChatbotMessage(
                            userId: userId,
                            conversationId: cid,
                            messageId: msg.id,
                          );
                          if (!mounted) return;
                          setState(() => _messages.removeWhere((m) => m.id == msg.id));
                          Navigator.of(ctx).pop();
                        },
                ),
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
      body: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildMessageList()),
          _buildQuickReplies(),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: AppColors.aiGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trợ lý AI',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                  ),
                ),
                Text(
                  'Powered by QuickChat AI',
                  style: TextStyle(
                    color: AppColors.aiGradient2,
                    fontSize: 11,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _showConversationsSheet,
            icon: const Icon(Icons.forum_outlined,
                color: AppColors.textSecondary, size: 22),
            tooltip: 'Danh sách cuộc trò chuyện',
          ),
          IconButton(
            onPressed: _newConversation,
            icon: const Icon(Icons.add_comment_rounded,
                color: AppColors.textSecondary, size: 22),
            tooltip: 'Cuộc trò chuyện mới',
          ),
          IconButton(
            onPressed: _deleteConversation,
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppColors.textSecondary, size: 22),
            tooltip: 'Xóa cuộc trò chuyện',
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return _MessageBubble(
          message: msg,
          typingController: _typingController,
          onTapMessage: () => _onMessageTap(msg),
        );
      },
    );
  }

  Widget _buildQuickReplies() {
    if (_messages.length > 2 || _isSending) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _quickReplies
              .map((q) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () => _sendMessage(q),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.primary.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          q,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        8 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSelectedFilesChips(),
          Row(
            children: [
              IconButton(
                onPressed: _isSending ? null : _pickFile,
                icon: Icon(
                  _selectedFiles.isEmpty
                      ? Icons.attach_file_rounded
                      : Icons.attach_file,
                  color: _selectedFiles.isEmpty
                      ? AppColors.textSecondary
                      : AppColors.primary,
                ),
                tooltip: _selectedFiles.isEmpty
                    ? 'Đính kèm file'
                    : 'Đã chọn ${_selectedFiles.length} file',
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.bgInput,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    style: const TextStyle(
                      fontSize: 14,
                      fontFamily: 'Inter',
                      color: AppColors.textPrimary,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Hỏi trợ lý AI...',
                      hintStyle: TextStyle(
                        color: AppColors.textHint,
                        fontSize: 14,
                        fontFamily: 'Inter',
                      ),
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: _sendMessage,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Nút gửi
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: _isSending ? null : AppColors.aiGradient,
                  color: _isSending ? AppColors.divider : null,
                  shape: BoxShape.circle,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap:
                        _isSending ? null : () => _sendMessage(_controller.text),
                    child: Center(
                      child: _isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.textSecondary,
                              ),
                            )
                          : const Icon(Icons.send_rounded,
                              color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MessageBubble — Widget hiển thị 1 tin nhắn
// ─────────────────────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final AnimationController typingController;
  final VoidCallback? onTapMessage;

  const _MessageBubble({
    required this.message,
    required this.typingController,
    this.onTapMessage,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            _buildAiAvatar(),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                _buildBubble(context),
                if (message.toolsUsed.isNotEmpty) _buildToolsBadge(),
                const SizedBox(height: 2),
                Text(
                  _formatTime(message.createdAt),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textHint,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildAiAvatar() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        gradient: AppColors.aiGradient,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
    );
  }

  Widget _buildBubble(BuildContext context) {
    if (message.isLoading) {
      return _TypingIndicator(controller: typingController);
    }

    final isUser = message.isUser;
    return GestureDetector(
      onTap: onTapMessage,
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: message.content));
      },
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? AppColors.bubbleMe : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.content.isNotEmpty)
              Text(
                message.content,
                style: TextStyle(
                  color:
                      isUser ? AppColors.bubbleMeText : AppColors.bubbleOtherText,
                  fontSize: 14,
                  fontFamily: 'Inter',
                  height: 1.45,
                ),
              ),
            if (message.attachments.isNotEmpty) ...[
              if (message.content.isNotEmpty) const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: message.attachments
                    .map(
                      (att) => InkWell(
                        onTap: () async {
                          try {
                            final dl = await chatbotService.getPresignedDownloadUrl(
                              fileUrl: att.url,
                              fileName: att.name,
                            );
                            final uri = Uri.parse(dl);
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Không tải được file: $e')),
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isUser
                                ? Colors.white.withOpacity(0.18)
                                : AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isUser
                                  ? Colors.white.withOpacity(0.25)
                                  : AppColors.primary.withOpacity(0.25),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.download_rounded,
                                size: 14,
                                color: isUser
                                    ? Colors.white.withOpacity(0.9)
                                    : AppColors.primary,
                              ),
                              const SizedBox(width: 6),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 160),
                                child: Text(
                                  att.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'Inter',
                                    color: isUser
                                        ? Colors.white.withOpacity(0.95)
                                        : AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildToolsBadge() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        children: message.toolsUsed
            .map((t) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '🔧 $t',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.primaryDark,
                      fontFamily: 'Inter',
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TypingIndicator — 3 chấm nhảy khi AI đang xử lý
// ─────────────────────────────────────────────────────────────────────────────

class _TypingIndicator extends StatelessWidget {
  final AnimationController controller;

  const _TypingIndicator({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomRight: Radius.circular(18),
          bottomLeft: Radius.circular(4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: controller,
            builder: (_, __) {
              final offset = math.sin(
                (controller.value * 2 * math.pi) - (i * math.pi / 2.5),
              );
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                child: Transform.translate(
                  offset: Offset(0, -4 * offset.clamp(0.0, 1.0)),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.aiGradient2.withOpacity(0.6 + offset * 0.4),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
