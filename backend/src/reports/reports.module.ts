import { Module } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { SchoolsModule } from '../schools/schools.module';
import { UsersModule } from '../users/users.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { ReportsController } from './reports.controller';
import { ReportsService } from './reports.service';

@Module({
  imports: [SchoolsModule, UsersModule, NotificationsModule],
  controllers: [ReportsController],
  providers: [ReportsService, PrismaService],
})
export class ReportsModule {}
