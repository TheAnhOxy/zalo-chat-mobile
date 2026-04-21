import 'dart:async';

import 'api_service.dart';
import 'auth_service.dart';

class SessionGuardService {
  SessionGuardService._internal();

  static final SessionGuardService _instance = SessionGuardService._internal();
  factory SessionGuardService() => _instance;

  Timer? _timer;
  bool _checking = false;

  void start() {
    if (_timer != null) return;

    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      _tick();
    });

    _tick();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (_checking) return;
    final userId = authService.userId;
    if (userId == null || userId.isEmpty) return;

    _checking = true;
    try {
      // Any revoked session (401) will be caught by ApiService interceptor.
      await apiService.getUserById(userId);
    } finally {
      _checking = false;
    }
  }
}

final sessionGuardService = SessionGuardService();
