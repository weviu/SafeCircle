import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.email,
    required this.role,
  });

  final String accessToken;
  final String refreshToken;
  final String userId;
  final String email;
  final String role;

  factory AuthSession.fromLoginResponse(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    return AuthSession(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      userId: user['id'] as String,
      email: user['email'] as String,
      role: user['role'] as String,
    );
  }

  AuthSession copyWith({String? accessToken, String? refreshToken}) {
    return AuthSession(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      userId: userId,
      email: email,
      role: role,
    );
  }
}

class TokenStore {
  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kUserId = 'user_id';
  static const _kEmail = 'user_email';
  static const _kRole = 'user_role';

  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  Future<void> save(AuthSession session) async {
    final prefs = await _prefs;
    await prefs.setString(_kAccess, session.accessToken);
    await prefs.setString(_kRefresh, session.refreshToken);
    await prefs.setString(_kUserId, session.userId);
    await prefs.setString(_kEmail, session.email);
    await prefs.setString(_kRole, session.role);
  }

  Future<AuthSession?> load() async {
    final prefs = await _prefs;
    final access = prefs.getString(_kAccess);
    final refresh = prefs.getString(_kRefresh);
    final userId = prefs.getString(_kUserId);
    final email = prefs.getString(_kEmail);
    final role = prefs.getString(_kRole);
    if (access == null ||
        refresh == null ||
        userId == null ||
        email == null ||
        role == null) {
      return null;
    }
    return AuthSession(
      accessToken: access,
      refreshToken: refresh,
      userId: userId,
      email: email,
      role: role,
    );
  }

  Future<void> clear() async {
    final prefs = await _prefs;
    await prefs.remove(_kAccess);
    await prefs.remove(_kRefresh);
    await prefs.remove(_kUserId);
    await prefs.remove(_kEmail);
    await prefs.remove(_kRole);
  }
}

/// Single source of truth for the current session.
///
/// Exposed as a [ChangeNotifier] so the router can use it as
/// `refreshListenable` — login, refresh-token rotation, and logout all
/// trigger route redirects through it.
class SessionManager extends ChangeNotifier {
  SessionManager(this._store) {
    _restore();
  }

  final TokenStore _store;

  AuthSession? session;
  bool restored = false;

  bool get isAuthenticated => restored && session != null;

  Future<void> _restore() async {
    session = await _store.load();
    restored = true;
    notifyListeners();
  }

  Future<void> setSession(AuthSession newSession) async {
    session = newSession;
    await _store.save(newSession);
    notifyListeners();
  }

  Future<void> updateTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    final current = session;
    if (current == null) return;
    session = current.copyWith(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    await _store.save(session!);
    notifyListeners();
  }

  Future<void> clear() async {
    session = null;
    await _store.clear();
    notifyListeners();
  }
}
