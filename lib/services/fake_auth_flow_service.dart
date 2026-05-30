import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../core/config/app_config.dart';
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

class AvatarUploadResult {
  final String avatarUrl;

  const AvatarUploadResult({required this.avatarUrl});
}

class S3UploadResult {
  final String fileUrl;

  const S3UploadResult({required this.fileUrl});
}

class LoginResult {
  final UserModel user;
  final AuthTokens tokens;

  const LoginResult({required this.user, required this.tokens});
}

class LoginChallengeInfo {
  final String challengeId;
  final String email;
  final DateTime challengeExpiredAt;
  final String? reason;

  const LoginChallengeInfo({
    required this.challengeId,
    required this.email,
    required this.challengeExpiredAt,
    this.reason,
  });
}

class LoginAttemptResult {
  final LoginResult? loginResult;
  final LoginChallengeInfo? challenge;

  const LoginAttemptResult({this.loginResult, this.challenge});

  bool get requiresEmailConfirmation => challenge != null;
}

class LoginChallengeStatusResult {
  final String challengeId;
  final String status;
  final LoginResult? loginResult;
  final bool revokedOldSessions;

  const LoginChallengeStatusResult({
    required this.challengeId,
    required this.status,
    this.loginResult,
    this.revokedOldSessions = false,
  });

  bool get isPending => status == 'pending';
  bool get isConsumed => status == 'consumed' && loginResult != null;
}

class FakeAuthFlowService {
  FakeAuthFlowService._internal();

  static final FakeAuthFlowService _instance = FakeAuthFlowService._internal();
  factory FakeAuthFlowService() => _instance;

  static const String emailOtpPurposeRegister = 'register';
  static const String emailOtpPurposeForgotPassword = 'forgot_password';
  static const String phoneOtpPurposeLogin = 'phone_login';

  final http.Client _client = http.Client();

  String get _baseUrl => AppConfig.baseUrl;

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

