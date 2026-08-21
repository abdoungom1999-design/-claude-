import { Injectable, NotFoundException } from '@nestjs/common';
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
        createdAt: true,
      },
    });
    if (!conducteur) {
      throw new NotFoundException('Conducteur introuvable');
    }
    return conducteur;
  }

  async mettreAJourStatut(id: string, dto: UpdateStatutDto) {
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
}
