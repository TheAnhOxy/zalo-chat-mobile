import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../navigation/bottom_nav_bar.dart';
import '../screens/chat/chat_list_screen.dart';
import '../screens/contacts/contacts_screen.dart';
import '../screens/ai/ai_screen.dart';
import '../screens/setting/setting_screen.dart';
import '../screens/notifications/notification_screen.dart';
import '../screens/story/story_feed_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MainNavigator — 4 tabs + Floating AI Button ở góc phải dưới
// ─────────────────────────────────────────────────────────────────────────────

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator>
    with TickerProviderStateMixin {
  int _currentIndex = 0;

  // ── Animation cho FAB pulse ──────────────────────────────────────
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  final List<Widget> _screens = const [
    ChatListScreen(),     // tab 0 — Tin nhắn
    ContactsScreen(),     // tab 1 — Danh bạ
    StoryFeedScreen(),    // tab 2 — Tin
    NotificationScreen(), // tab 3 — Thông báo
    SettingScreen(),      // tab 4 — Cài đặt
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // ── Mở AI chat dạng bottom sheet full height ─────────────────────
  void _openAiChat() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: false,
      builder: (_) => const _AiChatSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Stack(
        children: [
          // ── Màn hình chính ──────────────────────────────────────
          IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),

          // ── Floating AI Button ───────────────────────────────────
          Positioned(
            right: 16,
            bottom: 5,
            child: _FloatingAiButton(
              pulseAnim: _pulseAnim,
              onTap: _openAiChat,
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FloatingAiButton — Nút AI nổi ở góc phải dưới
// ─────────────────────────────────────────────────────────────────────────────

class _FloatingAiButton extends StatelessWidget {
  final Animation<double> pulseAnim;
  final VoidCallback onTap;

  const _FloatingAiButton({
    required this.pulseAnim,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnim,
      builder: (_, child) => Transform.scale(
        scale: pulseAnim.value,
        child: child,
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: AppColors.aiGradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.aiGradient2.withOpacity(0.45),
                blurRadius: 16,
                offset: const Offset(0, 6),
                spreadRadius: 1,
              ),
              BoxShadow(
                color: AppColors.aiGradient1.withOpacity(0.20),
                blurRadius: 24,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AiChatSheet — Bottom sheet chứa AiScreen chiếm ~95% màn hình
// ─────────────────────────────────────────────────────────────────────────────

class _AiChatSheet extends StatelessWidget {
  const _AiChatSheet();

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

    return Container(
      height: screenH * 0.92,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // ── Drag handle ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // ── Nội dung chat AI ─────────────────────────────────────
          const Expanded(
            child: ClipRRect(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(16)),
              child: AiScreen(),
            ),
          ),
        ],
      ),
    );
  }
}
