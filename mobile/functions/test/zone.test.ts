import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { BIAIS_ZONE, ZONE_SERVICE } from '../src/zone';

interface Lieu {
  nom: string;
  latitude: number;
  longitude: number;
}

const dedans = ({ latitude, longitude }: Lieu): boolean =>
  latitude >= ZONE_SERVICE.sud &&
  latitude <= ZONE_SERVICE.nord &&
  longitude >= ZONE_SERVICE.ouest &&
  longitude <= ZONE_SERVICE.est;

/** Centres et quartiers éloignés des trois villes, dans la zone de service. */
const DANS_LA_ZONE: Lieu[] = [
  { nom: 'Dakar (Plateau)', latitude: 14.6928, longitude: -17.4467 },
  { nom: 'Pointe des Almadies', latitude: 14.7447, longitude: -17.5436 },
  { nom: 'Guédiawaye', latitude: 14.7692, longitude: -17.3995 },
  { nom: 'Keur Massar', latitude: 14.7836, longitude: -17.3114 },
  { nom: 'Rufisque', latitude: 14.7167, longitude: -17.2733 },
  { nom: 'Diamniadio', latitude: 14.7189, longitude: -17.1833 },
  { nom: 'Lac Rose', latitude: 14.8386, longitude: -17.2297 },
  { nom: 'Thiès', latitude: 14.791, longitude: -16.9359 },
  { nom: 'Mont-Rolland', latitude: 14.8333, longitude: -16.9 },
  { nom: 'Mbour', latitude: 14.4196, longitude: -16.964 },
  { nom: 'Saly', latitude: 14.4472, longitude: -17.0 },
  { nom: 'Somone', latitude: 14.4906, longitude: -17.0561 },
  { nom: 'Nianing', latitude: 14.3458, longitude: -17.0 },
];

/** Villes voisines : hors de la zone, pour qu'elle ne s'étende pas sans qu'on le décide. */
const HORS_DE_LA_ZONE: Lieu[] = [
  { nom: 'Saint-Louis', latitude: 16.0179, longitude: -16.4896 },
  { nom: 'Louga', latitude: 15.6144, longitude: -16.2246 },
  { nom: 'Touba', latitude: 14.85, longitude: -15.8833 },
  { nom: 'Kaolack', latitude: 14.1652, longitude: -16.0758 },
  { nom: 'Joal-Fadiouth', latitude: 14.1667, longitude: -16.8333 },
  { nom: 'Ziguinchor', latitude: 12.5833, longitude: -16.2719 },
  { nom: 'Banjul (Gambie)', latitude: 13.4549, longitude: -16.579 },
];

test('zone de service : Dakar, Thiès, Mbour et les routes qui les relient sont dedans', () => {
  for (const lieu of DANS_LA_ZONE) assert.ok(dedans(lieu), `${lieu.nom} doit être dans la zone`);
});

test('zone de service : les autres villes restent dehors tant qu\'on ne les ajoute pas', () => {
  for (const lieu of HORS_DE_LA_ZONE) assert.equal(dedans(lieu), false, `${lieu.nom} doit rester hors de la zone`);
});

test('zone de service : élargir ne retire rien à Dakar (l\'ancien rectangle de Dakar est entièrement dedans)', () => {
  const ancien = { ouest: -17.63, est: -17.1, nord: 14.85, sud: 14.6 };
  assert.ok(ZONE_SERVICE.ouest <= ancien.ouest && ZONE_SERVICE.est >= ancien.est);
  assert.ok(ZONE_SERVICE.nord >= ancien.nord && ZONE_SERVICE.sud <= ancien.sud);
});

test('zone de service : bords cohérents (ouest < est, sud < nord) et taille raisonnable pour une aide à la saisie', () => {
  assert.ok(ZONE_SERVICE.ouest < ZONE_SERVICE.est);
  assert.ok(ZONE_SERVICE.sud < ZONE_SERVICE.nord);
  // Environ 95 km d'ouest en est et 67 km du sud au nord : Google accepte un rectangle de cette taille.
  const largeurKm = (ZONE_SERVICE.est - ZONE_SERVICE.ouest) * 111.32 * Math.cos((14.6 * Math.PI) / 180);
  const hauteurKm = (ZONE_SERVICE.nord - ZONE_SERVICE.sud) * 111.32;
  assert.ok(largeurKm > 80 && largeurKm < 110, `largeur ${largeurKm.toFixed(0)} km`);
  assert.ok(hauteurKm > 55 && hauteurKm < 80, `hauteur ${hauteurKm.toFixed(0)} km`);
});

test('biais Google Places : coin sud-ouest et coin nord-est de la zone', () => {
  assert.deepEqual(BIAIS_ZONE.rectangle.low, { latitude: ZONE_SERVICE.sud, longitude: ZONE_SERVICE.ouest });
  assert.deepEqual(BIAIS_ZONE.rectangle.high, { latitude: ZONE_SERVICE.nord, longitude: ZONE_SERVICE.est });
});

test('zone de service : l\'app (recherche de secours) et le serveur (Google Places) ont exactement les mêmes bords', () => {
  const source = readFileSync(resolve(__dirname, '..', '..', '..', 'lib', 'core', 'maps', 'zone_service.dart'), 'utf8');
  const bord = (nom: string): number => {
    const trouve = source.match(new RegExp(`static const double ${nom} = (-?[0-9.]+);`));
    assert.ok(trouve, `bord « ${nom} » introuvable dans lib/core/maps/zone_service.dart`);
    return Number(trouve[1]);
  };
  assert.deepEqual(
    { ouest: bord('ouest'), est: bord('est'), nord: bord('nord'), sud: bord('sud') },
    { ouest: ZONE_SERVICE.ouest, est: ZONE_SERVICE.est, nord: ZONE_SERVICE.nord, sud: ZONE_SERVICE.sud },
  );
});
