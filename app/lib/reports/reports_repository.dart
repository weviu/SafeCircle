import 'package:dio/dio.dart';

import 'reports_models.dart';

/// Teacher entry + parent summary endpoints of the reports module.
class ReportsRepository {
  ReportsRepository(this._dio);

  final Dio _dio;

  /// GET /reports/entries — the author's entries for one class + date.
  Future<List<ReportEntry>> listEntries({
    required String classId,
    required String date,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/reports/entries',
      queryParameters: {'classId': classId, 'date': date},
    );
    return [
      for (final raw in response.data ?? const [])
        ReportEntry.fromJson(raw as Map<String, dynamic>),
    ];
  }

  /// POST /reports/entries — upserts the whole class for one date.
  Future<List<ReportEntry>> createEntries({
    required String classId,
    required String reportDate,
    required List<EntryPayload> entries,
  }) async {
    final response = await _dio.post<List<dynamic>>(
      '/reports/entries',
      data: {
        'classId': classId,
        'reportDate': reportDate,
        'entries': [for (final entry in entries) entry.toJson()],
      },
    );
    return [
      for (final raw in response.data ?? const [])
        ReportEntry.fromJson(raw as Map<String, dynamic>),
    ];
  }

  /// GET /reports/summaries — parent's weekly summary (optional ISO week).
  Future<WeekSummary> summaries({String? week}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/reports/summaries',
      queryParameters: {if (week != null) 'week': week},
    );
    return WeekSummary.fromJson(response.data!);
  }
}
