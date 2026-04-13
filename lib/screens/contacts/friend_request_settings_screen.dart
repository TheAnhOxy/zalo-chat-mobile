import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/contacts_api_service.dart';

// ── SharedPreferences keys ────────────────────────────────────────────────────
const _kAllowQr = 'fr_allow_qr';
const _kAllowGroup = 'fr_allow_group';
const _kAllowCard = 'fr_allow_card';
const _kAllowSuggest = 'fr_allow_suggest';

class FriendRequestSettingsScreen extends StatefulWidget {
  const FriendRequestSettingsScreen({super.key});

  @override
  State<FriendRequestSettingsScreen> createState() =>
      _FriendRequestSettingsScreenState();
}

class _FriendRequestSettingsScreenState
    extends State<FriendRequestSettingsScreen> {
  // Từ backend: privacy.findByPhone
  bool _findByPhone = true;
  bool _savingPhone = false;

  // Local settings (SharedPreferences)
  bool _allowQr = true;
  bool _allowGroup = true;
  bool _allowCard = true;
  bool _allowSuggest = true;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Đọc findByPhone từ currentUser (đã có trong authService)
    final user = authService.currentUser;
    final prefs = await SharedPreferences.getInstance();

    // Nếu chưa có giá trị backend, mặc định true
    bool findByPhone = true;
    if (user != null) {
      // Thử fetch từ backend để lấy giá trị mới nhất
      try {
        final res = await ContactsApiService.instance
            .fetchUserPrivacy(authService.userId ?? '');
        findByPhone = res ?? true;
      } catch (_) {}
    }

    setState(() {
      _findByPhone = findByPhone;
      _allowQr = prefs.getBool(_kAllowQr) ?? true;
      _allowGroup = prefs.getBool(_kAllowGroup) ?? true;
      _allowCard = prefs.getBool(_kAllowCard) ?? true;
      _allowSuggest = prefs.getBool(_kAllowSuggest) ?? true;
      _loading = false;
    });
  }

  Future<void> _saveLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAllowQr, _allowQr);
    await prefs.setBool(_kAllowGroup, _allowGroup);
    await prefs.setBool(_kAllowCard, _allowCard);
    await prefs.setBool(_kAllowSuggest, _allowSuggest);
  }

  Future<void> _toggleFindByPhone(bool val) async {
    setState(() {
      _findByPhone = val;
      _savingPhone = true;
    });

    final ok = await ContactsApiService.instance
        .updateFindByPhone(authService.userId ?? '', val);

    if (!mounted) return;
    setState(() => _savingPhone = false);

    if (!ok) {
      // Rollback nếu lỗi
      setState(() => _findByPhone = !val);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Có lỗi xảy ra, vui lòng thử lại'),
          backgroundColor: Color(0xFF1C1C1C),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = authService.currentUser;
    final phoneDisplay = user?.phone ?? '';

    if (_loading) {
      return const Scaffold(
        body: Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

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
          'Quản lý nguồn tìm kiếm và kết bạn',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        children: [
          // ── Tìm qua số điện thoại ──────────────────────────────
          const SizedBox(height: 8),
          Container(
            color: AppColors.bgCard,
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cho phép người lạ tìm thấy và kết bạn qua số điện thoại',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (phoneDisplay.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          phoneDisplay,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _savingPhone
                    ? const SizedBox(
                        width: 36,
                        height: 36,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary),
                          ),
                        ),
                      )
                    : Switch(
                        value: _findByPhone,
                        onChanged: _toggleFindByPhone,
                        activeColor: AppColors.primary,
                        inactiveThumbColor: Colors.white,
                        inactiveTrackColor: const Color(0xFFCDD0D4),
                      ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Cho phép người lạ kết bạn ─────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cho phép người lạ kết bạn',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Người lạ có thể gửi lời mời kết bạn qua những nguồn này',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),

          // Checkboxes
          _CheckboxTile(
            title: 'Mã QR của tôi',
            value: _allowQr,
            onChanged: (v) {
              setState(() => _allowQr = v);
              _saveLocal();
            },
          ),
          _CheckboxTile(
            title: 'Nhóm chung',
            value: _allowGroup,
            onChanged: (v) {
              setState(() => _allowGroup = v);
              _saveLocal();
            },
          ),
          _CheckboxTile(
            title: 'Danh thiếp QuickChat',
            value: _allowCard,
            onChanged: (v) {
              setState(() => _allowCard = v);
              _saveLocal();
            },
          ),
          _CheckboxTile(
            title: 'Gợi ý "Có thể bạn quen"',
            value: _allowSuggest,
            onChanged: (v) {
              setState(() => _allowSuggest = v);
              _saveLocal();
            },
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Checkbox Tile ─────────────────────────────────────────────────────────────

class _CheckboxTile extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CheckboxTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Container(
        color: AppColors.bgCard,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: value ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: value ? AppColors.primary : AppColors.border,
                  width: 2,
                ),
              ),
              child: value
                  ? const Icon(Icons.check_rounded,
                      size: 15, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 14),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
