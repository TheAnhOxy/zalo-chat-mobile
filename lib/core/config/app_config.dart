import 'package:flutter/foundation.dart';
import 'dart:io';

class AppConfig {
  AppConfig._();

  static String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:8081';
    } else if (Platform.isAndroid) {
      return 'http://172.20.10.13:8081';
    } else {
      return 'http://localhost:8081';
    }
  }
}
