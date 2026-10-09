import { Timestamp, type Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';
import { DISTANCE_MAX_KM } from './commandes';
import type { ClientGoogle } from './google';
import { departExactDe } from './paiements';
import { distanceKm, type Point } from './tarification';

// ---------------------------------------------------------------------
// Itinéraire du chauffeur (callable `itineraireCourse`) : le tracé pour
// rejoindre son client, puis pour aller à la destination, avec la distance.
// Réservé au chauffeur attribué à la course ; la clé Google reste sur le
// serveur et le point visé est lu dans la course, jamais envoyé par l'app.
// ---------------------------------------------------------------------

const STATUTS_ACTIFS = ['acceptee', 'en_cours'];
const IDENTIFIANT = /^[A-Za-z0-9]{1,128}$/;

/**
 * Délai minimal entre deux calculs pour une même course : l'app en demande un
 * à l'acceptation, un au départ vers la destination, puis un seulement quand
 * le chauffeur quitte son itinéraire. Protège la facture Google d'un abus.
 */
export const INTERVALLE_MIN_MS = 10_000;

/** En dessous, le chauffeur est arrivé : pas de tracé à demander à Google. */
export const DISTANCE_ARRIVEE_M = 30;

export interface ItineraireCourse {
  /** Où mène l'itinéraire : le client (course acceptée), la destination (client à bord). */
  vers: 'client' | 'destination';
  distanceM: number;
  /** Tracé « encoded polyline » de Google ; vide quand le chauffeur est arrivé. */
  trace: string;
}

function donneesRequete(donnees: unknown): Record<string, unknown> {
  return typeof donnees === 'object' && donnees !== null ? (donnees as Record<string, unknown>) : {};
}

function coordonnee(valeur: unknown, max: number, nom: string): number {
  if (typeof valeur !== 'number' || !Number.isFinite(valeur) || Math.abs(valeur) > max) {
    throw new HttpsError('invalid-argument', `${nom} invalide.`);
  }
  return valeur;
}

function position(valeur: unknown): Point {
  const p = donneesRequete(valeur);
  return { latitude: coordonnee(p.latitude, 90, 'Latitude'), longitude: coordonnee(p.longitude, 180, 'Longitude') };
}

function indisponible(): HttpsError {
  return new HttpsError('unavailable', 'L’itinéraire est momentanément indisponible.');
}

export async function itineraireCourse(
  db: Firestore,
  google: ClientGoogle | null,
  uid: string | undefined,
  donnees: unknown,
  maintenant: Date,
): Promise<ItineraireCourse> {
  if (!uid) throw new HttpsError('unauthenticated', 'Connectez-vous.');
  const d = donneesRequete(donnees);
  if (typeof d.courseId !== 'string' || !IDENTIFIANT.test(d.courseId)) {
    throw new HttpsError('invalid-argument', 'Course invalide.');
  }
  const depuis = position(d.depuis);
  const ref = db.doc(`courses/${d.courseId}`);

  const cible = await db.runTransaction(async (tx) => {
    const course = await tx.get(ref);
    if (!course.exists) throw new HttpsError('not-found', 'Course introuvable.');
    if (course.get('chauffeurId') !== uid) throw new HttpsError('permission-denied', 'Cette course n’est pas la vôtre.');
    const statut = course.get('statut');
    if (!STATUTS_ACTIFS.includes(statut)) throw new HttpsError('failed-precondition', 'Cette course n’est plus en cours.');

    const vers = statut === 'en_cours' ? 'destination' : 'client';
    let latitude = course.get(vers === 'client' ? 'latitudeDepart' : 'latitudeArrivee');
    let longitude = course.get(vers === 'client' ? 'longitudeDepart' : 'longitudeArrivee');
    // Le départ de la course n'est qu'arrondi (voir `paiements.ts`) : la position
    // exacte du client est dans son document privé. Une ancienne course, sans
    // `departArrondi`, porte encore la position exacte.
    if (vers === 'client' && course.get('departArrondi') === true) {
      const exact = await tx.get(departExactDe(ref));
      latitude = exact.get('latitude');
      longitude = exact.get('longitude');
      if (!exact.exists || typeof latitude !== 'number' || typeof longitude !== 'number') {
        throw new HttpsError('failed-precondition', 'Le point de rendez-vous n’est pas disponible.');
      }
    }
    if (typeof latitude !== 'number' || typeof longitude !== 'number') {
      throw new HttpsError('failed-precondition', 'Cette course n’a pas de coordonnées.');
    }
    const point = { latitude, longitude };
    if (distanceKm(depuis, point) > DISTANCE_MAX_KM) {
      throw new HttpsError('invalid-argument', 'Votre position est trop éloignée de cette course.');
    }

    const dernier = course.get('itineraireLe');
    if (dernier instanceof Timestamp && maintenant.getTime() - dernier.toMillis() < INTERVALLE_MIN_MS) {
      throw new HttpsError('resource-exhausted', 'Itinéraire déjà calculé à l’instant.');
    }
    tx.update(ref, { itineraireLe: Timestamp.fromDate(maintenant) });
    return { vers, point } as const;
  });

  const metres = Math.round(distanceKm(depuis, cible.point) * 1000);
  if (metres < DISTANCE_ARRIVEE_M) return { vers: cible.vers, distanceM: metres, trace: '' };

  if (!google) {
    logger.error('Itinéraire : clé GOOGLE_MAPS_API_KEY absente');
    throw indisponible();
  }
  let itineraire;
  try {
    itineraire = await google.itineraireAvecTrace(depuis, cible.point);
  } catch (e) {
    logger.warn('Itinéraire : Routes API indisponible', e);
    throw indisponible();
  }
  if (!itineraire) throw indisponible();
  return { vers: cible.vers, distanceM: itineraire.distanceM, trace: itineraire.trace };
}
