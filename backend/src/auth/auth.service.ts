import { ConflictException, Injectable, OnModuleInit, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { argon2id, hash, verify } from 'argon2';
import { createHash, randomBytes } from 'node:crypto';
import { PrismaService } from '../prisma.service';
import { Prisma, Role, User } from '../generated/prisma';
import { SignupDto } from './dto/signup.dto';
import { LoginDto } from './dto/login.dto';

const REFRESH_TOKEN_TTL_MS = 30 * 24 * 60 * 60 * 1000;

export interface AuthResult {
  accessToken: string;
  refreshToken: string;
  user: { id: string; email: string; role: Role };
}

@Injectable()
export class AuthService implements OnModuleInit {
  private dummyHash = '';

  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
  ) {}

  async onModuleInit(): Promise<void> {
    this.dummyHash = await hash(randomBytes(16).toString('hex'), { type: argon2id });
  }

  async signup(dto: SignupDto): Promise<AuthResult> {
    const passwordHash = await hash(dto.password, { type: argon2id });
    let user: User;
    try {
      user = await this.prisma.user.create({
        data: {
          email: dto.email,
          passwordHash,
          role: dto.role.toUpperCase() as Role,
        },
      });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        throw new ConflictException('Email already registered');
      }
      throw error;
    }
    return this.issueTokens(user);
  }

  async login(dto: LoginDto): Promise<AuthResult> {
    const user = await this.prisma.user.findUnique({ where: { email: dto.email } });
    const passwordMatches = user
      ? await verify(user.passwordHash, dto.password)
      : await verify(this.dummyHash, dto.password);
    if (!user || !passwordMatches) {
      throw new UnauthorizedException('Invalid credentials');
    }
    return this.issueTokens(user);
  }

  async refresh(rawToken: string): Promise<AuthResult> {
    const tokenHash = sha256(rawToken);
    const stored = await this.prisma.refreshToken.findFirst({
      where: { tokenHash },
      include: { user: true },
    });
    if (!stored) {
      throw new UnauthorizedException('Invalid refresh token');
    }
    if (stored.revokedAt) {
      await this.prisma.refreshToken.updateMany({
        where: { userId: stored.userId, revokedAt: null },
        data: { revokedAt: new Date() },
      });
      throw new UnauthorizedException('Invalid refresh token');
    }
    if (stored.expiresAt.getTime() <= Date.now()) {
      throw new UnauthorizedException('Invalid refresh token');
    }

    await this.prisma.refreshToken.update({
      where: { id: stored.id },
      data: { revokedAt: new Date() },
    });
    return this.issueTokens(stored.user);
  }

  async logout(rawToken: string): Promise<{ message: string }> {
    await this.prisma.refreshToken.updateMany({
      where: { tokenHash: sha256(rawToken), revokedAt: null },
      data: { revokedAt: new Date() },
    });
    return { message: 'Logged out' };
  }

  private async issueTokens(user: Pick<User, 'id' | 'email' | 'role'>): Promise<AuthResult> {
    const accessToken = await this.jwtService.signAsync({
      sub: user.id,
      email: user.email,
      role: user.role,
    });
    const refreshToken = randomBytes(48).toString('base64url');
    await this.prisma.refreshToken.create({
      data: {
        userId: user.id,
        tokenHash: sha256(refreshToken),
        expiresAt: new Date(Date.now() + REFRESH_TOKEN_TTL_MS),
      },
    });
    return {
      accessToken,
      refreshToken,
      user: { id: user.id, email: user.email, role: user.role },
    };
  }
}

function sha256(value: string): string {
  return createHash('sha256').update(value).digest('hex');
}
