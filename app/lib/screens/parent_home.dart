import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../reports/iso_week.dart';
import '../reports/report_values.dart';
import '../reports/reports_models.dart';

class ParentHome extends ConsumerStatefulWidget {
  const ParentHome({super.key});

  @override
  ConsumerState<ParentHome> createState() => _ParentHomeState();
}

class _ParentHomeState extends ConsumerState<ParentHome> {
  late DateTime _weekStart;
  WeekSummary? _summary;
  bool _loading = true;
  String? _error;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    final today = dateOnly(DateTime.now());
    _weekStart = today.subtract(Duration(days: today.weekday - 1));
    _load();
  }

  String get _week => isoWeekLabel(_weekStart);

  Future<void> _load() async {
    final token = ++_token;
    final week = _week;
    setState(() => _loading = true);
    try {
      final summary = await ref
          .read(reportsRepositoryProvider)
          .summaries(week: week);
      if (!mounted || token != _token) return;
      setState(() {
        _summary = summary;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = _messageFor(error);
      });
    }
  }

  void _shiftWeek(int weeks) {
    setState(() => _weekStart = _weekStart.add(Duration(days: 7 * weeks)));
    _load();
  }

  String _messageFor(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] is String) {
        return data['message'] as String;
      }
    }
    return 'Something went wrong. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final students = summary?.students ?? const <SummaryStudent>[];
    final anyData = students.any((student) => student.hasData);
    return Scaffold(
      appBar: AppBar(title: const Text('Haftalık Özet')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  key: const Key('prev-week'),
                  tooltip: 'Önceki hafta',
                  onPressed: _loading ? null : () => _shiftWeek(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    _week,
                    key: const Key('week-label'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: const Key('next-week'),
                  tooltip: 'Sonraki hafta',
                  onPressed: _loading ? null : () => _shiftWeek(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: Theme.of(context).textTheme.bodySmall),
              ),
            if (!_loading && _error == null) ...[
              ...students.map(_studentCard),
              if (!anyData)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    'Demo verileri 2026-W39 ve 2026-W40 haftalarında yüklüdür.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _studentCard(SummaryStudent student) {
    final hasData = student.hasData;
    return Card(
      key: ValueKey('summary-${student.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    student.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (hasData && student.flaggedCount > 0)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('İşaretli: ${student.flaggedCount}'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (!hasData)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Bu hafta için kayıt yok',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else ...[
              _counts('Yoklama', student.attendance, attendanceLabels),
              _counts('Ödev', student.homework, homeworkLabels),
              _counts('Davranış', student.behavior, behaviorLabels),
              for (final note in student.notes)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${note.date}: ${note.note}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _counts(String title, Map<String, int> counts, Map<String, String> labels) {
    final parts = [
      for (final entry in counts.entries)
        if (entry.value > 0) '${labels[entry.key] ?? entry.key}: ${entry.value}',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text('$title — ${parts.join(', ')}'),
    );
  }
}
