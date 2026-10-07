import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safecircle/auth/auth_interceptor.dart';
import 'package:safecircle/auth/auth_repository.dart';
import 'package:safecircle/auth/session.dart';
import 'package:safecircle/config/api_config.dart';

const _email = 'flutter-e2e@test.local';
const _password = 'E2ePassw0rd!';

Future<void> _ensureUserExists() async {
  final dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));
  try {
    await dio.post<Map<String, dynamic>>(
      '/auth/signup',
      data: {
        'email': _email,
        'password': _password,
        'role': 'teacher',
        'name': 'Flutter E2E',
      },
    );
  } on DioException catch (error) {
    if (error.response?.statusCode != 409) rethrow;
  }
}

Future<void> _awaitRestore(SessionManager session) async {
  while (!session.restored) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Dio _clientWith(SessionManager session) {
  final dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));
  dio.interceptors.add(AuthInterceptor(session: session));
  return dio;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // flutter_test installs HttpOverrides.global returning 400 for every
    // request; clear it once (the binding never re-installs it) so these
    // tests hit the real backend.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    await _ensureUserExists();
  });

  test('login returns a session with access, refresh and role', () async {
    final session = SessionManager(TokenStore());
    await _awaitRestore(session);
    final repository = AuthRepository(_clientWith(session));

    final result = await repository.login(email: _email, password: _password);

    expect(result.accessToken, isNotEmpty);
    expect(result.refreshToken, isNotEmpty);
    expect(result.role, 'TEACHER');
    expect(result.email, _email);
  });

  test(
    'wrong password and unknown email yield the identical 401 message',
    () async {
      final dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));

      Future<Object?> messageOf(String email, String password) async {
        try {
          await dio.post<Map<String, dynamic>>(
            '/auth/login',
            data: {'email': email, 'password': password},
          );
          return 'no error';
        } on DioException catch (error) {
          final data = error.response?.data;
          return data is Map ? data['message'] : 'unexpected';
        }
      }

      final wrongPassword = await messageOf(_email, 'wrong-password');
      final unknownEmail = await messageOf('ghost@test.local', _password);

      expect(wrongPassword, 'Invalid credentials');
      expect(unknownEmail, wrongPassword);
    },
  );

  test(
    'invalid access token + valid refresh token → refresh + retry on 401',
    () async {
      final session = SessionManager(TokenStore());
      await _awaitRestore(session);
      final repository = AuthRepository(_clientWith(session));

      final fresh = await repository.login(email: _email, password: _password);
      await session.setSession(fresh);

      // Simulate an expired/garbage access token; refresh token stays valid.
      await session.updateTokens(
        accessToken: 'garbage-access-token',
        refreshToken: fresh.refreshToken,
      );

      final response = await _clientWith(
        session,
      ).get<Map<String, dynamic>>('/users/me');

      expect(response.statusCode, 200);
      expect(response.data?['email'], _email);
      // Rotated pair replaced the garbage token and was persisted.
      expect(session.session!.accessToken, isNot('garbage-access-token'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('access_token'), session.session!.accessToken);
      expect(prefs.getString('refresh_token'), session.session!.refreshToken);
    },
  );

  test(
    'invalid refresh token → session cleared (logout on failed refresh)',
    () async {
      final session = SessionManager(TokenStore());
      await _awaitRestore(session);
      final repository = AuthRepository(_clientWith(session));

      final fresh = await repository.login(email: _email, password: _password);
      await session.setSession(fresh);
      await session.updateTokens(
        accessToken: 'garbage-access-token',
        refreshToken: 'garbage-refresh-token',
      );

      await expectLater(
        _clientWith(session).get<Map<String, dynamic>>('/users/me'),
        throwsA(isA<DioException>()),
      );
      expect(session.session, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('access_token'), isNull);
      expect(prefs.getString('refresh_token'), isNull);
    },
  );
}
