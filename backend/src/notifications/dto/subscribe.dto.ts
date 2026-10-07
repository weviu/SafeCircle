import { IsOptional, IsString, MaxLength } from 'class-validator';

export class SubscribeDto {
  @IsOptional()
  @IsString()
  @MaxLength(50)
  platform?: string;
}