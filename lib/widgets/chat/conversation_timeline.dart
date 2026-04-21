import 'package:flutter/material.dart';

import '../../core/utils/date_utils.dart' as du;
import '../../data/models/chat_item.dart';
import '../../data/models/models.dart';
import '../common/common_widgets.dart';
import 'conversation_shared_bubbles.dart';

class ConversationTimeline extends StatelessWidget {
  final ScrollController controller;
  final List<ChatItem> items;
  final bool showTypingIndicator;
  final EdgeInsets padding;
  final Widget Function(MessageModel message, int index) messageBuilder;
  final Widget Function(CallModel call, int index) callBuilder;
  final Widget Function()? typingIndicatorBuilder;

  const ConversationTimeline({
    super.key,
    required this.controller,
    required this.items,
    required this.messageBuilder,
    required this.callBuilder,
    this.showTypingIndicator = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.typingIndicatorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && !showTypingIndicator) {
      return const SizedBox.shrink();
    }

    final totalCount = items.length + 1;
    final typingWidget =
        typingIndicatorBuilder ?? () => const ConversationTypingIndicator();

    return ListView.builder(
      controller: controller,
      padding: padding,
      itemCount: totalCount,
      itemBuilder: (_, index) {
        if (index == items.length) {
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.08),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: showTypingIndicator
                ? KeyedSubtree(
                    key: const ValueKey('typing_on'),
                    child: typingWidget(),
                  )
                : const SizedBox(key: ValueKey('typing_off')),
          );
        }

        final item = items[index];
        final previousItem = index > 0 ? items[index - 1] : null;
        final showDate =
            previousItem == null ||
            !du.DateUtils.isSameDay(previousItem.createdAt, item.createdAt);

        return Column(
          children: [
            if (showDate)
              ChatDateDivider(
                label: du.DateUtils.formatDateSeparator(item.createdAt),
              ),
            if (item.type == ChatItemType.call)
              callBuilder(item.call!, index)
            else
              messageBuilder(item.message!, index),
          ],
        );
      },
    );
  }
}
