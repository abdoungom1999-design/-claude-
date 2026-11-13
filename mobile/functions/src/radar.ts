import { FieldValue, type DocumentData, type DocumentReference, type Firestore } from 'firebase-admin/firestore';
import { arrondirPosition } from './proximite';
import { distanceKm, type Point } from './tarification';
import { VILLES_PROVINCE } from './zone';

/**
 * Radar des chauffeurs : ce qu'un chauffeur voit d'une course TANT QU'IL NE
 * L'A PAS ACCEPTÉE (décision du client, 13 novembre 2026 : avant l'acceptation,
 * une zone arrondie seulement ; l'adresse exacte et le point GPS précis
 * s'affichent une fois la course acceptée).
 *
 * La course elle-même (`courses/{id}`) porte l'adresse exacte du client : elle
 * n'est lisible que par lui, par le chauffeur qui l'a acceptée et par l'Admin.
 * Le radar est un document à part, `radar/{id}` (même identifiant), qui n'a que
 * ce qu'il faut pour juger une course : prix, distance, type, un départ et une
 * arrivée arrondis à une case d'environ 150 m, et des libellés de zone. Les
 * champs portent les mêmes noms que ceux de la course : l'app lit un document
 * du radar comme une course (`CourseFirestore.depuisDocument`).
 *
 * Le serveur l'écrit avec la course et le retire quand la course n'attend plus
 * (acceptée par le chauffeur dans la même écriture que l'acceptation, annulée,
 * expirée) ; la surveillance de chaque minute balaie ce qui aurait été oublié.
 * Aucune règle ne permet à une app d'y écrire.
 */
export const COLLECTION_RADAR = 'radar';

export const refRadar = (db: Firestore, courseId: string): DocumentReference => db.collection(COLLECTION_RADAR).doc(courseId);

/**
 * Libellé de zone : la ville de province dont le point est proche (Thiès,
 * Mbour), sinon Dakar et sa banlieue. Les centres et les rayons sont ceux de la
 * grille de prix (`zone.ts`) : aucune géographie de plus à tenir à jour.
 */
export function villeDe(point: Point): string {
  return VILLES_PROVINCE.find((ville) => distanceKm(ville.centre, point) <= ville.rayonKm)?.nom ?? 'Dakar';
}

/** Départ ou arrivée tel que le radar le montre : le centre d'une case d'environ 150 m. */
function zoneArrondie(latitude: unknown, longitude: unknown): { latitude: number; longitude: number; ville: string } {
  const centre = arrondirPosition(latitude as number, longitude as number);
  return { ...centre, ville: villeDe(centre) };
}

/**
 * Document du radar d'une course créée à partir de [c], la commande payée (ses
 * coordonnées sont exactes) : mêmes champs que la course, sauf les adresses
 * (remplacées par un libellé de zone) et les positions (arrondies).
 */
export function donneesRadar(c: DocumentData, prixFcfa: number): DocumentData {
  const depart = zoneArrondie(c.latitudeDepart, c.longitudeDepart);
  const arrivee = zoneArrondie(c.latitudeArrivee, c.longitudeArrivee);
  return {
    // Nécessaire à l'acceptation : la liaison chauffeur-client porte les deux identifiants.
    clientId: c.clientId,
    statut: 'en_attente',
    type: c.type,
    adresseDepart: `Zone de départ approximative (${depart.ville})`,
    adresseArrivee: `Zone d'arrivée approximative (${arrivee.ville})`,
    adressesMasquees: true,
    latitudeDepart: depart.latitude,
    longitudeDepart: depart.longitude,
    departArrondi: true,
    latitudeArrivee: arrivee.latitude,
    longitudeArrivee: arrivee.longitude,
    distanceKm: c.distanceKm,
    prixFcfa,
    methodePaiement: c.methodePaiement,
    timestamp: FieldValue.serverTimestamp(),
  };
}

/**
 * Retire du radar les courses qui n'attendent plus de chauffeur (course
 * supprimée, acceptée par une ancienne version de l'app qui ne retire pas le
 * radar, annulée). Rend le nombre de documents retirés.
 */
export async function balayerRadar(db: Firestore): Promise<number> {
  const radar = await db.collection(COLLECTION_RADAR).get();
  let retires = 0;
  for (const doc of radar.docs) {
    const course = await db.collection('courses').doc(doc.id).get();
    if (course.exists && course.get('statut') === 'en_attente') continue;
    await doc.ref.delete();
    retires++;
  }
  return retires;
}
