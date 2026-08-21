import { IsIn } from 'class-validator';
import { StatutConducteur } from '../../../generated/prisma/enums';

export class UpdateStatutDto {
  @IsIn(['EN_LIGNE', 'HORS_LIGNE'])
  statut: StatutConducteur;
}
