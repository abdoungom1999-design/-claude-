import { IsPhoneNumber, IsString } from 'class-validator';

export class LoginDto {
  @IsPhoneNumber('SN')
  telephone: string;

  @IsString()
  motDePasse: string;
}
