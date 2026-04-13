import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/themes/app_theme.dart';
import 'navigation/app_router.dart';
import 'services/auth_service.dart';
import 'services/socket_service.dart'; // Import thêm SocketService
import 'services/call_service.dart';

void main() {
  // 1. Đảm bảo các dịch vụ hệ thống của Flutter được khởi tạo
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Đọc biến USER_TYPE từ lệnh run: --dart-define=USER_TYPE=2
  const String userType = String.fromEnvironment('USER_TYPE', defaultValue: '1');
  
  // 3. Thực hiện đăng nhập giả lập
  if (userType == '2') {
    authService.loginAsUser2();
  } else {
    authService.loginAsUser1();
  }

  // 4. KÍCH HOẠT SOCKET REAL-TIME
  // Ngay khi có userId từ authService, ta phải kết nối socket ngay lập tức
  if (authService.isLoggedIn) {
    socketService.connect(authService.userId!);
    callService.init();
  }

  // 5. Cấu hình giao diện thanh trạng thái (Status Bar)
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
      title: 'Azure Connect',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      
      // 6. Điều hướng dựa trên trạng thái đăng nhập
      initialRoute: authService.isLoggedIn ? AppRouter.main : AppRouter.login,
      
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}