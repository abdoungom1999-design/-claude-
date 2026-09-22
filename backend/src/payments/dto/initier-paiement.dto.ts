import { IsString } from 'class-validator';

export class InitierPaiementDto {
  @IsString()
  courseId: string;
}
