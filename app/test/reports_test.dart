import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safecircle/auth/auth_interceptor.dart';
import 'package:safecircle/auth/auth_repository.dart';
import 'package:safecircle/auth/session.dart';
import 'package:safecircle/config/api_config.dart';
import 'package:safecircle/main.dart';
import 'package:safecircle/providers.dart';
import 'package:safecircle/reports/classes_repository.dart';
import 'package:safecircle/reports/reports_models.dart';
import 'package:safecircle/reports/reports_repository.dart';
import 'package:safecircle/screens/login_screen.dart';
import 'package:safecircle/screens/teacher_home.dart';

const _password = 'Passw0rd!123';

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

/// Taps [control] repeatedly (a no-op while it is disabled) and pumps real
/// I/O windows until [done] — used for date/week stepping.
Future<void> _stepUntil(
  WidgetTester tester,
  Finder control,
  bool Function() done, {
  int maxIterations = 400,
}) async {
  for (var i = 0; i < maxIterations && !done(); i++) {
    await tester.ensureVisible(control);
    await tester.tap(control);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _awaitRestore(SessionManager session) async {
  while (!session.restored) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Authenticated dio (session + refresh interceptor), ready for the backend.
Future<Dio> _authedDio(String email, String password) async {
  final session = SessionManager(TokenStore());
  await _awaitRestore(session);
  final dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))
    ..interceptors.add(AuthInterceptor(session: session));
  final fresh = await AuthRepository(dio).login(
    email: email,
    password: password,
  );
  await session.setSession(fresh);
  return dio;
}

Finder _row(String schoolNumber) => find.byKey(ValueKey('student-$schoolNumber'));

Finder _inRow(String schoolNumber, Finder matching) =>
    find.descendant(of: _row(schoolNumber), matching: matching);

String _segment(WidgetTester tester, Finder row, int index) {
  final segments = find.descendant(
    of: row,
    matching: find.byType(SegmentedButton<String>),
  );
  return tester.widget<SegmentedButton<String>>(segments.at(index)).selected.single;
}

/// Login as teacher1, resolve class 5-A + Ayşe (1001), ready-to-use client.
Future<({SchoolClass cls, Student ayse, ReportsRepository reports})> _teacher1Ctx() async {
  final dio = await _authedDio('teacher1@test.local', _password);
  final classes = await ClassesRepository(dio).listClasses();
  final cls = classes.firstWhere((c) => c.label == '5-A');
  final students = await ClassesRepository(dio).listStudents(cls.id);
  final ayse = students.firstWhere((s) => s.schoolNumber == '1001');
  return (cls: cls, ayse: ayse, reports: ReportsRepository(dio));
}

/// Stub repo for the pure-widget parent test (no backend needed).
class _StubReportsRepository implements ReportsRepository {
  _StubReportsRepository(this._summary);

  final WeekSummary _summary;

  @override
  Future<WeekSummary> summaries({String? week}) async => _summary;

  @override
  Future<List<ReportEntry>> listEntries({
    required String classId,
    required String date,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ReportEntry>> createEntries({
    required String classId,
    required String reportDate,
    required List<EntryPayload> entries,
  }) {
    throw UnimplementedError();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // flutter_test installs HttpOverrides.global returning 400 for every
    // request; clear it once (the binding never re-installs it) so the
    // tests hit the real backend.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('teacher: seed 2026-09-28 loads, flag appears on edit + submit, demo data restored', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ProviderScope(child: SafeCircleApp()));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'teacher1@test.local');
    await tester.enterText(find.byType(TextFormField).at(1), _password);
    await tester.tap(find.text('Log in'));
    await tester.pump();

    await _until(tester, () => find.byType(TeacherHome).evaluate().isNotEmpty);
    await _until(tester, () => find.text('5-A').evaluate().isNotEmpty);

    String dateLabel() =>
        tester.widget<Text>(find.byKey(const Key('date-label'))).data!;
    bool settledOn(target) =>
        dateLabel() == target &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty;

    await _stepUntil(
      tester,
      find.byKey(const Key('prev-day')),
      () => settledOn('2026-09-28'),
    );
    expect(dateLabel(), '2026-09-28');

    // Seeded 09-28 values: Ayşe EXCUSED/DONE/NEUTRAL, Zeynep PARTIAL homework.
    expect(_segment(tester, _row('1001'), 0), 'EXCUSED');
    expect(_segment(tester, _row('1003'), 1), 'PARTIAL');

    // Type a teacher note for Ayşe (round-trips via the note field).
    final noteField = find.byKey(const ValueKey('note-1001'));
    await tester.ensureVisible(noteField);
    await tester.enterText(noteField, 'Randevu gerekli');
    await tester.pump();

    // Change Ayşe's homework to NOT_DONE → seed has NOT_DONE on 09-29/30-10-01
    // so the POST flags homework_streak for her row.
    final notDone = _inRow('1001', find.text('Yapılmadı'));
    await tester.ensureVisible(notDone);
    await tester.tap(notDone);
    await tester.pump();
    expect(_segment(tester, _row('1001'), 1), 'NOT_DONE');

    final submit = find.byKey(const Key('submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();

    await _until(
      tester,
      () => _inRow('1001', find.text('Ödev şeridi')).evaluate().isNotEmpty,
    );
    expect(_inRow('1002', find.text('Ödev şeridi')), findsNothing);
    expect(_inRow('1003', find.text('Ödev şeridi')), findsNothing);
    expect(find.text('Kaydedildi (3 öğrenci)'), findsOneWidget);

    // The POST response re-applied entries: note + flag persisted server-side.
    await tester.runAsync(() async {
      final ctx = await _teacher1Ctx();
      final after = await ctx.reports.listEntries(
        classId: ctx.cls.id,
        date: '2026-09-28',
      );
      final ayse = after.firstWhere((e) => e.studentId == ctx.ayse.id);
      expect(ayse.note, 'Randevu gerekli');
      expect(ayse.homework, 'NOT_DONE');
      expect(ayse.flagged, isTrue);
      expect(ayse.flagReason, 'homework_streak');
    });

    // Clear the note → re-submit → backend stores NULL (field omitted), i.e.
    // the teacher can remove a previously saved note.
    await tester.ensureVisible(noteField);
    await tester.enterText(noteField, '');
    await tester.pump();
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    String? clearedNote = 'Randevu gerekli';
    for (var i = 0; i < 20 && clearedNote != null; i++) {
      await tester.runAsync(() async {
        final ctx = await _teacher1Ctx();
        final after = await ctx.reports.listEntries(
          classId: ctx.cls.id,
          date: '2026-09-28',
        );
        clearedNote = after.firstWhere((e) => e.studentId == ctx.ayse.id).note;
      });
      await tester.pump();
    }
    expect(clearedNote, isNull);
    expect(_inRow('1001', find.text('Ödev şeridi')), findsOneWidget);

    // Restore the seed value through the repository so later runs (and the
    // parent demo) see the original DONE state (note absent → NULL).
    await tester.runAsync(() async {
      final ctx = await _teacher1Ctx();
      final restored = await ctx.reports.createEntries(
        classId: ctx.cls.id,
        reportDate: '2026-09-28',
        entries: [
          EntryPayload(
            studentId: ctx.ayse.id,
            attendance: 'EXCUSED',
            homework: 'DONE',
            behavior: 'NEUTRAL',
          ),
        ],
      );
      expect(restored.single.flagged, isFalse);
      final after = await ctx.reports.listEntries(
        classId: ctx.cls.id,
        date: '2026-09-28',
      );
      final ayse = after.firstWhere((e) => e.studentId == ctx.ayse.id);
      expect(ayse.homework, 'DONE');
      expect(ayse.note, isNull);
      expect(ayse.flagReason, isNull);
    });

    await tester.pumpAndSettle(const Duration(seconds: 60));
  });

  testWidgets('parent: W41 empty, W39 shows children with Zeynep flag badge', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ProviderScope(child: SafeCircleApp()));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'parent2@test.local');
    await tester.enterText(find.byType(TextFormField).at(1), _password);
    await tester.tap(find.text('Log in'));
    await tester.pump();

    String weekLabel() =>
        tester.widget<Text>(find.byKey(const Key('week-label'))).data!;
    bool settledW39() =>
        weekLabel() == '2026-W39' &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty;

    await _until(tester, () => find.byKey(const Key('week-label')).evaluate().isNotEmpty);
    // Today is 2026-W41 — no entries → empty state with demo hint.
    await _until(
      tester,
      () => find.text('Bu hafta için kayıt yok').evaluate().isNotEmpty,
    );
    expect(weekLabel(), '2026-W41');

    await _stepUntil(tester, find.byKey(const Key('prev-week')), settledW39);
    expect(weekLabel(), '2026-W39');

    await _until(
      tester,
      () => find.text('Zeynep Kaya').evaluate().isNotEmpty,
    );
    expect(find.text('Zeynep Kaya'), findsOneWidget);
    expect(find.text('Mehmet Çelik'), findsOneWidget);
    expect(find.text('Ayşe Yılmaz'), findsNothing);
    // W39: Zeynep has one flagged entry (09-25 absence_streak), Mehmet none.
    expect(find.text('İşaretli: 1'), findsOneWidget);
    expect(find.text('İşaretli: 0'), findsNothing);

    await tester.pumpAndSettle(const Duration(seconds: 60));
  });

  testWidgets('parent: child without records shows inline empty text (stubbed summary)', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final session = (await tester.runAsync(() async {
      final s = SessionManager(TokenStore());
      await _awaitRestore(s);
      await s.setSession(
        const AuthSession(
          accessToken: 'stub-access',
          refreshToken: 'stub-refresh',
          userId: 'stub-parent',
          email: 'parent2@test.local',
          role: 'PARENT',
        ),
      );
      return s;
    }))!;

    final summary = WeekSummary(
      week: '2026-W39',
      start: '2026-09-21',
      end: '2026-09-25',
      students: const [
        SummaryStudent(
          id: 's-zeynep',
          name: 'Zeynep Kaya',
          attendance: {'PRESENT': 5},
          homework: {'DONE': 5},
          behavior: {'NEUTRAL': 5},
          flaggedCount: 1,
          notes: [],
        ),
        SummaryStudent(
          id: 's-mehmet',
          name: 'Mehmet Çelik',
          attendance: {},
          homework: {},
          behavior: {},
          flaggedCount: 0,
          notes: [],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWithValue(session),
          reportsRepositoryProvider.overrideWithValue(
            _StubReportsRepository(summary),
          ),
        ],
        child: const SafeCircleApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Both linked children are visible now (hasData filter is gone).
    expect(find.text('Zeynep Kaya'), findsOneWidget);
    expect(find.text('Mehmet Çelik'), findsOneWidget);
    expect(find.text('İşaretli: 1'), findsOneWidget);
    // Mehmet (no records) shows the message inside his card; Zeynep does not,
    // and the week-level empty state is suppressed because a child has data.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('summary-s-zeynep')),
        matching: find.text('Bu hafta için kayıt yok'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('summary-s-mehmet')),
        matching: find.text('Bu hafta için kayıt yok'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('Demo verileri 2026-W39 ve 2026-W40 haftalarında yüklüdür.'),
      findsNothing,
    );

    await tester.pumpAndSettle(const Duration(seconds: 60));
  });

  testWidgets('counselor lands on the Phase-4 placeholder, not a teacher screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ProviderScope(child: SafeCircleApp()));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'counselor1@test.local',
    );
    await tester.enterText(find.byType(TextFormField).at(1), _password);
    await tester.tap(find.text('Log in'));
    await tester.pump();

    await _until(
      tester,
      () => find.text('Hello, counselor').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();

    expect(find.text('Hello, counselor'), findsOneWidget);
    expect(find.text('COUNSELOR screens arrive in Phase 4'), findsOneWidget);
    expect(find.byType(TeacherHome), findsNothing);

    await tester.pumpAndSettle(const Duration(seconds: 60));
  });

  test('counselor cannot list classes — 403 from the roles guard', () async {
    final dio = await _authedDio('counselor1@test.local', _password);
    await expectLater(
      ClassesRepository(dio).listClasses(),
      throwsA(
        isA<DioException>().having(
          (error) => error.response?.statusCode,
          'statusCode',
          403,
        ),
      ),
    );
  });
}