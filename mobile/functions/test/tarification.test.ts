import { test } from 'node:test';
import assert from 'node:assert/strict';
import { distanceRouteEstimeeKm, estimerPrix, motifMajoration, TARIFS_PAR_ZONE, ZONES_TARIFAIRES } from '../src/tarification';

const a = (heure: number) => new Date(Date.UTC(2026, 8, 27, heure));

test('grille : 15 km hors pointe = 300 + 15 x 200 = 3 300 FCFA, sans facturation à la minute', () => {
  assert.equal(estimerPrix('PASSAGER', 15, a(12)).prixFcfa, 3300);
  assert.equal(estimerPrix('COLIS', 15, a(12)).prixFcfa, 3300);
});

test('majoration x1,2 appliquée avant l\'arrondi à la centaine', () => {
  // (300 + 5 x 200) x 1,2 = 1 560 -> 1 600.
  assert.equal(estimerPrix('PASSAGER', 5, a(8)).prixFcfa, 1600);
  assert.equal(estimerPrix('PASSAGER', 5, a(8)).motifMajoration, 'Heure de pointe');
  assert.equal(estimerPrix('PASSAGER', 5, a(23)).motifMajoration, 'Tarif de nuit');
  assert.equal(estimerPrix('PASSAGER', 5, a(12)).motifMajoration, null);
});

test('prix minimum 1 000 FCFA ; distance négative ramenée à 0', () => {
  assert.equal(estimerPrix('PASSAGER', 0.5, a(12)).prixFcfa, 1000);
  assert.equal(estimerPrix('PASSAGER', -3, a(12)).distanceKm, 0);
});

test('tranches horaires de Dakar (UTC)', () => {
  const attendus: Record<number, string | null> = {
    4: 'Tarif de nuit', 5: null, 6: null, 7: 'Heure de pointe', 9: 'Heure de pointe', 10: null,
    16: null, 17: 'Heure de pointe', 19: 'Heure de pointe', 20: null, 21: null, 22: 'Tarif de nuit', 0: 'Tarif de nuit',
  };
  for (const [heure, motif] of Object.entries(attendus)) assert.equal(motifMajoration(Number(heure)), motif, `${heure} h`);
});

