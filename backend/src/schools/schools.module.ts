import { Module } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { SchoolsController } from './schools.controller';
import { SchoolsService } from './schools.service';

@Module({
  controllers: [SchoolsController],
  providers: [SchoolsService, PrismaService],
  exports: [SchoolsService],
})
export class SchoolsModule {}
