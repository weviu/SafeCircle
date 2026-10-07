import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safecircle/config/api_config.dart';
import 'package:safecircle/notifications/notifications_models.dart';
import 'package:safecircle/notifications/notifications_providers.dart';
import 'package:safecircle/notifications/notifications_repository.dart';
import 'package:safecircle/notifications/ntfy_events.dart';
import 'package:safecircle/screens/notifications_screen.dart';

AppNotification _notification(String id, String title, {bool read = false}) {
  return AppNotification(
    id: id,
    type: 'REPORT_FLAG',
    title: title,
    body: '$title gövdesi',
    data: null,
    readAt: read ? DateTime(2026, 10, 7) : null,
    createdAt: DateTime(2026, 10, 7),
  );
}

void main() {
  group('tryParseNtfyMessageLine', () {
    test('decodes an ntfy message event line', () {
      const line =
          '{"id":"abc123","time":1690000000,"event":"message","topic":"sc-topic","title":"Uyarı","message":"metin"}';
      final message = tryParseNtfyMessageLine(line);
      expect(message, isNotNull);
      expect(message!.id, 'abc123');
      expect(message.topic, 'sc-topic');
      expect(message.title, 'Uyarı');
      expect(message.message, 'metin');
    });

    test('ignores open/keepalive housekeeping events', () {
      expect(tryParseNtfyMessageLine('{"event":"open","topic":"t"}'), isNull);
      expect(tryParseNtfyMessageLine('{"event":"keepalive"}'), isNull);
    });

    test('ignores garbage and html', () {
      expect(tryParseNtfyMessageLine(''), isNull);
      expect(tryParseNtfyMessageLine('not json'), isNull);
      expect(tryParseNtfyMessageLine('<!doctype html><html>...'), isNull);
    });
  });

  group('parseNtfyEvents', () {
    test('splits lines, drops housekeeping, returns trailing remainder', () {
      const chunk =
          '{"event":"open","topic":"sc-t"}\n'
          '{"id":"1","event":"message","topic":"sc-t","message":"hey"}\n'
          '{"event":"keepalive"}\n'
          '{"id":"2","event":"message","topic":"sc-t"}';

      final result = parseNtfyEvents(chunk);

      expect(result.messages, hasLength(1));
      expect(result.messages.single.id, '1');
      expect(result.messages.single.message, 'hey');
      expect(result.remainder, '{"id":"2","event":"message","topic":"sc-t"}');
    });

    test('a message split across chunks is recovered via the remainder', () {
      const firstChunk = '{"id":"x","event":"message","topic":"t","title":"Uyar\u0131';
      final afterFirst = parseNtfyEvents(firstChunk);
      expect(afterFirst.messages, isEmpty);
      expect(afterFirst.remainder, firstChunk);

      const secondChunk =
          ': Zeynep","message":"metin"}\n{"event":"keepalive"}\n';
      final afterSecond = parseNtfyEvents(afterFirst.remainder + secondChunk);

      expect(afterSecond.messages, hasLength(1));
      expect(afterSecond.messages.single.title, 'Uyarı: Zeynep');
      expect(afterSecond.messages.single.message, 'metin');
      expect(afterSecond.remainder, '');
    });

    test('a message without a trailing newline is held in the remainder', () {
      const chunk = '{"event":"open","topic":"t"}\n{"id":"y","event":"message"}';
      final result = parseNtfyEvents(chunk);
      expect(result.messages, isEmpty);
      expect(result.remainder, '{"id":"y","event":"message"}');
    });
  });

  group('NotificationsScreen pull-to-refresh', () {
    // Stubbed rather than live: driving a real HTTP call from a fling cannot
    // settle under flutter_test's fake async, so the refresh itself is fed
    // instant futures and asserted on the rows it swaps in.
    testWidgets('re-fetches and swaps the rows', (tester) async {
      final repository = _SequencedNotificationsRepository([
        NotificationList(
          unreadCount: 1,
          items: [_notification('n1', 'İlk satır')],
        ),
        NotificationList(
          unreadCount: 2,
          items: [
            _notification('n1', 'İlk satır', read: true),
            _notification('n2', 'Yeni satır'),
          ],
        ),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationsRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: NotificationsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('İlk satır'), findsOneWidget);
      expect(find.text('Yeni satır'), findsNothing);
      expect(repository.listCalls, 1);

      await tester.fling(
        find.byType(ListView),
        const Offset(0, 300),
        1000,
      );
      await tester.pumpAndSettle();

      expect(repository.listCalls, 2);
      expect(find.text('Yeni satır'), findsOneWidget);
    });
  });
}

/// Returns each queued [NotificationList] in turn, so a refresh can be told
/// apart from the initial load.
class _SequencedNotificationsRepository extends NotificationsRepository {
  _SequencedNotificationsRepository(this._responses)
    : super(Dio(BaseOptions(baseUrl: ApiConfig.baseUrl)));

  final List<NotificationList> _responses;
  int listCalls = 0;

  @override
  Future<NotificationList> list({int limit = 50}) async {
    final response = _responses[listCalls.clamp(0, _responses.length - 1)];
    listCalls++;
    return response;
  }

  @override
  Future<int> unreadCount() async => _responses[listCalls.clamp(0, _responses.length - 1)].unreadCount;

  @override
  Future<void> markRead(String id) => throw UnimplementedError();

  @override
  Future<void> markAllRead() => throw UnimplementedError();

  @override
  Future<AppSubscription> subscribe() => throw UnimplementedError();
}