// Valeurs produites par le moteur Dart de l'app (DistanceUtils +
// DemoData.estimerPrix) : le serveur doit donner exactement les mêmes.
const PARITE_DART: { trajet: number[]; heure: number; distanceKm: number; prixFcfa: number; dureeEstimeeMin: number }[] =
  [{"trajet": [14.6928, -17.4467, 14.7456, -17.5134], "heure": 3, "distanceKm": 10.196592130465401, "prixFcfa": 2800, "dureeEstimeeMin": 28}, {"trajet": [14.6928, -17.4467, 14.7456, -17.5134], "heure": 8, "distanceKm": 10.196592130465401, "prixFcfa": 2800, "dureeEstimeeMin": 28}, {"trajet": [14.6928, -17.4467, 14.7456, -17.5134], "heure": 12, "distanceKm": 10.196592130465401, "prixFcfa": 2300, "dureeEstimeeMin": 28}, {"trajet": [14.6928, -17.4467, 14.7456, -17.5134], "heure": 18, "distanceKm": 10.196592130465401, "prixFcfa": 2800, "dureeEstimeeMin": 28}, {"trajet": [14.6928, -17.4467, 14.7456, -17.5134], "heure": 23, "distanceKm": 10.196592130465401, "prixFcfa": 2800, "dureeEstimeeMin": 28}, {"trajet": [14.7167, -17.4677, 14.7645, -17.366], "heure": 3, "distanceKm": 13.375469664108023, "prixFcfa": 3600, "dureeEstimeeMin": 36}, {"trajet": [14.7167, -17.4677, 14.7645, -17.366], "heure": 8, "distanceKm": 13.375469664108023, "prixFcfa": 3600, "dureeEstimeeMin": 36}, {"trajet": [14.7167, -17.4677, 14.7645, -17.366], "heure": 12, "distanceKm": 13.375469664108023, "prixFcfa": 3000, "dureeEstimeeMin": 36}, {"trajet": [14.7167, -17.4677, 14.7645, -17.366], "heure": 18, "distanceKm": 13.375469664108023, "prixFcfa": 3600, "dureeEstimeeMin": 36}, {"trajet": [14.7167, -17.4677, 14.7645, -17.366], "heure": 23, "distanceKm": 13.375469664108023, "prixFcfa": 3600, "dureeEstimeeMin": 36}, {"trajet": [14.6937, -17.4441, 14.695, -17.445], "heure": 3, "distanceKm": 0.19136953014557695, "prixFcfa": 1000, "dureeEstimeeMin": 1}, {"trajet": [14.6937, -17.4441, 14.695, -17.445], "heure": 8, "distanceKm": 0.19136953014557695, "prixFcfa": 1000, "dureeEstimeeMin": 1}, {"trajet": [14.6937, -17.4441, 14.695, -17.445], "heure": 12, "distanceKm": 0.19136953014557695, "prixFcfa": 1000, "dureeEstimeeMin": 1}, {"trajet": [14.6937, -17.4441, 14.695, -17.445], "heure": 18, "distanceKm": 0.19136953014557695, "prixFcfa": 1000, "dureeEstimeeMin": 1}, {"trajet": [14.6937, -17.4441, 14.695, -17.445], "heure": 23, "distanceKm": 0.19136953014557695, "prixFcfa": 1000, "dureeEstimeeMin": 1}, {"trajet": [14.7392, -17.4731, 14.7833, -17.2833], "heure": 3, "distanceKm": 23.088027126152443, "prixFcfa": 5900, "dureeEstimeeMin": 63}, {"trajet": [14.7392, -17.4731, 14.7833, -17.2833], "heure": 8, "distanceKm": 23.088027126152443, "prixFcfa": 5900, "dureeEstimeeMin": 63}, {"trajet": [14.7392, -17.4731, 14.7833, -17.2833], "heure": 12, "distanceKm": 23.088027126152443, "prixFcfa": 4900, "dureeEstimeeMin": 63}, {"trajet": [14.7392, -17.4731, 14.7833, -17.2833], "heure": 18, "distanceKm": 23.088027126152443, "prixFcfa": 5900, "dureeEstimeeMin": 63}, {"trajet": [14.7392, -17.4731, 14.7833, -17.2833], "heure": 23, "distanceKm": 23.088027126152443, "prixFcfa": 5900, "dureeEstimeeMin": 63}, {"trajet": [14.67, -17.43, 14.77, -17.19], "heure": 3, "distanceKm": 30.914605884902425, "prixFcfa": 7800, "dureeEstimeeMin": 84}, {"trajet": [14.67, -17.43, 14.77, -17.19], "heure": 8, "distanceKm": 30.914605884902425, "prixFcfa": 7800, "dureeEstimeeMin": 84}, {"trajet": [14.67, -17.43, 14.77, -17.19], "heure": 12, "distanceKm": 30.914605884902425, "prixFcfa": 6500, "dureeEstimeeMin": 84}, {"trajet": [14.67, -17.43, 14.77, -17.19], "heure": 18, "distanceKm": 30.914605884902425, "prixFcfa": 7800, "dureeEstimeeMin": 84}, {"trajet": [14.67, -17.43, 14.77, -17.19], "heure": 23, "distanceKm": 30.914605884902425, "prixFcfa": 7800, "dureeEstimeeMin": 84}];

test('parité exacte avec le calcul de l\'app Flutter (25 cas)', () => {
  for (const cas of PARITE_DART) {
    const [latD, lngD, latA, lngA] = cas.trajet;
    const distance = distanceRouteEstimeeKm({ latitude: latD, longitude: lngD }, { latitude: latA, longitude: lngA });
    assert.ok(Math.abs(distance - cas.distanceKm) < 1e-9, `distance ${cas.trajet}`);
    const estimation = estimerPrix('PASSAGER', distance, a(cas.heure));
    assert.equal(estimation.prixFcfa, cas.prixFcfa, `prix ${cas.trajet} à ${cas.heure} h`);
    assert.equal(estimation.dureeEstimeeMin, cas.dureeEstimeeMin);
  }
});

test('zones : sans zone indiquée, la grille de Dakar, exactement comme avant', () => {
  assert.deepEqual(estimerPrix('PASSAGER', 15, a(12)), estimerPrix('PASSAGER', 15, a(12), 'DAKAR'));
  assert.equal(estimerPrix('PASSAGER', 15, a(12)).zoneTarifaire, 'DAKAR');
  assert.deepEqual([...ZONES_TARIFAIRES], ['DAKAR', 'PROVINCE']);
});

