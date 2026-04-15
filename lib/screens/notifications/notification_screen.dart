import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/models.dart';
import '../../services/notification_api_service.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<AppNotification>? _items;
  bool _markingAllRead = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await NotificationApiService.instance.getMyNotifications();
    if (!mounted) return;
    setState(() => _items = list);
  }

  Future<void> _markAllRead() async {
    if (_markingAllRead) return;
    setState(() => _markingAllRead = true);
    final ok = await NotificationApiService.instance.markAllRead();
    if (!mounted) return;
    setState(() {
      _markingAllRead = false;
      if (ok) {
        _items = (_items ?? [])
            .map(
              (n) => AppNotification(
                id: n.id,
                receiverId: n.receiverId,
                type: n.type,
                content: n.content,
                isRead: true,
                createdAt: n.createdAt,
              ),
            )
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final unreadCount = items?.where((x) => !x.isRead).length ?? 0;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          unreadCount > 0 ? 'Thông báo ($unreadCount)' : 'Thông báo',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: (items == null || items.isEmpty || _markingAllRead)
                ? null
                : _markAllRead,
            child: Text(
              _markingAllRead ? 'Đang xử lý...' : 'Đọc hết',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: items == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : items.isEmpty
              ? const Center(
                  child: Text(
                    'Chưa có thông báo nào',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primary,
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: AppColors.divider),
                    itemBuilder: (_, i) {
                      final n = items[i];
                      return ListTile(
                        tileColor: AppColors.bgCard,
                        leading: CircleAvatar(
                          backgroundColor: n.isRead
                              ? const Color(0xFFE5E7EB)
                              : AppColors.primaryLight,
                          child: Icon(
                            _iconForType(n.type),
                            color: n.isRead
                                ? AppColors.textSecondary
                                : AppColors.primary,
                          ),
                        ),
                        title: Text(
                          n.content.isNotEmpty
                              ? n.content
                              : 'Bạn có một thông báo mới',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          _relativeTime(n.createdAt),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            color: AppColors.textSecondary,
                          ),
                        ),
                        trailing: n.isRead
                            ? null
                            : Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                      );
                    },
                  ),
                ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'FRIEND_REQUEST':
        return Icons.person_add_alt_1_rounded;
      case 'CALL':
        return Icons.call_rounded;
      case 'MESSAGE':
      default:
        return Icons.message_rounded;
    }
  }

  String _relativeTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Vừa xong';
    if (d.inMinutes < 60) return '${d.inMinutes} phút trước';
    if (d.inHours < 24) return '${d.inHours} giờ trước';
    return '${d.inDays} ngày trước';
  }
}