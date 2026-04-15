import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/social_api_service.dart';
import '../../services/contacts_api_service.dart';
import '../../navigation/app_router.dart';

class SearchUsersScreen extends StatefulWidget {
  const SearchUsersScreen({super.key});

  @override
  State<SearchUsersScreen> createState() => _SearchUsersScreenState();
}

class _SearchUsersScreenState extends State<SearchUsersScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  List<ApiUserModel> _items = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    setState(() => _loading = true);
    try {
      final items = await SocialApiService.instance.searchUsers(
        q,
        limit: 20,
        includeRelated: true,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bạn cần đăng nhập (token thật) để tìm kiếm theo tên.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Tìm kiếm người dùng', style: TextStyle(fontFamily: 'Inter')),
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.bgCard,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(
                      hintText: 'Nhập tên / email / số điện thoại',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _loading ? null : _search,
                  child: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Tìm'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _items.isEmpty
                ? const Center(
                    child: Text(
                      'Nhập từ khoá để tìm người dùng',
                      style: TextStyle(color: AppColors.textHint, fontFamily: 'Inter'),
                    ),
                  )
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
                    itemBuilder: (_, i) {
                      final u = _items[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primaryLight,
                          foregroundImage: u.avatar.isNotEmpty ? NetworkImage(u.avatar) : null,
                          child: Text(
                            u.fullName.isNotEmpty ? u.fullName[0].toUpperCase() : '?',
                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                          ),
                        ),
                        title: Text(u.fullName, style: const TextStyle(fontFamily: 'Inter')),
                        subtitle: Text(u.phone, style: const TextStyle(color: AppColors.textSecondary)),
                        onTap: () => Navigator.pushNamed(context, AppRouter.foundUser, arguments: u),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

