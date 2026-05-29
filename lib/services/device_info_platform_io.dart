import 'dart:io';

String getDeviceType() {
  if (Platform.isAndroid) return 'ANDROID';
  if (Platform.isIOS) return 'IOS';
  return 'WEB';
}

String getDeviceName() {
  if (Platform.isAndroid) return 'Android Device';
  if (Platform.isIOS) return 'iOS Device';
  if (Platform.isWindows) return 'Windows';
  if (Platform.isMacOS) return 'macOS';
  if (Platform.isLinux) return 'Linux';
  return 'Device';
}
