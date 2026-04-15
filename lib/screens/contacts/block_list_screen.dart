import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/social_api_service.dart';
import '../../services/contacts_api_service.dart';

class BlockListScreen extends StatefulWidget {
  const BlockListScreen({super.key});

  @override
  State<BlockListScreen> createState() => _BlockListScreenState();
}

class _BlockListScreenState extends State<BlockListScreen> {
  bool _loading = true;
  List<ApiUserModel> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await SocialApiService.instance.listBlocks();
    final users = <ApiUserModel>[];
    for (final r in rows) {
      final blockedId = (r['blockedId'] ?? '').toString();
      if (blockedId.isEmpty) continue;
      final u = await SocialApiService.instance.getUserById(blockedId);
      if (u != null) users.add(u);
    }
    if (!mounted) return;
    setState(() {
      _items = users;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Danh sách chặn', style: TextStyle(fontFamily: 'Inter')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _items.isEmpty
              ? const Center(
                  child: Text('Chưa chặn ai', style: TextStyle(color: AppColors.textHint)),
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
                      ),
                      title: Text(u.fullName, style: const TextStyle(fontFamily: 'Inter')),
                      trailing: TextButton(
                        onPressed: () async {
                          final ok = await SocialApiService.instance.unblockUser(u.id);
                          if (!mounted) return;
                          if (ok) {
                            setState(() => _items = List.of(_items)..removeAt(i));
                          }
                        },
                        child: const Text('Bỏ chặn'),
                      ),
                    );
                  },
                ),
    );
  }
}

