import { argon2id, hash } from 'argon2';
import { Attendance, Behavior, Homework, PrismaClient, Role } from '../src/generated/prisma';
import { evaluateFlags } from '../src/reports/flagging';

const SEED_PASSWORD = 'Passw0rd!123';

const prisma = new PrismaClient();

async function upsertUser(email: string, role: Role): Promise<string> {
  const existing = await prisma.user.findUnique({ where: { email } });
  if (existing) {
    return existing.id;
  }
  const passwordHash = await hash(SEED_PASSWORD, { type: argon2id });
  const created = await prisma.user.create({ data: { email, passwordHash, role } });
  console.log(`created user ${email}`);
  return created.id;
}

async function upsertSchool(name: string): Promise<string> {
  const existing = await prisma.school.findFirst({ where: { name } });
  if (existing) {
    return existing.id;
  }
  const created = await prisma.school.create({ data: { name } });
  console.log(`created school ${name}`);
  return created.id;
}

async function upsertClass(schoolId: string, name: string, grade: string): Promise<string> {
  const existing = await prisma.class.findFirst({ where: { schoolId, name, grade } });
  if (existing) {
    return existing.id;
  }
  const created = await prisma.class.create({ data: { schoolId, name, grade } });
  console.log(`created class ${grade}-${name}`);
  return created.id;
}

async function upsertStudent(classId: string, name: string, schoolNumber: string): Promise<string> {
  const existing = await prisma.student.findFirst({ where: { schoolNumber } });
  if (existing) {
    return existing.id;
  }
  const created = await prisma.student.create({ data: { classId, name, schoolNumber } });
  console.log(`created student ${name} (${schoolNumber})`);
  return created.id;
}

const REPORT_DAYS = [
  '2026-09-21', // Mon, ISO week 2026-W39
  '2026-09-22',
  '2026-09-23',
  '2026-09-24',
  '2026-09-25', // Fri
  '2026-09-28', // Mon, ISO week 2026-W40
  '2026-09-29',
  '2026-09-30',
  '2026-10-01',
  '2026-10-02', // Fri
];

interface SeedEntryValues {
  attendance: Attendance;
  homework: Homework;
  behavior: Behavior;
  note: string | null;
}

function baseEntry(studentIdx: number, dayIdx: number): SeedEntryValues {
  let attendance: Attendance = Attendance.PRESENT;
  if ((studentIdx + dayIdx) % 7 === 3) {
    attendance = Attendance.LATE;
  } else if ((studentIdx * 2 + dayIdx) % 11 === 5) {
    attendance = Attendance.EXCUSED;
  }

  let homework: Homework = Homework.DONE;
  if ((studentIdx + dayIdx) % 5 === 2) {
    homework = Homework.PARTIAL;
  } else if ((studentIdx + dayIdx) % 13 === 9) {
    homework = Homework.NOT_GIVEN;
  }

  const behavior: Behavior = (studentIdx + dayIdx) % 6 === 0 ? Behavior.POSITIVE : Behavior.NEUTRAL;
  const note =
    (studentIdx + dayIdx) % 4 === 0 ? `Note for student ${studentIdx}, day ${dayIdx}.` : null;

  return { attendance, homework, behavior, note };
}

function applySeedOverrides(
  studentIdx: number,
  dayIdx: number,
  base: SeedEntryValues,
): SeedEntryValues {
  const values = { ...base };
  // 1003 Zeynep (class A): present Mon-Tue, absent Wed-Fri of W39
  // -> absence_streak flag appears only at day 4 (Fri), not before
  if (studentIdx === 2 && dayIdx <= 1) {
    values.attendance = Attendance.PRESENT;
  }
  if (studentIdx === 2 && dayIdx >= 2 && dayIdx <= 4) {
    values.attendance = Attendance.ABSENT;
  }
  // 1001 Ayşe (class A): NOT_DONE Tue-Thu of W40 -> homework_streak flag at day 8
  if (studentIdx === 0 && dayIdx >= 6 && dayIdx <= 8) {
    values.homework = Homework.NOT_DONE;
  }
  // 1006 Can (class B): severe behavior day 1 (W39)
  if (studentIdx === 5 && dayIdx === 1) {
    values.behavior = Behavior.SEVERE;
  }
  // 1004 Mehmet (class B): concern behavior day 7 (W40)
  if (studentIdx === 3 && dayIdx === 7) {
    values.behavior = Behavior.CONCERN;
  }
  return values;
}

