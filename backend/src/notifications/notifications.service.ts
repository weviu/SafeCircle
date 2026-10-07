import {
  Inject,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { randomBytes } from 'crypto';
import { Notification, NotificationType, Prisma } from '../generated/prisma';
import { PrismaService } from '../prisma.service';
import { PUSH_TRANSPORT, PushTransport, PushPayload } from './push/push-transport';

@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(
    private readonly prisma: PrismaService,
    @Inject(PUSH_TRANSPORT) private readonly transport: PushTransport,
  ) {}

  /**
   * Writes the notification to the recipient's inbox, then fans it out to the
   * recipient's push subscriptions. Inbox write first: even if every transport
   * fails (or none is configured), the row exists and the request succeeds.
   * Transport errors are caught+logged here; no retries/queues this phase.
   */
  async notify(
    userId: string,
    type: NotificationType,
    title: string,
    body: string,
    data?: Prisma.InputJsonValue,
  ): Promise<Notification> {
    const notification = await this.prisma.notification.create({
      data: { userId, type, title, body, data: data ?? Prisma.JsonNull },
    });

    const subscriptions = await this.prisma.pushSubscription.findMany({
      where: { userId },
    });
    const payload: PushPayload = { title, body, data: (data ?? {}) as Record<string, unknown> };
    await Promise.all(
      subscriptions.map(async (subscription) => {
        try {
          await this.transport.publish(subscription.topic, payload);
        } catch (error) {
          this.logger.warn(
            `push publish failed for topic ${subscription.topic}: ${
              error instanceof Error ? error.message : String(error)
            }`,
          );
        }
      }),
    );
    return notification;
  }

  async list(userId: string, limit: number) {
    const items = await this.prisma.notification.findMany({
      where: { userId },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit,
    });
    return items.map((item) => this.serialize(item));
  }

  async unreadCount(userId: string): Promise<number> {
    return this.prisma.notification.count({
      where: { userId, readAt: null },
    });
  }

  /** Marks one row read; 404 if the row does not exist or is not the user's. */
  async markRead(userId: string, id: string) {
    const updated = await this.prisma.notification.updateMany({
      where: { id, userId },
      data: { readAt: new Date() },
    });
    if (updated.count === 0) {
      throw new NotFoundException(`notification ${id} not found`);
    }
    const row = await this.prisma.notification.findUnique({ where: { id } });
    return this.serialize(row!);
  }

  async markAllRead(userId: string) {
    const result = await this.prisma.notification.updateMany({
      where: { userId, readAt: null },
      data: { readAt: new Date() },
    });
    return { ok: true as const, updated: result.count };
  }

  /**
   * Returns the user's push topic, creating it on first call (unguessable
   * server-generated value) and reusing the existing one for the same
   * user/platform afterwards. Also bumps lastSeenAt — evidence the client is
   * alive so a session without a topic can be garbage-collected later.
   */
  async ensureSubscription(userId: string, platform?: string) {
    const platformValue = platform ?? null;
    const existing = await this.prisma.pushSubscription.findFirst({
      where: { userId, platform: platformValue },
    });
    if (existing) {
      await this.prisma.pushSubscription.update({
        where: { id: existing.id },
        data: { lastSeenAt: new Date() },
      });
      return { topic: existing.topic };
    }
    const created = await this.prisma.pushSubscription.create({
      data: {
        userId,
        platform: platformValue,
        topic: `sc_${randomBytes(24).toString('hex')}`,
      },
    });
    return { topic: created.topic };
  }

  private serialize(notification: Notification) {
    return {
      id: notification.id,
      type: notification.type,
      title: notification.title,
      body: notification.body,
      data: notification.data,
      readAt: notification.readAt,
      createdAt: notification.createdAt,
    };
  }
}