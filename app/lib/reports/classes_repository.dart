import 'package:dio/dio.dart';

import 'reports_models.dart';

/// GET /classes and GET /classes/:id/students (teacher/admin).
class ClassesRepository {
  ClassesRepository(this._dio);

  final Dio _dio;

  Future<List<SchoolClass>> listClasses() async {
    final response = await _dio.get<List<dynamic>>('/classes');
    return [
      for (final raw in response.data ?? const [])
        SchoolClass.fromJson(raw as Map<String, dynamic>),
    ];
  }

  Future<List<Student>> listStudents(String classId) async {
    final response = await _dio.get<List<dynamic>>('/classes/$classId/students');
    return [
      for (final raw in response.data ?? const [])
        Student.fromJson(raw as Map<String, dynamic>),
    ];
  }
}
