import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';
import type { ClientGoogle, Coordonnees, PropositionAdresse } from './google';

/**
 * Callables `rechercherAdresses` et `coordonneesAdresse` : recherche
 * d'adresses Google Places pour l'app, sans exposer la clé. Réservées
 * aux utilisateurs connectés (chaque appel est facturé).
 */

const SESSION = /^[A-Za-z0-9_-]{8,64}$/;
const PLACE_ID = /^[A-Za-z0-9_-]{10,300}$/;

function champs(donnees: unknown): Record<string, unknown> {
  if (typeof donnees !== 'object' || donnees === null) throw new HttpsError('invalid-argument', 'Requête invalide.');
  return donnees as Record<string, unknown>;
}

function session(d: Record<string, unknown>): string {
  if (typeof d.session !== 'string' || !SESSION.test(d.session)) {
    throw new HttpsError('invalid-argument', 'Session de recherche invalide.');
  }
  return d.session;
}

function indisponible(e: unknown): HttpsError {
  logger.error('Places API', e);
  return new HttpsError('unavailable', 'La recherche d\'adresses est momentanément indisponible.');
}

export async function rechercherAdresses(
  google: ClientGoogle | null,
  uid: string | undefined,
  donnees: unknown,
): Promise<{ propositions: PropositionAdresse[] }> {
  if (!uid) throw new HttpsError('unauthenticated', 'Connectez-vous pour rechercher une adresse.');
  const d = champs(donnees);
  const texte = typeof d.texte === 'string' ? d.texte.trim() : '';
  if (texte.length < 2 || texte.length > 120) throw new HttpsError('invalid-argument', 'Texte de recherche invalide.');
  const jeton = session(d);
  if (!google) throw indisponible(new Error('Clé GOOGLE_MAPS_API_KEY absente'));
  try {
    return { propositions: await google.autocompletion(texte, jeton) };
  } catch (e) {
    throw indisponible(e);
  }
}

export async function coordonneesAdresse(
  google: ClientGoogle | null,
  uid: string | undefined,
  donnees: unknown,
): Promise<Coordonnees> {
  if (!uid) throw new HttpsError('unauthenticated', 'Connectez-vous pour rechercher une adresse.');
  const d = champs(donnees);
  if (typeof d.placeId !== 'string' || !PLACE_ID.test(d.placeId)) {
    throw new HttpsError('invalid-argument', 'Adresse invalide.');
  }
  const jeton = session(d);
  if (!google) throw indisponible(new Error('Clé GOOGLE_MAPS_API_KEY absente'));
  try {
    return await google.coordonnees(d.placeId, jeton);
  } catch (e) {
    throw indisponible(e);
  }
}
