import { Injectable } from '@nestjs/common';
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
        createdAt: true,
      },
      orderBy: { createdAt: 'desc' },
    });
  }
}
