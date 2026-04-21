import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/themes/app_theme.dart';
import 'navigation/app_navigator.dart';
import 'navigation/app_router.dart';
import 'services/auth_service.dart';
import 'services/socket_service.dart'; // Import thêm SocketService
import 'services/call_service.dart';
import 'services/session_guard_service.dart';

Future<void> main() async {
  // 1. Đảm bảo các dịch vụ hệ thống của Flutter được khởi tạo
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Khôi phục session đã lưu (nếu có) trước khi hiển thị UI
  await authService.restoreSession();

  // 3. Khi người dùng đăng nhập (mới hoặc khôi phục), kết nối socket & call service
  authService.subscribe(() {
    if (authService.isLoggedIn) {
      socketService.connect(authService.userId!);
      callService.init();
      sessionGuardService.start();
    } else {
      sessionGuardService.stop();
    }
  });

  // Nếu session đã được khôi phục, kết nối ngay
  if (authService.isLoggedIn) {
    socketService.connect(authService.userId!);
    callService.init();
    sessionGuardService.start();
  } else {
    sessionGuardService.stop();
  }

  // 4. Cấu hình giao diện thanh trạng thái (Status Bar)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuickChat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      navigatorKey: AppNavigator.navigatorKey,
      
      // 5. Vào thẳng main nếu session còn hợp lệ, ngược lại về login
      initialRoute: authService.isLoggedIn ? AppRouter.main : AppRouter.login,
      
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}