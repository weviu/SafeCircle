import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';
import { Attendance, Behavior, Homework } from '../../generated/prisma';

export class UpdateReportEntryDto {
  @IsOptional()
  @IsIn(Object.values(Attendance))
  attendance?: Attendance;

  @IsOptional()
  @IsIn(Object.values(Homework))
  homework?: Homework;

  @IsOptional()
  @IsIn(Object.values(Behavior))
  behavior?: Behavior;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  note?: string | null;
}
