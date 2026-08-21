import { IsPhoneNumber, IsString, MinLength } from 'class-validator';

export class RegisterClientDto {
  @IsString()
  @MinLength(2)
  nom: string;

  @IsPhoneNumber('SN')
  telephone: string;

  @IsString()
  @MinLength(8)
  motDePasse: string;
}
