class School {
  const School({required this.id, required this.name});

  final String id;
  final String name;

  factory School.fromJson(Map<String, dynamic> json) {
    return School(id: json['id'] as String, name: json['name'] as String);
  }
}

class SchoolClass {
  const SchoolClass({
    required this.id,
    required this.name,
    required this.grade,
    required this.school,
  });

  final String id;
  final String name;
  final String grade;
  final School school;

  /// Display label, e.g. `5-A`.
  String get label => '$grade-$name';

  factory SchoolClass.fromJson(Map<String, dynamic> json) {
    return SchoolClass(
      id: json['id'] as String,
      name: json['name'] as String,
      grade: json['grade'] as String,
      school: School.fromJson(json['school'] as Map<String, dynamic>),
    );
  }
}

class Student {
  const Student({
    required this.id,
    required this.name,
    required this.schoolNumber,
  });

  final String id;
  final String name;
  final String schoolNumber;

  factory Student.fromJson(Map<String, dynamic> json) {
    return Student(
      id: json['id'] as String,
      name: json['name'] as String,
      schoolNumber: json['schoolNumber'] as String,
    );
  }
}

class ReportEntry {
  const ReportEntry({
    required this.studentId,
    required this.attendance,
    required this.homework,
    required this.behavior,
    required this.note,
    required this.flagged,
    required this.flagReason,
  });

  final String studentId;
  final String attendance;
  final String homework;
  final String behavior;
  final String? note;
  final bool flagged;
  final String? flagReason;

  factory ReportEntry.fromJson(Map<String, dynamic> json) {
    return ReportEntry(
      studentId: json['studentId'] as String,
      attendance: json['attendance'] as String,
      homework: json['homework'] as String,
      behavior: json['behavior'] as String,
      note: json['note'] as String?,
      flagged: json['flagged'] as bool? ?? false,
      flagReason: json['flagReason'] as String?,
    );
  }
}

class EntryPayload {
  const EntryPayload({
    required this.studentId,
    required this.attendance,
    required this.homework,
    required this.behavior,
    this.note,
  });

  final String studentId;
  final String attendance;
  final String homework;
  final String behavior;
  final String? note;

  Map<String, dynamic> toJson() {
    return {
      'studentId': studentId,
      'attendance': attendance,
      'homework': homework,
      'behavior': behavior,
      if (note != null) 'note': note,
    };
  }
}

class SummaryNote {
  const SummaryNote({required this.date, required this.note});

  final String date;
  final String note;

  factory SummaryNote.fromJson(Map<String, dynamic> json) {
    return SummaryNote(date: json['date'] as String, note: json['note'] as String);
  }
}

class SummaryStudent {
  const SummaryStudent({
    required this.id,
    required this.name,
    required this.attendance,
    required this.homework,
    required this.behavior,
    required this.flaggedCount,
    required this.notes,
  });

  final String id;
  final String name;
  final Map<String, int> attendance;
  final Map<String, int> homework;
  final Map<String, int> behavior;
  final int flaggedCount;
  final List<SummaryNote> notes;

  bool get hasData {
    if (flaggedCount > 0 || notes.isNotEmpty) return true;
    return attendance.values.any((v) => v > 0) ||
        homework.values.any((v) => v > 0) ||
        behavior.values.any((v) => v > 0);
  }

  factory SummaryStudent.fromJson(Map<String, dynamic> json) {
    Map<String, int> counts(String key) {
      final raw = json[key] as Map<String, dynamic>;
      return raw.map((k, v) => MapEntry(k, (v as num).toInt()));
    }

    return SummaryStudent(
      id: json['id'] as String,
      name: json['name'] as String,
      attendance: counts('attendance'),
      homework: counts('homework'),
      behavior: counts('behavior'),
      flaggedCount: json['flaggedCount'] as int? ?? 0,
      notes: [
        for (final raw in json['notes'] as List<dynamic>? ?? const [])
          SummaryNote.fromJson(raw as Map<String, dynamic>),
      ],
    );
  }
}

class WeekSummary {
  const WeekSummary({
    required this.week,
    required this.start,
    required this.end,
    required this.students,
  });

  final String week;
  final String start;
  final String end;
  final List<SummaryStudent> students;

  bool get hasAnyData => students.any((student) => student.hasData);

  factory WeekSummary.fromJson(Map<String, dynamic> json) {
    return WeekSummary(
      week: json['week'] as String,
      start: json['start'] as String,
      end: json['end'] as String,
      students: [
        for (final raw in json['students'] as List<dynamic>? ?? const [])
          SummaryStudent.fromJson(raw as Map<String, dynamic>),
      ],
    );
  }
}
