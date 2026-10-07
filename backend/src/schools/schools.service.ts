import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Role } from '../generated/prisma';
import { PrismaService } from '../prisma.service';

const SCHOOL_SELECT = { id: true, name: true } as const;

@Injectable()
export class SchoolsService {
  constructor(private readonly prisma: PrismaService) {}

  async classesByIds(ids: string[]) {
    if (ids.length === 0) {
      return [];
    }
    return this.prisma.class.findMany({ where: { id: { in: ids } } });
  }

  async classesForTeacher(teacherId: string) {
    const links = await this.prisma.teacherClass.findMany({
      where: { teacherId },
      select: { classId: true },
    });
    if (links.length === 0) {
      return [];
    }
    return this.prisma.class.findMany({
      where: { id: { in: links.map((link) => link.classId) } },
      include: { school: { select: SCHOOL_SELECT } },
      orderBy: [{ grade: 'asc' }, { name: 'asc' }],
    });
  }

  async allClasses() {
    return this.prisma.class.findMany({
      include: { school: { select: SCHOOL_SELECT } },
      orderBy: [{ grade: 'asc' }, { name: 'asc' }],
    });
  }

  /**
   * Shared 404/403 gate for "may this user act on this class?".
   * Unknown class -> 404; admin -> always allowed; anyone else must have a
   * teacher_class link -> 403. Returns the class row.
   */
  async requireClassAccess(userId: string, role: Role, classId: string) {
    const classes = await this.classesByIds([classId]);
    if (classes.length === 0) {
      throw new NotFoundException(`class ${classId} not found`);
    }
    if (role === Role.ADMIN) {
      return classes[0];
    }
    const owned = await this.classesForTeacher(userId);
    if (!owned.some((cls) => cls.id === classId)) {
      throw new ForbiddenException('you do not teach this class');
    }
    return classes[0];
  }

  async studentsInClass(classId: string) {
    return this.prisma.student.findMany({
      where: { classId },
      orderBy: [{ schoolNumber: 'asc' }],
    });
  }

  async studentsByIds(ids: string[]) {
    if (ids.length === 0) {
      return [];
    }
    return this.prisma.student.findMany({ where: { id: { in: ids } } });
  }

  async studentsInSchool(schoolId: string) {
    return this.prisma.student.findMany({ where: { class: { schoolId } } });
  }

  async schoolsForCounselor(counselorId: string) {
    const links = await this.prisma.counselorSchool.findMany({
      where: { counselorId },
      select: { schoolId: true },
    });
    if (links.length === 0) {
      return [];
    }
    return this.prisma.school.findMany({ where: { id: { in: links.map((link) => link.schoolId) } } });
  }
}
