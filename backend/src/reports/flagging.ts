import { Attendance, Behavior, Homework } from '../generated/prisma';

export interface FlaggableEntry {
  id?: string;
  reportDate: Date;
  attendance: Attendance;
  homework: Homework;
  behavior: Behavior;
}

export interface FlagResult {
  flagged: boolean;
  flagReason: string | null;
}

export const STREAK_LENGTH = 3;
export const FLAGGED_BEHAVIORS: readonly Behavior[] = [Behavior.CONCERN, Behavior.SEVERE];
export const ABSENT_LIKE: readonly Attendance[] = [Attendance.ABSENT, Attendance.LATE];

/** Turkish labels for flag reasons — used in the parent notification copy. */
export const FLAG_REASON_LABELS: Record<string, string> = {
  behavior_severe: 'şiddetli davranış',
  behavior_concern: 'uyarı davranışı',
  absence_streak: 'devamsızlık şeridi',
  homework_streak: 'ödev şeridi',
};

/**
 * Flags are evaluated once, when an entry is written (created or edited).
 * Later rule changes do not backfill existing rows — acceptable for the pilot.
 *
 * Scope: the behavior rule looks only at the entry being written; the streak
 * rules look at the student's other entries regardless of author (one class
 * teacher per student in practice, but flags are student-level).
 *
 * Rules, in priority order:
 *  1. behavior CONCERN/SEVERE            -> behavior_concern | behavior_severe
 *  2. run of >= STREAK_LENGTH school days (Mon-Fri, consecutive calendar
 *     school days; a missing day or a non-ABSENT/LATE day breaks the run)
 *     containing the written entry's date, all ABSENT/LATE -> absence_streak
 *  3. run of >= STREAK_LENGTH entries in date order, all NOT_DONE,
 *     containing the written entry's date                    -> homework_streak
 */
export function evaluateFlags(written: FlaggableEntry, context: FlaggableEntry[]): FlagResult {
  if (written.behavior === Behavior.SEVERE) {
    return { flagged: true, flagReason: 'behavior_severe' };
  }
  if (written.behavior === Behavior.CONCERN) {
    return { flagged: true, flagReason: 'behavior_concern' };
  }

  const byDate = new Map<string, FlaggableEntry[]>();
  for (const entry of [...context, written]) {
    const key = dayKey(entry.reportDate);
    const bucket = byDate.get(key);
    if (bucket) {
      bucket.push(entry);
    } else {
      byDate.set(key, [entry]);
    }
  }
  const dayIsAbsentLike = (day: Date): boolean =>
    (byDate.get(dayKey(day)) ?? []).some((entry) => ABSENT_LIKE.includes(entry.attendance));

  if (dayIsAbsentLike(written.reportDate)) {
    let back = 0;
    for (let day = prevSchoolDay(written.reportDate); dayIsAbsentLike(day); day = prevSchoolDay(day)) {
      back += 1;
    }
    let forward = 0;
    for (let day = nextSchoolDay(written.reportDate); dayIsAbsentLike(day); day = nextSchoolDay(day)) {
      forward += 1;
    }
    if (back + 1 + forward >= STREAK_LENGTH) {
      return { flagged: true, flagReason: 'absence_streak' };
    }
  }

  if (written.homework === Homework.NOT_DONE) {
    const sorted = [...context, written].sort(
      (a, b) => a.reportDate.getTime() - b.reportDate.getTime(),
    );
    const index = sorted.indexOf(written);
    let back = 0;
    for (let i = index - 1; i >= 0 && sorted[i].homework === Homework.NOT_DONE; i -= 1) {
      back += 1;
    }
    let forward = 0;
    for (let i = index + 1; i < sorted.length && sorted[i].homework === Homework.NOT_DONE; i += 1) {
      forward += 1;
    }
    if (back + 1 + forward >= STREAK_LENGTH) {
      return { flagged: true, flagReason: 'homework_streak' };
    }
  }

  return { flagged: false, flagReason: null };
}

function utcDay(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

function dayKey(date: Date): string {
  return utcDay(date).toISOString().slice(0, 10);
}

function addDays(date: Date, days: number): Date {
  return new Date(utcDay(date).getTime() + days * 86_400_000);
}

function isSchoolDay(date: Date): boolean {
  const dayOfWeek = date.getUTCDay();
  return dayOfWeek >= 1 && dayOfWeek <= 5;
}

function prevSchoolDay(date: Date): Date {
  let day = addDays(date, -1);
  while (!isSchoolDay(day)) {
    day = addDays(day, -1);
  }
  return day;
}

function nextSchoolDay(date: Date): Date {
  let day = addDays(date, 1);
  while (!isSchoolDay(day)) {
    day = addDays(day, 1);
  }
  return day;
}
