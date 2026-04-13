import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/contacts_api_service.dart';
import 'birthday_calendar_screen.dart';
import 'birthday_settings_screen.dart';

class BirthdayScreen extends StatefulWidget {
  const BirthdayScreen({super.key});

  @override
  State<BirthdayScreen> createState() => _BirthdayScreenState();
}

class _BirthdayScreenState extends State<BirthdayScreen> {
  List<ApiUserModel>? _users;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = authService.userId ?? '';
    final result =
        await ContactsApiService.instance.fetchBirthdayContacts(userId);
    if (!mounted) return;
    setState(() {
      _users = result.data ?? [];
      _error = result.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Sinh nhật',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BirthdayCalendarScreen(
                    users: _users ?? [],
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const BirthdaySettingsScreen()),
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_users == null && _error == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null && (_users == null || _users!.isEmpty)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Thử lại'),
              style:
                  TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ],
        ),
      );
    }

    final groups = _groupByBirthday(_users ?? []);

    if (groups.past.isEmpty && groups.upcoming.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cake_rounded,
                  size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            const Text(
              'Không có thông tin sinh nhật nào',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (groups.past.isNotEmpty) ...[
            _SectionHeader(title: 'Sinh nhật đã qua'),
            ...groups.past.map((u) => _BirthdayTile(user: u)),
          ],
          if (groups.upcoming.isNotEmpty) ...[
            _SectionHeader(title: 'Sinh nhật sắp tới'),
            ...groups.upcoming.map((u) => _BirthdayTile(user: u)),
          ],
        ],
      ),
    );
  }

  _BirthdayGroups _groupByBirthday(List<ApiUserModel> users) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final past = <ApiUserModel>[];
    final upcoming = <ApiUserModel>[];

    for (final u in users) {
      final dob = u.dob!;
      // Sinh nhật năm nay
      final thisYear = DateTime(now.year, dob.month, dob.day);

      if (thisYear.isBefore(today)) {
        past.add(u);
      } else {
        upcoming.add(u);
      }
    }

    // Sắp xếp: past — gần nhất trước, upcoming — sắp đến trước
    past.sort((a, b) {
      final da = DateTime(now.year, a.dob!.month, a.dob!.day);
      final db = DateTime(now.year, b.dob!.month, b.dob!.day);
      return db.compareTo(da); // giảm dần (gần nhất lên đầu)
    });

    upcoming.sort((a, b) {
      final da = DateTime(now.year, a.dob!.month, a.dob!.day);
      final db = DateTime(now.year, b.dob!.month, b.dob!.day);
      return da.compareTo(db); // tăng dần (sắp nhất lên đầu)
    });

    return _BirthdayGroups(past: past, upcoming: upcoming);
  }
}

class _BirthdayGroups {
  final List<ApiUserModel> past;
  final List<ApiUserModel> upcoming;
  const _BirthdayGroups({required this.past, required this.upcoming});
}

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

// ── Birthday Tile ─────────────────────────────────────────────────────────────

class _BirthdayTile extends StatelessWidget {
  final ApiUserModel user;
  const _BirthdayTile({required this.user});

  @override
  Widget build(BuildContext context) {
    final dob = user.dob!;
    final now = DateTime.now();
    final birthdayThisYear = DateTime(now.year, dob.month, dob.day);
    final weekday = _weekdayVi(birthdayThisYear.weekday);
    final dateStr = '$weekday, ${dob.day} tháng ${dob.month}';

    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Avatar with cake badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primaryLight,
                foregroundImage: user.avatar.isNotEmpty
                    ? NetworkImage(user.avatar)
                    : null,
                child: Text(
                  _initials(user.fullName),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4D6D),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.cake_rounded,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          // Name + date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.fullName,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Chat button
          GestureDetector(
            onTap: () {},
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 18,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _weekdayVi(int weekday) {
    const map = {
      1: 'Thứ Hai',
      2: 'Thứ Ba',
      3: 'Thứ Tư',
      4: 'Thứ Năm',
      5: 'Thứ Sáu',
      6: 'Thứ Bảy',
      7: 'Chủ Nhật',
    };
    return map[weekday] ?? '';
  }

  String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
