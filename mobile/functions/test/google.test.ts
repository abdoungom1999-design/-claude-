import { test } from 'node:test';
import assert from 'node:assert/strict';
import { HttpsError } from 'firebase-functions/v2/https';
import { coordonneesAdresse, rechercherAdresses } from '../src/adresses';
import { ClientGoogle, ErreurGoogle } from '../src/google';

interface Appel {
  url: string;
  init: RequestInit;
}

/** fetch simulé : enregistre la requête et renvoie [reponse]. */
function fetchFactice(reponse: unknown, statut = 200) {
  const appels: Appel[] = [];
  const f = (async (url: string, init: RequestInit) => {
    appels.push({ url, init });
    return new Response(JSON.stringify(reponse), { status: statut });
  }) as unknown as typeof fetch;
  return { f, appels };
}

const entetes = (a: Appel) => a.init.headers as Record<string, string>;
const SESSION = 'session-12345678';

test('autocomplétion : Sénégal, Dakar en priorité, clé en en-tête, propositions lisibles', async () => {
  const { f, appels } = fetchFactice({
    suggestions: [
      {
        placePrediction: {
          placeId: 'ChIJ-ucad-1234',
          text: { text: 'UCAD, Dakar, Sénégal' },
          structuredFormat: { mainText: { text: 'UCAD' }, secondaryText: { text: 'Dakar, Sénégal' } },
        },
      },
      { queryPrediction: { text: { text: 'ucad restaurant' } } },
    ],
  });
  const propositions = await new ClientGoogle('CLE', f).autocompletion('ucad', SESSION);

  assert.deepEqual(propositions, [{ placeId: 'ChIJ-ucad-1234', principal: 'UCAD', secondaire: 'Dakar, Sénégal' }]);
  const [appel] = appels;
  assert.equal(appel.url, 'https://places.googleapis.com/v1/places:autocomplete');
  assert.equal(entetes(appel)['X-Goog-Api-Key'], 'CLE');
  const corps = JSON.parse(appel.init.body as string);
  assert.equal(corps.input, 'ucad');
  assert.equal(corps.sessionToken, SESSION);
  assert.deepEqual(corps.includedRegionCodes, ['sn']);
  assert.equal(corps.languageCode, 'fr');
  assert.ok(corps.locationBias.circle.radius > 0);
});

test('coordonnées : même session, champs minimaux (coût), latitude/longitude', async () => {
  const { f, appels } = fetchFactice({ formattedAddress: 'Dakar, Sénégal', location: { latitude: 14.69, longitude: -17.46 } });
  const c = await new ClientGoogle('CLE', f).coordonnees('ChIJ-ucad-1234', SESSION);

  assert.deepEqual(c, { latitude: 14.69, longitude: -17.46, adresse: 'Dakar, Sénégal' });
  assert.match(appels[0].url, /^https:\/\/places\.googleapis\.com\/v1\/places\/ChIJ-ucad-1234\?/);
  assert.match(appels[0].url, /sessionToken=session-12345678/);
  assert.equal(entetes(appels[0])['X-Goog-FieldMask'], 'formattedAddress,location');
});

test('itinéraire : distance par la route en km, sans trafic ; aucun itinéraire -> null', async () => {
  const { f, appels } = fetchFactice({ routes: [{ distanceMeters: 12345 }] });
  const google = new ClientGoogle('CLE', f);
  const itineraire = await google.itineraire({ latitude: 14.69, longitude: -17.44 }, { latitude: 14.74, longitude: -17.51 });

  assert.deepEqual(itineraire, { distanceKm: 12.345 });
  assert.equal(appels[0].url, 'https://routes.googleapis.com/directions/v2:computeRoutes');
  const corps = JSON.parse(appels[0].init.body as string);
  assert.equal(corps.routingPreference, 'TRAFFIC_UNAWARE');
  assert.deepEqual(corps.origin.location.latLng, { latitude: 14.69, longitude: -17.44 });

  const vide = fetchFactice({});
  assert.equal(await new ClientGoogle('CLE', vide.f).itineraire({ latitude: 1, longitude: 1 }, { latitude: 2, longitude: 2 }), null);
});

test('erreur Google (clé refusée, quota) : ErreurGoogle', async () => {
  const { f } = fetchFactice({ error: { message: 'API key not valid' } }, 403);
  await assert.rejects(new ClientGoogle('CLE', f).autocompletion('ucad', SESSION), ErreurGoogle);
});

test('callables d\'adresses : connexion, validation, erreur Google -> "unavailable"', async () => {
  const code = (c: string) => (e: unknown) => e instanceof HttpsError && e.code === c;
  const ok = fetchFactice({ suggestions: [] });
  const google = new ClientGoogle('CLE', ok.f);

  await assert.rejects(rechercherAdresses(google, undefined, { texte: 'ucad', session: SESSION }), code('unauthenticated'));
  await assert.rejects(rechercherAdresses(google, 'awa', { texte: 'u', session: SESSION }), code('invalid-argument'));
  await assert.rejects(rechercherAdresses(google, 'awa', { texte: 'ucad', session: 'x' }), code('invalid-argument'));
  await assert.rejects(coordonneesAdresse(google, 'awa', { placeId: '../../etc', session: SESSION }), code('invalid-argument'));
  assert.deepEqual(await rechercherAdresses(google, 'awa', { texte: 'ucad', session: SESSION }), { propositions: [] });
  assert.equal(ok.appels.length, 1);

  await assert.rejects(rechercherAdresses(null, 'awa', { texte: 'ucad', session: SESSION }), code('unavailable'));
  const panne = fetchFactice({}, 500);
  await assert.rejects(
    coordonneesAdresse(new ClientGoogle('CLE', panne.f), 'awa', { placeId: 'ChIJ-ucad-1234', session: SESSION }),
    code('unavailable'),
  );
});
