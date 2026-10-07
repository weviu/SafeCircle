import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma.service';
import { NotificationsController } from './notifications.controller';
import { NotificationsService } from './notifications.service';
import { PUSH_TRANSPORT } from './push/push-transport';
import { NtfyTransport } from './push/ntfy.transport';
import { LogOnlyPushTransport } from './push/log-only.transport';

/**
 * Notifications (inbox) + push subscriptions. Owns both its tables — other
 * modules reach it only through NotificationsService (reports module depends
 * on this one). The push transport is selected at boot: NTFY_BASE_URL unset →
 * log-only fallback, never a crash.
 */
@Module({
  controllers: [NotificationsController],
  providers: [
    NotificationsService,
    PrismaService,
    {
      provide: PUSH_TRANSPORT,
      inject: [ConfigService],
      useFactory: (configService: ConfigService) => {
        const baseUrl = configService.get<string>('NTFY_BASE_URL')?.trim();
        if (!baseUrl) {
          return new LogOnlyPushTransport();
        }
        return new NtfyTransport(baseUrl);
      },
    },
  ],
  exports: [NotificationsService],
})
export class NotificationsModule {}