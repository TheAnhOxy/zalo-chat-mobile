import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/themes/app_theme.dart';
import 'navigation/app_router.dart';
import 'services/auth_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );
  runApp(const AzureConnectApp());
}

class AzureConnectApp extends StatefulWidget {
  const AzureConnectApp({super.key});

  @override
  State<AzureConnectApp> createState() => _AzureConnectAppState();
}

class _AzureConnectAppState extends State<AzureConnectApp> {
  late final void Function() _unsubscribe;

  @override
  void initState() {
    super.initState();
    // Lắng nghe AuthService — tự rebuild khi login/logout
    _unsubscribe = authService.subscribe(() => setState(() {}));
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Azure Connect',
      debugShowCheckedModeBanner: false,

      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,

      home: authService.isLoggedIn
        ? AppRouter.getMainScreen()
        : AppRouter.getLoginScreen(),
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}