async function main(): Promise<void> {
  const adminId = await upsertUser('admin@test.local', Role.ADMIN);
  const counselorId = await upsertUser('counselor1@test.local', Role.COUNSELOR);
  const teacher1Id = await upsertUser('teacher1@test.local', Role.TEACHER);
  const teacher2Id = await upsertUser('teacher2@test.local', Role.TEACHER);
  const parent1Id = await upsertUser('parent1@test.local', Role.PARENT);
  const parent2Id = await upsertUser('parent2@test.local', Role.PARENT);
  const parent3Id = await upsertUser('parent3@test.local', Role.PARENT);
  void adminId;

  const schoolId = await upsertSchool('Test Okulu');
  const classAId = await upsertClass(schoolId, 'A', '5');
  const classBId = await upsertClass(schoolId, 'B', '6');

  const student1Id = await upsertStudent(classAId, 'Ayşe Yılmaz', '1001');
  const student2Id = await upsertStudent(classAId, 'Emre Demir', '1002');
  const student3Id = await upsertStudent(classAId, 'Zeynep Kaya', '1003');
  const student4Id = await upsertStudent(classBId, 'Mehmet Çelik', '1004');
  const student5Id = await upsertStudent(classBId, 'Elif Şahin', '1005');
  const student6Id = await upsertStudent(classBId, 'Can Öztürk', '1006');

  await prisma.counselorSchool.upsert({
    where: { counselorId_schoolId: { counselorId, schoolId } },
    create: { counselorId, schoolId },
    update: {},
  });

  await prisma.teacherClass.upsert({
    where: { teacherId_classId: { teacherId: teacher1Id, classId: classAId } },
    create: { teacherId: teacher1Id, classId: classAId },
    update: {},
  });
  await prisma.teacherClass.upsert({
    where: { teacherId_classId: { teacherId: teacher2Id, classId: classBId } },
    create: { teacherId: teacher2Id, classId: classBId },
    update: {},
  });

  const parentLinks: Array<[string, string]> = [
    [parent1Id, student1Id],
    [parent1Id, student2Id],
    [parent2Id, student3Id],
    [parent2Id, student4Id],
    [parent3Id, student5Id],
    [parent3Id, student6Id],
  ];
  for (const [parentId, studentId] of parentLinks) {
    await prisma.parentStudent.upsert({
      where: { parentId_studentId: { parentId, studentId } },
      create: { parentId, studentId },
      update: {},
    });
  }

  const studentIds = [student1Id, student2Id, student3Id, student4Id, student5Id, student6Id];
  let entriesCreated = 0;
  let entriesSkipped = 0;
  let entriesFlagged = 0;
  for (const [dayIdx, day] of REPORT_DAYS.entries()) {
    const reportDate = new Date(`${day}T00:00:00Z`);
    for (const [studentIdx, studentId] of studentIds.entries()) {
      const authorId = studentIdx < 3 ? teacher1Id : teacher2Id;
      const existing = await prisma.reportEntry.findUnique({
        where: { studentId_authorId_reportDate: { studentId, authorId, reportDate } },
        select: { id: true },
      });
      if (existing) {
        entriesSkipped += 1;
        continue;
      }
      const values = applySeedOverrides(studentIdx, dayIdx, baseEntry(studentIdx, dayIdx));
      const context = await prisma.reportEntry.findMany({
        where: { studentId, NOT: { authorId, reportDate } },
      });
      const flags = evaluateFlags(
        {
          reportDate,
          attendance: values.attendance,
          homework: values.homework,
          behavior: values.behavior,
        },
        context,
      );
      const created = await prisma.reportEntry.create({
        data: { studentId, authorId, reportDate, ...values, ...flags },
      });
      entriesCreated += 1;
      if (created.flagged) {
        entriesFlagged += 1;
      }
    }
  }
  console.log(
    `Report entries: ${entriesCreated} created, ${entriesSkipped} skipped (already present), ${entriesFlagged} newly flagged`,
  );

  console.log('Seed complete.');
  console.log(`Dev password for all seeded users: ${SEED_PASSWORD}`);
  console.log(
    [
      'admin@test.local (admin)',
      'counselor1@test.local (counselor)',
      'teacher1@test.local (teacher, class 5-A)',
      'teacher2@test.local (teacher, class 6-B)',
      'parent1@test.local (parents of 1001, 1002)',
      'parent2@test.local (parents of 1003, 1004)',
      'parent3@test.local (parents of 1005, 1006)',
    ].join('\n'),
  );
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
