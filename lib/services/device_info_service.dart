import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'device_info_platform_stub.dart'
    if (dart.library.html) 'device_info_platform_web.dart'
    if (dart.library.io) 'device_info_platform_io.dart';

class DeviceInfoService {
  DeviceInfoService._internal();

  static final DeviceInfoService _instance = DeviceInfoService._internal();
  factory DeviceInfoService() => _instance;

  static const _keyDeviceFingerprint = 'device_fingerprint';
  final _uuid = const Uuid();

  Future<String> getDeviceFingerprint() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keyDeviceFingerprint);
    if (saved != null && saved.trim().isNotEmpty) return saved;

    final fingerprint = _uuid.v4();
    await prefs.setString(_keyDeviceFingerprint, fingerprint);
    return fingerprint;
  }

  String get deviceType => getDeviceType();
  String get deviceName => getDeviceName();
}

final deviceInfoService = DeviceInfoService();
