import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class ClientsService {
  constructor(private readonly prisma: PrismaService) {}

  async findById(id: string) {
    const client = await this.prisma.client.findUnique({
      where: { id },
      select: {
        id: true,
        nom: true,
        telephone: true,
        preferences: true,
        createdAt: true,
      },
    });
    if (!client) {
      throw new NotFoundException('Client introuvable');
    }
    return client;
  }
}
