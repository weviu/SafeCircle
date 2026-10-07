import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { Role } from '../generated/prisma';

export interface UserProfile {
  id: string;
  email: string;
  role: Role;
  createdAt: Date;
}

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async findById(id: string): Promise<UserProfile | null> {
    return this.prisma.user.findUnique({
      where: { id },
      select: { id: true, email: true, role: true, createdAt: true },
    });
  }

  /** Student ids linked to this parent via `parent_student` (public API —
   * other modules must not query the join table directly). */
  async linkedStudentIds(parentId: string): Promise<string[]> {
    const links = await this.prisma.parentStudent.findMany({
      where: { parentId },
      select: { studentId: true },
    });
    return links.map((link) => link.studentId);
  }
}
