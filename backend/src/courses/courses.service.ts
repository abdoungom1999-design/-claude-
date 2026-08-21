import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateCourseDto } from './dto/create-course.dto';

@Injectable()
export class CoursesService {
  constructor(private readonly prisma: PrismaService) {}

  creer(clientId: string, dto: CreateCourseDto) {
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
