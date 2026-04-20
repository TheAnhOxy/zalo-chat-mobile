import 'package:flutter/foundation.dart';
import 'dart:io';

class AppConfig {
  AppConfig._();

  static String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:8081';
    } else if (Platform.isAndroid) {
      return 'http://10.122.169.187:8081';
    } else {
      return 'http://localhost:8081';
    }
  }
}
