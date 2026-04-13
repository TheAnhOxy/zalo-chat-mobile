import 'package:flutter/material.dart';
import '../screens/auth/login_screen.dart';
import '../screens/chat/chat_detail_screen.dart';
import '../screens/call/voice_call_screen.dart';
import '../screens/call/video_call_screen.dart';
import '../screens/group/group_detail_screen.dart';
import '../data/models/models.dart';
import '../navigation/main_navigator.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../widgets/call/incoming_call_overlay.dart';


// ─────────────────────────────────────────────────────────────────────────────
// AppRouter — Tập trung tất cả route vào 1 chỗ

// Cách dùng trong main.dart:
//   MaterialApp(
//     initialRoute: AppRouter.login,
//     onGenerateRoute: AppRouter.generateRoute,
//   )
// ─────────────────────────────────────────────────────────────────────────────

class AppRouter {
  AppRouter._();

  static Widget getMainScreen() => const MainNavigator();
  static Widget getLoginScreen() => const LoginScreen();

  // ── Route Names ─────────────────────────────────────────────
  static const String login = '/login';
  static const String main = '/main'; // Bottom nav shell
  static const String chatDetail = '/chat/detail';
  static const String voiceCall = '/call/voice';
  static const String videoCall = '/call/video';
  static const String groupDetail = '/group/detail';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';

  // ── Route Generator ─────────────────────────────────────────
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      // ── Auth ──────────────────────────────────────────────────
      case login:
        return _fade(const LoginScreen(onLoginSuccess: _noOp));

      case register:
        return _fade(const RegisterScreen());

      case forgotPassword:
        return _fade(const ForgotPasswordScreen());

      // ── Main Shell (Bottom Nav) ───────────────────────────────
      case main:
        return _fade(IncomingCallListener(child: const MainNavigator()));

      // ── Chat 1-1 ──────────────────────────────────────────────
      case chatDetail:
        final args = settings.arguments as Map<String, dynamic>;
        return _slide(
          ChatDetailScreen(
            conversationId: args['conversationId'] as String,
            otherUser: args['otherUser'] as UserModel?,
            conversation: args['conversation'] as ConversationModel,
          ),
        );

      // ── Voice Call ────────────────────────────────────────────
      case voiceCall:
        final args = settings.arguments as Map<String, dynamic>;
        return _fullscreen(
          VoiceCallScreen(
            otherUser: args['otherUser'] as UserModel,
            isIncoming: args['isIncoming'] as bool? ?? false,
          ),
        );

      // ── Video Call ────────────────────────────────────────────
      case videoCall:
        final args = settings.arguments as Map<String, dynamic>;
        return _fullscreen(
          VideoCallScreen(
            otherUser: args['otherUser'] as UserModel,
            isIncoming: args['isIncoming'] as bool? ?? false,
          ),
        );

      // ── Group Chat ────────────────────────────────────────────
      case groupDetail:
        final args = settings.arguments as Map<String, dynamic>;
        return _slide(
          GroupDetailScreen(
            conversation: args['conversation'] as ConversationModel,
          ),
        );

      // ── 404 ───────────────────────────────────────────────────
      default:
        return _fade(
          const Scaffold(body: Center(child: Text('Route not found'))),
        );
    }
  }

  // ── Transition helpers ───────────────────────────────────────

  /// Slide từ phải — dùng cho màn hình con (chat detail, call...)
  static PageRoute _slide(Widget page) => PageRouteBuilder(
    pageBuilder: (_, a, _) => page,
    transitionsBuilder: (_, a, _, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
    transitionDuration: const Duration(milliseconds: 280),
  );

  /// Fade — dùng cho màn hình chính (login, main)
  static PageRoute _fade(Widget page) => PageRouteBuilder(
    pageBuilder: (_, a, _) => page,
    transitionsBuilder: (_, a, _, child) =>
        FadeTransition(opacity: a, child: child),
    transitionDuration: const Duration(milliseconds: 220),
  );

  /// Full screen (không animation rõ) — dùng cho call
  static PageRoute _fullscreen(Widget page) => PageRouteBuilder(
    pageBuilder: (_, a, _) => page,
    transitionsBuilder: (_, a, _, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
    transitionDuration: const Duration(milliseconds: 350),
    fullscreenDialog: true,
  );

  // Internal helper vì LoginScreen cần callback
  static void _noOp() {}
}

// ─────────────────────────────────────────────────────────────────────────────
// HOW TO NAVIGATE từ bất kỳ screen nào:
//
// Chat Detail:
//   Navigator.pushNamed(context, AppRouter.chatDetail, arguments: {
//     'conversationId': conv.id,
//     'otherUser': otherUser,
//     'conversation': conv,
//   });
//
// Voice Call:
//   Navigator.pushNamed(context, AppRouter.voiceCall, arguments: {
//     'otherUser': user,
//     'isIncoming': false,
//   });
//
// Video Call:
//   Navigator.pushNamed(context, AppRouter.videoCall, arguments: {
//     'otherUser': user,
//     'isIncoming': false,
//   });
// ─────────────────────────────────────────────────────────────────────────────
