import { Timestamp, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

// ---------------------------------------------------------------------
// Chauffeurs à proximité (callable `chauffeursProches`), pour la carte de
// l'accueil client. Jamais d'identité ni de position exacte : chaque
// chauffeur disponible est ramené au centre d'une case d'environ 150 m,
// une case n'apparaît qu'une fois, et seul le cap (arrondi à 45°) sert à
// orienter l'icône de moto.
// ---------------------------------------------------------------------

/** Taille des cases de la grille d'anonymisation, en mètres. */
export const PAS_ANONYMISATION_M = 150;

/** Rayon de recherche autour du client. */
export const RAYON_KM = 3;

/** Une position plus ancienne n'est plus affichée (chauffeur parti ou signal perdu). */
export const FRAICHEUR_MS = 2 * 60 * 1000;

/** Plafond d'icônes renvoyées. */
export const MAX_CHAUFFEURS = 15;

/** Vitesse moyenne d'une moto dans Dakar, pour l'estimation d'approche. */
const VITESSE_KMH = 20;

const METRES_PAR_DEGRE = 111_320;

export interface ChauffeurProche {
  latitude: number;
  longitude: number;
  /** Cap en degrés, arrondi à 45° (0 = nord), ou null s'il est inconnu. */
  cap: number | null;
}

export interface Proximite {
  chauffeurs: ChauffeurProche[];
  /** Approche estimée du plus proche, en minutes (null : aucun chauffeur). */
  approcheMinutes: number | null;
}

const arrondi5 = (x: number) => Math.round(x * 1e5) / 1e5;

/** Centre de la case d'environ 150 m qui contient ce point. */
export function arrondirPosition(latitude: number, longitude: number): { latitude: number; longitude: number } {
  const pasLat = PAS_ANONYMISATION_M / METRES_PAR_DEGRE;
  const lat = Math.round(latitude / pasLat) * pasLat;
  const pasLng = PAS_ANONYMISATION_M / (METRES_PAR_DEGRE * Math.cos((lat * Math.PI) / 180));
  const lng = Math.round(longitude / pasLng) * pasLng;
  return { latitude: arrondi5(lat), longitude: arrondi5(lng) };
}

/** Cap arrondi à 45° (8 directions), ou null. */
export function arrondirCap(cap: unknown): number | null {
  if (typeof cap !== 'number' || !Number.isFinite(cap) || cap < 0) return null;
  return (Math.round(cap / 45) * 45) % 360;
}

export function distanceKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const rad = (d: number) => (d * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 6371 * 2 * Math.asin(Math.min(1, Math.sqrt(a)));
}

function coordonnee(valeur: unknown, max: number, nom: string): number {
  if (typeof valeur !== 'number' || !Number.isFinite(valeur) || Math.abs(valeur) > max) {
    throw new HttpsError('invalid-argument', `${nom} invalide.`);
  }
  return valeur;
}

export async function chauffeursProches(
  db: Firestore,
  uid: string | undefined,
  donnees: unknown,
  maintenant: Date,
): Promise<Proximite> {
  if (!uid) throw new HttpsError('unauthenticated', 'Connectez-vous pour voir les chauffeurs à proximité.');
  const d = (donnees ?? {}) as Record<string, unknown>;
  const lat = coordonnee(d.latitude, 90, 'Latitude');
  const lng = coordonnee(d.longitude, 180, 'Longitude');

  const dLat = (RAYON_KM * 1000) / METRES_PAR_DEGRE;
  const instantane = await db
    .collection('positions_chauffeurs')
    .where('latitude', '>=', lat - dLat)
    .where('latitude', '<=', lat + dLat)
    .get();

  const limite = maintenant.getTime() - FRAICHEUR_MS;
  const candidats: { distance: number; chauffeur: ChauffeurProche }[] = [];
  for (const doc of instantane.docs) {
    const p = doc.data();
    // Chauffeur en course (déjà pris), position périmée ou incomplète : ignoré.
    if (typeof p.courseId === 'string' && p.courseId) continue;
    if (!(p.majLe instanceof Timestamp) || p.majLe.toMillis() < limite) continue;
    if (typeof p.latitude !== 'number' || typeof p.longitude !== 'number') continue;
    const distance = distanceKm(lat, lng, p.latitude, p.longitude);
    if (distance > RAYON_KM) continue;
    candidats.push({
      distance,
      chauffeur: { ...arrondirPosition(p.latitude, p.longitude), cap: arrondirCap(p.cap) },
    });
  }

  candidats.sort((a, b) => a.distance - b.distance);
  const cases = new Set<string>();
  const chauffeurs: ChauffeurProche[] = [];
  for (const { chauffeur } of candidats) {
    const cle = `${chauffeur.latitude},${chauffeur.longitude}`;
    if (cases.has(cle)) continue;
    cases.add(cle);
    chauffeurs.push(chauffeur);
    if (chauffeurs.length >= MAX_CHAUFFEURS) break;
  }

  // Approche : distance du plus proche + 1 min de prise en charge, au
  // moins 2 min (jamais une promesse trop précise).
  const approcheMinutes = candidats.length
    ? Math.max(2, Math.ceil((candidats[0].distance / VITESSE_KMH) * 60) + 1)
    : null;
  return { chauffeurs, approcheMinutes };
}