test('zones : le résultat dit quelle grille a servi', () => {
  assert.equal(estimerPrix('COLIS', 4, a(12), 'PROVINCE').zoneTarifaire, 'PROVINCE');
  assert.equal(estimerPrix('COLIS', 4, a(12), 'DAKAR').zoneTarifaire, 'DAKAR');
});

test('zones : la grille de province est celle qui sert aux départs de province (et elle seule)', () => {
  const avant = { PASSAGER: { ...TARIFS_PAR_ZONE.PROVINCE.PASSAGER }, COLIS: { ...TARIFS_PAR_ZONE.PROVINCE.COLIS } };
  try {
    // Des prix de province de démonstration : 200 + 100 x km, minimum 500.
    Object.assign(TARIFS_PAR_ZONE.PROVINCE.PASSAGER, { prisEnCharge: 200, parKm: 100, parMinute: 0, prixMinimum: 500 });
    assert.equal(estimerPrix('PASSAGER', 10, a(12), 'PROVINCE').prixFcfa, 1200);
    assert.equal(estimerPrix('PASSAGER', 1, a(12), 'PROVINCE').prixFcfa, 500);
    // La majoration s'applique à la grille de province comme à celle de Dakar.
    assert.equal(estimerPrix('PASSAGER', 10, a(8), 'PROVINCE').prixFcfa, 1400); // 1 200 x 1,2 = 1 440 -> 1 400
    // Dakar et les colis de province n'ont pas bougé.
    assert.equal(estimerPrix('PASSAGER', 10, a(12), 'DAKAR').prixFcfa, 2300);
    assert.equal(estimerPrix('PASSAGER', 10, a(12)).prixFcfa, 2300);
    assert.equal(estimerPrix('COLIS', 10, a(12), 'PROVINCE').prixFcfa, 1200); // 150 + 10 x 100 = 1 150 -> 1 200
  } finally {
    Object.assign(TARIFS_PAR_ZONE.PROVINCE.PASSAGER, avant.PASSAGER);
    Object.assign(TARIFS_PAR_ZONE.PROVINCE.COLIS, avant.COLIS);
  }
});

test('province (Thiès, Mbour) : 150 FCFA + 100 FCFA par km, minimum 300 FCFA, comme décidé par le client le 12 octobre 2026', () => {
  const grille = { prisEnCharge: 150, parKm: 100, parMinute: 0, prixMinimum: 300 };
  assert.deepEqual(TARIFS_PAR_ZONE.PROVINCE, { PASSAGER: grille, COLIS: grille }, 'mêmes prix pour la moto et pour le colis');
  const province = (type: 'PASSAGER' | 'COLIS', km: number, heure = 12) => estimerPrix(type, km, a(heure), 'PROVINCE').prixFcfa;
  for (const type of ['PASSAGER', 'COLIS'] as const) {
    assert.equal(province(type, 0.5), 300, 'minimum de course'); // 150 + 50 = 200 -> 300
    assert.equal(province(type, 1), 300); // 250 -> 300
    assert.equal(province(type, 2), 400); // 350 -> 400
    assert.equal(province(type, 5), 700); // 650 -> 700
    assert.equal(province(type, 10), 1200); // 1 150 -> 1 200
    assert.equal(province(type, 15), 1700); // 1 650 -> 1 700
    // Majoration x1,2 conservée aux heures de pointe et la nuit, avant l'arrondi à la centaine.
    assert.equal(province(type, 5, 8), 800); // 650 x 1,2 = 780 -> 800
    assert.equal(province(type, 5, 18), 800);
    assert.equal(province(type, 5, 23), 800);
    assert.equal(province(type, 10, 8), 1400); // 1 150 x 1,2 = 1 380 -> 1 400
  }
  // Dakar n'a pas bougé : la province est environ moitié moins chère.
  assert.equal(estimerPrix('PASSAGER', 5, a(12), 'DAKAR').prixFcfa, 1300);
  assert.equal(estimerPrix('PASSAGER', 5, a(8), 'PROVINCE').motifMajoration, 'Heure de pointe');
});
