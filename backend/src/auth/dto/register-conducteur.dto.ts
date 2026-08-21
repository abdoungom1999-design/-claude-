import {
  IsOptional,
  IsPhoneNumber,
  IsString,
  MinLength,
} from 'class-validator';

export class RegisterConducteurDto {
  @IsString()
  @MinLength(2)
  nom: string;

  @IsPhoneNumber('SN')
  telephone: string;

  @IsString()
  @MinLength(8)
  motDePasse: string;

  @IsOptional()
  @IsString()
  vehiculeId?: string;
}
