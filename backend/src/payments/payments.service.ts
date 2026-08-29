import { Injectable, NotFoundException } from '@nestjs/common';
import { StatutPaiement } from '../../generated/prisma/enums';
import { PrismaService } from '../prisma/prisma.service';
import { PaiementWebhookDto } from './dto/paiement-webhook.dto';

@Injectable()
export class PaymentsService {
  constructor(private readonly prisma: PrismaService) {}

  async traiterWebhookWave(dto: PaiementWebhookDto): Promise<void> {
    await this.enregistrerPaiement(
      'WAVE',
      dto,
      this.normaliserStatutWave(dto.statut),
    );
  }

  async traiterWebhookOrangeMoney(dto: PaiementWebhookDto): Promise<void> {
    await this.enregistrerPaiement(
      'ORANGE_MONEY',
      dto,
      this.normaliserStatutOrangeMoney(dto.statut),
    );
  }

  private normaliserStatutWave(statutBrut: string): StatutPaiement {
    switch (statutBrut.toLowerCase()) {
      case 'success':
      case 'succeeded':
        return StatutPaiement.REUSSI;
      case 'failed':
      case 'cancelled':
        return StatutPaiement.ECHOUE;
      default:
        return StatutPaiement.EN_ATTENTE;
    }
  }

  private normaliserStatutOrangeMoney(statutBrut: string): StatutPaiement {
    switch (statutBrut.toUpperCase()) {
      case 'SUCCESS':
      case 'SUCCESSFUL':
        return StatutPaiement.REUSSI;
      case 'FAILED':
        return StatutPaiement.ECHOUE;
      default:
        return StatutPaiement.EN_ATTENTE;
    }
  }

  private async enregistrerPaiement(
    provider: 'WAVE' | 'ORANGE_MONEY',
    dto: PaiementWebhookDto,
    statut: StatutPaiement,
  ): Promise<void> {
    const course = await this.prisma.course.findUnique({
      where: { id: dto.reference },
    });
    if (!course) {
      throw new NotFoundException('Course introuvable pour ce paiement');
    }

    await this.prisma.paiement.upsert({
      where: { courseId: dto.reference },
      create: {
        courseId: dto.reference,
        provider,
        referenceExterne: dto.transactionId,
        statut,
        montantFcfa: dto.montantFcfa,
      },
      update: {
        referenceExterne: dto.transactionId,
        statut,
        montantFcfa: dto.montantFcfa,
      },
    });
  }
}
