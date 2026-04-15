import 'package:intl/intl.dart';

class DateUtils {
  DateUtils._();

  static String formatChatTime(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);

    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inHours < 1) return '${diff.inMinutes} phút';
    if (local.day == now.day) return DateFormat('HH:mm').format(local);

    final yesterday = now.subtract(const Duration(days: 1));
    if (local.day == yesterday.day) return 'Hôm qua';

    final weekdays = ['', 'Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'CN'];
    if (diff.inDays < 7) return weekdays[dt.weekday];

    return DateFormat('dd/MM').format(local);
  }

  static String formatMessageTime(DateTime dt) {
    return DateFormat('HH:mm').format(dt.toLocal());
  }

  static String formatDateSeparator(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (local.day == now.day) return 'HÔM NAY';
    final yesterday = now.subtract(const Duration(days: 1));
    if (local.day == yesterday.day) return 'HÔM QUA';
    if (diff.inDays < 7) {
      const days = ['', 'Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'Chủ nhật'];
      return days[dt.weekday].toUpperCase();
    }
    return DateFormat('dd/MM/yyyy').format(local);
  }

  static bool isSameDay(DateTime a, DateTime b) =>
      a.toLocal().year == b.toLocal().year &&
      a.toLocal().month == b.toLocal().month &&
      a.toLocal().day == b.toLocal().day;
}