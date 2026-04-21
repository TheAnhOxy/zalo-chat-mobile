import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../common/common_widgets.dart';

class ConversationHeader extends StatelessWidget {
  final String title;
  final String avatarName;
  final String? avatarUrl;
  final bool isOnline;
  final String presenceText;
  final VoidCallback onBackTap;
  final VoidCallback onVoiceCallTap;
  final VoidCallback onVideoCallTap;
  final VoidCallback onAppearanceTap;
  final VoidCallback onInfoTap;

  const ConversationHeader({
    super.key,
    required this.title,
    required this.avatarName,
    required this.avatarUrl,
    required this.isOnline,
    required this.presenceText,
    required this.onBackTap,
    required this.onVoiceCallTap,
    required this.onVideoCallTap,
    required this.onAppearanceTap,
    required this.onInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.primary, size: 22),
            onPressed: onBackTap,
          ),
          SizedBox(
            width: 38,
            height: 38,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AvatarWidget(url: avatarUrl, name: avatarName, size: 38),
                if (isOnline)
                  Positioned(
                    left: -1,
                    bottom: -1,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: AppColors.online,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.bgCard, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  presenceText,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: isOnline ? AppColors.online : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.phone_outlined, color: AppColors.primary, size: 22),
            onPressed: onVoiceCallTap,
          ),
          IconButton(
            icon: const Icon(Icons.videocam_outlined, color: AppColors.primary, size: 24),
            onPressed: onVideoCallTap,
          ),
          IconButton(
            icon: const Icon(Icons.wallpaper_outlined, color: AppColors.primary, size: 22),
            onPressed: onAppearanceTap,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, color: AppColors.primary, size: 22),
            onPressed: onInfoTap,
          ),
        ],
      ),
    );
  }
}
