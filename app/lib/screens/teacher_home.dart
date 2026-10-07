import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../reports/iso_week.dart';
import '../reports/report_values.dart';
import '../reports/reports_models.dart';

class TeacherHome extends ConsumerStatefulWidget {
  const TeacherHome({super.key});

  @override
  ConsumerState<TeacherHome> createState() => _TeacherHomeState();
}

class _EntryDraft {
  _EntryDraft({
    required this.attendance,
    required this.homework,
    required this.behavior,
    this.note,
  });

  String attendance;
  String homework;
  String behavior;
  String? note;

  factory _EntryDraft.from(ReportEntry? entry) => _EntryDraft(
    attendance: entry?.attendance ?? 'PRESENT',
    homework: entry?.homework ?? 'DONE',
    behavior: entry?.behavior ?? 'NEUTRAL',
    note: entry?.note,
  );
}

class _TeacherHomeState extends ConsumerState<TeacherHome> {
  List<SchoolClass> _classes = const [];
  SchoolClass? _class;
  List<Student> _students = const [];
  Map<String, ReportEntry> _entries = {};
  Map<String, _EntryDraft> _drafts = {};
  final Map<String, TextEditingController> _noteControllers = {};
  DateTime _date = dateOnly(DateTime.now());
  bool _loadingClasses = true;
  bool _loading = false;
  bool _submitting = false;
  String? _error;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  @override
  void dispose() {
    for (final controller in _noteControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _disposeNoteControllers() {
    for (final controller in _noteControllers.values) {
      controller.dispose();
    }
    _noteControllers.clear();
  }

  Future<void> _loadClasses() async {
    setState(() => _loadingClasses = true);
    try {
      final classes = await ref.read(classesRepositoryProvider).listClasses();
      if (!mounted) return;
      setState(() {
        _classes = classes;
        _loadingClasses = false;
        _class ??= classes.isEmpty ? null : classes.first;
      });
      if (_class != null) await _reload(refreshStudents: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingClasses = false;
        _error = _messageFor(error);
      });
    }
  }

  Future<void> _reload({bool refreshStudents = false}) async {
    final cls = _class;
    if (cls == null) return;
    final token = ++_token;
    setState(() => _loading = true);
    try {
      if (refreshStudents || _students.isEmpty) {
        final students = await ref
            .read(classesRepositoryProvider)
            .listStudents(cls.id);
        if (!mounted || token != _token || _class?.id != cls.id) return;
        setState(() => _students = students);
      }
      final date = isoDate(_date);
      final entries = await ref
          .read(reportsRepositoryProvider)
          .listEntries(classId: cls.id, date: date);
      if (!mounted || token != _token || _class?.id != cls.id) return;
      _applyEntries(entries);
      setState(() {
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

  void _applyEntries(List<ReportEntry> entries) {
    final byStudent = {for (final entry in entries) entry.studentId: entry};
    setState(() {
      _entries = byStudent;
      _drafts = {
        for (final student in _students)
          student.id: _EntryDraft.from(byStudent[student.id]),
      };
      for (final student in _students) {
        final controller = _noteControllers[student.id];
        if (controller == null) continue;
        final note = byStudent[student.id]?.note ?? '';
        if (controller.text != note) controller.text = note;
      }
    });
  }

  void _selectClass(SchoolClass? cls) {
    if (cls == null || cls.id == _class?.id) return;
    setState(() {
      _class = cls;
      _students = const [];
      _entries = {};
      _drafts = {};
    });
    _disposeNoteControllers();
    _reload(refreshStudents: true);
  }

  void _shiftDate(int days) {
    setState(() => _date = dateOnly(_date.add(Duration(days: days))));
    _reload();
  }

  void _setDraft(String studentId, {String? attendance, String? homework, String? behavior}) {
    final draft = _drafts[studentId];
    if (draft == null) return;
    setState(() {
      if (attendance != null) draft.attendance = attendance;
      if (homework != null) draft.homework = homework;
      if (behavior != null) draft.behavior = behavior;
    });
  }

  TextEditingController _noteController(String studentId) {
    return _noteControllers.putIfAbsent(
      studentId,
      () => TextEditingController(text: _drafts[studentId]?.note ?? ''),
    );
  }

  void _setDraftNote(String studentId, String value) {
    final draft = _drafts[studentId];
    if (draft == null) return;
    setState(() => draft.note = value);
  }

  /// Empty/whitespace-only notes are sent as *absent*, which the backend
  /// stores as NULL (`note: input.note ?? null`) — the variant that lets a
  /// teacher clear a previously saved note. A literal empty string would be
  /// persisted instead, so it is never sent.
  String? _notePayload(_EntryDraft draft) {
    final note = draft.note;
    if (note == null || note.trim().isEmpty) return null;
    return note;
  }

  Future<void> _submit() async {
    final cls = _class;
    if (cls == null || _students.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    final payload = [
      for (final student in _students)
        EntryPayload(
          studentId: student.id,
          attendance: _drafts[student.id]?.attendance ?? 'PRESENT',
          homework: _drafts[student.id]?.homework ?? 'DONE',
          behavior: _drafts[student.id]?.behavior ?? 'NEUTRAL',
          note: _notePayload(_drafts[student.id] ?? _EntryDraft.from(null)),
        ),
    ];
    try {
      final saved = await ref
          .read(reportsRepositoryProvider)
          .createEntries(
            classId: cls.id,
            reportDate: isoDate(_date),
            entries: payload,
          );
      if (!mounted) return;
      _applyEntries(saved);
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydedildi (${saved.length} öğrenci)')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
    }
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
    return Scaffold(
      appBar: AppBar(title: const Text('Günlük Rapor')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_classes.isEmpty && !_loadingClasses)
              const Text('Atandığınız sınıf yok')
            else
              DropdownButton<SchoolClass>(
                value: _class,
                isExpanded: true,
                items: [
                  for (final cls in _classes)
                    DropdownMenuItem(value: cls, child: Text(cls.label)),
                ],
                onChanged: _loading ? null : _selectClass,
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  key: const Key('prev-day'),
                  tooltip: 'Önceki gün',
                  onPressed: _loading ? null : () => _shiftDate(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    isoDate(_date),
                    key: const Key('date-label'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: const Key('next-day'),
                  tooltip: 'Sonraki gün',
                  onPressed: _loading ? null : () => _shiftDate(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (_loading || _loadingClasses) const LinearProgressIndicator(),
            if (_error != null) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: Theme.of(context).textTheme.bodySmall),
            ),
            if (!_loading && _students.isEmpty && _class != null)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text('Bu sınıfta öğrenci yok'),
              ),
            const SizedBox(height: 8),
            for (final student in _students) _studentCard(student),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('submit'),
              onPressed:
                  _loading || _loadingClasses || _submitting || _students.isEmpty
                      ? null
                      : _submit,
              child:
                  _submitting
                      ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _studentCard(Student student) {
    final draft = _drafts[student.id] ?? _EntryDraft.from(null);
    final entry = _entries[student.id];
    return Card(
      key: ValueKey('student-${student.schoolNumber}'),
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
                Text(
                  student.schoolNumber,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if (entry != null && entry.flagged && entry.flagReason != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(flagLabel(entry.flagReason!)),
                ),
              ),
            const SizedBox(height: 8),
            _valuePicker(
              studentId: student.id,
              label: 'Yoklama',
              values: attendanceValues,
              labels: attendanceLabels,
              selected: draft.attendance,
              onSelected: (value) => _setDraft(student.id, attendance: value),
            ),
            _valuePicker(
              studentId: student.id,
              label: 'Ödev',
              values: homeworkValues,
              labels: homeworkLabels,
              selected: draft.homework,
              onSelected: (value) => _setDraft(student.id, homework: value),
            ),
            _valuePicker(
              studentId: student.id,
              label: 'Davranış',
              values: behaviorValues,
              labels: behaviorLabels,
              selected: draft.behavior,
              onSelected: (value) => _setDraft(student.id, behavior: value),
            ),
            const SizedBox(height: 4),
            TextField(
              key: ValueKey('note-${student.schoolNumber}'),
              controller: _noteController(student.id),
              onChanged: (value) => _setDraftNote(student.id, value),
              maxLines: 2,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Öğretmen notu',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _valuePicker({
    required String studentId,
    required String label,
    required List<String> values,
    required Map<String, String> labels,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          SegmentedButton<String>(
            segments: [
              for (final value in values)
                ButtonSegment(value: value, label: Text(labels[value]!)),
            ],
            selected: {selected},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => onSelected(selection.first),
          ),
        ],
      ),
    );
  }
}
