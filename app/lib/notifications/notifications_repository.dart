import 'package:dio/dio.dart';

import 'notifications_models.dart';

class NotificationsRepository {
  NotificationsRepository(this._dio);

  final Dio _dio;

  Future<NotificationList> list({int limit = 50}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/notifications',
      queryParameters: {'limit': limit},
    );
    return NotificationList.fromJson(response.data!);
  }

  Future<int> unreadCount() async =>
      (await _dio.get<Map<String, dynamic>>('/notifications')).data!['unreadCount'] as int;

  Future<void> markRead(String id) async {
    await _dio.post<void>('/notifications/$id/read');
  }

  Future<void> markAllRead() async {
    await _dio.post<void>('/notifications/read-all');
  }

  Future<AppSubscription> subscribe() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/notifications/subscribe',
      data: {'platform': 'flutter'},
    );
    return AppSubscription.fromJson(response.data!);
  }
}

class AppSubscription {
  const AppSubscription({required this.topic});

  final String topic;

  factory AppSubscription.fromJson(Map<String, dynamic> json) {
    return AppSubscription(topic: json['topic'] as String);
  }
}