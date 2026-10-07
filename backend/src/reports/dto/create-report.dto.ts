import { Type } from 'class-transformer';
import {
  ArrayNotEmpty,
  IsArray,
  IsDateString,
  IsIn,
  IsNotEmpty,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  ValidateNested,
} from 'class-validator';
import { Attendance, Behavior, Homework } from '../../generated/prisma';
import { DATE_RE } from './query.dto';

export class ReportEntryInputDto {
  @IsString()
  @IsNotEmpty()
  studentId: string;

  @IsIn(Object.values(Attendance))
  attendance: Attendance;

  @IsIn(Object.values(Homework))
  homework: Homework;

  @IsIn(Object.values(Behavior))
  behavior: Behavior;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  note?: string | null;
}

export class CreateReportDto {
  @IsString()
  @IsNotEmpty()
  classId: string;

  @IsDateString()
  @Matches(DATE_RE)
  reportDate: string;

  @IsArray()
  @ArrayNotEmpty()
  @ValidateNested({ each: true })
  @Type(() => ReportEntryInputDto)
  entries: ReportEntryInputDto[];
}
