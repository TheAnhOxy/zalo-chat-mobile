import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

class ConversationVoiceRecordingBar extends StatelessWidget {
  final bool isCancelHint;
  final double dragOffset;
  final List<double> waveValues;
  final String durationText;
  final VoidCallback onCancelTap;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final ValueChanged<DragEndDetails> onDragEnd;
  final VoidCallback onSendTap;

  const ConversationVoiceRecordingBar({
    super.key,
    required this.isCancelHint,
    required this.dragOffset,
    required this.waveValues,
    required this.durationText,
    required this.onCancelTap,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onSendTap,
  });

  @override
  Widget build(BuildContext context) {
    final waveColor = isCancelHint ? AppColors.error : AppColors.primary;

    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isCancelHint
                ? 'Thả tay để hủy'
                : 'Vuốt sang trái để hủy, hoặc bấm gửi để gửi',
            style: TextStyle(
              fontSize: 13,
              color: isCancelHint ? AppColors.error : AppColors.textSecondary,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              InkResponse(
                onTap: onCancelTap,
                radius: 24,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.delete_outline, color: AppColors.error, size: 30),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onHorizontalDragUpdate: onDragUpdate,
                  onHorizontalDragEnd: onDragEnd,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    transform: Matrix4.translationValues(
                      dragOffset.clamp(-60, 0).toDouble(),
                      0,
                      0,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.bgInput,
                      borderRadius: BorderRadius.circular(36),
                      border: Border.all(
                        color: isCancelHint
                            ? AppColors.error.withOpacity(0.45)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(
                            color: AppColors.bgCardLight,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isCancelHint ? Icons.close_rounded : Icons.mic_rounded,
                            color: isCancelHint ? AppColors.error : AppColors.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: waveValues
                                .map(
                                  (v) => Container(
                                    width: 3,
                                    height: 8 + (v * 20),
                                    margin: const EdgeInsets.symmetric(horizontal: 1.2),
                                    decoration: BoxDecoration(
                                      color: waveColor.withOpacity(0.9),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          durationText,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              InkResponse(
                onTap: onSendTap,
                radius: 24,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
