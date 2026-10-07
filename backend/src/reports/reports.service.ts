import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Attendance, Behavior, Homework, Prisma, ReportEntry, Role } from '../generated/prisma';
import { PrismaService } from '../prisma.service';
import { SchoolsService } from '../schools/schools.service';
import { UsersService, UserProfile } from '../users/users.service';
import { evaluateFlags } from './flagging';
import { currentWeek, parseIsoWeek, toUtcDateString } from './iso-week';
import { CreateReportDto } from './dto/create-report.dto';
import { UpdateReportEntryDto } from './dto/update-report-entry.dto';

@Injectable()
export class ReportsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly schools: SchoolsService,
    private readonly users: UsersService,
  ) {}

  async createEntries(authorId: string, dto: CreateReportDto) {
    await this.requireOwnedClass(authorId, dto.classId);

    const seen = new Set<string>();
    for (const entry of dto.entries) {
      if (seen.has(entry.studentId)) {
        throw new BadRequestException(`duplicate studentId in payload: ${entry.studentId}`);
      }
      seen.add(entry.studentId);
    }
    const studentIds = [...seen];

    const known = await this.schools.studentsByIds(studentIds);
    const knownIds = new Set(known.map((student) => student.id));
    const unknown = studentIds.filter((id) => !knownIds.has(id));
    if (unknown.length > 0) {
      throw new NotFoundException(`students not found: ${unknown.join(', ')}`);
    }
    const inClass = await this.schools.studentsInClass(dto.classId);
    const inClassIds = new Set(inClass.map((student) => student.id));
    const foreign = studentIds.filter((id) => !inClassIds.has(id));
    if (foreign.length > 0) {
      throw new ForbiddenException(`students not in this class: ${foreign.join(', ')}`);
    }

    const reportDate = new Date(`${dto.reportDate}T00:00:00Z`);
    const saved: ReportEntry[] = [];
    for (const input of dto.entries) {
      const context = await this.prisma.reportEntry.findMany({
        where: { studentId: input.studentId, NOT: { authorId, reportDate } },
      });
      const flags = evaluateFlags(
        {
          reportDate,
          attendance: input.attendance,
          homework: input.homework,
          behavior: input.behavior,
        },
        context,
      );
      const entry = await this.prisma.reportEntry.upsert({
        where: { studentId_authorId_reportDate: { studentId: input.studentId, authorId, reportDate } },
        create: {
          studentId: input.studentId,
          authorId,
          reportDate,
          attendance: input.attendance,
          homework: input.homework,
          behavior: input.behavior,
          note: input.note ?? null,
          ...flags,
        },
        update: {
          attendance: input.attendance,
          homework: input.homework,
          behavior: input.behavior,
          note: input.note ?? null,
          ...flags,
        },
      });
      saved.push(entry);
    }
    return saved.map((entry) => this.serializeEntry(entry));
  }

  async listEntries(authorId: string, classId: string, date: string) {
    await this.requireOwnedClass(authorId, classId);
    const reportDate = new Date(`${date}T00:00:00Z`);
    const students = await this.schools.studentsInClass(classId);
    const entries = await this.prisma.reportEntry.findMany({
      where: {
        authorId,
        reportDate,
        studentId: { in: students.map((student) => student.id) },
      },
      orderBy: [{ studentId: 'asc' }, { id: 'asc' }],
    });
    return entries.map((entry) => this.serializeEntry(entry));
  }

  async updateEntry(authorId: string, id: string, dto: UpdateReportEntryDto) {
    const existing = await this.prisma.reportEntry.findUnique({ where: { id } });
    if (!existing) {
      throw new NotFoundException(`report entry ${id} not found`);
    }
    if (existing.authorId !== authorId) {
      throw new ForbiddenException('only the author may edit this entry');
    }

    const data: Prisma.ReportEntryUpdateInput = {};
    if (dto.attendance !== undefined) {
      data.attendance = dto.attendance;
    }
    if (dto.homework !== undefined) {
      data.homework = dto.homework;
    }
    if (dto.behavior !== undefined) {
      data.behavior = dto.behavior;
    }
    if (dto.note !== undefined) {
      data.note = dto.note;
    }

    const flags = evaluateFlags(
      {
        id: existing.id,
        reportDate: existing.reportDate,
        attendance: dto.attendance ?? existing.attendance,
        homework: dto.homework ?? existing.homework,
        behavior: dto.behavior ?? existing.behavior,
      },
      await this.prisma.reportEntry.findMany({ where: { studentId: existing.studentId, NOT: { id } } }),
    );
    const updated = await this.prisma.reportEntry.update({ where: { id }, data: { ...data, ...flags } });
    return this.serializeEntry(updated);
  }

  async summaries(parentId: string, week?: string) {
    const range = (week ? parseIsoWeek(week) : currentWeek()) ?? this.badWeek(week);

    const studentIds = await this.users.linkedStudentIds(parentId);
    const students = await this.schools.studentsByIds(studentIds);
    const entries =
      studentIds.length === 0
        ? []
        : await this.prisma.reportEntry.findMany({
            where: {
              studentId: { in: studentIds },
              reportDate: { gte: range.monday, lte: range.friday },
            },
          });

    const byStudent = new Map<string, ReportEntry[]>();
    for (const entry of entries) {
      const bucket = byStudent.get(entry.studentId);
      if (bucket) {
        bucket.push(entry);
      } else {
        byStudent.set(entry.studentId, [entry]);
      }
    }

    const output = students
      .map((student) => {
        const rows = byStudent.get(student.id) ?? [];
        return {
          id: student.id,
          name: student.name,
          attendance: this.countBy(rows, 'attendance', Object.values(Attendance)),
          homework: this.countBy(rows, 'homework', Object.values(Homework)),
          behavior: this.countBy(rows, 'behavior', Object.values(Behavior)),
          flaggedCount: rows.filter((row) => row.flagged).length,
          notes: rows
            .filter((row): row is ReportEntry & { note: string } => row.note !== null)
            .map((row) => ({
              studentId: row.studentId,
              date: toUtcDateString(row.reportDate),
              note: row.note,
              authorId: row.authorId,
            })),
        };
      })
      .sort((a, b) => a.name.localeCompare(b.name));

    return {
      week: range.label,
      start: toUtcDateString(range.monday),
      end: toUtcDateString(range.friday),
      students: output,
    };
  }

  async flagged(userId: string, role: Role, week?: string) {
    const range = (week ? parseIsoWeek(week) : currentWeek()) ?? this.badWeek(week);

    let studentIds: string[] | undefined;
    if (role === Role.TEACHER) {
      const classes = await this.schools.classesForTeacher(userId);
      const students = await Promise.all(classes.map((cls) => this.schools.studentsInClass(cls.id)));
      studentIds = students.flat().map((student) => student.id);
    } else if (role === Role.COUNSELOR) {
      const schools = await this.schools.schoolsForCounselor(userId);
      const students = await Promise.all(schools.map((school) => this.schools.studentsInSchool(school.id)));
      studentIds = students.flat().map((student) => student.id);
    }
    if (studentIds && studentIds.length === 0) {
      return [];
    }

    const entries = await this.prisma.reportEntry.findMany({
      where: {
        flagged: true,
        reportDate: { gte: range.monday, lte: range.friday },
        ...(studentIds ? { studentId: { in: studentIds } } : {}),
      },
      orderBy: [{ reportDate: 'desc' }, { id: 'asc' }],
    });
    if (entries.length === 0) {
      return [];
    }

    const studentIdsPresent = [...new Set(entries.map((entry) => entry.studentId))];
    const authorIds = [...new Set(entries.map((entry) => entry.authorId))];
    const [students, authors] = await Promise.all([
      this.schools.studentsByIds(studentIdsPresent),
      Promise.all(authorIds.map((id) => this.users.findById(id))),
    ]);
    const studentById = new Map(students.map((student) => [student.id, { id: student.id, name: student.name }]));
    const authorById = new Map<string, UserProfile>();
    authorIds.forEach((id, index) => {
      const author = authors[index];
      if (author) {
        authorById.set(id, author);
      }
    });

    return entries.map((entry) => ({
      ...this.serializeEntry(entry),
      student: studentById.get(entry.studentId) ?? { id: entry.studentId, name: 'unknown' },
      author: authorById.get(entry.authorId) ?? null,
    }));
  }

  private async requireOwnedClass(teacherId: string, classId: string): Promise<string> {
    const cls = await this.schools.requireClassAccess(teacherId, Role.TEACHER, classId);
    return cls.id;
  }

  private badWeek(week: string | undefined): never {
    throw new BadRequestException(`invalid ISO week: ${week ?? ''}`);
  }

  private countBy(
    rows: ReportEntry[],
    field: 'attendance' | 'homework' | 'behavior',
    values: readonly string[],
  ): Record<string, number> {
    const counts: Record<string, number> = Object.fromEntries(values.map((value) => [value, 0]));
    for (const row of rows) {
      counts[row[field]] = (counts[row[field]] ?? 0) + 1;
    }
    return counts;
  }

  private serializeEntry(entry: ReportEntry) {
    return {
      id: entry.id,
      studentId: entry.studentId,
      authorId: entry.authorId,
      reportDate: toUtcDateString(entry.reportDate),
      attendance: entry.attendance,
      homework: entry.homework,
      behavior: entry.behavior,
      note: entry.note,
      flagged: entry.flagged,
      flagReason: entry.flagReason,
      createdAt: entry.createdAt,
      updatedAt: entry.updatedAt,
    };
  }
}
