import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../services/contacts_api_service.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  List<ApiFriendRequest>? _received;
  List<ApiFriendRequest>? _sent;
  String? _errorReceived;
  String? _errorSent;

  // Track đang xử lý request nào
  final Set<String> _processing = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final userId = authService.userId ?? '';
    final results = await Future.wait([
      ContactsApiService.instance.fetchReceivedRequests(userId),
      ContactsApiService.instance.fetchSentRequests(userId),
    ]);
    if (!mounted) return;
    setState(() {
      _received = results[0].data ?? [];
      _errorReceived = results[0].error;
      _sent = results[1].data ?? [];
      _errorSent = results[1].error;
    });
  }

  Future<void> _accept(ApiFriendRequest req) async {
    setState(() => _processing.add(req.friendshipId));
    final ok = await ContactsApiService.instance.acceptFriendRequest(req.friendshipId);
    if (!mounted) return;
    setState(() {
      _processing.remove(req.friendshipId);
      if (ok) _received?.remove(req);
    });
    if (ok) {
      _showToast('Đã chấp nhận lời mời từ ${req.user.fullName}');
    } else {
      _showToast('Có lỗi xảy ra, vui lòng thử lại');
    }
  }

  Future<void> _reject(ApiFriendRequest req) async {
    setState(() => _processing.add(req.friendshipId));
    final ok = await ContactsApiService.instance.rejectFriendRequest(req.friendshipId);
    if (!mounted) return;
    setState(() {
      _processing.remove(req.friendshipId);
      if (ok) _received?.remove(req);
    });
    if (ok) {
      _showToast('Đã từ chối lời mời từ ${req.user.fullName}');
    } else {
      _showToast('Có lỗi xảy ra, vui lòng thử lại');
    }
  }

  Future<void> _cancelSent(ApiFriendRequest req) async {
    final confirm = await _showConfirmDialog(
      'Thu hồi lời mời kết bạn với ${req.user.fullName}?',
    );
    if (!confirm) return;

    setState(() => _processing.add(req.friendshipId));
    final ok = await ContactsApiService.instance.cancelSentRequest(req.friendshipId);
    if (!mounted) return;
    setState(() {
      _processing.remove(req.friendshipId);
      if (ok) _sent?.remove(req);
    });
    if (ok) {
      _showToast('Đã thu hồi lời mời kết bạn');
    }
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF1C1C1C),
      ),
    );
  }

  Future<bool> _showConfirmDialog(String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Xác nhận'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Huỷ'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Đồng ý',
                  style: TextStyle(color: AppColors.primary),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final receivedCount = _received?.length ?? 0;

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
          'Lời mời kết bạn',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {},
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          tabs: [
            Tab(text: receivedCount > 0 ? 'Đã nhận  $receivedCount' : 'Đã nhận'),
            const Tab(text: 'Đã gửi'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ReceivedTab(
            requests: _received,
            error: _errorReceived,
            processing: _processing,
            onAccept: _accept,
            onReject: _reject,
            onRetry: _loadAll,
          ),
          _SentTab(
            requests: _sent,
            error: _errorSent,
            processing: _processing,
            onCancel: _cancelSent,
            onRetry: _loadAll,
          ),
        ],
      ),
    );
  }
}

// ── Received Tab ──────────────────────────────────────────────────────────────

class _ReceivedTab extends StatelessWidget {
  final List<ApiFriendRequest>? requests;
  final String? error;
  final Set<String> processing;
  final Future<void> Function(ApiFriendRequest) onAccept;
  final Future<void> Function(ApiFriendRequest) onReject;
  final VoidCallback onRetry;

