import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/contacts_api_service.dart';

class SendFriendRequestScreen extends StatefulWidget {
  final ApiUserModel targetUser;

  const SendFriendRequestScreen({super.key, required this.targetUser});

  @override
  State<SendFriendRequestScreen> createState() =>
      _SendFriendRequestScreenState();
}

class _SendFriendRequestScreenState extends State<SendFriendRequestScreen> {
  late final TextEditingController _msgCtrl;
  bool _isSending = false;
  static const int _maxLen = 150;

  @override
  void initState() {
    super.initState();
    final myName = authService.currentUser?.fullName ?? 'tôi';
    _msgCtrl = TextEditingController(
      text: 'Xin chào, mình là $myName. Kết bạn với mình nhé!',
    );
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final myId = authService.userId;
    if (myId == null || myId.isEmpty) return;

    setState(() => _isSending = true);
    final result = await ContactsApiService.instance.sendFriendRequest(
      requesterId: myId,
      receiverId: widget.targetUser.id,
      message: _msgCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _isSending = false);

    if (result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.data ?? 'Thành công'),
          backgroundColor: AppColors.primary,
        ),
      );
      Navigator.pop(context, true); // trả true → màn hình trước biết đã xử lý
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Gửi lời mời thất bại, vui lòng thử lại'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.targetUser;
    final initials = _initials(user.fullName);

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
          'Kết bạn',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Card nội dung ──────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar + Tên + icon bút
                    Row(
                      children: [
                        // Avatar
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primaryLight,
                            border: Border.all(
                                color: AppColors.border, width: 1.5),
                          ),
                          child: ClipOval(
                            child: user.avatar.isNotEmpty
                                ? Image.network(
                                    user.avatar,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _avatarFallback(initials),
                                  )
                                : _avatarFallback(initials),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Tên + icon bút (trang trí)
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  user.fullName,
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.edit_outlined,
                                size: 16,
                                color: AppColors.textSecondary,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ── Ô nhập lời nhắn ────────────────────────────────
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _msgCtrl,
                      builder: (_, val, __) {
                        final len = val.text.length;
                        final over = len > _maxLen;
                        return Container(
                          decoration: BoxDecoration(
                            color: AppColors.bgDark,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _msgCtrl,
                                      maxLines: 4,
                                      minLines: 3,
                                      maxLength: _maxLen,
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 14,
                                        color: AppColors.textPrimary,
                                      ),
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        isDense: true,
                                        counterText: '',
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                  // Nút xoá
                                  if (val.text.isNotEmpty)
                                    GestureDetector(
                                      onTap: () {
                                        _msgCtrl.clear();
                                        setState(() {});
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.only(
                                            left: 4, top: 2),
                                        child: Icon(
                                          Icons.close,
                                          size: 18,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              // Đếm ký tự
                              Text(
                                '$len/$_maxLen',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 11,
                                  color: over
                                      ? AppColors.error
                                      : AppColors.textHint,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Nút GỬI YÊU CẦU ──────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(
                16, 8, 16, MediaQuery.of(context).padding.bottom + 16),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _msgCtrl,
              builder: (_, val, __) {
                final canSend =
                    !_isSending && val.text.length <= _maxLen;
                return SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: canSend ? _send : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor: AppColors.bgInput,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isSending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'GỬI YÊU CẦU',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback(String initials) => Container(
        color: AppColors.primaryLight,
        child: Center(
          child: Text(
            initials,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
      );

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
