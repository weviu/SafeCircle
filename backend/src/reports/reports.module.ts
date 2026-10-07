import { Module } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { SchoolsModule } from '../schools/schools.module';
import { UsersModule } from '../users/users.module';
import { ReportsController } from './reports.controller';
import { ReportsService } from './reports.service';

@Module({
  imports: [SchoolsModule, UsersModule],
  controllers: [ReportsController],
  providers: [ReportsService, PrismaService],
})
export class ReportsModule {}
