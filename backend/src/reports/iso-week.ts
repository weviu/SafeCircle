export const ISO_WEEK_RE = /^\d{4}-W(0[1-9]|[1-4]\d|5[0-3])$/;

const DAY_MS = 86_400_000;

export interface IsoWeekRange {
  label: string;
  monday: Date;
  friday: Date;
}

function utcDay(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

function addDays(date: Date, days: number): Date {
  return new Date(utcDay(date).getTime() + days * DAY_MS);
}

/** Monday of ISO week 1 of the given year (Jan 4 is always in week 1). */
function week1Monday(year: number): Date {
  const jan4 = new Date(Date.UTC(year, 0, 4));
  const dayOfWeek = (jan4.getUTCDay() + 6) % 7;
  return addDays(jan4, -dayOfWeek);
}

export function isoWeekLabel(date: Date): string {
  const day = utcDay(date);
  const dayOfWeek = (day.getUTCDay() + 6) % 7;
  const thursday = addDays(day, 3 - dayOfWeek);
  const year = thursday.getUTCFullYear();
  const week = Math.floor((thursday.getTime() - week1Monday(year).getTime()) / (7 * DAY_MS)) + 1;
  return `${year}-W${String(week).padStart(2, '0')}`;
}

/** Returns the Mon-Fri range for a label like `2026-W39`, or null if invalid (bad format, week 53 in a 52-week year, ...). */
export function parseIsoWeek(label: string): IsoWeekRange | null {
  const match = ISO_WEEK_RE.exec(label);
  if (!match) {
    return null;
  }
  const year = Number(label.slice(0, 4));
  const week = Number(match[1]);
  const monday = addDays(week1Monday(year), (week - 1) * 7);
  if (isoWeekLabel(monday) !== label) {
    return null;
  }
  return { label, monday, friday: addDays(monday, 4) };
}

export function currentWeek(): IsoWeekRange {
  const label = isoWeekLabel(new Date());
  const range = parseIsoWeek(label);
  if (!range) {
    throw new Error(`current ISO week ${label} failed to parse`);
  }
  return range;
}

export function toUtcDateString(date: Date): string {
  return utcDay(date).toISOString().slice(0, 10);
}
