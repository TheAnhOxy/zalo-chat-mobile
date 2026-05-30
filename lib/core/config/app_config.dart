import 'package:flutter/foundation.dart';
import 'dart:io';

class AppConfig {
  AppConfig._();

  static String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:8081';
    } else if (Platform.isAndroid) {
      const isEmulator = bool.fromEnvironment('EMULATOR', defaultValue: false);
      if (isEmulator) {
        return 'http://10.0.2.2:8081';
      }
      return 'http://192.168.1.4:8081'; // ← đổi chỗ này, IP máy tính của bạn
    } else {
      return 'http://localhost:8081';
    }
  }
}