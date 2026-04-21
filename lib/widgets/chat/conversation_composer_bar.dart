import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

class ConversationComposerAction {
  final IconData icon;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onTapDown;
  final GestureLongPressStartCallback? onLongPressStart;
  final bool enabled;
  final Color? color;

  const ConversationComposerAction({
    required this.icon,
    this.onTap,
    this.onTapDown,
    this.onLongPressStart,
    this.enabled = true,
    this.color,
  });
}

class ConversationComposerBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final List<ConversationComposerAction> actions;
  final VoidCallback? onEmojiTap;
  final VoidCallback? onSend;
  final VoidCallback? onEmptyActionTap;
  final Color backgroundColor;
  final Color inputColor;
  final EdgeInsets padding;

  const ConversationComposerBar({
    super.key,
    required this.controller,
    this.focusNode,
    required this.hintText,
    required this.actions,
    this.onEmojiTap,
    this.onSend,
    this.onEmptyActionTap,
    this.backgroundColor = AppColors.bgCard,
    this.inputColor = AppColors.bgInput,
    this.padding = const EdgeInsets.fromLTRB(10, 6, 10, 10),
  });

  @override
  State<ConversationComposerBar> createState() => _ConversationComposerBarState();
}

class _ConversationComposerBarState extends State<ConversationComposerBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant ConversationComposerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChanged);
      widget.controller.addListener(_handleTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChanged);
    super.dispose();
  }

  void _handleTextChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.trim().isNotEmpty;

    Widget actionButton(ConversationComposerAction action) {
      final color = action.color ?? AppColors.primary;
      return GestureDetector(
        onTap: action.enabled ? action.onTap : null,
        onTapDown: action.enabled ? action.onTapDown : null,
        onLongPressStart: action.enabled ? action.onLongPressStart : null,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            action.icon,
            color: action.enabled ? color : AppColors.textHint,
            size: 24,
          ),
        ),
      );
    }

    return Container(
      color: widget.backgroundColor,
      padding: widget.padding,
      child: Row(
        children: [
          ...widget.actions.map(actionButton),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 38, maxHeight: 120),
              decoration: BoxDecoration(
                color: widget.inputColor,
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                maxLines: null,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: AppColors.textHint,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  suffixIcon: InkResponse(
                    onTap: widget.onEmojiTap,
                    radius: 22,
                    child: const Icon(
                      Icons.sentiment_satisfied_alt_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          InkResponse(
            onTap: hasText ? widget.onSend : widget.onEmptyActionTap,
            radius: 24,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                hasText ? Icons.send_rounded : Icons.thumb_up,
                color: AppColors.primary,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
