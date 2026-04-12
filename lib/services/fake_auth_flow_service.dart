import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/models/models.dart';

class FakeAuthException implements Exception {
  final String message;
  const FakeAuthException(this.message);

  @override
  String toString() => message;
}

class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiredAt;

  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiredAt,
  });
}

class OtpSession {
  final String sessionId;
  final String email;
  final DateTime expiredAt;

  const OtpSession({
    required this.sessionId,
    required this.email,
    required this.expiredAt,
  });
}

class LoginResult {
  final UserModel user;
  final AuthTokens tokens;

  const LoginResult({required this.user, required this.tokens});
}

class FakeAuthFlowService {
  FakeAuthFlowService._internal();

  static final FakeAuthFlowService _instance = FakeAuthFlowService._internal();
  factory FakeAuthFlowService() => _instance;

  static const String emailOtpPurposeRegister = 'register';
  static const String emailOtpPurposeForgotPassword = 'forgot_password';
  static const String phoneOtpPurposeLogin = 'phone_login';

  static const String _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8081/api/v1',
  );

  final http.Client _client = http.Client();

  String get _baseUrl => _defaultBaseUrl;

  bool isValidEmail(String email) {
    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return regex.hasMatch(email.trim());
  }

  bool isValidVietnamPhone(String phone) {
    final normalized = normalizePhone(phone);
    final regex = RegExp(r'^(0|84)(3|5|7|8|9)[0-9]{8}$');
    return regex.hasMatch(normalized);
  }

  String normalizePhone(String value) {
    return value.replaceAll(RegExp(r'\s+'), '');
  }

  bool isStrongPassword(String password) {
    final minLength = password.length >= 8;
    final hasUpper = RegExp(r'[A-Z]').hasMatch(password);
    final hasLower = RegExp(r'[a-z]').hasMatch(password);
    final hasDigit = RegExp(r'[0-9]').hasMatch(password);
    return minLength && hasUpper && hasLower && hasDigit;
  }

  Future<LoginResult> login({
    required String identifier,
    required String password,
    String device = 'web',
    String deviceName = 'Flutter App',
  }) async {
    final data = await _post('/auth/login', {
      'identifier': identifier.trim(),
      'password': password,
      'device': device,
      'deviceName': deviceName,
    });

    return LoginResult(
      user: _parseUser(_extractMap(data['user'])),
      tokens: _parseTokens(_extractMap(data['tokens'])),
    );
  }

  Future<OtpSession> register({
    required String fullName,
    required String phone,
    required String email,
    required String password,
  }) async {
    final data = await _post('/auth/register', {
      'fullName': fullName.trim(),
      'phone': normalizePhone(phone),
      'email': email.trim().toLowerCase(),
      'password': password,
    });

    return _parseOtpSession(data, defaultEmail: email.trim().toLowerCase());
  }

  Future<LoginResult> verifyRegisterOtp({
    required String sessionId,
    required String otp,
  }) async {
    final data = await _post('/auth/verify-register-otp', {
      'sessionId': sessionId,
      'otp': otp.trim(),
    });

    return LoginResult(
      user: _parseUser(_extractMap(data['user'])),
      tokens: _parseTokens(_extractMap(data['tokens'])),
    );
  }

  Future<OtpSession> requestForgotPasswordOtp({
    required String email,
    required String newPassword,
  }) async {
    final data = await _post('/auth/forgot-password/request-otp', {
      'email': email.trim().toLowerCase(),
      'newPassword': newPassword,
    });

    return _parseOtpSession(data, defaultEmail: email.trim().toLowerCase());
  }

  Future<void> verifyForgotPasswordOtp({
    required String sessionId,
    required String otp,
  }) async {
    await _post('/auth/forgot-password/verify-otp', {
      'sessionId': sessionId,
      'otp': otp.trim(),
    });
  }

  Future<OtpSession> resendOtp(String sessionId) async {
    final data = await _post('/auth/otp/resend', {
      'sessionId': sessionId,
    });

    return _parseOtpSession(data, defaultEmail: '');
  }

  Future<AuthTokens> refreshAccessToken(String refreshToken) async {
    final data = await _post('/auth/refresh-token', {
      'refreshToken': refreshToken,
    });

    final tokenMap = data.containsKey('tokens')
        ? _extractMap(data['tokens'])
        : data;
    return _parseTokens(tokenMap);
  }

  Future<void> logout(String refreshToken) async {
    await _post('/auth/logout', {'refreshToken': refreshToken});
  }

  Future<List<Map<String, dynamic>>> getSessionsByUserId(String userId) async {
    final data = await _get('/auth/sessions/$userId');
    final sessions = data['sessions'] ?? data['items'] ?? data['data'] ?? data;

    if (sessions is! List) return [];
    return sessions
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> changePassword({
    required String userId,
    required String oldPassword,
    required String newPassword,
  }) async {
    await _post('/auth/change-password', {
      'userId': userId,
      'oldPassword': oldPassword,
      'newPassword': newPassword,
    });
  }

  Future<void> logoutAllDevices(String userId) async {
    await _post('/auth/logout-all-devices', {
      'userId': userId,
    });
  }

  Future<OtpSession> requestPhoneLoginOtp({required String phone}) async {
    final data = await _post('/auth/phone-login/request-otp', {
      'phone': normalizePhone(phone),
    });

    return _parseOtpSession(data, defaultEmail: '');
  }

  Future<LoginResult> verifyPhoneLoginOtp({
    required String sessionId,
    required String otp,
  }) async {
    final data = await _post('/auth/phone-login/verify-otp', {
      'sessionId': sessionId.trim(),
      'otp': otp.trim(),
    });

    return LoginResult(
      user: _parseUser(_extractMap(data['user'])),
      tokens: _parseTokens(_extractMap(data['tokens'])),
    );
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('$_baseUrl$path');
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final uri = Uri.parse('$_baseUrl$path');
    final response = await _client.get(uri);
    return _handleResponse(response);
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    final parsed = _safeDecode(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FakeAuthException(_extractErrorMessage(parsed));
    }

    if (parsed is! Map<String, dynamic>) {
      return <String, dynamic>{};
    }

    final success = parsed['success'];
    if (success is bool && !success) {
      throw FakeAuthException(_extractErrorMessage(parsed));
    }

    final data = parsed['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }

    return parsed;
  }

  dynamic _safeDecode(String body) {
    if (body.isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(body);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String _extractErrorMessage(Map<String, dynamic>? payload) {
    if (payload == null) return 'Yeu cau that bai.';

    final error = payload['error'];
    if (error is Map<String, dynamic>) {
      final msg = error['message'];
      if (msg is String && msg.trim().isNotEmpty) return msg;
    }

    final message = payload['message'];
    if (message is String && message.trim().isNotEmpty) return message;

    return 'Yeu cau that bai.';
  }

  OtpSession _parseOtpSession(
    Map<String, dynamic> data, {
    required String defaultEmail,
  }) {
    final sessionId =
        (data['sessionId'] ?? data['otpSessionId'] ?? '').toString().trim();
    if (sessionId.isEmpty) {
      throw const FakeAuthException('Khong nhan duoc sessionId tu backend.');
    }

    final rawEmail = (data['email'] ?? defaultEmail).toString();
    final rawExpired = data['otpExpiredAt'] ?? data['expiredAt'];

    final expiredAt = _parseDateTime(rawExpired) ??
        DateTime.now().add(const Duration(minutes: 2));

    return OtpSession(
      sessionId: sessionId,
      email: rawEmail,
      expiredAt: expiredAt,
    );
  }

  AuthTokens _parseTokens(Map<String, dynamic> map) {
    final accessToken = _pickString(map, ['accessToken', 'token']);
    final refreshToken = _pickString(map, ['refreshToken']);

    if (accessToken.isEmpty || refreshToken.isEmpty) {
      throw const FakeAuthException('Backend chua tra day du token.');
    }

    final accessExpiredAt = _parseDateTime(
          map['accessExpiredAt'] ?? map['accessTokenExpiredAt'],
        ) ??
        DateTime.now().add(const Duration(minutes: 30));

    return AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessExpiredAt: accessExpiredAt,
    );
  }

  UserModel _parseUser(Map<String, dynamic> map) {
    final id = _pickString(map, ['id', '_id', 'userId']);
    final fullName = _pickString(map, ['fullName', 'name'], fallback: 'User');
    final phone = _pickString(map, ['phone'], fallback: '');
    final email = _pickString(map, ['email'], fallback: '');
    final avatar = _pickString(
      map,
      ['avatar', 'avatarUrl'],
      fallback: 'https://i.pravatar.cc/150?u=${id.isEmpty ? email : id}',
    );

    final statusMap = map['status'] is Map<String, dynamic>
        ? map['status'] as Map<String, dynamic>
        : <String, dynamic>{};

    final isOnline = statusMap['isOnline'] == true;
    final lastSeen = _parseDateTime(statusMap['lastSeen']);

    return UserModel(
      id: id.isEmpty ? DateTime.now().millisecondsSinceEpoch.toString() : id,
      fullName: fullName,
      phone: phone,
      email: email.isEmpty ? null : email,
      avatar: avatar,
      status: UserStatus(isOnline: isOnline, lastSeen: lastSeen),
      isVerified: map['isVerified'] == true,
    );
  }

  Map<String, dynamic> _extractMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  String _pickString(
    Map<String, dynamic> map,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return fallback;
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

final fakeAuthFlowService = FakeAuthFlowService();
