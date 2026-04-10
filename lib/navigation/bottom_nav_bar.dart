import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BottomNavBar — Tách riêng để dễ sửa tab label, icon, thứ tự
//
// Muốn thêm tab mới: thêm vào _tabs list bên dưới là xong
// Muốn đổi icon: sửa _NavTab ở cuối file
// ─────────────────────────────────────────────────────────────────────────────

class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  // ── Tab definitions — sửa ở đây nếu muốn đổi tab ────────────
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
      icon: Icons.notifications_none_rounded,
      activeIcon: Icons.notifications_rounded,
      label: 'Thông báo',
    ),
    _NavTab(
      icon: Icons.auto_awesome_outlined,
      activeIcon: Icons.auto_awesome,
      label: 'AI',
      isAI: true,
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
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 12,
            offset: Offset(0, -2),
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
              // Active indicator dot
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

              // Icon
              _buildIcon(isActive),

              const SizedBox(height: 4),

              // Label
              Text(
                tab.label,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'Inter',
                  color: isActive ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(bool isActive) {
    final icon = Icon(
      isActive ? tab.activeIcon : tab.icon,
      size: 24,
      color: isActive ? AppColors.primary : AppColors.textSecondary,
    );

    // AI tab dùng gradient khi active
    if (tab.isAI && isActive) {
      return ShaderMask(
        shaderCallback: (b) => AppColors.aiGradient.createShader(b),
        child: Icon(tab.activeIcon, size: 24, color: Colors.white),
      );
    }

    return icon;
  }
}

// ── Tab data class ────────────────────────────────────────────────────────────
class _NavTab {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isAI;

  const _NavTab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.isAI = false,
  });
}