  bool isValidDob(String value) {
    final text = value.trim();
    if (text.isEmpty) return true;
    final regex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!regex.hasMatch(text)) return false;
    return DateTime.tryParse(text) != null;
  }

  bool isValidGender(String value) {
    return value == 'male' || value == 'female' || value == 'other';
  }

  bool isValidShowPhone(String value) {
    return value == 'ALL' || value == 'FRIEND' || value == 'PRIVATE';
  }

  bool isValidUrl(String value) {
    if (value.trim().isEmpty) return true;
    final uri = Uri.tryParse(value.trim());
    return uri != null && uri.hasScheme && uri.hasAuthority;
  }

  bool isImageMimeType(String? value) {
    if (value == null || value.trim().isEmpty) return false;
    return value.toLowerCase().startsWith('image/');
  }

  Future<LoginAttemptResult> login({
    required String identifier,
    required String password,
    required String deviceFingerprint,
    String device = 'web',
    String deviceName = 'Flutter App',
  }) async {
    final data = await _post('/auth/login', {
      'identifier': identifier.trim(),
      'password': password,
      'device': device,
      'deviceName': deviceName,
      'deviceFingerprint': deviceFingerprint,
    });

    final requiresChallenge = data['requiresEmailConfirmation'] == true;
    if (requiresChallenge) {
      final challengeId = (data['challengeId'] ?? '').toString().trim();
      final email = (data['email'] ?? '').toString().trim();
      final expiredAt = _parseDateTime(data['challengeExpiredAt']);
      if (challengeId.isEmpty || expiredAt == null) {
        throw const FakeAuthException('Khong nhan duoc challenge hop le tu backend.');
      }
      return LoginAttemptResult(
        challenge: LoginChallengeInfo(
          challengeId: challengeId,
          email: email,
          challengeExpiredAt: expiredAt,
          reason: (data['reason'] ?? '').toString().trim(),
        ),
      );
    }

    return LoginAttemptResult(
      loginResult: LoginResult(
        user: _parseUser(_extractMap(data['user'])),
        tokens: _parseTokens(_extractMap(data['tokens'])),
      ),
    );
  }

  Future<LoginChallengeStatusResult> getLoginChallengeStatus(
    String challengeId,
  ) async {
    final data = await _post('/auth/login-challenge/status', {
      'challengeId': challengeId.trim(),
    });

    final id = (data['challengeId'] ?? challengeId).toString().trim();
    final rawStatus = (data['status'] ?? '').toString().trim();
    final status = rawStatus.toUpperCase();

    if (status == 'APPROVED' || status == 'CONSUMED') {
      return LoginChallengeStatusResult(
        challengeId: id,
        status: rawStatus,
        loginResult: LoginResult(
          user: _parseUser(_extractMap(data['user'])),
          tokens: _parseTokens(_extractMap(data['tokens'])),
        ),
        revokedOldSessions: data['revokedOldSessions'] == true,
      );
    }

    return LoginChallengeStatusResult(
      challengeId: id,
      status: rawStatus.isEmpty ? 'PENDING' : rawStatus,
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
    final data = await _post('/auth/otp/resend', {'sessionId': sessionId});

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

  Future<AuthTokens> refreshToken(String refreshToken) {
    return refreshAccessToken(refreshToken);
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
    await _post('/auth/logout-all-devices', {'userId': userId});
  }

  Future<OtpSession> requestPhoneLoginOtp({
    required String phone,
    required String deviceFingerprint,
    String device = 'web',
    String deviceName = 'Flutter App',
  }) async {
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

  Future<Map<String, dynamic>> getUserProfile(String userId) async {
    final data = await _get('/users/$userId');
    if (data.containsKey('user')) {
      return _extractMap(data['user']);
    }
    return data;
  }

  Future<UserModel> updateUserProfile({
    required String userId,
    required String fullName,
    String? bio,
    String? gender,
    String? dob,
    bool? isBlocked,
  }) async {
    final body = <String, dynamic>{'fullName': fullName.trim()};

    if (bio != null && bio.trim().isNotEmpty) {
      body['bio'] = bio.trim();
    }
    if (gender != null && gender.trim().isNotEmpty) {
      body['gender'] = gender.trim();
    }
    if (dob != null && dob.trim().isNotEmpty) {
      body['dob'] = dob.trim();
    }
    if (isBlocked != null) {
      body['isBlocked'] = isBlocked;
    }

    final data = await _put('/users/$userId', body);
    final userMap = data.containsKey('user') ? _extractMap(data['user']) : data;
    return _parseUser(userMap);
  }

  Future<Map<String, dynamic>> updatePrivacy({
    required String userId,
    required String showPhone,
    required bool showOnline,
    required bool allowStrangerMessage,
    required bool findByPhone,
  }) async {
    if (!isValidShowPhone(showPhone)) {
      throw const FakeAuthException(
        'showPhone chi nhan ALL | FRIEND | PRIVATE.',
      );
    }

    final data = await _patch('/users/$userId/privacy', {
      'showPhone': showPhone,
      'showOnline': showOnline,
      'allowStrangerMessage': allowStrangerMessage,
      'findByPhone': findByPhone,
    });
    return data;
  }

  Future<Map<String, dynamic>> updateOnlineStatus({
    required String userId,
    required bool isOnline,
  }) async {
    final data = await _patch('/users/$userId/status', {'isOnline': isOnline});
    return data;
  }

  Future<AvatarUploadResult> uploadAvatarToS3({
    required String userId,
    required XFile file,
  }) async {
    final uploaded = await uploadFileToS3(
      userId: userId,
      file: file,
      presignPath: '/users/$userId/avatar/presign',
      uploadFailedMessage: 'Upload avatar len S3 that bai.',
    );
    await _patch('/users/$userId/avatar', {'avatar': uploaded.fileUrl});

    return AvatarUploadResult(avatarUrl: uploaded.fileUrl);
  }

  Future<S3UploadResult> uploadCoverToS3({
    required String userId,
    required XFile file,
  }) async {
    final uploaded = await uploadFileToS3(
      userId: userId,
      file: file,
      presignPath: '/users/$userId/cover/presign',
      uploadFailedMessage: 'Upload anh bia len S3 that bai.',
    );
    await _patch('/users/$userId/cover', {'coverImage': uploaded.fileUrl});
    return uploaded;
  }

  Future<S3UploadResult> uploadFileToS3({
    required String userId,
    required XFile file,
    String? presignPath,
    String uploadFailedMessage = 'Upload len S3 that bai.',
  }) async {
    final contentType = _resolveImageMimeType(file);
    if (contentType == null || !isImageMimeType(contentType)) {
      throw const FakeAuthException('contentType phai la image/*');
    }

    final presign = await _post(
      presignPath ?? '/users/$userId/avatar/presign',
      {'fileName': file.name, 'contentType': contentType},
    );

    final uploadUrl = (presign['uploadUrl'] ?? '').toString();
    final fileUrl = (presign['fileUrl'] ?? '').toString();

    if (uploadUrl.isEmpty || fileUrl.isEmpty) {
      throw const FakeAuthException('Backend chua tra uploadUrl/fileUrl.');
    }

    final bytes = await file.readAsBytes();
    final putRes = await _client.put(
      Uri.parse(uploadUrl),
      headers: {'Content-Type': contentType},
      body: bytes,
    );

    if (putRes.statusCode < 200 || putRes.statusCode >= 300) {
      throw FakeAuthException(uploadFailedMessage);
    }

    return S3UploadResult(fileUrl: fileUrl);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('$_baseUrl$path');
    final headers = {'Content-Type': 'application/json'};
    final encoded = jsonEncode(body);
    try {
      final response = await _client.post(
        uri,
        headers: headers,
        body: encoded,
      );
      return _handleResponse(response);
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _put(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('$_baseUrl$path');
    final response = await _client.put(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> _patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('$_baseUrl$path');
    final response = await _client.patch(
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
    final sessionId = (data['sessionId'] ?? data['otpSessionId'] ?? '')
        .toString()
        .trim();
    if (sessionId.isEmpty) {
      throw const FakeAuthException('Khong nhan duoc sessionId tu backend.');
    }

    final rawEmail = (data['email'] ?? defaultEmail).toString();
    final rawExpired = data['otpExpiredAt'] ?? data['expiredAt'];

    final expiredAt =
        _parseDateTime(rawExpired) ??
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

    final accessExpiredAt =
        _parseDateTime(map['accessExpiredAt'] ?? map['accessTokenExpiredAt']) ??
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
    final avatar = _pickString(map, [
      'avatar',
      'avatarUrl',
    ], fallback: 'https://i.pravatar.cc/150?u=${id.isEmpty ? email : id}');

    final statusMap = map['status'] is Map<String, dynamic>
        ? map['status'] as Map<String, dynamic>
        : <String, dynamic>{};

    final privacyMap = map['privacy'] is Map<String, dynamic>
        ? map['privacy'] as Map<String, dynamic>
        : <String, dynamic>{};

    final isOnline = statusMap['isOnline'] == true;
    final lastSeen = _parseDateTime(statusMap['lastSeen']);

    return UserModel(
      id: id.isEmpty ? DateTime.now().millisecondsSinceEpoch.toString() : id,
      fullName: fullName,
      phone: phone,
      email: email.isEmpty ? null : email,
      avatar: avatar,
      coverImage: _pickString(map, ['coverImage'], fallback: ''),
      bio: _pickString(map, ['bio'], fallback: ''),
      gender: _pickString(map, ['gender'], fallback: 'other'),
      status: UserStatus(isOnline: isOnline, lastSeen: lastSeen),
      privacy: UserPrivacy(
        showPhone: _pickString(privacyMap, ['showPhone'], fallback: 'FRIEND'),
        showOnline: privacyMap['showOnline'] != false,
        allowStrangerMessage: privacyMap['allowStrangerMessage'] == true,
      ),
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

  String? _resolveImageMimeType(XFile file) {
    if (isImageMimeType(file.mimeType)) return file.mimeType;

    final lower = file.name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return null;
  }
}

final fakeAuthFlowService = FakeAuthFlowService();
