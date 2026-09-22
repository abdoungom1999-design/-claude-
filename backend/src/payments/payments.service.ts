import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { MethodePaiement, StatutPaiement } from '../../generated/prisma/enums';
import { PrismaService } from '../prisma/prisma.service';
import { PaiementWebhookDto } from './dto/paiement-webhook.dto';
import { OrangeMoneyService } from './orange-money.service';
import { WaveService } from './wave.service';

@Injectable()
export class PaymentsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly waveService: WaveService,
    private readonly orangeMoneyService: OrangeMoneyService,
  ) {}

  async initierWave(clientId: string, courseId: string) {
    const course = await this.courseEligiblePourPaiement(
      clientId,
      courseId,
      'WAVE',
    );
    const session = await this.waveService.creerSessionCheckout(
      course.id,
      course.prixFcfa!,
    );
    await this.enregistrerPaiementInitie('WAVE', course.id, session.id);
    return { checkoutUrl: session.urlPaiement };
  }

  async initierOrangeMoney(clientId: string, courseId: string) {
    const course = await this.courseEligiblePourPaiement(
      clientId,
      courseId,
      'ORANGE_MONEY',
    );
    const session = await this.orangeMoneyService.creerSessionPaiement(
      course.id,
      course.prixFcfa!,
    );
    await this.enregistrerPaiementInitie('ORANGE_MONEY', course.id, session.id);
    return { checkoutUrl: session.urlPaiement };
  }

  async traiterWebhookWave(
    corpsBrut: Buffer,
    signature: string | undefined,
    dto: PaiementWebhookDto,
  ): Promise<void> {
    if (!this.waveService.verifierSignatureWebhook(corpsBrut, signature)) {
      throw new UnauthorizedException('Signature Wave invalide');
    }
    await this.enregistrerResultatPaiement(
      'WAVE',
      dto,
      this.normaliserStatutWave(dto.statut),
    );
  }

  async traiterWebhookOrangeMoney(
    corpsBrut: Buffer,
    signature: string | undefined,
    dto: PaiementWebhookDto,
  ): Promise<void> {
    if (
      !this.orangeMoneyService.verifierSignatureWebhook(corpsBrut, signature)
    ) {
      throw new UnauthorizedException('Signature Orange Money invalide');
    }
    await this.enregistrerResultatPaiement(
      'ORANGE_MONEY',
      dto,
      this.normaliserStatutOrangeMoney(dto.statut),
    );
  }

  private async courseEligiblePourPaiement(
    clientId: string,
    courseId: string,
    provider: 'WAVE' | 'ORANGE_MONEY',
  ) {
    const course = await this.prisma.course.findUnique({
      where: { id: courseId },
      include: { paiement: true },
    });
    if (!course) {
      throw new NotFoundException('Course introuvable');
    }
    if (course.clientId !== clientId) {
      throw new ForbiddenException("Cette course n'appartient pas à ce client");
    }
    if (course.methodePaiement !== provider) {
      throw new BadRequestException(
        `Cette course est configurée pour un autre moyen de paiement (${course.methodePaiement})`,
      );
    }
    if (!course.prixFcfa) {
      throw new BadRequestException('Le prix de la course est indisponible');
    }
    if (course.paiement?.statut === 'REUSSI') {
      throw new ConflictException('Cette course a déjà été payée');
    }
    return course;
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

  private async enregistrerPaiementInitie(
    provider: MethodePaiement,
    courseId: string,
    referenceExterne: string,
  ): Promise<void> {
    await this.prisma.paiement.upsert({
      where: { courseId },
      create: {
        courseId,
        provider,
        referenceExterne,
        statut: 'EN_ATTENTE',
      },
      update: {
        referenceExterne,
        statut: 'EN_ATTENTE',
      },
    });
  }

  private async enregistrerResultatPaiement(
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
