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
  final List<AuthListener> _listeners = [];

  // ── Public Getters ────────────────────────────────────────────
  UserModel? get currentUser => _currentUser;
  String?    get userId      => _currentUser?.id;
  String?    get accessToken => _accessToken;
  String?    get refreshToken => _refreshToken;
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


  // ── Stub cho NGƯỜI 1 (AUTH) implement sau ─────────────────────
  /// Gọi sau khi decode JWT thành công
  void setUser(UserModel user, {String? token, String? refreshToken}) {
    _currentUser = user;
    if (token != null) _accessToken = token;
    if (refreshToken != null) _refreshToken = refreshToken;
    _notify();
  }

  void updateCurrentUser(UserModel user) {
    _currentUser = user;
    _notify();
  }

  void logout() {
    _currentUser = null;
    _accessToken = null;
    _refreshToken = null;
    _notify();
  }
} 

/// Global singleton
final authService = AuthService();