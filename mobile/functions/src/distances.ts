import { createHash } from 'node:crypto';
import { Timestamp, type Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import type { ClientGoogle } from './google';
import { distanceRouteEstimeeKm, type Point } from './tarification';

/**
 * Distance d'un trajet, pour le prix :
 * - "route" : distance réelle par la route (Google Routes API) ;
 * - "estimation" : secours si Google ne répond pas (vol d'oiseau x 1,1),
 *   pour ne jamais bloquer une commande.
 */
export interface DistanceTrajet {
  distanceKm: number;
  source: 'route' | 'estimation';
}

export type CalculDistance = (depart: Point, arrivee: Point) => Promise<DistanceTrajet>;

/** Une distance par la route reste valable 30 jours (routes stables). */
export const VALIDITE_CACHE_MS = 30 * 24 * 3600 * 1000;

/**
 * Clé du cache : mêmes coordonnées (au mètre près), même sens. Le prix
 * affiché puis recalculé à la commande repose ainsi sur la même distance,
 * et Google n'est appelé qu'une fois par trajet.
 */
export function cleTrajet(depart: Point, arrivee: Point): string {
  const p = (x: Point) => `${x.latitude.toFixed(5)},${x.longitude.toFixed(5)}`;
  return createHash('sha256').update(`${p(depart)}>${p(arrivee)}`).digest('hex').slice(0, 32);
}

export function calculDistance(db: Firestore, google: ClientGoogle | null, maintenant: () => Date): CalculDistance {
  return async (depart, arrivee) => {
    const secours: DistanceTrajet = { distanceKm: distanceRouteEstimeeKm(depart, arrivee), source: 'estimation' };
    if (!google) return secours;

    // Collection réservée au serveur (aucune règle ne l'ouvre à l'app).
    const ref = db.collection('distances').doc(cleTrajet(depart, arrivee));
    try {
      const cache = await ref.get();
      const calculeLe = cache.get('calculeLe') as Timestamp | undefined;
      if (cache.exists && calculeLe && maintenant().getTime() - calculeLe.toMillis() < VALIDITE_CACHE_MS) {
        return { distanceKm: cache.get('distanceKm') as number, source: 'route' };
      }
    } catch (e) {
      logger.warn('Cache des distances illisible', e);
    }

    try {
      const itineraire = await google.itineraire(depart, arrivee);
      if (!itineraire) return secours;
      await ref
        .set({ distanceKm: itineraire.distanceKm, calculeLe: Timestamp.fromDate(maintenant()), depart, arrivee })
        .catch((e) => logger.warn('Cache des distances non écrit', e));
      return { distanceKm: itineraire.distanceKm, source: 'route' };
    } catch (e) {
      logger.warn('Routes API indisponible : distance estimée', e);
      return secours;
    }
  };
}
