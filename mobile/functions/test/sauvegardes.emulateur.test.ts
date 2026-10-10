// Alertes des sauvegardes sur l'émulateur Firestore : npm run test:emulateur.
// L'envoi réel (Firebase Cloud Messaging) et la lecture chez Google sont
// remplacés par des faux qui enregistrent ce qui serait envoyé.
import { after, before, beforeEach, mock, test } from 'node:test';
import assert from 'node:assert/strict';
import { deleteApp, initializeApp, type App } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import type { EnvoiPush, Messagerie } from '../src/notifications';
import { prevenirAdmins, verifierSauvegardes, type AccesGoogle, type ReponseGoogle } from '../src/sauvegardes';

const BASE = 'projects/sprint-vtc/databases/(default)';
const FIRESTORE = 'https://firestore.googleapis.com/v1';
const LUNDI = new Date('2026-10-12T09:07:00Z');
const DIMANCHE = new Date('2026-10-11T09:07:00Z');
const il_y_a = (heures: number, depuis: Date) => new Date(depuis.getTime() - heures * 3_600_000).toISOString();

let app: App;
let db: Firestore;

interface Envoi {
  jetons: string[];
  push: EnvoiPush;
}
class MessagerieFausse implements Messagerie {
  envois: Envoi[] = [];
  jetonsMorts = new Set<string>();
  enPanne = false;

  async envoyer(jetons: string[], push: EnvoiPush) {
    if (this.enPanne) throw new Error('FCM indisponible');
    this.envois.push({ jetons: [...jetons].sort(), push });
    return { envoyes: jetons.filter((j) => !this.jetonsMorts.has(j)).length, invalides: jetons.filter((j) => this.jetonsMorts.has(j)) };
  }
}
let fcm: MessagerieFausse;

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'à lancer via npm run test:emulateur');
  app = initializeApp({ projectId: 'demo-sprint' }, 'sauvegardes');
  db = getFirestore(app);
});
after(() => deleteApp(app));

beforeEach(async () => {
  for (const nom of ['users', 'appareils']) await db.recursiveDelete(db.collection(nom));
  fcm = new MessagerieFausse();
  await db.doc('users/admin1').set({ role: 'admin', nom: 'Abdou' });
  await db.doc('users/admin2').set({ role: 'admin', nom: 'Second Admin' });
  await db.doc('users/awa').set({ role: 'client', nom: 'Awa' });
  await db.doc('users/moussa').set({ role: 'conducteur', nom: 'Moussa' });
  await db.doc('appareils/admin1/jetons/tAdminTel').set({ plateforme: 'android' });
  await db.doc('appareils/admin1/jetons/tAdminWeb').set({ plateforme: 'web' });
  await db.doc('appareils/awa/jetons/tAwa').set({ plateforme: 'android' });
  await db.doc('appareils/moussa/jetons/tMoussa').set({ plateforme: 'android' });
});

const push: EnvoiPush = {
  titre: 'Sauvegardes : à vérifier',
  corps: 'La dernière sauvegarde a 2 j 12 h.',
  canal: 'messages',
  lien: '/#/admin',
  donnees: { type: 'sauvegardes', statut: 'perimee' },
  dureeVieSecondes: 86400,
};

test('alerte : seuls les appareils des comptes Admin la reçoivent, jamais ceux des clients ni des chauffeurs', async () => {
  const atteints = await prevenirAdmins(db, fcm, push);
  assert.equal(atteints, 2);
  assert.equal(fcm.envois.length, 1);
  assert.deepEqual(fcm.envois[0].jetons, ['tAdminTel', 'tAdminWeb']);
  assert.deepEqual(fcm.envois[0].push, push);
});

test('alerte : aucun Admin, ou aucun appareil Admin enregistré = personne n\'est atteint, rien n\'est envoyé', async () => {
  await db.recursiveDelete(db.collection('appareils/admin1/jetons'));
  assert.equal(await prevenirAdmins(db, fcm, push), 0);
  assert.equal(fcm.envois.length, 0);

  await db.doc('users/admin1').update({ role: 'client' });
  await db.doc('users/admin2').update({ role: 'conducteur' });
  assert.equal(await prevenirAdmins(db, fcm, push), 0);
  assert.equal(fcm.envois.length, 0);
});

