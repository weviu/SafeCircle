import { Module } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { SchoolsService } from './schools.service';

@Module({
  providers: [SchoolsService, PrismaService],
  exports: [SchoolsService],
})
export class SchoolsModule {}
