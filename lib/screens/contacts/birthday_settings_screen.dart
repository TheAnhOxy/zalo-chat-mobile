import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_colors.dart';

// ── Keys lưu SharedPreferences ───────────────────────────────────────────────
const _kShowDob = 'birthday_show_dob';          // 0=Không hiện,1=Bạn bè,2=Tất cả
const _kNotifyFriends = 'birthday_notify_friends'; // bool
const _kNotifyMe = 'birthday_notify_me';          // bool

const List<String> _showDobOptions = [
  'Không hiện',
  'Bạn bè',
  'Tất cả mọi người',
];

class BirthdaySettingsScreen extends StatefulWidget {
  const BirthdaySettingsScreen({super.key});

  @override
  State<BirthdaySettingsScreen> createState() => _BirthdaySettingsScreenState();
}

class _BirthdaySettingsScreenState extends State<BirthdaySettingsScreen> {
  int _showDobIndex = 0;       // 0 = Không hiện
  bool _notifyFriends = false; // Disabled khi không hiện dob
  bool _notifyMe = true;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _showDobIndex = prefs.getInt(_kShowDob) ?? 0;
      _notifyFriends = prefs.getBool(_kNotifyFriends) ?? false;
      _notifyMe = prefs.getBool(_kNotifyMe) ?? true;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kShowDob, _showDobIndex);
    await prefs.setBool(_kNotifyFriends, _notifyFriends);
    await prefs.setBool(_kNotifyMe, _notifyMe);
  }

  void _onShowDobChanged(int idx) {
    setState(() {
      _showDobIndex = idx;
      // Nếu không hiện dob thì tắt thông báo cho bạn bè
      if (idx == 0) _notifyFriends = false;
    });
    _save();
  }

  void _onNotifyFriendsChanged(bool val) {
    if (_showDobIndex == 0) return; // không cho bật khi dob ẩn
    setState(() => _notifyFriends = val);
    _save();
  }

  void _onNotifyMeChanged(bool val) {
    setState(() => _notifyMe = val);
    _save();
  }

  void _pickShowDob() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ShowDobPicker(
        selected: _showDobIndex,
        onSelect: (idx) {
          Navigator.pop(context);
          _onShowDobChanged(idx);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final dobDisabled = _showDobIndex == 0;

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
          'Quản lý sinh nhật',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        children: [
          // ── Cá nhân ─────────────────────────────────────────────
          _SectionHeader(title: 'Cá nhân'),

          // Hiện ngày sinh
          _TappableTile(
            title: 'Hiện ngày sinh',
            trailing: _showDobOptions[_showDobIndex],
            onTap: _pickShowDob,
          ),

          // Báo cho bạn bè
          _ToggleTile(
            title: 'Báo cho bạn bè về sinh nhật của tôi',
            subtitle: 'Bao gồm thông báo đẩy và thông báo trong trò chuyện',
            value: _notifyFriends,
            enabled: !dobDisabled,
            onChanged: _onNotifyFriendsChanged,
          ),

          const SizedBox(height: 8),

          // ── Bạn bè ─────────────────────────────────────────────
          _SectionHeader(title: 'Bạn bè'),

          // Báo cho tôi
          _ToggleTile(
            title: 'Báo cho tôi về sinh nhật của bạn bè',
            subtitle: 'Bao gồm thông báo đẩy và thông báo trong trò chuyện',
            value: _notifyMe,
            enabled: true,
            onChanged: _onNotifyMeChanged,
          ),
        ],
      ),
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

// ── Tappable Tile (Hiện ngày sinh) ────────────────────────────────────────────

class _TappableTile extends StatelessWidget {
  final String title;
  final String trailing;
  final VoidCallback onTap;

  const _TappableTile({
    required this.title,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: AppColors.bgCard,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Text(
              trailing,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Toggle Tile ───────────────────────────────────────────────────────────────

class _ToggleTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: enabled
                        ? AppColors.textPrimary
                        : AppColors.textDisabled,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: enabled
                        ? AppColors.textSecondary
                        : AppColors.textDisabled,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: enabled ? value : false,
            onChanged: enabled ? onChanged : null,
            activeColor: AppColors.primary,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFFCDD0D4),
          ),
        ],
      ),
    );
  }
}

// ── Show Dob Picker ───────────────────────────────────────────────────────────

class _ShowDobPicker extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;

  const _ShowDobPicker({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.divider,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Hiện ngày sinh',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const Divider(height: 20),
        ...List.generate(_showDobOptions.length, (i) {
          final isSelected = i == selected;
          return ListTile(
            title: Text(
              _showDobOptions[i],
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: isSelected ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            trailing: isSelected
                ? const Icon(Icons.check_rounded, color: AppColors.primary)
                : null,
            onTap: () => onSelect(i),
          );
        }),
        const SizedBox(height: 16),
      ],
    );
  }
}