  const _ReceivedTab({
    required this.requests,
    required this.error,
    required this.processing,
    required this.onAccept,
    required this.onReject,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (requests == null && error == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (error != null && (requests == null || requests!.isEmpty)) {
      return _ErrorView(message: error!, onRetry: onRetry);
    }

    if (requests!.isEmpty) {
      return _EmptyView(
        message: 'Chưa có lời mời kết bạn nào',
        icon: Icons.person_add_disabled_outlined,
      );
    }

    // Nhóm theo thời gian: tháng hiện tại và cũ hơn
    final now = DateTime.now();
    final recent = requests!
        .where((r) =>
            r.createdAt.year == now.year && r.createdAt.month == now.month)
        .toList();
    final older = requests!
        .where((r) =>
            !(r.createdAt.year == now.year && r.createdAt.month == now.month))
        .toList();

    return RefreshIndicator(
      onRefresh: () async => onRetry(),
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (recent.isNotEmpty) ...[
            _SectionHeader(
              title: _formatMonth(recent.first.createdAt),
            ),
            ...recent.map((r) => _ReceivedRequestTile(
                  request: r,
                  isProcessing: processing.contains(r.friendshipId),
                  onAccept: () => onAccept(r),
                  onReject: () => onReject(r),
                )),
          ],
          if (older.isNotEmpty) ...[
            const _SectionHeader(title: 'Cũ hơn'),
            ...older.map((r) => _ReceivedRequestTile(
                  request: r,
                  isProcessing: processing.contains(r.friendshipId),
                  onAccept: () => onAccept(r),
                  onReject: () => onReject(r),
                )),
          ],
        ],
      ),
    );
  }

  String _formatMonth(DateTime dt) {
    return 'Tháng ${dt.month.toString().padLeft(2, '0')}, ${dt.year}';
  }
}

// ── Sent Tab ──────────────────────────────────────────────────────────────────

class _SentTab extends StatelessWidget {
  final List<ApiFriendRequest>? requests;
  final String? error;
  final Set<String> processing;
  final Future<void> Function(ApiFriendRequest) onCancel;
  final VoidCallback onRetry;

  const _SentTab({
    required this.requests,
    required this.error,
    required this.processing,
    required this.onCancel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (requests == null && error == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (error != null && (requests == null || requests!.isEmpty)) {
      return _ErrorView(message: error!, onRetry: onRetry);
    }

    if (requests!.isEmpty) {
      return _EmptyView(
        message: 'Chưa gửi lời mời kết bạn nào',
        icon: Icons.send_outlined,
        showIllustration: true,
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRetry(),
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: requests!
            .map((r) => _SentRequestTile(
                  request: r,
                  isProcessing: processing.contains(r.friendshipId),
                  onCancel: () => onCancel(r),
                ))
            .toList(),
      ),
    );
  }
}

// ── Received Request Tile ─────────────────────────────────────────────────────

class _ReceivedRequestTile extends StatelessWidget {
  final ApiFriendRequest request;
  final bool isProcessing;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _ReceivedRequestTile({
    required this.request,
    required this.isProcessing,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final u = request.user;
    return Container(
      color: AppColors.bgCard,
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          _Avatar(url: u.avatar, name: u.fullName, isOnline: u.isOnline),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + date
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        u.fullName,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      _formatDate(request.createdAt),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // Source
                const Text(
                  'Muốn kết bạn với bạn',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                // Buttons
                isProcessing
                    ? const SizedBox(
                        height: 32,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: _OutlineButton(
                              label: 'TỪ CHỐI',
                              onTap: onReject,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _FilledButton(
                              label: 'ĐỒNG Ý',
                              onTap: onAccept,
                            ),
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }
}

// ── Sent Request Tile ─────────────────────────────────────────────────────────

class _SentRequestTile extends StatelessWidget {
  final ApiFriendRequest request;
  final bool isProcessing;
  final VoidCallback onCancel;

  const _SentRequestTile({
    required this.request,
    required this.isProcessing,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final u = request.user;
    return Container(
      color: AppColors.bgCard,
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(url: u.avatar, name: u.fullName, isOnline: u.isOnline),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  u.fullName,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Đã gửi lời mời • ${_formatDate(request.createdAt)}',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                isProcessing
                    ? const SizedBox(
                        height: 32,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      )
                    : _OutlineButton(
                        label: 'THU HỒI',
                        onTap: onCancel,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }
}

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgDark,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
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

// ── Buttons ───────────────────────────────────────────────────────────────────

class _FilledButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _FilledButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _OutlineButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.bgInput,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Avatar ────────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String url;
  final String name;
  final bool isOnline;
  const _Avatar({required this.url, required this.name, required this.isOnline});

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    return Stack(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: AppColors.primaryLight,
          foregroundImage: url.isNotEmpty ? NetworkImage(url) : null,
          child: Text(
            initials,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.online,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  String _initials(String n) {
    final parts = n.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

// ── Empty / Error Views ───────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  final String message;
  final IconData icon;
  final bool showIllustration;

  const _EmptyView({
    required this.message,
    required this.icon,
    this.showIllustration = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: AppColors.primary.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

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
            const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: AppColors.textSecondary)),
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
