import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BottomNavBar — 4 tabs (bỏ tab AI, AI dùng floating button)
// ─────────────────────────────────────────────────────────────────────────────

class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const _tabs = [
    _NavTab(
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
      label: 'Tin nhắn',
    ),
    _NavTab(
      icon: Icons.people_outline_rounded,
      activeIcon: Icons.people_rounded,
      label: 'Danh bạ',
    ),
    _NavTab(
      icon: Icons.amp_stories_outlined,
      activeIcon: Icons.amp_stories_rounded,
      label: 'Tin',
    ),
    _NavTab(
      icon: Icons.notifications_none_rounded,
      activeIcon: Icons.notifications_rounded,
      label: 'Thông báo',
    ),
    _NavTab(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      label: 'Cài đặt',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: const Border(
          top: BorderSide(color: AppColors.divider, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: List.generate(_tabs.length, (i) {
              return _NavItemWidget(
                tab: _tabs[i],
                index: i,
                current: currentIndex,
                onTap: onTap,
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ── Single tab item widget ────────────────────────────────────────────────────
class _NavItemWidget extends StatelessWidget {
  final _NavTab tab;
  final int index;
  final int current;
  final ValueChanged<int> onTap;

  const _NavItemWidget({
    required this.tab,
    required this.index,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = index == current;

    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: isActive ? 20 : 0,
                height: 2,
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              Icon(
                isActive ? tab.activeIcon : tab.icon,
                size: 24,
                color: isActive ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(height: 4),
              Text(
                tab.label,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'Inter',
                  color:
                      isActive ? AppColors.primary : AppColors.textSecondary,
                  fontWeight:
                      isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Tab data class ────────────────────────────────────────────────────────────
class _NavTab {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavTab({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
