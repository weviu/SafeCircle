import { argon2id, hash } from 'argon2';
import { PrismaClient, Role } from '../src/generated/prisma';

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
