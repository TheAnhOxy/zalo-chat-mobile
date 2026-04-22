import 'package:flutter/foundation.dart';
import 'dart:io';

class AppConfig {
  AppConfig._();

  static String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:8081';
    } else if (Platform.isAndroid) {
      return 'http://192.168.1.81:8081';//10.0.0.2
    } else {
      return 'http://localhost:8081';
    }
  }
}
