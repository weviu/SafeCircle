import { Injectable, Logger } from '@nestjs/common';
import { PushTransport, PushPayload } from './push-transport';

/**
 * Dev fallback used when NTFY_BASE_URL is unset/empty: notifications are still
 * stored in the inbox (DB), but nothing is pushed anywhere. Publish -> log.
 * Never a crash: no transport is always preferable to report submission
 * failing because push is misconfigured.
 */
@Injectable()
export class LogOnlyPushTransport implements PushTransport {
  private readonly logger = new Logger(LogOnlyPushTransport.name);

  async publish(topic: string, payload: PushPayload): Promise<void> {
    this.logger.log(
      `[push] would publish to topic=${topic} title=${payload.title} body=${payload.body}`,
    );
  }
}