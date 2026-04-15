import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/models.dart';
import '../../services/auth_service.dart';
import '../../services/fake_auth_flow_service.dart';
import '../../widgets/common/common_widgets.dart';
import '../../widgets/common/top_notice.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _coverCtrl = TextEditingController();

  String _gender = 'other';
  String _avatarUrl = '';
  DateTime? _selectedDob;
  bool _isBlocked = false;
  bool _loading = false;
  bool _uploadingAvatar = false;
  bool _uploadingCover = false;

  @override
  void initState() {
    super.initState();
    _hydrateFromCurrentUser();
    _loadProfileFromServer();
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _bioCtrl.dispose();
    _dobCtrl.dispose();
    _coverCtrl.dispose();
    super.dispose();
  }

  void _hydrateFromCurrentUser() {
    final user = authService.currentUser;
    if (user == null) return;
    _fullNameCtrl.text = user.fullName;
    _phoneCtrl.text = user.phone;
    _emailCtrl.text = user.email ?? '';
    _bioCtrl.text = user.bio ?? '';
    _gender = user.gender;
    _avatarUrl = user.avatar;
    _coverCtrl.text = user.coverImage ?? '';
  }

  Future<void> _loadProfileFromServer() async {
    final userId = authService.userId;
    if (userId == null || userId.isEmpty) return;

    try {
      final map = await fakeAuthFlowService.getUserProfile(userId);
      if (!mounted || map.isEmpty) return;

      _fullNameCtrl.text = (map['fullName'] ?? _fullNameCtrl.text).toString();
      _phoneCtrl.text = (map['phone'] ?? _phoneCtrl.text).toString();
      _emailCtrl.text = (map['email'] ?? _emailCtrl.text).toString();
      _bioCtrl.text = (map['bio'] ?? _bioCtrl.text).toString();
      final dobRaw = (map['dob'] ?? '').toString();
      _selectedDob = _parseServerDob(dobRaw);
      _dobCtrl.text = _formatDate(_selectedDob);
      _coverCtrl.text = (map['coverImage'] ?? _coverCtrl.text).toString();
      _avatarUrl = (map['avatar'] ?? _avatarUrl).toString();
      _gender = (map['gender'] ?? _gender).toString();
      _isBlocked = map['isBlocked'] == true;
      setState(() {});
    } catch (_) {
      // Silent fallback to local user state.
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final userId = authService.userId;
    if (userId == null || userId.isEmpty) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() => _uploadingAvatar = true);
    try {
      final uploaded = await fakeAuthFlowService.uploadAvatarToS3(
        userId: userId,
        file: picked,
      );
      if (!mounted) return;
      setState(() => _avatarUrl = uploaded.avatarUrl);
      showTopNotice(context, message: 'Cập nhật ảnh đại diện thành công.');
    } on FakeAuthException catch (e) {
      if (!mounted) return;
      showTopNotice(context, message: e.message, isError: true);
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _saveProfile() async {
    final userId = authService.userId;
    if (userId == null || userId.isEmpty) return;

    if (_fullNameCtrl.text.trim().length < 2) {
      showTopNotice(context, message: 'Họ tên không hợp lệ.', isError: true);
      return;
    }

    if (!fakeAuthFlowService.isValidDob(_dobCtrl.text.trim())) {
      showTopNotice(context, message: 'Ngày sinh phải đúng định dạng YYYY-MM-DD.', isError: true);
      return;
    }

    if (!fakeAuthFlowService.isValidGender(_gender)) {
      showTopNotice(context, message: 'Giới tính chỉ nhận male/female/other.', isError: true);
      return;
    }

    if (!fakeAuthFlowService.isValidUrl(_avatarUrl)) {
      showTopNotice(context, message: 'URL ảnh đại diện không hợp lệ.', isError: true);
      return;
    }

    if (!fakeAuthFlowService.isValidUrl(_coverCtrl.text.trim())) {
      showTopNotice(context, message: 'URL ảnh bìa không hợp lệ.', isError: true);
      return;
    }

    setState(() => _loading = true);
    try {
      final updatedUser = await fakeAuthFlowService.updateUserProfile(
        userId: userId,
        fullName: _fullNameCtrl.text,
        bio: _bioCtrl.text,
        gender: _gender,
        dob: _selectedDob == null ? null : _formatDate(_selectedDob),
      );

      authService.updateCurrentUser(
        UserModel(
          id: updatedUser.id,
          fullName: updatedUser.fullName,
          phone: updatedUser.phone,
          email: updatedUser.email,
          avatar: updatedUser.avatar,
          coverImage: updatedUser.coverImage,
          bio: updatedUser.bio,
          gender: updatedUser.gender,
          status: updatedUser.status,
          privacy: authService.currentUser?.privacy ?? updatedUser.privacy,
          isVerified: updatedUser.isVerified,
        ),
      );

      if (!mounted) return;
      showTopNotice(context, message: 'Cập nhật hồ sơ thành công.');
    } on FakeAuthException catch (e) {
      if (!mounted) return;
      showTopNotice(context, message: e.message, isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAndUploadCoverImage() async {
    final userId = authService.userId;
    if (userId == null || userId.isEmpty) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1440,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() => _uploadingCover = true);
    try {
      final uploaded = await fakeAuthFlowService.uploadCoverToS3(
        userId: userId,
        file: picked,
      );
      if (!mounted) return;
      _coverCtrl.text = uploaded.fileUrl;
      showTopNotice(context, message: 'Cập nhật ảnh bìa thành công.');
    } on FakeAuthException catch (e) {
      if (!mounted) return;
      showTopNotice(context, message: e.message, isError: true);
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  Future<void> _showCoverImageOptions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Chọn ảnh từ thiết bị'),
              onTap: () => Navigator.of(context).pop('pick'),
            ),
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: const Text('Dán link ảnh'),
              onTap: () => Navigator.of(context).pop('paste'),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );

    if (!mounted) return;
    if (action == 'pick') {
      await _pickAndUploadCoverImage();
      return;
    }
    if (action == 'paste') {
      await _showPasteCoverLinkDialog();
    }
  }

  Future<void> _showPasteCoverLinkDialog() async {
    final controller = TextEditingController(text: _coverCtrl.text.trim());

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Dán link ảnh bìa'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: _decoration('https://...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) return;

    final link = controller.text.trim();
    if (!fakeAuthFlowService.isValidUrl(link)) {
      showTopNotice(context, message: 'Link ảnh không hợp lệ.', isError: true);
      return;
    }

    setState(() => _coverCtrl.text = link);
    showTopNotice(context, message: 'Đã cập nhật link ảnh bìa.');
  }

  @override
  Widget build(BuildContext context) {
    final verified = authService.currentUser?.isVerified == true;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgDark,
        elevation: 0,
        title: const Text(
          'Chỉnh sửa hồ sơ',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontFamily: 'Inter',
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Stack(
                  children: [
                    AvatarWidget(
                      url: _avatarUrl,
                      name: _fullNameCtrl.text.isEmpty ? 'User' : _fullNameCtrl.text,
                      size: 86,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: _uploadingAvatar
                              ? const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _formCard(
            child: Column(
              children: [
                _field(_fullNameCtrl, 'Họ và tên'),
                const SizedBox(height: 10),
                _field(
                  _phoneCtrl,
                  'Số điện thoại (chỉ đọc)',
                  keyboardType: TextInputType.phone,
                  readOnly: true,
                ),
                const SizedBox(height: 10),
                _field(
                  _emailCtrl,
                  'Email (chỉ đọc)',
                  keyboardType: TextInputType.emailAddress,
                  readOnly: true,
                ),
                const SizedBox(height: 10),
                _field(_bioCtrl, 'Giới thiệu'),
                const SizedBox(height: 10),
                _datePickerField(),
                const SizedBox(height: 10),
                _field(
                  _coverCtrl,
                  'Ảnh bìa (URL)',
                  suffix: IconButton(
                    onPressed: _uploadingCover ? null : _showCoverImageOptions,
                    icon: _uploadingCover
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.image_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration: _decoration('Giới tính'),
                  items: const [
                    DropdownMenuItem(value: 'male', child: Text('Nam')),
                    DropdownMenuItem(value: 'female', child: Text('Nữ')),
                    DropdownMenuItem(value: 'other', child: Text('Khác')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _gender = v);
                  },
                ),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  value: _isBlocked,
                  onChanged: (v) => setState(() => _isBlocked = v),
                  title: const Text('Chặn tài khoản'),
                  subtitle: const Text('Trạng thái chặn tài khoản'),
                  activeThumbColor: AppColors.primary,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Xác thực tài khoản'),
                  subtitle: Text(verified ? 'true' : 'false'),
                  trailing: Icon(
                    verified ? Icons.verified_rounded : Icons.error_outline,
                    color: verified ? AppColors.success : AppColors.warning,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GradientButton(
            label: 'Lưu thông tin hồ sơ',
            loading: _loading,
            onTap: _saveProfile,
          ),
        ],
      ),
    );
  }

  Widget _formCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType keyboardType = TextInputType.text,
    bool readOnly = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      readOnly: readOnly,
      decoration: _decoration(label, readOnly: readOnly, suffix: suffix),
    );
  }

  Widget _datePickerField() {
    return TextField(
      controller: _dobCtrl,
      readOnly: true,
      onTap: _pickDob,
      decoration: _decoration('Ngày sinh (YYYY-MM-DD)').copyWith(
        suffixIcon: IconButton(
          icon: const Icon(Icons.calendar_month_outlined),
          onPressed: _pickDob,
        ),
      ),
    );
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = _selectedDob ?? DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900, 1, 1),
      lastDate: now,
    );

    if (picked == null) return;
    setState(() {
      _selectedDob = picked;
      _dobCtrl.text = _formatDate(picked);
    });
  }

  DateTime? _parseServerDob(String value) {
    if (value.trim().isEmpty) return null;
    return DateTime.tryParse(value);
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  InputDecoration _decoration(
    String label, {
    bool readOnly = false,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      suffixIcon: suffix,
      filled: true,
      fillColor: readOnly ? AppColors.bgDark : AppColors.bgInput,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }
}
