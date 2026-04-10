// import 'package:flutter/material.dart';

// class UserModel {
//   final String id;
//   final String fullName;
//   final String phone;
//   final String avatar;
//   final bool isOnline;

//   const UserModel({
//     required this.id,
//     required this.fullName,
//     required this.phone,
//     required this.avatar,
//     this.isOnline = true,
//   });
// }

// typedef AuthListener = void Function();

// class AuthService {
//   static final AuthService _instance = AuthService._internal();
//   factory AuthService() => _instance;
//   AuthService._internal();

//   UserModel? _currentUser = const UserModel(
//     id: 'USR_001',
//     fullName: 'Nguyễn Văn An',
//     phone: '0901234567',
//     avatar: 'https://i.pravatar.cc/150?img=11',
//   );

//   final List<AuthListener> _listeners = [];

//   UserModel? get currentUser => _currentUser;
//   String?    get userId      => _currentUser?.id;
//   bool       get isLoggedIn  => _currentUser != null;

//   VoidCallback subscribe(AuthListener listener) {
//     _listeners.add(listener);
//     return () => _listeners.remove(listener);
//   }

//   void _notify() { for (final l in _listeners) l(); }

//   void loginAsUser1() {
//     _currentUser = const UserModel(
//       id: 'USR_001', fullName: 'Nguyễn Văn An',
//       phone: '0901234567', avatar: 'https://i.pravatar.cc/150?img=11',
//     );
//     _notify();
//   }

//   void loginAsUser2() {
//     _currentUser = const UserModel(
//       id: 'USR_002', fullName: 'Trần Thị Bảo',
//       phone: '0912345678', avatar: 'https://i.pravatar.cc/150?img=5',
//     );
//     _notify();
//   }

//   void setUser(UserModel user) { _currentUser = user; _notify(); }
//   void logout() { _currentUser = null; _notify(); }
// }

// final authService = AuthService();

import '../data/models/models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AuthService — Fake implementation cho phần Chat/Call
//
// THIẾT KẾ:
//   • Singleton — toàn app dùng 1 instance: authService.xxx
//   • Subscribe pattern — giống RN cũ, component lắng nghe thay đổi
//   • Interface công khai giữ nguyên — khi NGƯỜI 1 (AUTH) xong chỉ cần
//     implement loginWithPhone() + verifyOTP() rồi gọi setUser()
//
// NGƯỜI LÀM AUTH sẽ thêm vào:
//   • loginWithPhone(phone) → gọi API → lưu JWT
//   • verifyOTP(otp) → validate → setUser(decoded user)
//   • refreshToken() → lấy token mới
//   • Lưu token vào SharedPreferences
// ─────────────────────────────────────────────────────────────────────────────

typedef AuthListener = void Function();

class AuthService {
  // ── Singleton ─────────────────────────────────────────────────
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // ── State ─────────────────────────────────────────────────────
  /// Fake user mặc định — bỏ qua màn Login khi test Chat
  UserModel? _currentUser = const UserModel(
    id: 'USR_001',
    fullName: 'Nguyễn Văn An',
    phone: '0901234567',
    email: 'an@azureconnect.vn',
    avatar: 'https://i.pravatar.cc/150?img=11',
    bio: 'Flutter Developer 🚀',
    gender: 'male',
    status: UserStatus(isOnline: true),
    isVerified: true,
  );

  String? _accessToken = 'fake-jwt-token-for-dev';
  final List<AuthListener> _listeners = [];

  // ── Public Getters ────────────────────────────────────────────
  UserModel? get currentUser => _currentUser;
  String?    get userId      => _currentUser?.id;
  String?    get accessToken => _accessToken;
  bool       get isLoggedIn  => _currentUser != null;
  bool       get isVerified  => _currentUser?.isVerified ?? false;

  // ── Subscribe / Unsubscribe ───────────────────────────────────
  /// Trả về hàm unsubscribe — gọi trong dispose()
  void Function() subscribe(AuthListener listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _notify() {
    for (final l in List.from(_listeners)) {
      l();
    }
  }

  // ── Fake Login (dùng để test nhanh) ──────────────────────────
  void loginAsUser1() {
    _currentUser = const UserModel(
      id: 'USR_001',
      fullName: 'Nguyễn Văn An',
      phone: '0901234567',
      email: 'an@azureconnect.vn',
      avatar: 'https://i.pravatar.cc/150?img=11',
      bio: 'Flutter Developer 🚀',
      status: UserStatus(isOnline: true),
      isVerified: true,
    );
    _accessToken = 'fake-jwt-user1';
    _notify();
  }

  void loginAsUser2() {
    _currentUser = const UserModel(
      id: 'USR_002',
      fullName: 'Nguyễn Linh',
      phone: '0912345678',
      email: 'linh@azureconnect.vn',
      avatar: 'https://i.pravatar.cc/150?img=5',
      bio: 'UI/UX Designer ✨',
      status: UserStatus(isOnline: true),
      isVerified: true,
    );
    _accessToken = 'fake-jwt-user2';
    _notify();
  }

  // ── Stub cho NGƯỜI 1 (AUTH) implement sau ─────────────────────
  /// Gọi sau khi decode JWT thành công
  void setUser(UserModel user, {String? token}) {
    _currentUser = user;
    if (token != null) _accessToken = token;
    _notify();
  }

  /// NGƯỜI 1 implement: gọi API /auth/login-phone
  Future<void> loginWithPhone(String phone, String password) async {
    // TODO(AUTH_TEAM): Gọi API thật
    // final res = await ApiService.post('/auth/login', {phone, password});
    // final user = UserModel.fromJson(res['user']);
    // setUser(user, token: res['accessToken']);

    // Fake: simulate API delay
    await Future.delayed(const Duration(seconds: 1));
    loginAsUser1();
  }

  /// NGƯỜI 1 implement: gọi API /auth/verify-otp
  Future<void> verifyOTP(String otp) async {
    // TODO(AUTH_TEAM): Gọi API thật
    await Future.delayed(const Duration(milliseconds: 500));
  }

  void logout() {
    _currentUser = null;
    _accessToken = null;
    _notify();
  }
}

/// Global singleton — dùng như: authService.currentUser
final authService = AuthService();