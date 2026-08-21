import {
  IsEnum,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsString,
} from 'class-validator';
import { MethodePaiement, TypeCourse } from '../../../generated/prisma/enums';

export class CreateCourseDto {
  @IsEnum(TypeCourse)
  type: TypeCourse;

  @IsString()
  adresseDepart: string;

  @IsLatitude()
  latitudeDepart: number;

  @IsLongitude()
  longitudeDepart: number;

  @IsString()
  adresseArrivee: string;

  @IsLatitude()
  latitudeArrivee: number;

  @IsLongitude()
  longitudeArrivee: number;

  @IsOptional()
  @IsEnum(MethodePaiement)
  methodePaiement?: MethodePaiement;
}
