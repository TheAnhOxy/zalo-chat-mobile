import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/themes/app_theme.dart';
import 'navigation/app_router.dart';
import 'services/auth_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,  // icon tối trên nền trắng
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
      theme: AppTheme.light,          // ← đổi từ dark → light
      initialRoute: authService.isLoggedIn
          ? AppRouter.main
          : AppRouter.login,
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}