import 'package:web/web.dart' as web;

String getDeviceType() => 'WEB';

String getDeviceName() {
  final ua = web.window.navigator.userAgent.toLowerCase();

  String os = 'Unknown';
  if (ua.contains('windows')) {
    os = 'Windows';
  }
  if (ua.contains('mac os')) {
    os = 'macOS';
  }
  if (ua.contains('iphone') || ua.contains('ipad')) {
    os = 'iOS';
  }
  if (ua.contains('android')) {
    os = 'Android';
  }
  if (ua.contains('linux')) {
    os = 'Linux';
  }

  String browser = 'Browser';
  if (ua.contains('edg/')) {
    browser = 'Edge';
  } else if (ua.contains('chrome/')) {
    browser = 'Chrome';
  } else if (ua.contains('safari/') && !ua.contains('chrome/')) {
    browser = 'Safari';
  } else if (ua.contains('firefox/')) {
    browser = 'Firefox';
  }

  return '$browser $os';
}
