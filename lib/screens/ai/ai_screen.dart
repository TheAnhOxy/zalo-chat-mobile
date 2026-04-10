import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AiScreen — Tab 2: AI Assistant
// Placeholder — có thể mở CONV_AI từ Chat List để chat với AI
// ─────────────────────────────────────────────────────────────────────────────

class AiScreen extends StatelessWidget {
  const AiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgDark,
        elevation: 0,
        title: ShaderMask(
          shaderCallback: (b) => AppColors.aiGradient.createShader(b),
          child: const Text(
            'AI Assistant',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // AI Logo
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                gradient: AppColors.aiGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.aiGradient1.withOpacity(0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 42),
            ),
            const SizedBox(height: 24),
            const Text(
              'Trợ lý AI',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Chat với AI từ tab Tin nhắn → Trợ lý AI',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 32),
            // Quick start button
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              child: ElevatedButton.icon(
                onPressed: () {
                  // Navigate về tab Tin nhắn (index 0)
                  // Nếu cần navigate tới CONV_AI:
                  // Navigator.pushNamed(context, AppRouter.chatDetail, arguments: {...})
                },
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text(
                  'Bắt đầu trò chuyện',
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
