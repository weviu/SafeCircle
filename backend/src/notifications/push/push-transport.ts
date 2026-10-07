export const PUSH_TRANSPORT = Symbol('PUSH_TRANSPORT');

export interface PushPayload {
  title: string;
  body: string;
  data?: Record<string, unknown>;
}

/**
 * Transport boundary for outbound push. Notifications are always written to
 * the inbox first; a failing transport must never break the caller — the
 * caller (NotifyService) catches+logs transport errors, so publish() is
 * allowed to throw.
 */
export interface PushTransport {
  publish(topic: string, payload: PushPayload): Promise<void>;
}