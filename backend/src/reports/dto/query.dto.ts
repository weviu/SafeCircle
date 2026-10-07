import { IsDateString, IsNotEmpty, IsOptional, IsString, Matches } from 'class-validator';
import { ISO_WEEK_RE } from '../iso-week';

export const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

export class ListEntriesQueryDto {
  @IsString()
  @IsNotEmpty()
  classId: string;

  @IsDateString()
  @Matches(DATE_RE)
  date: string;
}

export class WeekQueryDto {
  @IsOptional()
  @Matches(ISO_WEEK_RE)
  week?: string;
}