test('alerte : un jeton que Google déclare mort est supprimé, les autres restent', async () => {
  fcm.jetonsMorts.add('tAdminWeb');
  assert.equal(await prevenirAdmins(db, fcm, push), 1);
  assert.equal((await db.doc('appareils/admin1/jetons/tAdminWeb').get()).exists, false);
  assert.equal((await db.doc('appareils/admin1/jetons/tAdminTel').get()).exists, true);
  assert.equal((await db.doc('appareils/awa/jetons/tAwa').get()).exists, true);
});

test('alerte : Firebase Cloud Messaging en panne = 0 sans lever d\'erreur (le contrôle ne plante pas)', async () => {
  const journal = mock.method(logger, 'warn', () => {});
  try {
    fcm.enPanne = true;
    assert.equal(await prevenirAdmins(db, fcm, push), 0);
  } finally {
    journal.mock.restore();
  }
});

function googleAvec(heures: number, depuis: Date): AccesGoogle {
  const routes: Record<string, unknown> = {
    [`${FIRESTORE}/${BASE}/backupSchedules`]: {
      backupSchedules: [
        { dailyRecurrence: {}, createTime: il_y_a(300, depuis) },
        { weeklyRecurrence: { day: 'SUNDAY' }, createTime: il_y_a(300, depuis) },
      ],
    },
    [`${FIRESTORE}/${BASE}`]: { locationId: 'nam5' },
    [`${FIRESTORE}/projects/sprint-vtc/locations/nam5/backups`]: {
      backups: [{ database: BASE, snapshotTime: il_y_a(heures, depuis), expireTime: il_y_a(-300, depuis), state: 'READY' }],
    },
  };
  return {
    async lire(url: string): Promise<ReponseGoogle> {
      const corps = routes[url] ?? { error: { message: 'route inconnue' } };
      return { statut: url in routes ? 200 : 404, json: corps, texte: JSON.stringify(corps) };
    },
  };
}

test('contrôle de bout en bout : sauvegarde périmée = notification sur les appareils des Admin', async () => {
  const journal = [mock.method(logger, 'info', () => {}), mock.method(logger, 'error', () => {})];
  try {
    const verdict = await verifierSauvegardes({
      google: googleAvec(60, LUNDI),
      prevenir: (p) => prevenirAdmins(db, fcm, p),
      maintenant: LUNDI,
    });
    assert.equal(verdict.statut, 'perimee');
    assert.equal(fcm.envois.length, 1);
    assert.deepEqual(fcm.envois[0].jetons, ['tAdminTel', 'tAdminWeb']);
    assert.equal(fcm.envois[0].push.titre, 'Sauvegardes : à vérifier');
    assert.match(fcm.envois[0].push.corps, /2 j 12 h : trop ancienne/);
    assert.equal(fcm.envois[0].push.donnees.statut, 'perimee');
  } finally {
    journal.forEach((j) => j.mock.restore());
  }
});

test('contrôle de bout en bout : tout va bien = silence en semaine, « tout va bien » le dimanche', async () => {
  const journal = [mock.method(logger, 'info', () => {}), mock.method(logger, 'error', () => {})];
  try {
    await verifierSauvegardes({ google: googleAvec(21, LUNDI), prevenir: (p) => prevenirAdmins(db, fcm, p), maintenant: LUNDI });
    assert.equal(fcm.envois.length, 0);

    await verifierSauvegardes({ google: googleAvec(21, DIMANCHE), prevenir: (p) => prevenirAdmins(db, fcm, p), maintenant: DIMANCHE });
    assert.equal(fcm.envois.length, 1);
    assert.equal(fcm.envois[0].push.titre, 'Sauvegardes : tout va bien');
    assert.equal(fcm.envois[0].push.corps, 'Dernière sauvegarde il y a 21 h. Contrôle automatique chaque jour.');
  } finally {
    journal.forEach((j) => j.mock.restore());
  }
});
