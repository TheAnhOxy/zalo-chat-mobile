import 'package:intl/intl.dart';

class DateUtils {
  DateUtils._();

  static String formatChatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inHours < 1) return '${diff.inMinutes} phút';
    if (dt.day == now.day) return DateFormat('HH:mm').format(dt);

    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.day == yesterday.day) return 'Hôm qua';

    final weekdays = ['', 'Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'CN'];
    if (diff.inDays < 7) return weekdays[dt.weekday];

    return DateFormat('dd/MM').format(dt);
  }

  static String formatMessageTime(DateTime dt) {
    return DateFormat('HH:mm').format(dt);
  }

  static String formatDateSeparator(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (dt.day == now.day) return 'HÔM NAY';
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.day == yesterday.day) return 'HÔM QUA';
    if (diff.inDays < 7) {
      const days = ['', 'Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'Chủ nhật'];
      return days[dt.weekday].toUpperCase();
    }
    return DateFormat('dd/MM/yyyy').format(dt);
  }

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}