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

import '../screens/auth/otp_verify_screen.dart';
import '../screens/auth/post_login_security_screen.dart';
import '../screens/auth/login_challenge_waiting_screen.dart';
import '../screens/setting/account_security_screen.dart';
import '../screens/setting/device_sessions_screen.dart';
import '../screens/setting/edit_profile_screen.dart';
import '../screens/setting/privacy_screen.dart';
import '../screens/contacts/add_friend_screen.dart';
import '../screens/contacts/found_user_screen.dart';
import '../screens/contacts/friend_requests_screen.dart';
import '../screens/contacts/birthday_screen.dart';
import '../screens/contacts/send_friend_request_screen.dart';
import '../screens/contacts/qr_scan_screen.dart';
import '../services/contacts_api_service.dart';
import '../data/models/story_model.dart';
import '../screens/story/create_story_screen.dart';
import '../screens/story/story_viewer_screen.dart';

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
  static const String otpVerify = '/otp-verify';
  static const String postLoginSecurity = '/post-login-security';
  static const String loginChallengeWaiting = '/auth/login-challenge-waiting';
  static const String accountSecurity = '/settings/account-security';
  static const String deviceSessions = '/settings/device-sessions';
  static const String editProfile = '/settings/edit-profile';
  static const String privacy = '/settings/privacy';
  static const String addFriend = '/contacts/add-friend';
  static const String foundUser = '/contacts/found-user';
  static const String sendFriendRequest = '/contacts/send-friend-request';
  static const String friendRequests = '/contacts/friend-requests';
  static const String birthday = '/contacts/birthday';
  static const String qrScan = '/contacts/qr-scan';
  static const String createStory = '/create-story';
  static const String storyViewer = '/story-viewer';

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

      case otpVerify:
        final args = settings.arguments as OtpVerifyArguments;
        return _fade(OtpVerifyScreen(args: args));

      case postLoginSecurity:
        final args = settings.arguments as PostLoginSecurityArguments;
        return _fade(PostLoginSecurityScreen(args: args));

      case loginChallengeWaiting:
        final args = settings.arguments as LoginChallengeWaitingArguments;
        return _fade(LoginChallengeWaitingScreen(args: args));

      case accountSecurity:
        return _fade(const AccountSecurityScreen());

      case deviceSessions:
        return _fade(const DeviceSessionsScreen());

      case editProfile:
        return _fade(const EditProfileScreen());

      case privacy:
        return _fade(const PrivacyScreen());

      case addFriend:
        return _slide(const AddFriendScreen());

      case foundUser:
        final user = settings.arguments as ApiUserModel;
        return _slide(FoundUserScreen(user: user));

      case sendFriendRequest:
        final user = settings.arguments as ApiUserModel;
        return _slide(SendFriendRequestScreen(targetUser: user));

      case friendRequests:
        return _slide(const FriendRequestsScreen());

      case birthday:
        return _slide(const BirthdayScreen());

      case qrScan:
        return _fullscreen(const QrScanScreen());

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

      // ── Story ─────────────────────────────────────────────────
      case createStory:
        return _slide(const CreateStoryScreen());
        
      case storyViewer:
        final args = settings.arguments as Map<String, dynamic>;
        return _fullscreen(
          StoryViewerScreen(
            stories: args['stories'] as List<ApiStoryModel>,
            initialIndex: args['initialIndex'] as int? ?? 0,
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
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
    transitionDuration: const Duration(milliseconds: 280),
  );

  /// Fade — dùng cho màn hình chính (login, main)
  static PageRoute _fade(Widget page) => PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(opacity: animation, child: child),
    transitionDuration: const Duration(milliseconds: 220),
  );

  /// Full screen (không animation rõ) — dùng cho call
  static PageRoute _fullscreen(Widget page) => PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
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
