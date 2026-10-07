import { Controller, Get, Param, Req, UnauthorizedException } from '@nestjs/common';
import type { Request } from 'express';
import { Role } from '../generated/prisma';
import { Roles } from '../auth/decorators/roles.decorator';
import type { UserProfile } from '../users/users.service';
import { SchoolsService } from './schools.service';

interface RequestWithUser extends Request {
  user?: UserProfile;
}

@Controller('classes')
export class SchoolsController {
  constructor(private readonly schools: SchoolsService) {}

  @Get()
  @Roles(Role.TEACHER, Role.ADMIN)
  async listClasses(@Req() req: RequestWithUser) {
    const user = this.currentUser(req);
    const classes =
      user.role === Role.ADMIN
        ? await this.schools.allClasses()
        : await this.schools.classesForTeacher(user.id);
    return classes.map((cls) => ({
      id: cls.id,
      name: cls.name,
      grade: cls.grade,
      school: { id: cls.school.id, name: cls.school.name },
    }));
  }

  @Get(':id/students')
  @Roles(Role.TEACHER, Role.ADMIN)
  async listClassStudents(@Req() req: RequestWithUser, @Param('id') id: string) {
    const user = this.currentUser(req);
    await this.schools.requireClassAccess(user.id, user.role, id);
    const students = await this.schools.studentsInClass(id);
    return students.map((student) => ({
      id: student.id,
      name: student.name,
      schoolNumber: student.schoolNumber,
    }));
  }

  private currentUser(req: RequestWithUser): UserProfile {
    if (!req.user) {
      throw new UnauthorizedException();
    }
    return req.user;
  }
}
