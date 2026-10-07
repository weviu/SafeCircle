import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'notifications_repository.dart';
import 'ntfy_events.dart';

/// Owns the Foreground notification session: subscribes to a stable push
/// topic, keeps an ntfy JSON-event stream open (with reconnect backoff), and
/// tracks the unread badge count.
///
/// The stream is best effort: parse errors or HTTP failures are swallowed and
/// the session reconnects with exponential backoff capped at 30 seconds.
class PushController extends ChangeNotifier {
  PushController({required NotificationsRepository repository, required Dio dio})
      : _repository = repository,
        _dio = dio;

  final NotificationsRepository _repository;
  final Dio _dio;

  int unreadCount = 0;
  String? topic;
  bool _started = false;
  bool _listening = false;
  bool _disposed = false;
  String? _streamTopic;
  CancelToken? _streamToken;
  Timer? _reconnectTimer;
  String _carry = '';

  bool get hasUnread => unreadCount > 0;

  /// Called once when the authenticated area mounts. Safe to retry: repeated
  /// calls are no-ops for the lifetime of the controller.
  Future<void> startSession() async {
    if (_started) {
      return;
    }
    _started = true;
    try {
      final subscription = await _repository.subscribe();
      topic = subscription.topic;
      notifyListeners();
      _listen(topic!);
    } catch (_) {
      // Session expired or backend unreachable; the unread badge still works,
      // so do not tear anything down from here.
    }
    await refreshUnread();
  }

  Future<void> refreshUnread() async {
    final int count;
    try {
      count = await _repository.unreadCount();
    } catch (_) {
      return;
    }
    if (count == unreadCount) {
      return;
    }
    unreadCount = count;
    notifyListeners();
  }

  Future<void> readAll() async {
    try {
      await _repository.markAllRead();
    } catch (_) {
      return;
    }
    unreadCount = 0;
    notifyListeners();
  }

  void stopSession() {
    _listening = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _streamToken?.cancel();
    _streamToken = null;
    _streamTopic = null;
  }

  void _listen(String topic, {int attempt = 0}) {
    if (_disposed || !_started) {
      return;
    }
    _listening = true;
    _streamTopic = topic;
    final token = CancelToken();
    _streamToken = token;
    runZonedGuarded(() async {
      try {
        final response = await _dio.get<ResponseBody>(
          '/ntfy/$topic/json',
          options: Options(responseType: ResponseType.stream),
          cancelToken: token,
        );
        final stream = response.data?.stream;
        if (stream == null) {
          _scheduleReconnect(topic, attempt);
          return;
        }
        await for (final chunk in stream) {
          final decoded = utf8.decode(chunk, allowMalformed: true);
          final result = parseNtfyEvents(_carry + decoded);
          _carry = result.remainder;
          if (result.messages.isNotEmpty) {
            await refreshUnread();
          }
        }
        _scheduleReconnect(topic, attempt);
      } catch (_) {
        if (_disposed || !_listening || _streamTopic != topic || token.isCancelled) {
          return;
        }
        _scheduleReconnect(topic, attempt);
      }
    }, (_, __) {
      _scheduleReconnect(topic, attempt);
    });
  }

  void _scheduleReconnect(String topic, int attempt) {
    if (_disposed || !_listening || _streamTopic != topic) {
      return;
    }
    _reconnectTimer?.cancel();
    final delaySeconds = math.min(30, 1 << attempt);
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (_disposed || !_listening || _streamTopic != topic) {
        return;
      }
      _listen(topic, attempt: attempt + 1);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    stopSession();
    super.dispose();
  }
}