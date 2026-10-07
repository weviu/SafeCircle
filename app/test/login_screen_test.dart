import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safecircle/config/api_config.dart';
import 'package:safecircle/main.dart';
import 'package:safecircle/screens/login_screen.dart';

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

/// Real HTTP needs the real event loop (socket events) while the widget's
/// future continuations need the fake-async zone to be pumped — so alternate
/// between [WidgetTester.runAsync] windows and [WidgetTester.pump] until
/// [done] or ~12s real time.
Future<void> _until(
  WidgetTester tester,
  bool Function() done, {
  int maxIterations = 120,
}) async {
  for (var i = 0; i < maxIterations && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // flutter_test installs HttpOverrides.global returning 400 for every
    // request; clear it once (the binding never re-installs it) so the
    // widget tests hit the real backend.
    HttpOverrides.global = null;
  });

  testWidgets('login → token stored → redirect to Hello, teacher', (
    tester,
  ) async {
    await tester.runAsync(_ensureUserExists);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ProviderScope(child: SafeCircleApp()));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), _email);
    await tester.enterText(find.byType(TextFormField).at(1), _password);
    await tester.tap(find.text('Log in'));
    await tester.pump();

    await _until(
      tester,
      () => find.text('Hello, teacher').evaluate().isNotEmpty,
    );
    // Let the login→home page transition finish so LoginScreen is unmounted.
    await tester.pumpAndSettle();

    expect(find.text('Hello, teacher'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('access_token'), isNotEmpty);
    expect(prefs.getString('refresh_token'), isNotEmpty);
    expect(prefs.getString('user_role'), 'TEACHER');

    // Elapse past dart:io's HttpClient keep-alive timers (15s idle) so no
    // fake timers remain pending when flutter_test checks invariants.
    await tester.pumpAndSettle(const Duration(seconds: 60));
  });

  testWidgets('wrong password shows generic error, stays on login', (
    tester,
  ) async {
    await tester.runAsync(_ensureUserExists);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ProviderScope(child: SafeCircleApp()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), _email);
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong-password');
    await tester.tap(find.text('Log in'));
    await tester.pump();

    await _until(
      tester,
      () => find.text('Invalid credentials').evaluate().isNotEmpty,
    );

    expect(find.text('Invalid credentials'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('access_token'), isNull);

    // Let the SnackBar dismiss timer fire — flutter_test asserts that no
    // fake timers are still pending when the test ends.
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
}
