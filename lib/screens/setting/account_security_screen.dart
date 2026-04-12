import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/fake_auth_flow_service.dart';
import '../../widgets/common/common_widgets.dart';
import '../../widgets/common/top_notice.dart';

class AccountSecurityScreen extends StatefulWidget {
  const AccountSecurityScreen({super.key});

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obOld = true;
  bool _obNew = true;
  bool _obConfirm = true;
  bool _loading = false;

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (_loading) return;

    final userId = authService.userId;
    if (userId == null || userId.isEmpty) {
      showTopNotice(context, message: 'Ban chua dang nhap.', isError: true);
      return;
    }

    final oldPassword = _oldCtrl.text;
    final newPassword = _newCtrl.text;
    final confirm = _confirmCtrl.text;

    if (!fakeAuthFlowService.isStrongPassword(newPassword)) {
      showTopNotice(
        context,
        message: 'Mat khau moi can >=8 ky tu va co chu hoa, chu thuong, so.',
        isError: true,
      );
      return;
    }
    if (newPassword != confirm) {
      showTopNotice(context, message: 'Xac nhan mat khau chua khop.', isError: true);
      return;
    }

    setState(() => _loading = true);
    try {
      await fakeAuthFlowService.changePassword(
        userId: userId,
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
      if (!mounted) return;
      showTopNotice(context, message: 'Doi mat khau thanh cong.');
      _oldCtrl.clear();
      _newCtrl.clear();
      _confirmCtrl.clear();
    } on FakeAuthException catch (e) {
      showTopNotice(context, message: e.message, isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgDark,
        elevation: 0,
        title: const Text(
          'Tai khoan & Bao mat',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Doi mat khau',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 12),
                _buildPasswordField(
                  controller: _oldCtrl,
                  label: 'Mat khau hien tai',
                  obscure: _obOld,
                  onToggle: () => setState(() => _obOld = !_obOld),
                ),
                const SizedBox(height: 12),
                _buildPasswordField(
                  controller: _newCtrl,
                  label: 'Mat khau moi',
                  obscure: _obNew,
                  onToggle: () => setState(() => _obNew = !_obNew),
                ),
                const SizedBox(height: 12),
                _buildPasswordField(
                  controller: _confirmCtrl,
                  label: 'Nhap lai mat khau moi',
                  obscure: _obConfirm,
                  onToggle: () => setState(() => _obConfirm = !_obConfirm),
                ),
                const SizedBox(height: 16),
                GradientButton(
                  label: 'Cap nhat mat khau',
                  loading: _loading,
                  onTap: _changePassword,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: const Text(
              'Bao mat 2 lop se bo sung o phase sau.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Inter',
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.bgInput,
            suffixIcon: IconButton(
              onPressed: onToggle,
              icon: Icon(
                obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              ),
            ),
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
          ),
        ),
      ],
    );
  }
}
