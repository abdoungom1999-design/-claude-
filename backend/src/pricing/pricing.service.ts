import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { TypeCourse } from '../../generated/prisma/enums';

export interface EstimationPrix {
  distanceKm: number;
  dureeEstimeeMin: number;
  multiplicateurTrafic: number;
  prixFcfa: number;
}

interface TarifsType {
  prisEnCharge: number;
  parKm: number;
  parMinute: number;
  prixMinimum: number;
}

/**
 * Calcule le prix d'une course : (prise en charge + distance*tarifKm +
 * durée*tarifMinute) * multiplicateur de trafic, arrondi à la centaine de
 * FCFA la plus proche.
 *
 * La durée est estimée à partir d'une vitesse moyenne (pas de moteur
 * d'itinéraire réel branché). Le multiplicateur de trafic est une règle
 * horaire (heures de pointe / nuit) : un proxy simple en l'absence d'un
 * flux de données trafic temps réel (nécessiterait une API payante type
 * Google/TomTom).
 */
@Injectable()
export class PricingService {
  constructor(private readonly configService: ConfigService) {}

  estimer(type: TypeCourse, distanceKmBrut: number): EstimationPrix {
    const distanceKm = Math.max(distanceKmBrut, 0);
    const vitesseMoyenneKmh = this.configService.get<number>(
      'pricing.vitesseMoyenneKmh',
    )!;
    const dureeEstimeeMin = Math.round((distanceKm / vitesseMoyenneKmh) * 60);

    const tarifs = this.tarifsPour(type);
    const multiplicateurTrafic = this.multiplicateurTraficActuel();

    const montantBrut =
      (tarifs.prisEnCharge +
        distanceKm * tarifs.parKm +
        dureeEstimeeMin * tarifs.parMinute) *
      multiplicateurTrafic;

    const prixFcfa = Math.max(
      this.arrondirCentaine(montantBrut),
      tarifs.prixMinimum,
    );

    return { distanceKm, dureeEstimeeMin, multiplicateurTrafic, prixFcfa };
  }

  private tarifsPour(type: TypeCourse): TarifsType {
    return type === 'COLIS'
      ? this.configService.get<TarifsType>('pricing.colis')!
      : this.configService.get<TarifsType>('pricing.passager')!;
  }

  private multiplicateurTraficActuel(): number {
    // Le Sénégal est en UTC+0 toute l'année (pas de changement d'heure) :
    // on utilise l'heure UTC pour rester correct quel que soit le fuseau
    // du serveur de déploiement.
    const heure = new Date().getUTCHours();
    const heurePointe =
      (heure >= 7 && heure < 10) || (heure >= 17 && heure < 20);
    const heureNuit = heure >= 22 || heure < 5;

    if (heurePointe) return 1.4;
    if (heureNuit) return 1.2;
    return 1.0;
  }

  private arrondirCentaine(montant: number): number {
    return Math.round(montant / 100) * 100;
  }
}
