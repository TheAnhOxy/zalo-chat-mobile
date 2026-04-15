import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/contacts_api_service.dart';
import '../../services/social_api_service.dart';
import '../../navigation/app_router.dart';

class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({super.key});

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen> {
  final TextEditingController _phoneController = TextEditingController();
  String _countryCode = '+84';
  bool _isSearching = false;
  List<ApiUserModel>? _suggested;
  bool _loadingSuggested = false;

  @override
  void initState() {
    super.initState();
    _loadSuggested();
  }

  Future<void> _loadSuggested() async {
    if (authService.accessToken == null) {
      setState(() => _suggested = []);
      return;
    }
    setState(() => _loadingSuggested = true);
    final list = await SocialApiService.instance.getSuggestedFriends(limit: 20);
    if (!mounted) return;
    setState(() {
      _suggested = list;
      _loadingSuggested = false;
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String get _qrData {
    final user = authService.currentUser;
    if (user == null) return 'zalo://unknown';
    final phone = user.phone.isNotEmpty ? user.phone : user.id;
    return 'zalo://add-friend?phone=$phone';
  }

  @override
  Widget build(BuildContext context) {
    final user = authService.currentUser;
    final userName = user?.fullName ?? 'Người dùng';

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
          'Thêm bạn',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── QR Card ─────────────────────────────────────────────
            _QrCard(userName: userName, qrData: _qrData),

            const SizedBox(height: 10),

            // ── Phone Search Row ─────────────────────────────────────
            Container(
              color: AppColors.bgCard,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // Country code selector
                  GestureDetector(
                    onTap: () => _showCountryPicker(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.bgInput,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _countryCode,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down_rounded,
                              size: 18, color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Phone input
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.bgInput,
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                        hintText: 'Nhập số điện thoại',
                        hintStyle: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          color: AppColors.textHint,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Search button
                  GestureDetector(
                    onTap: (_phoneController.text.trim().isEmpty || _isSearching)
                        ? null
                        : () => _searchByPhone(context),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: _phoneController.text.trim().isEmpty
                            ? AppColors.bgInput
                            : AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(
                              Icons.arrow_forward_rounded,
                              color: _phoneController.text.trim().isEmpty
                                  ? AppColors.textHint
                                  : Colors.white,
                              size: 20,
                            ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // ── Quick Actions ────────────────────────────────────────
            Container(
              color: AppColors.bgCard,
              child: Column(
                children: [
                  _ActionTile(
                    icon: Icons.qr_code_scanner_rounded,
                    iconColor: AppColors.primary,
                    iconBg: AppColors.primaryLight,
                    title: 'Quét mã QR',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Tính năng quét mã QR đang phát triển'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 58),
                    child: Divider(height: 1, thickness: 1, color: AppColors.divider),
                  ),
                  _ActionTile(
                    icon: Icons.people_alt_outlined,
                    iconColor: const Color(0xFF9C27B0),
                    iconBg: const Color(0xFFF3E5F5),
                    title: 'Bạn bè có thể quen',
                    onTap: () {
                      if ((_suggested ?? []).isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Chưa có gợi ý hoặc bạn cần đăng nhập'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                        return;
                      }
                      _showSuggestedSheet();
                    },
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 58),
                    child: Divider(height: 1, thickness: 1, color: AppColors.divider),
                  ),
                  _ActionTile(
                    icon: Icons.search_rounded,
                    iconColor: const Color(0xFF009688),
                    iconBg: const Color(0xFFE0F2F1),
                    title: 'Tìm kiếm người dùng',
                    onTap: () => Navigator.pushNamed(context, AppRouter.searchUsers),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Bottom hint ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Xem lời mời kết bạn đã gửi tại trang Danh bạ QuickChat',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: AppColors.textHint,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _searchByPhone(BuildContext context) async {
    final raw = _phoneController.text.trim();
    if (raw.isEmpty) return;

    // Gửi nguyên số nhập vào, backend tự xử lý cả 2 định dạng 0xxx / +84xxx
    final phone = raw;

    setState(() => _isSearching = true);
    final result = await ContactsApiService.instance.searchByPhone(phone);
    if (!mounted) return;
    setState(() => _isSearching = false);

    if (!result.isSuccess) {
      _showNotFoundToast(context);
      return;
    }

    final user = result.data;
    if (user == null) {
      _showNotFoundToast(context);
      return;
    }

    Navigator.pushNamed(context, AppRouter.foundUser, arguments: user);
  }

  void _showSuggestedSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        final items = _suggested ?? [];
        return SafeArea(
          child: SizedBox(
            height: 520,
            child: Column(
              children: [
                const SizedBox(height: 10),
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
                  'Gợi ý kết bạn',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _loadingSuggested
                      ? const Center(
                          child: CircularProgressIndicator(color: AppColors.primary),
                        )
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
                          itemBuilder: (_, i) {
                            final u = items[i];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primaryLight,
                                foregroundImage: u.avatar.isNotEmpty ? NetworkImage(u.avatar) : null,
                                child: Text(
                                  u.fullName.isNotEmpty ? u.fullName[0].toUpperCase() : '?',
                                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                                ),
                              ),
                              title: Text(
                                u.fullName,
                                style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                u.phone,
                                style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.textSecondary),
                              ),
                              trailing: TextButton(
                                onPressed: () async {
                                  if (u.id == authService.userId) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Không thể gửi lời mời cho chính bạn'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                    return;
                                  }
                                  final ok = await SocialApiService.instance.sendFriendRequest(u.id);
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        ok
                                            ? 'Đã gửi lời mời'
                                            : (SocialApiService.instance.lastError ??
                                                'Gửi lời mời thất bại'),
                                      ),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                },
                                child: const Text('Kết bạn'),
                              ),
                              onTap: () => Navigator.pushNamed(context, AppRouter.foundUser, arguments: u),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showNotFoundToast(BuildContext context) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (_) => _NotFoundToast(
        message: 'Số điện thoại này chưa đăng ký tài khoản\nhoặc không cho phép tìm kiếm',
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 3), () => entry.remove());
  }

  void _showCountryPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CountryPickerSheet(
        selected: _countryCode,
        onSelect: (code) {
          setState(() => _countryCode = code);
          Navigator.pop(context);
        },
      ),
    );
  }
}

// ── QR Card ───────────────────────────────────────────────────────────────────

class _QrCard extends StatelessWidget {
  final String userName;
  final String qrData;

  const _QrCard({required this.userName, required this.qrData});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0068FF), Color(0xFF1E88E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          // User name
          Text(
            userName,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          // QR code with QuickChat branding overlay
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 160,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black87,
                  ),
                ),
                // Center logo
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Center(
                    child: Text(
                      'Q',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Quét mã để thêm bạn QuickChat với tôi',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ── Action Tile ───────────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textHint, size: 22),
          ],
        ),
      ),
    );
  }
}

// ── Not Found Toast ───────────────────────────────────────────────────────────

class _NotFoundToast extends StatelessWidget {
  final String message;
  const _NotFoundToast({required this.message});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).size.height * 0.28,
      left: 20,
      right: 20,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1C),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: Colors.white,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Country Picker ────────────────────────────────────────────────────────────

class _CountryPickerSheet extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;

  const _CountryPickerSheet({
    required this.selected,
    required this.onSelect,
  });

  static const _countries = [
    ('+84', 'Việt Nam 🇻🇳'),
    ('+1', 'Hoa Kỳ 🇺🇸'),
    ('+86', 'Trung Quốc 🇨🇳'),
    ('+81', 'Nhật Bản 🇯🇵'),
    ('+82', 'Hàn Quốc 🇰🇷'),
    ('+65', 'Singapore 🇸🇬'),
    ('+60', 'Malaysia 🇲🇾'),
    ('+66', 'Thái Lan 🇹🇭'),
    ('+62', 'Indonesia 🇮🇩'),
    ('+44', 'Anh 🇬🇧'),
    ('+33', 'Pháp 🇫🇷'),
    ('+49', 'Đức 🇩🇪'),
  ];

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
          'Chọn mã quốc gia',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const Divider(height: 16),
        ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: _countries
              .map((c) => ListTile(
                    leading: Text(
                      c.$1,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.$1 == selected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    ),
                    title: Text(
                      c.$2,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    trailing: c.$1 == selected
                        ? const Icon(Icons.check_rounded,
                            color: AppColors.primary)
                        : null,
                    onTap: () => onSelect(c.$1),
                  ))
              .toList(),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
