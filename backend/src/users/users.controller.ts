import { Controller, Get, Req, UnauthorizedException } from '@nestjs/common';
import type { Request } from 'express';
import { UserProfile, UsersService } from './users.service';

interface RequestWithUser extends Request {
  user?: UserProfile;
}

@Controller('users')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get('me')
  async findMe(@Req() req: RequestWithUser): Promise<UserProfile> {
    if (!req.user) {
      throw new UnauthorizedException();
    }
    const user = await this.usersService.findById(req.user.id);
    if (!user) {
      throw new UnauthorizedException();
    }
    return user;
  }
}
