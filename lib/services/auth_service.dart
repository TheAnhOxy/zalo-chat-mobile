import '../data/models/models.dart';

typedef AuthListener = void Function();

class AuthService {
  // ── Singleton ─────────────────────────────────────────────────
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // ── State ─────────────────────────────────────────────────────
  UserModel? _currentUser = const UserModel(
    id: '69da71a2431bb5f06428519b',
    fullName: 'Nguyễn Văn An',
    phone: '0901234567',
    email: 'an@azureconnect.vn',
    avatar: 'https://i.pravatar.cc/150?img=11',
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
    _notify();
  }


  Future<void> loginWithPhone(String phone, String password) async {
    await Future.delayed(const Duration(milliseconds: 500));
    _notify();
  }

  void setUser(UserModel user, {String? token}) {
    _currentUser = user;
    if (token != null) _accessToken = token;
    _notify();
  }

  void logout() {
    _currentUser = null;
    _accessToken = null;
    _notify();
  }
} 

/// Global singleton
final authService = AuthService();