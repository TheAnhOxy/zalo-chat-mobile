import 'package:flutter/material.dart';
import '../../services/notification_service.dart';
import '../../services/story_service.dart';
import '../../services/api_service.dart';
import '../../data/models/story_model.dart';
import 'package:intl/intl.dart';
import '../../navigation/app_router.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final _service = notificationService;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChange);
    // Tải dữ liệu thực tế từ database khi mở màn hình
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _service.fetchNotifications();
    });
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChange);
    super.dispose();
  }

  void _onServiceChange() {
    if (mounted) setState(() {});
  }

  /// Tải stories của người gửi và mở StoryViewerScreen
  Future<void> _openStory(RealNotification notif) async {
    final senderId = notif.senderId;
    if (senderId == null || senderId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy thông tin người dùng')),
      );
      return;
    }

    // Đánh dấu đã đọc
    await _service.markAsRead(notif.id);

    // Hiển thị loading
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.orange)),
    );

    try {
      final List<ApiStoryModel> stories = await storyService.getStoriesByUserId(senderId);
      if (!mounted) return;
      Navigator.pop(context); // Đóng loading dialog

      if (stories.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${notif.senderName ?? "Người dùng"} không còn story nào')),
        );
        return;
      }

      Navigator.pushNamed(
        context,
        AppRouter.storyViewer,
        arguments: {
          'stories': stories,
          'initialIndex': 0,
        },
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Đóng loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể tải story, vui lòng thử lại')),
      );
    }
  }

  /// Fetch ConversationModel by ID rồi navigate vào ChatDetailScreen
  Future<void> _navigateToChat(String conversationId) async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final conv = await apiService.getConversationById(conversationId);
      if (!mounted) return;
      Navigator.pop(context); // đóng loading

      if (conv == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không tìm thấy cuộc trò chuyện')),
        );
        return;
      }

      Navigator.pushNamed(
        context,
        AppRouter.chatDetail,
        arguments: {
          'conversationId': conv.id,
          'otherUser': null,
          'conversation': conv,
        },
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // đóng loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể mở cuộc trò chuyện')),
      );
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} phút trước';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} giờ trước';
    } else {
      return DateFormat('dd/MM HH:mm').format(dt);
    }
  }

  Widget _getIconForType(String type) {
    IconData icon;
    Color color;
    switch (type) {
      case 'FRIEND_REQUEST':
        icon = Icons.person_add_rounded;
        color = Colors.blue;
        break;
      case 'FRIEND_ACCEPTED':
        icon = Icons.people_alt_rounded;
        color = Colors.green;
        break;
      case 'MESSAGE_REACTION':
        icon = Icons.favorite_rounded;
        color = Colors.pinkAccent;
        break;
      case 'CALL':
      case 'MISSED_CALL':
        icon = Icons.phone_missed_rounded;
        color = Colors.red;
        break;
      case 'MESSAGE':
        icon = Icons.chat_bubble_rounded;
        color = Colors.purple;
        break;
      case 'STORY':
        icon = Icons.amp_stories_rounded;
        color = Colors.orange;
        break;
      default:
        icon = Icons.notifications_rounded;
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Icon(icon, size: 12, color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _service.notifications;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87, size: 20),
          onPressed: () {
            // Chuyển hướng an toàn về trang chủ (màn hình chat chính) tránh lỗi route not found
            Navigator.pushNamedAndRemoveUntil(context, '/main', (route) => false);
          },
        ),
        title: const Text(
          'Thông báo',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.black54),
            onPressed: () => _service.fetchNotifications(),
          ),
          if (list.any((n) => !n.isRead))
            TextButton.icon(
              onPressed: () {
                _service.markAllAsRead();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã đánh dấu đọc tất cả thông báo')),
                );
              },
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: const Text('Đọc tất cả'),
              style: TextButton.styleFrom(foregroundColor: Colors.blue),
            ),
        ],
      ),
      body: _service.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.blue),
            )
          : list.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none_rounded, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('Bạn không có thông báo nào', style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: Colors.blue,
                  onRefresh: () => _service.fetchNotifications(),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final notif = list[index];
                      return Dismissible(
                        key: Key(notif.id),
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete_forever_rounded, color: Colors.white),
                        ),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) {
                          _service.removeNotification(notif.id);
                        },
                        child: InkWell(
                          onTap: () {
                            _service.markAsRead(notif.id);
                            if (notif.type == 'FRIEND_REQUEST') {
                              Navigator.pushNamed(context, AppRouter.friendRequests);
                            } else if (notif.type == 'MESSAGE_REACTION') {
                              if (notif.conversationId != null) {
                                _navigateToChat(notif.conversationId!);
                              }
                            } else if (notif.type == 'FRIEND_ACCEPTED') {
                              // Chuyển về màn hình chính hoặc danh bạ
                              Navigator.pushNamedAndRemoveUntil(context, AppRouter.main, (route) => false);
                            } else if (notif.type == 'CALL' || notif.type == 'MISSED_CALL') {
                              if (notif.conversationId != null) {
                                _navigateToChat(notif.conversationId!);
                              }
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: notif.isRead ? Colors.white : const Color(0xFFF4FAFF),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: notif.isRead ? Colors.grey.withOpacity(0.1) : Colors.blue.withOpacity(0.2),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.02),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Avatar stack with type icon badge
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    CircleAvatar(
                                      radius: 26,
                                      backgroundImage: NetworkImage(notif.senderAvatar ?? 'https://i.pravatar.cc/150?img=3'),
                                      backgroundColor: Colors.grey[200],
                                    ),
                                    Positioned(
                                      right: -4,
                                      bottom: -4,
                                      child: _getIconForType(notif.type),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                // Content details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      RichText(
                                        text: TextSpan(
                                          style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.4),
                                          children: [
                                            TextSpan(
                                              text: notif.senderName ?? 'Người dùng',
                                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                                            ),
                                            const TextSpan(text: ' '),
                                            TextSpan(text: notif.content),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _formatTime(notif.createdAt),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: notif.isRead ? Colors.grey[600] : Colors.blue[700],
                                          fontWeight: notif.isRead ? FontWeight.normal : FontWeight.w600,
                                        ),
                                      ),
                                      // Custom interactive buttons inside notification card
                                      if (notif.type == 'FRIEND_REQUEST') ...[
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: ElevatedButton(
                                                onPressed: () async {
                                                  await _service.markAsRead(notif.id);
                                                  Navigator.pushNamed(context, AppRouter.friendRequests);
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.blue,
                                                  foregroundColor: Colors.white,
                                                  elevation: 0,
                                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                ),
                                                child: const Text('Xem lời mời', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: OutlinedButton(
                                                onPressed: () {
                                                  _service.removeNotification(notif.id);
                                                },
                                                style: OutlinedButton.styleFrom(
                                                  side: BorderSide(color: Colors.grey.shade300),
                                                  foregroundColor: Colors.black87,
                                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                ),
                                                child: const Text('Bỏ qua', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ] else if (notif.type == 'CALL') ...[
                                        const SizedBox(height: 12),
                                        ElevatedButton.icon(
                                          onPressed: () {
                                            _service.markAsRead(notif.id);
                                            if (notif.conversationId != null) {
                                              _navigateToChat(notif.conversationId!);
                                            }
                                          },
                                          icon: const Icon(Icons.phone_rounded, size: 16),
                                          label: const Text('Gọi lại', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                        ),
                                      ] else if (notif.type == 'STORY') ...[
                                        const SizedBox(height: 12),
                                        ElevatedButton.icon(
                                          onPressed: () => _openStory(notif),
                                          icon: const Icon(Icons.play_circle_fill_rounded, size: 16),
                                          label: const Text('Xem tin', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.orange,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                        ),
                                      ]
                                    ],
                                  ),
                                ),
                                if (!notif.isRead)
                                  Container(
                                    margin: const EdgeInsets.only(top: 6, left: 12),
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(
                                      color: Colors.blue,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}