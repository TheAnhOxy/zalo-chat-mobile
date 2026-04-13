import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/contacts_api_service.dart';
import '../../navigation/app_router.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  int _filterIndex = 0; // 0: Tất cả, 1: Mới truy cập

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _TopBar(
              controller: _searchController,
              onAdd: () => Navigator.pushNamed(context, AppRouter.addFriend),
              onSearchChanged: (_) => setState(() {}),
            ),
            Container(
              color: AppColors.primary,
              child: TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white.withValues(alpha: 0.85),
                labelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500),
                tabs: const [
                  Tab(text: 'Bạn bè'),
                  Tab(text: 'Nhóm'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _FriendsTab(
                    query: _searchController.text,
                    filterIndex: _filterIndex,
                    onChangeFilter: (i) => setState(() => _filterIndex = i),
                  ),
                  _GroupsTab(query: _searchController.text),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onAdd;
  final ValueChanged<String> onSearchChanged;

  const _TopBar({
    required this.controller,
    required this.onAdd,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      child: Row(
        children: [
          const Icon(Icons.search, color: Colors.white, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: controller,
                onChanged: onSearchChanged,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.2),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                  hintText: 'Tìm kiếm',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  suffixIcon: controller.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            controller.clear();
                            onSearchChanged('');
                            FocusScope.of(context).unfocus();
                          },
                          child: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.8), size: 18),
                        )
                      : null,
                  suffixIconConstraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onAdd,
            child: const Icon(Icons.person_add_alt_1_outlined, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _FriendsTab extends StatefulWidget {
  final String query;
  final int filterIndex;
  final ValueChanged<int> onChangeFilter;

  const _FriendsTab({
    required this.query,
    required this.filterIndex,
    required this.onChangeFilter,
  });

  @override
  State<_FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<_FriendsTab> {
  List<ApiUserModel>? _friends;
  String? _error;
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = authService.userId ?? '';
    final result = await ContactsApiService.instance.fetchFriends(userId);
    final pending =
        await ContactsApiService.instance.fetchPendingRequestCount(userId);
    if (!mounted) return;
    setState(() {
      _friends = result.data ?? [];
      _error = result.error;
      _pendingCount = pending;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_friends == null && _error == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null && (_friends == null || _friends!.isEmpty)) {
      return _ErrorView(message: _error!, onRetry: _load);
    }

    final friends = _friends ?? [];
    final q = widget.query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? friends
        : friends
            .where((u) => _normalize(u.fullName).contains(_normalize(q)))
            .toList();

    final sections = _buildSections(filtered);

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: 8),
          _QuickActionTile(
            icon: Icons.person_add_alt_rounded,
            iconBg: const Color(0xFFE8F0FF),
            iconColor: AppColors.primary,
            title: _pendingCount > 0
                ? 'Lời mời kết bạn ($_pendingCount)'
                : 'Lời mời kết bạn',
            badge: _pendingCount > 0 ? _pendingCount : null,
            onTap: () => Navigator.pushNamed(context, AppRouter.friendRequests)
                .then((_) => _load()),
          ),
          _QuickActionTile(
            icon: Icons.cake_rounded,
            iconBg: const Color(0xFFFFF3E0),
            iconColor: const Color(0xFFFF9800),
            title: 'Sinh nhật',
            onTap: () => Navigator.pushNamed(context, AppRouter.birthday),
          ),
          const SizedBox(height: 8),
          _FilterRow(
            allCount: filtered.length,
            current: widget.filterIndex,
            onChange: widget.onChangeFilter,
          ),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.search_off_rounded, size: 40, color: AppColors.textHint),
                    const SizedBox(height: 10),
                    Text(
                      q.isEmpty
                          ? 'Chưa có bạn bè nào'
                          : 'Không tìm thấy "$q"',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...sections.expand((section) {
              return [
                if (q.isEmpty) _SectionHeader(title: section.letter),
                ...List.generate(section.items.length, (i) {
                  final item = section.items[i];
                  return _ContactRow(
                    name: item.name,
                    avatarUrl: item.avatarUrl,
                    highlightQuery: q,
                    onCall: () {},
                    onVideo: () {},
                    showDivider: i != section.items.length - 1,
                  );
                }),
              ];
            }),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _GroupsTab extends StatefulWidget {
  final String query;
  const _GroupsTab({required this.query});

  @override
  State<_GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<_GroupsTab> {
  List<ApiGroupModel>? _groups;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = authService.userId ?? '';
    final result = await ContactsApiService.instance.fetchGroups(userId);
    if (!mounted) return;
    setState(() {
      _groups = result.data ?? [];
      _error = result.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_groups == null && _error == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null && (_groups == null || _groups!.isEmpty)) {
      return _ErrorView(message: _error!, onRetry: _load);
    }

    final groups = _groups ?? [];
    final q = widget.query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? groups
        : groups
            .where((g) => g.name.toLowerCase().contains(q))
            .toList();

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: 8),
          _QuickActionTile(
            icon: Icons.group_add_rounded,
            iconBg: const Color(0xFFE8F0FF),
            iconColor: AppColors.primary,
            title: 'Tạo nhóm mới',
            onTap: () {},
          ),
          const SizedBox(height: 8),
          _GroupsHeaderRow(
            title: 'Nhóm đang tham gia (${filtered.length})',
            onSort: () {},
          ),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(
                child: Text(
                  'Chưa tham gia nhóm nào',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: AppColors.textHint,
                  ),
                ),
              ),
            )
          else
            ...List.generate(filtered.length, (i) {
              final g = filtered[i];
              final avatarUrls = g.avatar.isNotEmpty ? [g.avatar] : <String>[];
              return _GroupRow(
                name: g.name.isEmpty ? 'Nhóm' : g.name,
                subtitle: g.lastMessageContent ?? 'Chưa có tin nhắn',
                trailing: g.lastMessageAt != null
                    ? _formatRelative(g.lastMessageAt!)
                    : _formatRelative(g.updatedAt),
                avatarUrls: avatarUrls,
                showDivider: i != filtered.length - 1,
                onTap: () {},
              );
            }),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final int? badge;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: AppColors.bgCard,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                if (badge != null && badge! > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.badge,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badge! > 99 ? '99+' : '$badge',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final int allCount;
  final int current;
  final ValueChanged<int> onChange;

  const _FilterRow({
    required this.allCount,
    required this.current,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          _ChipButton(
            text: 'Tất cả $allCount',
            active: current == 0,
            onTap: () => onChange(0),
          ),
          const SizedBox(width: 10),
          _ChipButton(
            text: 'Mới truy cập',
            active: current == 1,
            onTap: () => onChange(1),
          ),
        ],
      ),
    );
  }
}

class _ChipButton extends StatelessWidget {
  final String text;
  final bool active;
  final VoidCallback onTap;

  const _ChipButton({
    required this.text,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = active ? const Color(0xFFE8F0FF) : const Color(0xFFF3F4F6);
    final fg = active ? AppColors.primary : AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
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

class _GroupsHeaderRow extends StatelessWidget {
  final String title;
  final VoidCallback onSort;

  const _GroupsHeaderRow({
    required this.title,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          InkWell(
            onTap: onSort,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: const [
                  Icon(Icons.swap_vert_rounded, size: 16, color: AppColors.textHint),
                  SizedBox(width: 4),
                  Text(
                    'Sắp xếp',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  final String name;
  final String subtitle;
  final String trailing;
  final List<String> avatarUrls;
  final bool showDivider;
  final VoidCallback onTap;

  const _GroupRow({
    required this.name,
    required this.subtitle,
    required this.trailing,
    required this.avatarUrls,
    required this.showDivider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: AppColors.bgCard,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GroupAvatarStack(urls: avatarUrls),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    trailing,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            if (showDivider)
              const Padding(
                padding: EdgeInsets.only(left: 60),
                child: Divider(height: 1, thickness: 1, color: AppColors.divider),
              ),
          ],
        ),
      ),
    );
  }
}

class _GroupAvatarStack extends StatelessWidget {
  final List<String> urls;
  const _GroupAvatarStack({required this.urls});

  @override
  Widget build(BuildContext context) {
    final shown = urls.take(3).toList();
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        children: [
          if (shown.isNotEmpty)
            Positioned(
              left: 0,
              top: 0,
              child: _SmallCircleAvatar(url: shown[0]),
            ),
          if (shown.length >= 2)
            Positioned(
              left: 18,
              top: 0,
              child: _SmallCircleAvatar(url: shown[1]),
            ),
          if (shown.length >= 3)
            Positioned(
              left: 9,
              top: 18,
              child: _SmallCircleAvatar(url: shown[2]),
            ),
        ],
      ),
    );
  }
}

class _SmallCircleAvatar extends StatelessWidget {
  final String url;
  const _SmallCircleAvatar({required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.bgCard, width: 2),
        color: const Color(0xFFE5E7EB),
        image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final String highlightQuery;
  final VoidCallback onCall;
  final VoidCallback onVideo;
  final bool showDivider;

  const _ContactRow({
    required this.name,
    required this.avatarUrl,
    this.highlightQuery = '',
    required this.onCall,
    required this.onVideo,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgCard,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _Avatar(url: avatarUrl, name: name),
                const SizedBox(width: 12),
                Expanded(
                  child: _HighlightText(
                    text: name,
                    query: highlightQuery,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onCall,
                  icon: const Icon(Icons.call, color: AppColors.textSecondary, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: onVideo,
                  icon: const Icon(Icons.videocam_rounded, color: AppColors.textSecondary, size: 22),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          if (showDivider)
            const Padding(
              padding: EdgeInsets.only(left: 60),
              child: Divider(height: 1, thickness: 1, color: AppColors.divider),
            ),
        ],
      ),
    );
  }
}

// ── Highlight matching text ───────────────────────────────────────────────────

class _HighlightText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle style;

  const _HighlightText({
    required this.text,
    required this.query,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    }

    final lowerText = _normalize(text);
    final lowerQuery = _normalize(query);
    final idx = lowerText.indexOf(lowerQuery);

    if (idx < 0) {
      return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    }

    final before = text.substring(0, idx);
    final match = text.substring(idx, idx + query.length);
    final after = text.substring(idx + query.length);

    return Text.rich(
      TextSpan(children: [
        if (before.isNotEmpty) TextSpan(text: before, style: style),
        TextSpan(
          text: match,
          style: style.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
            backgroundColor: AppColors.primaryLight,
          ),
        ),
        if (after.isNotEmpty) TextSpan(text: after, style: style),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  final String name;
  const _Avatar({required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    final initials = _initialsFromName(name);
    return CircleAvatar(
      radius: 20,
      backgroundColor: const Color(0xFFE5E7EB),
      foregroundImage: (url == null || url!.isEmpty) ? null : NetworkImage(url!),
      child: Text(
        initials,
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

String _initialsFromName(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '';
  if (parts.length == 1) return parts.first.characters.take(1).toString().toUpperCase();
  final first = parts.first.characters.take(1).toString();
  final last = parts.last.characters.take(1).toString();
  return (first + last).toUpperCase();
}

// ── Helper: build sections A/B/C... từ danh sách ApiUserModel ────────────────

List<_ContactSection> _buildSections(List<ApiUserModel> users) {
  final grouped = <String, List<_ContactItem>>{};
  for (final u in users) {
    final letter = _groupLetter(u.fullName);
    (grouped[letter] ??= [])
        .add(_ContactItem(name: u.fullName, avatarUrl: u.avatar, phone: u.phone));
  }
  final letters = grouped.keys.toList()..sort();
  return letters
      .map((l) => _ContactSection(
            letter: l,
            items: grouped[l]!..sort((a, b) => a.name.compareTo(b.name)),
          ))
      .toList();
}

String _groupLetter(String name) {
  final n = _normalize(name);
  if (n.isEmpty) return '#';
  final ch = n.characters.first.toUpperCase();
  return RegExp(r'^[A-Z]$').hasMatch(ch) ? ch : '#';
}

String _normalize(String s) {
  final lower = s.toLowerCase();
  return lower
      .replaceAll(RegExp(r'[àáạảãâầấậẩẫăằắặẳẵ]'), 'a')
      .replaceAll(RegExp(r'[èéẹẻẽêềếệểễ]'), 'e')
      .replaceAll(RegExp(r'[ìíịỉĩ]'), 'i')
      .replaceAll(RegExp(r'[òóọỏõôồốộổỗơờớợởỡ]'), 'o')
      .replaceAll(RegExp(r'[ùúụủũưừứựửữ]'), 'u')
      .replaceAll(RegExp(r'[ỳýỵỷỹ]'), 'y')
      .replaceAll(RegExp(r'[đ]'), 'd')
      .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
      .trim();
}

String _formatRelative(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 60) return '${diff.inMinutes} phút';
  if (diff.inHours < 24) return '${diff.inHours} giờ';
  return '${diff.inDays} ngày';
}

// ── Data wrappers ──────────────────────────────────────────────────────────────

class _ContactSection {
  final String letter;
  final List<_ContactItem> items;
  const _ContactSection({required this.letter, required this.items});
}

class _ContactItem {
  final String name;
  final String? avatarUrl;
  final String phone;
  const _ContactItem({required this.name, required this.avatarUrl, required this.phone});
}

// ── ErrorView ─────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Thử lại'),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
