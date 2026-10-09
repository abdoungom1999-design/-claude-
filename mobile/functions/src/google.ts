import type { Point } from './tarification';

/**
 * Appels à Google Maps Platform depuis les Cloud Functions : la clé
 * (secret GOOGLE_MAPS_API_KEY) ne quitte jamais le serveur.
 *
 * - Places API (New) : autocomplétion et coordonnées d'une adresse.
 * - Routes API : distance par la route, qui sert au prix.
 */

/** Centre de Dakar : les résultats proches sont favorisés. */
const CENTRE_DAKAR = { latitude: 14.7167, longitude: -17.4677 };
const RAYON_PRIORITE_M = 30000;
const DELAI_MS = 5000;

export interface PropositionAdresse {
  placeId: string;
  /** "Université Cheikh Anta Diop" */
  principal: string;
  /** "Avenue Cheikh Anta Diop, Dakar, Sénégal" */
  secondaire: string;
}

export interface Coordonnees {
  latitude: number;
  longitude: number;
  adresse: string;
}

export interface Itineraire {
  distanceKm: number;
}

/** Itinéraire à suivre, pour guider un chauffeur sur la carte. */
export interface ItineraireTrace {
  distanceM: number;
  /** Tracé au format « encoded polyline » de Google (points à 5 décimales). */
  trace: string;
}

export class ErreurGoogle extends Error {}

type Fetch = typeof fetch;

export class ClientGoogle {
  constructor(
    private readonly cle: string,
    private readonly fetcher: Fetch = fetch,
  ) {}

  private async appeler(url: string, init: RequestInit, masque: string): Promise<unknown> {
    let reponse: Response;
    try {
      reponse = await this.fetcher(url, {
        ...init,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': this.cle,
          'X-Goog-FieldMask': masque,
        },
        signal: AbortSignal.timeout(DELAI_MS),
      });
    } catch (e) {
      throw new ErreurGoogle(`Google injoignable : ${(e as Error).message}`);
    }
    if (!reponse.ok) {
      throw new ErreurGoogle(`Google a répondu ${reponse.status} : ${(await reponse.text()).slice(0, 300)}`);
    }
    return reponse.json();
  }

  /** Autocomplétion d'adresses, limitée au Sénégal, Dakar en priorité. */
  async autocompletion(texte: string, session: string): Promise<PropositionAdresse[]> {
    const donnees = (await this.appeler(
      'https://places.googleapis.com/v1/places:autocomplete',
      {
        method: 'POST',
        body: JSON.stringify({
          input: texte,
          sessionToken: session,
          languageCode: 'fr',
          regionCode: 'sn',
          includedRegionCodes: ['sn'],
          locationBias: { circle: { center: CENTRE_DAKAR, radius: RAYON_PRIORITE_M } },
        }),
      },
      'suggestions.placePrediction.placeId,suggestions.placePrediction.text,suggestions.placePrediction.structuredFormat',
    )) as { suggestions?: { placePrediction?: Prediction }[] };

    const propositions: PropositionAdresse[] = [];
    for (const suggestion of donnees.suggestions ?? []) {
      const p = suggestion.placePrediction;
      if (!p?.placeId) continue;
      const principal = p.structuredFormat?.mainText?.text ?? p.text?.text ?? '';
      if (!principal) continue;
      propositions.push({
        placeId: p.placeId,
        principal,
        secondaire: p.structuredFormat?.secondaryText?.text ?? '',
      });
    }
    return propositions;
  }

  /**
   * Coordonnées d'une adresse choisie. Même jeton de session que
   * l'autocomplétion : Google facture alors la recherche comme une
   * seule session.
   */
  async coordonnees(placeId: string, session: string): Promise<Coordonnees> {
    const params = new URLSearchParams({ languageCode: 'fr', regionCode: 'sn', sessionToken: session });
    const donnees = (await this.appeler(
      `https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}?${params}`,
      { method: 'GET' },
      'formattedAddress,location',
    )) as { formattedAddress?: string; location?: { latitude?: number; longitude?: number } };

    const { latitude, longitude } = donnees.location ?? {};
    if (typeof latitude !== 'number' || typeof longitude !== 'number') {
      throw new ErreurGoogle('Adresse sans coordonnées.');
    }
    return { latitude, longitude, adresse: donnees.formattedAddress ?? '' };
  }

  /**
   * Distance par la route (voiture, sans trafic : résultat stable d'un
   * appel à l'autre). `null` si Google ne trouve aucun itinéraire.
   */
  async itineraire(depart: Point, arrivee: Point): Promise<Itineraire | null> {
    const donnees = (await this.appeler(
      'https://routes.googleapis.com/directions/v2:computeRoutes',
      {
        method: 'POST',
        body: JSON.stringify({
          origin: { location: { latLng: depart } },
          destination: { location: { latLng: arrivee } },
          travelMode: 'DRIVE',
          routingPreference: 'TRAFFIC_UNAWARE',
          languageCode: 'fr',
          units: 'METRIC',
        }),
      },
      'routes.distanceMeters',
    )) as { routes?: { distanceMeters?: number }[] };

    const metres = donnees.routes?.[0]?.distanceMeters;
    if (typeof metres !== 'number' || metres <= 0) return null;
    return { distanceKm: metres / 1000 };
  }

  /**
   * Itinéraire à suivre (voiture, sans trafic) : distance et tracé, pour
   * guider un chauffeur vers son client puis vers la destination. Mêmes
   * réglages que [itineraire], plus le tracé. `null` si Google ne trouve
   * aucun itinéraire.
   */
  async itineraireAvecTrace(depart: Point, arrivee: Point): Promise<ItineraireTrace | null> {
    const donnees = (await this.appeler(
      'https://routes.googleapis.com/directions/v2:computeRoutes',
      {
        method: 'POST',
        body: JSON.stringify({
          origin: { location: { latLng: depart } },
          destination: { location: { latLng: arrivee } },
          travelMode: 'DRIVE',
          routingPreference: 'TRAFFIC_UNAWARE',
          polylineQuality: 'HIGH_QUALITY',
          polylineEncoding: 'ENCODED_POLYLINE',
          languageCode: 'fr',
          units: 'METRIC',
        }),
      },
      'routes.distanceMeters,routes.polyline',
    )) as { routes?: { distanceMeters?: number; polyline?: { encodedPolyline?: string } }[] };

    const route = donnees.routes?.[0];
    const metres = route?.distanceMeters;
    const trace = route?.polyline?.encodedPolyline;
    if (typeof metres !== 'number' || metres <= 0 || typeof trace !== 'string' || trace === '') return null;
    return { distanceM: Math.round(metres), trace };
  }
}

interface Prediction {
  placeId?: string;
  text?: { text?: string };
  structuredFormat?: { mainText?: { text?: string }; secondaryText?: { text?: string } };
}
