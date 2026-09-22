import {
  IsEnum,
  IsLatitude,
  IsLongitude,
  IsNumber,
  IsOptional,
  IsString,
  Min,
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
  @IsNumber()
  @Min(0)
  distanceKm?: number;

  @IsOptional()
  @IsEnum(MethodePaiement)
  methodePaiement?: MethodePaiement;
}
