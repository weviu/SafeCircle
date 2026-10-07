import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  Query,
  Req,
  UnauthorizedException,
} from '@nestjs/common';
import type { Request } from 'express';
import type { UserProfile } from '../users/users.service';
import { NotificationsService } from './notifications.service';
import { SubscribeDto } from './dto/subscribe.dto';
import { ListNotificationsQueryDto } from './dto/list-notifications.query.dto';

interface RequestWithUser extends Request {
  user?: UserProfile;
}

@Controller('notifications')
export class NotificationsController {
  constructor(private readonly notificationsService: NotificationsService) {}

  @Get()
  async list(
    @Req() req: RequestWithUser,
    @Query() query: ListNotificationsQueryDto,
  ) {
    const user = this.currentUser(req);
    const limit = query.limit ?? 30;
    const [unreadCount, items] = await Promise.all([
      this.notificationsService.unreadCount(user.id),
      this.notificationsService.list(user.id, limit),
    ]);
    return { unreadCount, items };
  }

  @Post(':id/read')
  async markRead(@Req() req: RequestWithUser, @Param('id') id: string) {
    const user = this.currentUser(req);
    return this.notificationsService.markRead(user.id, id);
  }

  @Post('read-all')
  @HttpCode(HttpStatus.OK)
  async markAllRead(@Req() req: RequestWithUser) {
    const user = this.currentUser(req);
    return this.notificationsService.markAllRead(user.id);
  }

  @Post('subscribe')
  @HttpCode(HttpStatus.OK)
  async subscribe(@Req() req: RequestWithUser, @Body() dto: SubscribeDto) {
    const user = this.currentUser(req);
    return this.notificationsService.ensureSubscription(user.id, dto.platform);
  }

  private currentUser(req: RequestWithUser): UserProfile {
    if (!req.user) {
      throw new UnauthorizedException();
    }
    return req.user;
  }
}