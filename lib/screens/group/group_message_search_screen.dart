import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/date_utils.dart' as du;
import '../../data/models/models.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/common/common_widgets.dart';

/// Màn tìm tin nhắn trong nhóm (UI giống chat + header tìm + thanh lên/xuống kết quả).
class GroupMessageSearchScreen extends StatefulWidget {
  final String conversationId;
  final String userId;

  const GroupMessageSearchScreen({
    super.key,
    required this.conversationId,
    required this.userId,
  });

  @override
  State<GroupMessageSearchScreen> createState() =>
      _GroupMessageSearchScreenState();
}

class _GroupMessageSearchScreenState extends State<GroupMessageSearchScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = {};

  List<MessageModel> _all = [];
  Map<String, MessageModel> _byId = {};
  Map<String, UserModel> _users = {};
  bool _loading = true;
  int _matchIndex = 0;

  String get _q => _searchCtrl.text.trim();

  List<MessageModel> get _ordered {
    final list = List<MessageModel>.from(_all);
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  List<MessageModel> get _filtered {
    final q = _q.toLowerCase();
    if (q.isEmpty) return _ordered;
    return _ordered.where((m) {
      if (m.isRecalled) return false;
      final blob =
          '${m.content} ${m.metadata?.fileName ?? ''}'.toLowerCase();
      return blob.contains(q);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _load();
  }

  void _onSearchChanged() {
    final text = _searchCtrl.text.trim();
    setState(() => _matchIndex = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final f = _filtered;
      if (text.isNotEmpty && f.isNotEmpty) {
        final ctx = _keyFor(f.first.id).currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            alignment: 0.12,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await apiService.getMessages(
      widget.conversationId,
      widget.userId,
    );
    if (!mounted) return;

    final byId = <String, MessageModel>{};
    for (final m in list) {
      byId[m.id] = m;
    }
    final senderIds = list.map((m) => m.senderId).toSet().toList();
    final users = <String, UserModel>{};
    await Future.wait(senderIds.map((id) async {
      final u = await apiService.getUserById(id);
      if (u != null) users[id] = u;
    }));

    if (!mounted) return;
    setState(() {
      _all = list;
      _byId = byId;
      _users = users;
      _loading = false;
    });
  }

  GlobalKey _keyFor(String messageId) =>
      _itemKeys.putIfAbsent(messageId, GlobalKey.new);

  void _jumpMatch(int delta) {
    final f = _filtered;
    final q = _q;
    if (f.isEmpty || q.isEmpty) return;
    var i = _matchIndex + delta;
    if (i < 0) i = f.length - 1;
    if (i >= f.length) i = 0;
    setState(() => _matchIndex = i);
    final id = f[i].id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keyFor(id).currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: 0.15,
        );
      }
    });
  }

  Color _nameColor(String userId) {
    const colors = [
      Color(0xFFE91E63),
      Color(0xFF2196F3),
      Color(0xFF4CAF50),
      Color(0xFFFF9800),
      Color(0xFF9C27B0),
      Color(0xFF00BCD4),
    ];
    return colors[userId.hashCode.abs() % colors.length];
  }

  String _senderName(String senderId) {
    final u = _users[senderId];
    if (u != null && u.fullName.isNotEmpty) return u.fullName;
    return 'Thành viên';
  }

  MessageModel? _replyTo(MessageModel m) {
    final id = m.replyToId;
    if (id == null || id.isEmpty) return null;
    return _byId[id];
  }

  List<InlineSpan> _highlightSpans(String text, String query) {
    if (query.isEmpty) {
      return [TextSpan(text: text)];
    }
    final pattern = RegExp(RegExp.escape(query), caseSensitive: false);
    final spans = <InlineSpan>[];
    var start = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > start) {
        spans.add(TextSpan(text: text.substring(start, m.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(m.start, m.end),
          style: const TextStyle(
            backgroundColor: Color(0xFFFFF59D),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      start = m.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return spans.isEmpty ? [TextSpan(text: text)] : spans;
  }

  bool _sameDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  String _dateLabel(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    if (_sameDay(local, now)) {
      return '${du.DateUtils.formatMessageTime(local)} · Hôm nay';
    }
    return '${du.DateUtils.formatMessageTime(local)} · '
        '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  Widget _buildDateChip(DateTime dt) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFE0E0E0),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            _dateLabel(dt),
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              color: Color(0xFF616161),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(MessageModel m, bool isMe, String query) {
    final name = _senderName(m.senderId);
    final time = du.DateUtils.formatMessageTime(m.createdAt);
    final reply = _replyTo(m);

    Widget content;
    if (m.isRecalled) {
      content = const Text(
        'Tin nhắn đã thu hồi',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontStyle: FontStyle.italic,
          color: AppColors.textHint,
        ),
      );
    } else if (m.type != 'TEXT') {
      content = Text(
        '[${m.type}] ${m.metadata?.fileName ?? m.content}',
        style: const TextStyle(fontFamily: 'Inter', fontSize: 14),
      );
    } else {
      content = RichText(
        text: TextSpan(
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            color: Color(0xFF1A1A1A),
            height: 1.35,
          ),
          children: _highlightSpans(m.content, query),
        ),
      );
    }

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.78,
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFFB8E6F0) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: isMe
            ? null
            : Border.all(color: const Color(0xFFB3E5FC), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reply != null && !reply.isRecalled) ...[
            Container(
              padding: const EdgeInsets.only(left: 8, bottom: 6),
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Color(0xFF2196F3), width: 3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _senderName(reply.senderId),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2196F3),
                    ),
                  ),
                  Text(
                    reply.type == 'TEXT'
                        ? (reply.content.length > 80
                            ? '${reply.content.substring(0, 80)}…'
                            : reply.content)
                        : '[${reply.type}]',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
          content,
          const SizedBox(height: 4),
          Text(
            time,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );

    if (isMe) {
      return Align(
        alignment: Alignment.centerRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            bubble,
            if (m.reactions.isNotEmpty) _reactionRow(m),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AvatarWidget(
          url: _users[m.senderId]?.avatar,
          name: name,
          size: 36,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _nameColor(m.senderId),
                ),
              ),
              const SizedBox(height: 2),
              bubble,
              if (m.reactions.isNotEmpty) _reactionRow(m),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reactionRow(MessageModel m) {
    if (m.reactions.isEmpty) return const SizedBox.shrink();
    final emojis = m.reactions.map((r) => r.emoji).join(' ');
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 3,
            ),
          ],
        ),
        child: Text(emojis, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final q = _q;
    final canJump = q.isNotEmpty && filtered.length > 1;

    return Scaffold(
      backgroundColor: const Color(0xFFE8F2E8),
      body: Column(
        children: [
          Material(
            color: AppColors.primary,
            elevation: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          color: Colors.white,
                          fontSize: 15,
                        ),
                        cursorColor: Colors.white,
                        decoration: InputDecoration(
                          hintText: 'Tìm tin nhắn văn bản',
                          hintStyle: TextStyle(
                            fontFamily: 'Inter',
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.15),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : filtered.isEmpty
                    ? Center(
                        child: Text(
                          q.isEmpty
                              ? 'Chưa có tin nhắn'
                              : 'Không có kết quả',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.textHint,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        itemCount: _searchItemCount(filtered),
                        itemBuilder: (context, index) {
                          return _searchItemAt(filtered, index, q);
                        },
                      ),
          ),
          Material(
            color: AppColors.bgCard,
            elevation: 6,
            child: SafeArea(
              top: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Tìm theo thành viên (sắp có)',
                      icon: Icon(
                        Icons.person_search_outlined,
                        color: q.isEmpty
                            ? AppColors.textHint
                            : AppColors.textSecondary,
                      ),
                      onPressed: q.isEmpty
                          ? null
                          : () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Lọc theo thành viên: dùng từ khóa tên trong tin nhắn',
                                    style: TextStyle(fontFamily: 'Inter'),
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        Icons.keyboard_arrow_up_rounded,
                        color: canJump
                            ? AppColors.primary
                            : AppColors.textHint,
                      ),
                      onPressed: canJump ? () => _jumpMatch(-1) : null,
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: canJump
                            ? AppColors.primary
                            : AppColors.textHint,
                      ),
                      onPressed: canJump ? () => _jumpMatch(1) : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _searchItemCount(List<MessageModel> f) {
    if (f.isEmpty) return 0;
    var c = 0;
    DateTime? lastDay;
    for (final m in f) {
      final d = m.createdAt.toLocal();
      final day = DateTime(d.year, d.month, d.day);
      if (lastDay == null ||
          day.year != lastDay.year ||
          day.month != lastDay.month ||
          day.day != lastDay.day) {
        c++;
        lastDay = day;
      }
      c++;
    }
    return c;
  }

  Widget _searchItemAt(List<MessageModel> f, int index, String query) {
    var i = 0;
    DateTime? lastDay;
    final myId = authService.userId ?? '';
    for (final m in f) {
      final d = m.createdAt.toLocal();
      final day = DateTime(d.year, d.month, d.day);
      if (lastDay == null ||
          day.year != lastDay.year ||
          day.month != lastDay.month ||
          day.day != lastDay.day) {
        if (i == index) return _buildDateChip(d);
        i++;
        lastDay = day;
      }
      if (i == index) {
        final isMe = m.senderId == myId;
        return KeyedSubtree(
          key: _keyFor(m.id),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildBubble(m, isMe, query),
          ),
        );
      }
      i++;
    }
    return const SizedBox.shrink();
  }
}
