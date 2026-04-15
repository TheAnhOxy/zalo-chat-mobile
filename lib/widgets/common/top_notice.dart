import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

void showTopNotice(
  BuildContext context, {
  required String message,
  bool isError = false,
  Duration duration = const Duration(seconds: 2),
}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _TopNoticeOverlay(
      message: message,
      isError: isError,
      duration: duration,
      onFinished: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );

  overlay.insert(entry);
}

class _TopNoticeOverlay extends StatefulWidget {
  final String message;
  final bool isError;
  final Duration duration;
  final VoidCallback onFinished;

  const _TopNoticeOverlay({
    required this.message,
    required this.isError,
    required this.duration,
    required this.onFinished,
  });

  @override
  State<_TopNoticeOverlay> createState() => _TopNoticeOverlayState();
}

class _TopNoticeOverlayState extends State<_TopNoticeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
    );

    _slide = Tween<Offset>(
      begin: const Offset(0, -0.24),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    _controller.forward();
    Future.delayed(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (_closing) return;
    _closing = true;
    if (mounted) {
      await _controller.reverse();
    }
    widget.onFinished();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 10;

    return Material(
      color: Colors.transparent,
      child: IgnorePointer(
        ignoring: true,
        child: Stack(
          children: [
            Positioned(
              top: top,
              left: 14,
              right: 14,
              child: FadeTransition(
                opacity: _fade,
                child: SlideTransition(
                  position: _slide,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      gradient: widget.isError
                          ? const LinearGradient(
                              colors: [Color(0xFFF55858), Color(0xFFE63A3A)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 14,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          widget.isError
                              ? Icons.error_outline_rounded
                              : Icons.check_circle_outline_rounded,
                          color: Colors.white,
                          size: 19,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
