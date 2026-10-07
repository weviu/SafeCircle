import 'package:dio/dio.dart';

import 'auth_repository.dart';
import 'session.dart';

class AuthController {
  AuthController(this._repository, this._session);

  final AuthRepository _repository;
  final SessionManager _session;

  /// Logs in and persists the session. Throws [DioException] on failure
  /// (401 generic message for unknown email or wrong password).
  Future<void> login({required String email, required String password}) async {
    final session = await _repository.login(email: email, password: password);
    await _session.setSession(session);
  }
}
