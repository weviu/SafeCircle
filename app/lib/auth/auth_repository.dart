import 'package:dio/dio.dart';

import 'session.dart';

class AuthRepository {
  AuthRepository(this._dio);

  final Dio _dio;

  /// POST /auth/login — returns a fully populated [AuthSession].
  /// Throws [DioException] with 401 for unknown email/wrong password
  /// (both yield the same generic backend message).
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
    return AuthSession.fromLoginResponse(response.data!);
  }
}
