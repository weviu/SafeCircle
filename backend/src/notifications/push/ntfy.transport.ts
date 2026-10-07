import { Injectable } from '@nestjs/common';
import { PushTransport, PushPayload } from './push-transport';

/**
 * Self-hosted ntfy. Publishes to `${baseUrl}/<topic>`; ntfy delivers it to
 * every long-poll/stream subscriber of that topic. ntfy's publish JSON format
 * uses `title`/`message` — our generic `body` maps to ntfy's `message`.
 */
@Injectable()
export class NtfyTransport implements PushTransport {
  constructor(private readonly baseUrl: string) {}

  async publish(topic: string, payload: PushPayload): Promise<void> {
    const response = await fetch(`${this.baseUrl}/${topic}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title: payload.title, message: payload.body }),
    });
    if (!response.ok) {
      throw new Error(
        `ntfy publish failed: ${response.status} ${await response.text()}`,
      );
    }
  }
}