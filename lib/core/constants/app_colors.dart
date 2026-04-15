import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Brand ──────────────────────────────────────────────────────
  static const Color primary      = Color(0xFF388E3C);
  static const Color primaryDark  = Color(0xFF1B5E20);
  static const Color primaryLight = Color(0xFFE8F5E9);
  static const Color accent       = Color(0xFF66BB6A);

  // ── Background (Light theme) ──────────────────────────────────
  static const Color bgDark       = Color(0xFFF0F2F5); // Nền chính — xám nhạt
  static const Color bgCard       = Color(0xFFFFFFFF); // Card = trắng
  static const Color bgCardLight  = Color(0xFFF5F7FA); // Card hover
  static const Color bgInput      = Color(0xFFF0F2F5); // Input background
  static const Color bgOverlay    = Color(0xFFFFFFFF); // Bottom sheet

  // ── Surface / Divider ─────────────────────────────────────────
  static const Color surface      = Color(0xFFFFFFFF);
  static const Color divider      = Color(0xFFE4E6EB);
  static const Color border       = Color(0xFFDDE1E7);

  // ── Text ──────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF111111);
  static const Color textSecondary = Color(0xFF65676B);
  static const Color textHint      = Color(0xFF9EA3A8);
  static const Color textDisabled  = Color(0xFFBCC0C4);

  // ── Chat Bubbles ──────────────────────────────────────────────
  static const Color bubbleMe        = Color(0xFF388E3C);
  static const Color bubbleMeText    = Color(0xFFFFFFFF);
  static const Color bubbleOther     = Color(0xFFFFFFFF);
  static const Color bubbleOtherText = Color(0xFF111111);

  // ── Status ────────────────────────────────────────────────────
  static const Color online    = Color(0xFF31A24C);
  static const Color away      = Color(0xFFFFB300);
  static const Color offline   = Color(0xFF9EA3A8);
  static const Color error     = Color(0xFFE41E3F);
  static const Color success   = Color(0xFF31A24C);
  static const Color warning   = Color(0xFFFFB300);

  // ── Call Screen ───────────────────────────────────────────────
  static const Color callBg      = Color(0xFF1A3A1A);
  static const Color callAccept  = Color(0xFF31A24C);
  static const Color callReject  = Color(0xFFE41E3F);
  static const Color callMuted   = Color(0xFF2E4A2E);

  // ── AI Bot ────────────────────────────────────────────────────
  static const Color aiBubble    = Color(0xFFE8F5E9);
  static const Color aiGradient1 = Color(0xFF1B5E20);
  static const Color aiGradient2 = Color(0xFF388E3C);

  // ── Gradients ─────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, Color(0xFF81C784)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient bgGradient = LinearGradient(
    colors: [Color(0xFFF0F2F5), Color(0xFFFFFFFF)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient aiGradient = LinearGradient(
    colors: [aiGradient1, aiGradient2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Unread Badge ──────────────────────────────────────────────
  static const Color badge = Color(0xFFE41E3F);
}