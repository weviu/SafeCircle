import { IsEmail, IsIn, IsNotEmpty, IsString, MaxLength, MinLength } from 'class-validator';

export class SignupDto {
  @IsEmail()
  email: string;

  @IsString()
  @MinLength(8)
  @MaxLength(128)
  password: string;

  @IsIn(['parent', 'teacher', 'counselor'])
  role: 'parent' | 'teacher' | 'counselor';

  @IsString()
  @IsNotEmpty()
  @MaxLength(120)
  name: string;
}
