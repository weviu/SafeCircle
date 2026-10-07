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
}
