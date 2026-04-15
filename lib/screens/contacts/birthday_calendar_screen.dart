import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/contacts_api_service.dart';
import 'birthday_settings_screen.dart';

class BirthdayCalendarScreen extends StatefulWidget {
  final List<ApiUserModel> users;

  const BirthdayCalendarScreen({super.key, required this.users});

  @override
  State<BirthdayCalendarScreen> createState() =>
      _BirthdayCalendarScreenState();
}

class _BirthdayCalendarScreenState extends State<BirthdayCalendarScreen> {
  late DateTime _focusedMonth;
  late DateTime _selectedDay;

  // Map từ "month-day" → danh sách user
  late Map<String, List<ApiUserModel>> _birthdayMap;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
    _buildBirthdayMap();
  }

  void _buildBirthdayMap() {
    _birthdayMap = {};
    for (final u in widget.users) {
      if (u.dob == null) continue;
      final key = '${u.dob!.month}-${u.dob!.day}';
      (_birthdayMap[key] ??= []).add(u);
    }
  }

  List<ApiUserModel> _birthdaysOn(DateTime day) =>
      _birthdayMap['${day.month}-${day.day}'] ?? [];

  void _prevMonth() => setState(() {
        _focusedMonth =
            DateTime(_focusedMonth.year, _focusedMonth.month - 1);
      });

  void _nextMonth() => setState(() {
        _focusedMonth =
            DateTime(_focusedMonth.year, _focusedMonth.month + 1);
      });

  @override
  Widget build(BuildContext context) {
    final selectedBirthdays = _birthdaysOn(_selectedDay);

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
        title: Text(
          'Tháng ${_focusedMonth.month}, ${_focusedMonth.year}',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _prevMonth,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _nextMonth,
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
      body: Column(
        children: [
          // ── Calendar ────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: _CalendarGrid(
              focusedMonth: _focusedMonth,
              selectedDay: _selectedDay,
              birthdayMap: _birthdayMap,
              onDaySelected: (day) =>
                  setState(() => _selectedDay = day),
            ),
          ),

          // ── Selected day label ───────────────────────────────────
          _SelectedDayHeader(day: _selectedDay),

          // ── Birthdays list ───────────────────────────────────────
          Expanded(
            child: selectedBirthdays.isEmpty
                ? const Center(
                    child: Text(
                      'Không có sinh nhật vào ngày này',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      ...selectedBirthdays.expand((u) => [
                            _BirthdayDayHeader(day: _selectedDay),
                            _BirthdayTile(user: u),
                          ]),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Calendar Grid ─────────────────────────────────────────────────────────────

class _CalendarGrid extends StatelessWidget {
  final DateTime focusedMonth;
  final DateTime selectedDay;
  final Map<String, List<ApiUserModel>> birthdayMap;
  final ValueChanged<DateTime> onDaySelected;

  const _CalendarGrid({
    required this.focusedMonth,
    required this.selectedDay,
    required this.birthdayMap,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    const weekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

    // Ngày đầu tháng (weekday: 1=Mon ... 7=Sun)
    final firstDay = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final daysInMonth =
        DateTime(focusedMonth.year, focusedMonth.month + 1, 0).day;
    // Offset: Mon=0, Tue=1, ... Sun=6
    final startOffset = (firstDay.weekday - 1) % 7;

    final today = DateTime.now();

    return Column(
      children: [
        // Weekday headers
        Row(
          children: weekdays
              .map((d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: d == 'CN'
                              ? AppColors.error
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 6),

        // Days grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 0.85,
          ),
          itemCount: startOffset + daysInMonth,
          itemBuilder: (_, i) {
            if (i < startOffset) return const SizedBox();
            final day = i - startOffset + 1;
            final date =
                DateTime(focusedMonth.year, focusedMonth.month, day);
            final isToday = date.year == today.year &&
                date.month == today.month &&
                date.day == today.day;
            final isSelected = date.year == selectedDay.year &&
                date.month == selectedDay.month &&
                date.day == selectedDay.day;
            final isSunday = date.weekday == 7;
            final hasBirthday =
                birthdayMap.containsKey('${date.month}-${date.day}');

            return GestureDetector(
              onTap: () => onDaySelected(date),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? AppColors.primary
                          : isToday
                              ? AppColors.primaryLight
                              : Colors.transparent,
                      border: isToday && !isSelected
                          ? Border.all(
                              color: AppColors.primary, width: 1.5)
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '$day',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : isSunday
                                  ? AppColors.error
                                  : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  if (hasBirthday)
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.cake_rounded,
                        size: 10,
                        color: Color(0xFFFF4D6D),
                      ),
                    )
                  else
                    const SizedBox(height: 12),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

// ── Selected Day Header ───────────────────────────────────────────────────────

class _SelectedDayHeader extends StatelessWidget {
  final DateTime day;
  const _SelectedDayHeader({required this.day});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;

    final weekday = _weekdayVi(day.weekday);
    final label = isToday
        ? 'Hôm nay • $weekday, ${day.day} tháng ${day.month}'
        : '$weekday, ${day.day} tháng ${day.month}';

    return Container(
      width: double.infinity,
      color: AppColors.primaryLight,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }

  String _weekdayVi(int w) {
    const m = {
      1: 'Thứ Hai',
      2: 'Thứ Ba',
      3: 'Thứ Tư',
      4: 'Thứ Năm',
      5: 'Thứ Sáu',
      6: 'Thứ Bảy',
      7: 'Chủ Nhật',
    };
    return m[w] ?? '';
  }
}

// ── Birthday Day Header ───────────────────────────────────────────────────────

class _BirthdayDayHeader extends StatelessWidget {
  final DateTime day;
  const _BirthdayDayHeader({required this.day});

  @override
  Widget build(BuildContext context) {
    final weekday = _weekdayVi(day.weekday);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        '$weekday, ${day.day} tháng ${day.month}',
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  String _weekdayVi(int w) {
    const m = {
      1: 'Thứ Hai',
      2: 'Thứ Ba',
      3: 'Thứ Tư',
      4: 'Thứ Năm',
      5: 'Thứ Sáu',
      6: 'Thứ Bảy',
      7: 'Chủ Nhật',
    };
    return m[w] ?? '';
  }
}

// ── Birthday Tile ─────────────────────────────────────────────────────────────

class _BirthdayTile extends StatelessWidget {
  final ApiUserModel user;
  const _BirthdayTile({required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
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
          Expanded(
            child: Text(
              'Sinh nhật ${user.fullName}',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {},
            child: Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
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

  String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
