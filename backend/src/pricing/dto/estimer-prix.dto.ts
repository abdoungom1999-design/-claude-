import { IsEnum, IsNumber, Min } from 'class-validator';
import { TypeCourse } from '../../../generated/prisma/enums';

export class EstimerPrixDto {
  @IsEnum(TypeCourse)
  type: TypeCourse;

  @IsNumber()
  @Min(0)
  distanceKm: number;
}
