import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/app_colors.dart';

// ── AvatarWidget ─────────────────────────────────────────────────────────────
class AvatarWidget extends StatelessWidget {
  final String? url;
  final String name;
  final double size;
  final bool showOnline;
  final bool isOnline;
  final bool isGroup;

  const AvatarWidget({
    super.key,
    this.url,
    required this.name,
    this.size = 48,
    this.showOnline = false,
    this.isOnline = false,
    this.isGroup = false,
  });

  String get _initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: ClipOval(
            child: url != null && url!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: url!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _buildInitials(),
                    errorWidget: (_, __, ___) => _buildInitials(),
                  )
                : _buildInitials(),
          ),
        ),
        if (showOnline && isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.27,
              height: size * 0.27,
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

  Widget _buildInitials() => Center(
    child: Text(
      _initials,
      style: TextStyle(
        color: Colors.white,
        fontSize: size * 0.35,
        fontWeight: FontWeight.w700,
        fontFamily: 'Inter',
      ),
    ),
  );
}

// ── GroupAvatarWidget (stack 2-3 avatars) ────────────────────────────────────
class GroupAvatarWidget extends StatelessWidget {
  final List<String?> avatarUrls;
  final List<String> names;
  final double size;

  const GroupAvatarWidget({
    super.key,
    required this.avatarUrls,
    required this.names,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final count = avatarUrls.length.clamp(0, 4);
    final mini = size * 0.62;
    final offset = size * 0.38;

    if (count <= 1) {
      return AvatarWidget(url: avatarUrls.firstOrNull, name: names.firstOrNull ?? '', size: size);
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned(
            right: 0, bottom: 0,
            child: AvatarWidget(url: avatarUrls[0], name: names[0], size: mini),
          ),
          Positioned(
            left: 0, top: 0,
            child: AvatarWidget(url: avatarUrls[1], name: names.length > 1 ? names[1] : '', size: mini),
          ),
          if (count > 2)
            Positioned(
              right: offset * 0.3, top: offset * 0.3,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: AppColors.bgDark, shape: BoxShape.circle),
                child: AvatarWidget(url: avatarUrls[2], name: names.length > 2 ? names[2] : '', size: mini * 0.75),
              ),
            ),
        ],
      ),
    );
  }
}

// ── UnreadBadge ───────────────────────────────────────────────────────────────
class UnreadBadge extends StatelessWidget {
  final int count;
  const UnreadBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.badge,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white, fontSize: 11,
          fontWeight: FontWeight.w700, fontFamily: 'Inter',
        ),
      ),
    );
  }
}

// ── GradientButton ────────────────────────────────────────────────────────────
class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double height;
  final bool loading;

  const GradientButton({
    super.key,
    required this.label,
    this.onTap,
    this.height = 50,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.35),
              blurRadius: 16, offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w600, fontFamily: 'Inter',
                  ),
                ),
        ),
      ),
    );
  }
}

// ── SectionDivider ────────────────────────────────────────────────────────────
class ChatDateDivider extends StatelessWidget {
  final String label;
  const ChatDateDivider({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        const Expanded(child: Divider(color: AppColors.divider)),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textHint, fontFamily: 'Inter')),
        const SizedBox(width: 12),
        const Expanded(child: Divider(color: AppColors.divider)),
      ]),
    );
  }
}
