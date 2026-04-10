import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../navigation/bottom_nav_bar.dart';
import '../screens/chat/chat_list_screen.dart';
import '../screens/contacts/contacts_screen.dart';
import '../screens/ai/ai_screen.dart';
import '../screens/setting/setting_screen.dart';
import '../screens/notifications/notification_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MainNavigator — Shell quản lý Bottom Nav + IndexedStack
//
// Chỉ làm nhiệm vụ giữ tab hiện tại.
// Từng tab screen nằm trong file riêng:
//   0 → lib/screens/chat/chat_list_screen.dart
//   1 → lib/screens/contacts/contacts_screen.dart
//   2 → lib/screens/notifications/notifications_screen.dart
//   3 → lib/screens/ai/ai_screen.dart
//   4 → lib/screens/profile/profile_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    ChatListScreen(),  // tab 0 — Tin nhắn
    ContactsScreen(),  // tab 1 — Danh bạ
    NotificationScreen(), // tab 2 — Thông báo
    AiScreen(),        // tab 3 — AI
    SettingScreen(),   // tab 4 — Setting
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}
