import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  Query,
  Req,
  UnauthorizedException,
} from '@nestjs/common';
import type { Request } from 'express';
import { Role } from '../generated/prisma';
import { Roles } from '../auth/decorators/roles.decorator';
import type { UserProfile } from '../users/users.service';
import { ReportsService } from './reports.service';
import { CreateReportDto } from './dto/create-report.dto';
import { UpdateReportEntryDto } from './dto/update-report-entry.dto';
import { ListEntriesQueryDto, WeekQueryDto } from './dto/query.dto';

interface RequestWithUser extends Request {
  user?: UserProfile;
}

@Controller('reports')
export class ReportsController {
  constructor(private readonly reportsService: ReportsService) {}

  @Post('entries')
  @Roles(Role.TEACHER)
  async createEntries(@Req() req: RequestWithUser, @Body() dto: CreateReportDto) {
    const user = this.currentUser(req);
    return this.reportsService.createEntries(user.id, dto);
  }

  @Get('entries')
  @Roles(Role.TEACHER)
  async listEntries(@Req() req: RequestWithUser, @Query() query: ListEntriesQueryDto) {
    const user = this.currentUser(req);
    return this.reportsService.listEntries(user.id, query.classId, query.date);
  }

  @Patch('entries/:id')
  @Roles(Role.TEACHER)
  async updateEntry(
    @Req() req: RequestWithUser,
    @Param('id') id: string,
    @Body() dto: UpdateReportEntryDto,
  ) {
    const user = this.currentUser(req);
    return this.reportsService.updateEntry(user.id, id, dto);
  }

  @Get('summaries')
  @Roles(Role.PARENT)
  async summaries(@Req() req: RequestWithUser, @Query() query: WeekQueryDto) {
    const user = this.currentUser(req);
    return this.reportsService.summaries(user.id, query.week);
  }

  @Get('flagged')
  @Roles(Role.TEACHER, Role.COUNSELOR, Role.ADMIN)
  async flagged(@Req() req: RequestWithUser, @Query() query: WeekQueryDto) {
    const user = this.currentUser(req);
    return this.reportsService.flagged(user.id, user.role, query.week);
  }

  private currentUser(req: RequestWithUser): UserProfile {
    if (!req.user) {
      throw new UnauthorizedException();
    }
    return req.user;
  }
}
