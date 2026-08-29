import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class AdminService {
  constructor(private readonly prisma: PrismaService) {}

  listerClients() {
    return this.prisma.client.findMany({
      select: { id: true, nom: true, telephone: true, createdAt: true },
      orderBy: { createdAt: 'desc' },
    });
  }

  listerConducteurs() {
    return this.prisma.conducteur.findMany({
      select: {
        id: true,
        nom: true,
        telephone: true,
        vehiculeId: true,
        statut: true,
        estValide: true,
        createdAt: true,
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  async validerConducteur(id: string) {
    const conducteur = await this.prisma.conducteur.findUnique({
      where: { id },
    });
    if (!conducteur) {
      throw new NotFoundException('Conducteur introuvable');
    }

    return this.prisma.conducteur.update({
      where: { id },
      data: { estValide: true },
      select: { id: true, nom: true, estValide: true },
    });
  }
}
