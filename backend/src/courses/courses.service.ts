import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { PricingService } from '../pricing/pricing.service';
import { CreateCourseDto } from './dto/create-course.dto';

@Injectable()
export class CoursesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly pricingService: PricingService,
  ) {}

  creer(clientId: string, dto: CreateCourseDto) {
    // Le prix n'est jamais accepté depuis le client : il est toujours
    // recalculé côté serveur à partir de la distance, pour éviter toute
    // falsification du montant facturé.
    const estimation = this.pricingService.estimer(
      dto.type,
      dto.distanceKm ?? 0,
    );

    return this.prisma.course.create({
      data: {
        clientId,
        type: dto.type,
        adresseDepart: dto.adresseDepart,
        latitudeDepart: dto.latitudeDepart,
        longitudeDepart: dto.longitudeDepart,
        adresseArrivee: dto.adresseArrivee,
        latitudeArrivee: dto.latitudeArrivee,
        longitudeArrivee: dto.longitudeArrivee,
        distanceKm: estimation.distanceKm,
        dureeEstimeeMin: estimation.dureeEstimeeMin,
        prixFcfa: estimation.prixFcfa,
        methodePaiement: dto.methodePaiement,
      },
    });
  }

  listerPourClient(clientId: string) {
    return this.prisma.course.findMany({
      where: { clientId },
      orderBy: { createdAt: 'desc' },
    });
  }

  listerPourConducteur(conducteurId: string) {
    return this.prisma.course.findMany({
      where: { conducteurId },
      orderBy: { createdAt: 'desc' },
    });
  }
}
