import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma.service';

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
    return this.prisma.class.findMany({ where: { id: { in: links.map((link) => link.classId) } } });
  }

  async studentsInClass(classId: string) {
    return this.prisma.student.findMany({ where: { classId } });
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
