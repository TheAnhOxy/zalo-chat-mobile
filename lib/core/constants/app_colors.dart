import 'package:flutter/material.dart';

/// Azure Connect — Color System
/// Dark background + Xanh nước biển chủ đạo
class AppColors {
  AppColors._();

  // ── Brand ──────────────────────────────────────────────────────
  static const Color primary      = Color(0xFF2B7FFF); // Xanh chính
  static const Color primaryDark  = Color(0xFF1A5FCC);
  static const Color primaryLight = Color(0xFF5BA3FF);
  static const Color accent       = Color(0xFF00D4FF); // Accent cyan

  // ── Background (Dark theme) ───────────────────────────────────
  static const Color bgDark       = Color(0xFF0F0F1A); // Nền tối nhất
  static const Color bgCard       = Color(0xFF1A1A2E); // Card background
  static const Color bgCardLight  = Color(0xFF22223A); // Card hover
  static const Color bgInput      = Color(0xFF1E1E30); // Input background
  static const Color bgOverlay    = Color(0xFF16213E); // Bottom sheet

  // ── Surface / Divider ─────────────────────────────────────────
  static const Color surface      = Color(0xFF252540);
  static const Color divider      = Color(0xFF2A2A45);
  static const Color border       = Color(0xFF333360);

  // ── Text ──────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B0CC);
  static const Color textHint      = Color(0xFF6060A0);
  static const Color textDisabled  = Color(0xFF404060);

  // ── Chat Bubbles ──────────────────────────────────────────────
  static const Color bubbleMe        = Color(0xFF2B7FFF); // Xanh — tin của mình
  static const Color bubbleMeText    = Color(0xFFFFFFFF);
  static const Color bubbleOther     = Color(0xFF22223A); // Dark — tin người kia
  static const Color bubbleOtherText = Color(0xFFEEEEFF);

  // ── Status ────────────────────────────────────────────────────
  static const Color online    = Color(0xFF00E676); // Xanh lá online
  static const Color away      = Color(0xFFFFB300); // Vàng away
  static const Color offline   = Color(0xFF606080);
  static const Color error     = Color(0xFFFF4C6A);
  static const Color success   = Color(0xFF00C87A);
  static const Color warning   = Color(0xFFFFB300);

  // ── Call Screen ───────────────────────────────────────────────
  static const Color callBg      = Color(0xFF0A0A18);
  static const Color callAccept  = Color(0xFF00C87A);
  static const Color callReject  = Color(0xFFFF4C6A);
  static const Color callMuted   = Color(0xFF333360);

  // ── AI Bot ────────────────────────────────────────────────────
  static const Color aiBubble    = Color(0xFF1A2A4A);
  static const Color aiGradient1 = Color(0xFF4A00E0);
  static const Color aiGradient2 = Color(0xFF2B7FFF);

  // ── Gradients ─────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, Color(0xFF5BA3FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient bgGradient = LinearGradient(
    colors: [Color(0xFF0F0F1A), Color(0xFF1A1A2E)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient aiGradient = LinearGradient(
    colors: [aiGradient1, aiGradient2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Unread Badge ──────────────────────────────────────────────
  static const Color badge = Color(0xFFFF4C6A);
}
