const attendanceValues = ['PRESENT', 'ABSENT', 'LATE', 'EXCUSED'];
const homeworkValues = ['DONE', 'PARTIAL', 'NOT_DONE', 'NOT_GIVEN'];
const behaviorValues = ['POSITIVE', 'NEUTRAL', 'CONCERN', 'SEVERE'];

const attendanceLabels = {
  'PRESENT': 'Var',
  'ABSENT': 'Devamsız',
  'LATE': 'Geç',
  'EXCUSED': 'İzinli',
};

const homeworkLabels = {
  'DONE': 'Yapıldı',
  'PARTIAL': 'Kısmen',
  'NOT_DONE': 'Yapılmadı',
  'NOT_GIVEN': 'Verilmedi',
};

const behaviorLabels = {
  'POSITIVE': 'Olumlu',
  'NEUTRAL': 'Nötr',
  'CONCERN': 'Uyarı',
  'SEVERE': 'Şiddetli',
};

const flagReasonLabels = {
  'behavior_severe': 'Şiddetli davranış',
  'behavior_concern': 'Uyarı davranışı',
  'absence_streak': 'Devamsızlık şeridi',
  'homework_streak': 'Ödev şeridi',
};

String flagLabel(String reason) => flagReasonLabels[reason] ?? reason;
