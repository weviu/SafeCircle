/// ISO-8601 week helpers (Mon–Sun weeks, week 1 contains Jan 4).
String isoWeekLabel(DateTime date) {
  final day = DateTime.utc(date.year, date.month, date.day);
  final thursday = day.add(Duration(days: 4 - day.weekday));
  final year = thursday.year;
  final jan4 = DateTime.utc(year, 1, 4);
  final week1Monday = jan4.subtract(Duration(days: jan4.weekday - 1));
  final week = thursday.difference(week1Monday).inDays ~/ 7 + 1;
  return '$year-W${week.toString().padLeft(2, '0')}';
}

DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// `yyyy-MM-dd` (the format the backend expects/returns).
String isoDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
