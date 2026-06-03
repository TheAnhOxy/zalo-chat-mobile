import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/models.dart';

typedef AuthListener = void Function();

class AuthService {
  // ── Singleton ─────────────────────────────────────────────────
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // ── State ─────────────────────────────────────────────────────
  UserModel? _currentUser;
  String? _accessToken;
  String? _refreshToken;
  DateTime? _accessExpiredAt;
  final List<AuthListener> _listeners = [];

  // ── Public Getters ────────────────────────────────────────────
  UserModel? get currentUser => _currentUser;
  String?    get userId      => _currentUser?.id;
  String?    get accessToken => _accessToken;
  String?    get refreshToken => _refreshToken;
  DateTime?  get accessExpiredAt => _accessExpiredAt;
  bool       get isLoggedIn  => _currentUser != null;

  // ── Subscribe / Unsubscribe ───────────────────────────────────
  void Function() subscribe(AuthListener listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _notify() {
    for (final l in List.from(_listeners)) {
      l();
    }
  }

  // ── Logic Login Giả lập cho Test ──────────────────────────────

  void loginAsUser1() {
    _currentUser = const UserModel(
      id: '69da71a2431bb5f06428519b', // ID User A trong DB của bạn
      fullName: 'Nguyễn Văn An',
      phone: '0901234567',
      avatar: 'https://i.pravatar.cc/150?img=11',
      status: UserStatus(isOnline: true),
    );
    _accessToken = 'fake-jwt-user1';
    _refreshToken = 'fake-refresh-user1';
    _notify();
  }

  void loginAsUser2() {
    _currentUser = const UserModel(
      id: '69da71a2431bb5f06428519d', 
      fullName: 'Nguyễn Linh',
      phone: '0912345678',
      avatar: 'https://i.pravatar.cc/150?img=5',
      status: UserStatus(isOnline: true),
    );
    _accessToken = 'fake-jwt-user2';
    _refreshToken = 'fake-refresh-user2';
    _notify();
  }


  Future<void> loginWithPhone(String phone, String password) async {
    await Future.delayed(const Duration(milliseconds: 500));
    _notify();
  }


  // ── Persistence (SharedPreferences / localStorage on web) ────
  static const _keyUser         = 'auth_user';
  static const _keyAccessToken  = 'auth_access_token';
  static const _keyRefreshToken = 'auth_refresh_token';
  static const _keyAccessExpiredAt = 'auth_access_expired_at';
  static const _keyTrustedUntil = 'auth_trusted_until';

  static const Duration _defaultTrustedDuration = Duration(days: 30);

  /// Lưu session vào SharedPreferences
  Future<void> _saveSession() async {
    if (_currentUser == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUser, jsonEncode({
      'id':        _currentUser!.id,
      'fullName':  _currentUser!.fullName,
      'phone':     _currentUser!.phone,
      'email':     _currentUser!.email ?? '',
      'avatar':    _currentUser!.avatar,
      'coverImage': _currentUser!.coverImage ?? '',
      'bio':       _currentUser!.bio ?? '',
      'gender':    _currentUser!.gender,
      'isVerified': _currentUser!.isVerified,
    }));
    if (_accessToken != null)  await prefs.setString(_keyAccessToken,  _accessToken!);
    if (_refreshToken != null) await prefs.setString(_keyRefreshToken, _refreshToken!);
    if (_accessExpiredAt != null) {
      await prefs.setString(_keyAccessExpiredAt, _accessExpiredAt!.toIso8601String());
    }
  }

  /// Xóa session khỏi SharedPreferences
  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUser);
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyAccessExpiredAt);
  }

  Future<void> _clearTrustedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyTrustedUntil);
  }

  Future<void> markDeviceTrusted({Duration? ttl}) async {
    final until = DateTime.now().add(ttl ?? _defaultTrustedDuration);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTrustedUntil, until.toIso8601String());
  }

  Future<bool> isDeviceTrusted() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyTrustedUntil);
    if (raw == null || raw.isEmpty) return false;
    final until = DateTime.tryParse(raw);
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      await _clearTrustedDevice();
      return false;
    }
    return true;
  }

  /// Khôi phục session từ SharedPreferences khi app khởi động.
  /// Trả về `true` nếu đã khôi phục thành công.
  Future<bool> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString(_keyUser);
      if (userJson == null) return false;

      final map = jsonDecode(userJson) as Map<String, dynamic>;
      _currentUser = UserModel(
        id:          map['id'] ?? '',
        fullName:    map['fullName'] ?? '',
        phone:       map['phone'] ?? '',
        email:       (map['email'] as String?)?.isNotEmpty == true ? map['email'] : null,
        avatar:      map['avatar'] ?? '',
        coverImage:  (map['coverImage'] as String?)?.isNotEmpty == true ? map['coverImage'] : null,
        bio:         (map['bio'] as String?)?.isNotEmpty == true ? map['bio'] : null,
        gender:      map['gender'] ?? 'other',
        isVerified:  map['isVerified'] == true,
      );
      _accessToken  = prefs.getString(_keyAccessToken);
      _refreshToken = prefs.getString(_keyRefreshToken);
        final rawExpiredAt = prefs.getString(_keyAccessExpiredAt);
        _accessExpiredAt =
          rawExpiredAt == null ? null : DateTime.tryParse(rawExpiredAt);
      _notify();
      return _currentUser!.id.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ── Stub cho NGƯỜI 1 (AUTH) implement sau ─────────────────────
  /// Gọi sau khi decode JWT thành công
  void setUser(
    UserModel user, {
    String? token,
    String? refreshToken,
    DateTime? accessExpiredAt,
  }) {
    _currentUser = user;
    if (token != null) _accessToken = token;
    if (refreshToken != null) _refreshToken = refreshToken;
    if (accessExpiredAt != null) _accessExpiredAt = accessExpiredAt;
    _saveSession();
    _notify();
  }

  void updateTokens({
    required String accessToken,
    required String refreshToken,
    required DateTime accessExpiredAt,
  }) {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _accessExpiredAt = accessExpiredAt;
    _saveSession();
    _notify();
  }

  void updateCurrentUser(UserModel user) {
    _currentUser = user;
    _saveSession();
    _notify();
  }

  void logout({bool clearTrusted = false}) {
    _currentUser = null;
    _accessToken = null;
    _refreshToken = null;
    _accessExpiredAt = null;
    _clearSession();
    if (clearTrusted) {
      _clearTrustedDevice();
    }
    _notify();
  }
} 

/// Global singleton
final authService = AuthService();