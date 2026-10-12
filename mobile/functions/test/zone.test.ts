import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { DISTANCE_TRAJET_MAX_KM, validerTrajet } from '../src/commandes';
import { FRAICHEUR_POSITION_ALERTE_MS, RAYON_ALERTE_KM } from '../src/notifications';
import { distanceKm } from '../src/tarification';
import { BIAIS_ZONE, VILLES_PROVINCE, ZONE_SERVICE, zoneTarifaire } from '../src/zone';

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

/** Source d'un fichier de l'app Flutter (dossier lib/ du projet), lu depuis functions/lib/test. */
const sourceDart = (...chemin: string[]): string => readFileSync(resolve(__dirname, '..', '..', '..', 'lib', ...chemin), 'utf8');

test('zone de service : l\'app (recherche de secours) et le serveur (Google Places) ont exactement les mêmes bords', () => {
  const source = sourceDart('core', 'maps', 'zone_service.dart');
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

test('zone tarifaire : Thiès, Mbour et leurs environs = province ; Dakar, sa banlieue et tout le reste = Dakar', () => {
  const province: Lieu[] = [
    { nom: 'Thiès (centre)', latitude: 14.791, longitude: -16.9359 },
    { nom: 'Mont-Rolland', latitude: 14.8333, longitude: -16.9 },
    { nom: 'Pout', latitude: 14.77, longitude: -17.05 },
    { nom: 'Mbour (centre)', latitude: 14.4196, longitude: -16.964 },
    { nom: 'Saly', latitude: 14.4472, longitude: -17.0 },
    { nom: 'Somone', latitude: 14.4906, longitude: -17.0561 },
    { nom: 'Nianing', latitude: 14.3458, longitude: -17.0 },
  ];
  const dakar: Lieu[] = [
    { nom: 'Dakar (Plateau)', latitude: 14.6928, longitude: -17.4467 },
    { nom: 'Pointe des Almadies', latitude: 14.7447, longitude: -17.5436 },
    { nom: 'Keur Massar', latitude: 14.7836, longitude: -17.3114 },
    { nom: 'Rufisque', latitude: 14.7167, longitude: -17.2733 },
    { nom: 'Diamniadio', latitude: 14.7189, longitude: -17.1833 },
    { nom: 'Sébikotane', latitude: 14.75, longitude: -17.13 },
    { nom: 'Lac Rose', latitude: 14.8386, longitude: -17.2297 },
    { nom: 'Popenguine (au-delà des 20 km de Mbour)', latitude: 14.55, longitude: -17.12 },
    { nom: 'Saint-Louis (hors zone : grille de Dakar par défaut)', latitude: 16.0179, longitude: -16.4896 },
  ];
  for (const lieu of province) assert.equal(zoneTarifaire(lieu), 'PROVINCE', lieu.nom);
  for (const lieu of dakar) assert.equal(zoneTarifaire(lieu), 'DAKAR', lieu.nom);
});

test('zone tarifaire : les cercles de Thiès et de Mbour ne se touchent pas, et leurs centres sont dans la zone de service', () => {
  const [thies, mbour] = VILLES_PROVINCE;
  const ecart = distanceKm(thies.centre, mbour.centre);
  assert.ok(ecart > thies.rayonKm + mbour.rayonKm, `${ecart.toFixed(1)} km entre les centres`);
  for (const ville of VILLES_PROVINCE) {
    assert.ok(dedans({ nom: ville.nom, ...ville.centre }), `${ville.nom} doit être dans la zone de service`);
  }
});

test('zone tarifaire : la limite exacte est le rayon (juste dedans = province, juste dehors = Dakar)', () => {
  const [thies] = VILLES_PROVINCE;
  // 1 degré de latitude = 111,195 km.
  const versLeNord = (km: number) => ({ latitude: thies.centre.latitude + km / 111.195, longitude: thies.centre.longitude });
  assert.equal(zoneTarifaire(versLeNord(thies.rayonKm - 0.1)), 'PROVINCE');
  assert.equal(zoneTarifaire(versLeNord(thies.rayonKm + 0.1)), 'DAKAR');
});

test('villes de province : l\'app (mode démo, écran Admin) et le serveur ont les mêmes villes, centres et rayons', () => {
  const source = sourceDart('core', 'maps', 'zone_service.dart');
  const villesDart = [
    ...source.matchAll(/VilleProvince\(nom: '([^']+)', latitude: (-?[0-9.]+), longitude: (-?[0-9.]+), rayonKm: ([0-9.]+)\)/g),
  ].map(([, nom, latitude, longitude, rayonKm]) => ({
    nom,
    centre: { latitude: Number(latitude), longitude: Number(longitude) },
    rayonKm: Number(rayonKm),
  }));
  assert.deepEqual(
    villesDart,
    VILLES_PROVINCE.map(({ nom, centre, rayonKm }) => ({ nom, centre: { ...centre }, rayonKm })),
  );
});

test('trajet maximum et rayon des alertes : mêmes valeurs dans l\'app et sur le serveur', () => {
  const nombreDart = (fichier: string[], motif: RegExp): number => {
    const trouve = sourceDart(...fichier).match(motif);
    assert.ok(trouve, `introuvable dans lib/${fichier.join('/')} : ${motif}`);
    return Number(trouve[1]);
  };
  assert.equal(
    nombreDart(['features', 'courses', 'data', 'estimation_course_controller.dart'], /static const distanceMaximaleKm = ([0-9.]+);/),
    DISTANCE_TRAJET_MAX_KM,
  );
  assert.equal(nombreDart(['features', 'conducteur', 'data', 'rayon_alertes.dart'], /static const rayonKm = ([0-9.]+);/), RAYON_ALERTE_KM);
  assert.equal(
    nombreDart(['features', 'conducteur', 'data', 'rayon_alertes.dart'], /static const fraicheurPosition = Duration\(minutes: ([0-9]+)\);/) * 60 * 1000,
    FRAICHEUR_POSITION_ALERTE_MS,
  );
});

test('trajet trop long : l\'app affiche mot pour mot le message du serveur', () => {
  const source = sourceDart('features', 'courses', 'data', 'estimation_course_controller.dart');
  const declaration = source.match(/static const messageTrajetTropLong =([^;]*);/);
  assert.ok(declaration, 'messageTrajetTropLong introuvable');
  // Plusieurs chaînes Dart côte à côte = une seule ; \' est une apostrophe.
  const messageDart = [...declaration[1].matchAll(/'((?:[^'\\]|\\.)*)'/g)].map(([, morceau]) => morceau.replace(/\\'/g, "'")).join('');

  let messageServeur = '';
  try {
    validerTrajet({
      type: 'PASSAGER',
      depart: { latitude: 14.6928, longitude: -17.4467 },
      arrivee: { latitude: 14.791, longitude: -16.9359 },
    });
  } catch (e) {
    messageServeur = (e as Error).message;
  }
  assert.equal(messageDart, messageServeur);
  assert.match(messageServeur, /^Ce trajet dépasse 30 km\./);
});
