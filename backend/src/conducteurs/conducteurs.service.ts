import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { UpdatePositionDto } from './dto/update-position.dto';
import { UpdateStatutDto } from './dto/update-statut.dto';

@Injectable()
export class ConducteursService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {}

  async findById(id: string) {
    const conducteur = await this.prisma.conducteur.findUnique({
      where: { id },
      select: {
        id: true,
        nom: true,
        telephone: true,
        vehiculeId: true,
        statut: true,
        estValide: true,
        createdAt: true,
      },
    });
    if (!conducteur) {
      throw new NotFoundException('Conducteur introuvable');
    }
    return conducteur;
  }

  async mettreAJourStatut(id: string, dto: UpdateStatutDto) {
    if (dto.statut === 'EN_LIGNE') {
      const conducteur = await this.prisma.conducteur.findUnique({
        where: { id },
        select: { estValide: true },
      });
      if (!conducteur?.estValide) {
        throw new ForbiddenException(
          "Compte conducteur en attente de validation par l'administrateur",
        );
      }
    }

    return this.prisma.conducteur.update({
      where: { id },
      data: { statut: dto.statut },
      select: { id: true, statut: true },
    });
  }

  async mettreAJourPosition(id: string, dto: UpdatePositionDto) {
    await this.redis.majPositionConducteur(id, dto);
    await this.prisma.conducteur.update({
      where: { id },
      data: {
        latitudeActuelle: dto.latitude,
        longitudeActuelle: dto.longitude,
        derniereMajPosition: new Date(),
      },
    });
    return { ok: true };
  }

  async trouverProches(latitude: number, longitude: number, rayonKm: number) {
    const idsProches = await this.redis.conducteursProches(
      { latitude, longitude },
      rayonKm,
    );
    if (idsProches.length === 0) {
      return [];
    }

    return this.prisma.conducteur.findMany({
      where: {
        id: { in: idsProches },
        statut: 'EN_LIGNE',
        estValide: true,
      },
      select: {
        id: true,
        nom: true,
        vehiculeId: true,
        latitudeActuelle: true,
        longitudeActuelle: true,
      },
    });
  }
}
