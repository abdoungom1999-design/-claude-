import { mock, test } from 'node:test';
import assert from 'node:assert/strict';
import { logger } from 'firebase-functions';
import { LIENS, messageFcm, type EnvoiPush } from '../src/notifications';
import {
  AccesGoogleReel,
  alerte,
  bilanHebdomadaire,
  controlerSauvegardes,
  evaluerFraicheur,
  formaterAge,
  planificationsAbsentes,
  sauvegardesPretes,
  typeDePlanification,
  verifierSauvegardes,
  type AccesGoogle,
  type Planification,
  type ReponseGoogle,
  type Sauvegarde,
} from '../src/sauvegardes';

// 12 octobre 2026 : un lundi. Le 11 est un dimanche.
const LUNDI = new Date('2026-10-12T09:07:00Z');
const DIMANCHE = new Date('2026-10-11T09:07:00Z');
const il_y_a = (heures: number, depuis = LUNDI) => new Date(depuis.getTime() - heures * 3_600_000).toISOString();

const BASE = 'projects/sprint-vtc/databases/(default)';
const FIRESTORE = 'https://firestore.googleapis.com/v1';
const U_PLANIFICATIONS = `${FIRESTORE}/${BASE}/backupSchedules`;
const U_BASE = `${FIRESTORE}/${BASE}`;
const U_SAUVEGARDES = `${FIRESTORE}/projects/sprint-vtc/locations/nam5/backups`;
const U_SAUVEGARDES_TOUS = `${FIRESTORE}/projects/sprint-vtc/locations/-/backups`;

const quotidienne = (extra: Planification = {}): Planification => ({ dailyRecurrence: {}, createTime: il_y_a(200), ...extra });
const hebdomadaire = (extra: Planification = {}): Planification => ({ weeklyRecurrence: { day: 'SUNDAY' }, createTime: il_y_a(200), ...extra });
const sauvegarde = (heures: number, extra: Sauvegarde = {}, depuis = LUNDI): Sauvegarde => ({
  database: BASE,
  snapshotTime: il_y_a(heures, depuis),
  expireTime: il_y_a(-300, depuis),
  state: 'READY',
  ...extra,
});

type Route = { statut?: number; corps?: unknown };

/** Faux Google : réponses par adresse, trace des adresses lues. */
function fauxGoogle(routes: Record<string, Route>) {
  const appels: string[] = [];
  const google: AccesGoogle = {
    async lire(url: string): Promise<ReponseGoogle> {
      appels.push(url);
      const route = routes[url] ?? { statut: 404, corps: { error: { message: `route inconnue : ${url}` } } };
      const corps = route.corps ?? {};
      return { statut: route.statut ?? 200, json: corps, texte: JSON.stringify(corps) };
    },
  };
  return { google, appels };
}

const toutVaBien = (heures: number, depuis = LUNDI): Record<string, Route> => ({
  [U_PLANIFICATIONS]: { corps: { backupSchedules: [quotidienne(), hebdomadaire()] } },
  [U_BASE]: { corps: { locationId: 'nam5' } },
  [U_SAUVEGARDES]: { corps: { backups: [sauvegarde(heures + 24, {}, depuis), sauvegarde(heures, {}, depuis)] } },
});

/** Neutralise le journal pendant un test et garde ce qui y a été écrit. */
function surveillerJournal() {
  const ecrits: { niveau: string; texte: string }[] = [];
  const espions = (['info', 'warn', 'error'] as const).map((niveau) =>
    mock.method(logger, niveau, (texte: string) => {
      ecrits.push({ niveau, texte });
    }),
  );
  return { ecrits, restaurer: () => espions.forEach((e) => e.mock.restore()) };
}

// ---------------------------------------------------------------------
// Briques pures
// ---------------------------------------------------------------------

test('genre d\'une planification, et seules les planifications absentes sont signalées', () => {
  assert.equal(typeDePlanification(quotidienne()), 'quotidienne');
  assert.equal(typeDePlanification(hebdomadaire()), 'hebdomadaire');
  assert.equal(typeDePlanification({ retention: '60s' }), null);
  assert.equal(typeDePlanification(null), null);
  assert.equal(typeDePlanification('x'), null);

  assert.deepEqual(planificationsAbsentes([]), ['quotidienne', 'hebdomadaire']);
  assert.deepEqual(planificationsAbsentes([quotidienne()]), ['hebdomadaire']);
  assert.deepEqual(planificationsAbsentes([hebdomadaire(), quotidienne()]), []);
});

test('sauvegardes prêtes : cette base seulement, ni en cours de création ni indisponibles, la plus récente d\'abord', () => {
  const lues = sauvegardesPretes(
    [
      sauvegarde(30),
      sauvegarde(2, { database: 'projects/sprint-vtc/databases/restauration-essai' }),
      sauvegarde(1, { state: 'CREATING' }),
      sauvegarde(3, { state: 'NOT_AVAILABLE' }),
      sauvegarde(6),
      sauvegarde(60, { state: undefined }),
      { database: BASE, state: 'READY' },
    ],
    BASE,
  );
  assert.deepEqual(
    lues.map((s) => s.snapshotTime),
    [il_y_a(6), il_y_a(30), il_y_a(60), undefined],
  );
});

test('âge lisible', () => {
  assert.equal(formaterAge(0.2), '0 h');
  assert.equal(formaterAge(5.4), '5 h');
  assert.equal(formaterAge(23.6), '1 j 0 h');
  assert.equal(formaterAge(28), '1 j 4 h');
  assert.equal(formaterAge(-3), '0 h');
});

test('verdict : moins de 36 h, c\'est bon ; plus de 36 h, c\'est périmé', () => {
  const planifications = [quotidienne(), hebdomadaire()];
  const bon = evaluerFraicheur({ planifications, sauvegardes: [sauvegarde(35.9)], maintenant: LUNDI });
  assert.equal(bon.statut, 'ok');
  assert.equal(bon.message, 'Dernière sauvegarde il y a 1 j 12 h.');

  const pile = evaluerFraicheur({ planifications, sauvegardes: [sauvegarde(36)], maintenant: LUNDI });
  assert.equal(pile.statut, 'ok');

  const perimee = evaluerFraicheur({ planifications, sauvegardes: [sauvegarde(36.1)], maintenant: LUNDI });
  assert.equal(perimee.statut, 'perimee');
  assert.match(perimee.message, /1 j 12 h : trop ancienne \(plus de 36 h\)/);
});

test('verdict : une date illisible n\'est jamais prise pour une sauvegarde récente', () => {
  const v = evaluerFraicheur({
    planifications: [quotidienne(), hebdomadaire()],
    sauvegardes: [{ database: BASE, snapshotTime: 'pas une date', state: 'READY' }],
    maintenant: LUNDI,
  });
  assert.equal(v.statut, 'perimee');
  assert.match(v.message, /illisible/);
});

test('verdict : aucune sauvegarde juste après la création des planifications = on attend ; plus tard = problème', () => {
  const jeunes = [quotidienne({ createTime: il_y_a(3) }), hebdomadaire({ createTime: il_y_a(3) })];
  assert.equal(evaluerFraicheur({ planifications: jeunes, sauvegardes: [], maintenant: LUNDI }).statut, 'attente');

  const vieilles = [quotidienne({ createTime: il_y_a(40) }), hebdomadaire({ createTime: il_y_a(40) })];
  const absente = evaluerFraicheur({ planifications: vieilles, sauvegardes: [], maintenant: LUNDI });
  assert.equal(absente.statut, 'absente');
  assert.match(absente.message, /Aucune sauvegarde alors que les planifications existent depuis plus de 36 h/);

  // Dates de création illisibles : jamais de « on attend » à tort.
  const sansDate = [{ dailyRecurrence: {} }, { weeklyRecurrence: {} }];
  assert.equal(evaluerFraicheur({ planifications: sansDate, sauvegardes: [], maintenant: LUNDI }).statut, 'absente');
});

test('verdict : une planification manquante passe avant tout, même avec une sauvegarde récente', () => {
  const v = evaluerFraicheur({ planifications: [quotidienne()], sauvegardes: [sauvegarde(2)], maintenant: LUNDI });
  assert.equal(v.statut, 'planification-absente');
  assert.equal(v.message, 'Planification absente : hebdomadaire.');
});

// ---------------------------------------------------------------------
// Lecture chez Google
// ---------------------------------------------------------------------

test('contrôle : les trois lectures, dans l\'ordre, et le verdict de la dernière sauvegarde', async () => {
  const { google, appels } = fauxGoogle(toutVaBien(21));
  const v = await controlerSauvegardes(google, LUNDI);
  assert.equal(v.statut, 'ok');
  assert.equal(v.message, 'Dernière sauvegarde il y a 21 h.');
  assert.deepEqual(appels, [U_PLANIFICATIONS, U_BASE, U_SAUVEGARDES]);
});

test('contrôle : une sauvegarde d\'une autre base ne compte pas', async () => {
  const routes = toutVaBien(21);
  routes[U_SAUVEGARDES] = { corps: { backups: [sauvegarde(1, { database: 'projects/sprint-vtc/databases/autre' })] } };
  const { google } = fauxGoogle(routes);
  const v = await controlerSauvegardes(google, LUNDI);
  assert.equal(v.statut, 'absente');
});

test('contrôle : emplacement de la base illisible = on cherche dans tous les emplacements', async () => {
  const routes = toutVaBien(4);
  routes[U_BASE] = { statut: 403, corps: { error: { message: 'refusé' } } };
  routes[U_SAUVEGARDES_TOUS] = { corps: { backups: [sauvegarde(4)] } };
  const { google, appels } = fauxGoogle(routes);
  const v = await controlerSauvegardes(google, LUNDI);
  assert.equal(v.statut, 'ok');
  assert.equal(appels.at(-1), U_SAUVEGARDES_TOUS);
});

test('contrôle : un refus de Google (rôles manquants) est « illisible », jamais un faux « tout va bien »', async () => {
  const refus = fauxGoogle({
    [U_PLANIFICATIONS]: { statut: 403, corps: { error: { message: 'Permission denied on resource' } } },
  });
  const v = await controlerSauvegardes(refus.google, LUNDI);
  assert.equal(v.statut, 'illisible');
  assert.match(v.message, /Lecture des planifications impossible \(HTTP 403\) : Permission denied on resource/);
  assert.deepEqual(refus.appels, [U_PLANIFICATIONS], 'rien d\'autre n\'est lu');

  const routes = toutVaBien(4);
  routes[U_SAUVEGARDES] = { statut: 500, corps: { error: { message: 'panne' } } };
  const panne = await controlerSauvegardes(fauxGoogle(routes).google, LUNDI);
  assert.equal(panne.statut, 'illisible');
  assert.match(panne.message, /Lecture des sauvegardes impossible \(HTTP 500\) : panne/);
});

test('contrôle : Google injoignable (pas de code HTTP) est dit tel quel', async () => {
  const google: AccesGoogle = { lire: async () => ({ statut: 0, json: null, texte: 'Google injoignable : fetch failed' }) };
  const v = await controlerSauvegardes(google, LUNDI);
  assert.equal(v.statut, 'illisible');
  assert.equal(v.message, 'Lecture des planifications impossible : Google injoignable : fetch failed');
});

test('contrôle : un emplacement injoignable est journalisé sans changer le verdict', async () => {
  const journal = surveillerJournal();
  try {
    const routes = toutVaBien(4);
    routes[U_SAUVEGARDES] = { corps: { backups: [sauvegarde(4)], unreachable: ['projects/sprint-vtc/locations/eur3'] } };
    const v = await controlerSauvegardes(fauxGoogle(routes).google, LUNDI);
    assert.equal(v.statut, 'ok');
    assert.ok(journal.ecrits.some((e) => e.niveau === 'warn' && /injoignable/.test(e.texte)));
  } finally {
    journal.restaurer();
  }
});

// ---------------------------------------------------------------------
// Accès réel (jeton, essais)
// ---------------------------------------------------------------------

function scenario(reponses: (Response | Error)[]) {
  const appels: { url: string; autorisation: string | undefined }[] = [];
  const fetcher = (async (url: string | URL | Request, init?: RequestInit) => {
    appels.push({ url: String(url), autorisation: (init?.headers as Record<string, string> | undefined)?.authorization });
    const suivante = reponses.shift() ?? new Response('{}', { status: 200 });
    if (suivante instanceof Error) throw suivante;
    return suivante;
  }) as typeof fetch;
  const pauses: number[] = [];
  const pause = async (ms: number) => {
    pauses.push(ms);
  };
  return { appels, fetcher, pauses, pause };
}
const reponse = (statut: number, corps: unknown = {}) => new Response(JSON.stringify(corps), { status: statut });
const JETON = 'jeton-de-test-ne-jamais-afficher';

test('accès réel : le jeton du compte des fonctions part en en-tête, la réponse JSON est rendue', async () => {
  const s = scenario([reponse(200, { backups: [] })]);
  const acces = new AccesGoogleReel(async () => JETON, s.fetcher, s.pause);
  const r = await acces.lire(U_SAUVEGARDES);
  assert.equal(r.statut, 200);
  assert.deepEqual(r.json, { backups: [] });
  assert.deepEqual(s.appels, [{ url: U_SAUVEGARDES, autorisation: `Bearer ${JETON}` }]);
  assert.deepEqual(s.pauses, []);
});

test('accès réel : panne passagère (503, 429, réseau) réessayée, avec 1 s puis 2 s d\'attente', async () => {
  const s = scenario([reponse(503), new Error('fetch failed'), reponse(200, { ok: true })]);
  const r = await new AccesGoogleReel(async () => JETON, s.fetcher, s.pause).lire(U_BASE);
  assert.equal(r.statut, 200);
  assert.equal(s.appels.length, 3);
  assert.deepEqual(s.pauses, [1000, 2000]);

  const limite = scenario([reponse(429), reponse(200, {})]);
  assert.equal((await new AccesGoogleReel(async () => JETON, limite.fetcher, limite.pause).lire(U_BASE)).statut, 200);
});

test('accès réel : trois échecs de suite = on rend le dernier, sans insister', async () => {
  const s = scenario([reponse(503), reponse(500), reponse(502, { error: { message: 'bad gateway' } })]);
  const r = await new AccesGoogleReel(async () => JETON, s.fetcher, s.pause).lire(U_BASE);
  assert.equal(r.statut, 502);
  assert.equal(s.appels.length, 3);

  const reseau = scenario([new Error('a'), new Error('b'), new Error('fetch failed')]);
  const panne = await new AccesGoogleReel(async () => JETON, reseau.fetcher, reseau.pause).lire(U_BASE);
  assert.equal(panne.statut, 0);
  assert.equal(panne.texte, 'Google injoignable : fetch failed');
});

test('accès réel : un refus (403, 404) est définitif, un seul appel', async () => {
  for (const statut of [401, 403, 404]) {
    const s = scenario([reponse(statut, { error: { message: 'non' } }), reponse(200)]);
    const r = await new AccesGoogleReel(async () => JETON, s.fetcher, s.pause).lire(U_BASE);
    assert.equal(r.statut, statut);
    assert.equal(s.appels.length, 1, `HTTP ${statut}`);
  }
});

test('accès réel : jeton indisponible = « statut 0 » et le jeton ne sert à rien d\'autre', async () => {
  const s = scenario([]);
  const acces = new AccesGoogleReel(
    async () => {
      throw new Error('metadata server injoignable');
    },
    s.fetcher,
    s.pause,
  );
  const r = await acces.lire(U_BASE);
  assert.equal(r.statut, 0);
  assert.equal(r.texte, 'Jeton Google indisponible : metadata server injoignable');
  assert.equal(s.appels.length, 0);
  assert.equal(JSON.stringify(r).includes(JETON), false);
});

// ---------------------------------------------------------------------
// Prévenir
// ---------------------------------------------------------------------

test('notifications : alerte et bilan hebdomadaire passent par le canal des Admin, texte court, lien vers l\'espace Admin', () => {
  const v = evaluerFraicheur({ planifications: [quotidienne(), hebdomadaire()], sauvegardes: [sauvegarde(60)], maintenant: LUNDI });
  const a = alerte(v);
  assert.equal(a.titre, 'Sauvegardes : à vérifier');
  assert.equal(a.corps, 'La dernière sauvegarde a 2 j 12 h : trop ancienne (plus de 36 h). Voir Google Cloud > Firestore > Sauvegardes.');
  assert.deepEqual(a.donnees, { type: 'sauvegardes', statut: 'perimee' });
  assert.equal(a.lien, LIENS.admin);
  assert.equal(LIENS.admin, '/#/admin');

  const ok = evaluerFraicheur({ planifications: [quotidienne(), hebdomadaire()], sauvegardes: [sauvegarde(5)], maintenant: LUNDI });
  const b = bilanHebdomadaire(ok);
  assert.equal(b.titre, 'Sauvegardes : tout va bien');
  assert.equal(b.corps, 'Dernière sauvegarde il y a 5 h. Contrôle automatique chaque jour.');
  assert.deepEqual(b.donnees, { type: 'sauvegardes', statut: 'ok' });

  // Message FCM valide (données en chaînes, lien absolu pour le site).
  for (const push of [a, b]) {
    const m = messageFcm(['jeton'], push);
    assert.ok(Object.values(m.data ?? {}).every((valeur) => typeof valeur === 'string'));
    assert.equal(m.webpush?.fcmOptions?.link, 'https://sprint-vtc.web.app/#/admin');
  }
});

function dependances(routes: Record<string, Route>, maintenant: Date, remis = 1) {
  const envoyes: EnvoiPush[] = [];
  return {
    envoyes,
    dep: {
      google: fauxGoogle(routes).google,
      prevenir: async (push: EnvoiPush) => {
        envoyes.push(push);
        return remis;
      },
      maintenant,
    },
  };
}

test('contrôle complet : tout va bien un jour de semaine = silence (journal seulement)', async () => {
  const journal = surveillerJournal();
  try {
    const { dep, envoyes } = dependances(toutVaBien(21), LUNDI);
    const v = await verifierSauvegardes(dep);
    assert.equal(v.statut, 'ok');
    assert.deepEqual(envoyes, []);
    assert.ok(journal.ecrits.some((e) => e.niveau === 'info' && /il y a 21 h/.test(e.texte)));
    assert.equal(journal.ecrits.some((e) => e.niveau === 'error'), false);
  } finally {
    journal.restaurer();
  }
});

test('contrôle complet : tout va bien un dimanche = le « tout va bien » de la semaine', async () => {
  const journal = surveillerJournal();
  try {
    const { dep, envoyes } = dependances(toutVaBien(21, DIMANCHE), DIMANCHE);
    await verifierSauvegardes(dep);
    assert.equal(envoyes.length, 1);
    assert.equal(envoyes[0].titre, 'Sauvegardes : tout va bien');
  } finally {
    journal.restaurer();
  }
});

test('contrôle complet : sauvegarde périmée, planification absente ou lecture refusée = alerte aux Admin et erreur au journal', async () => {
  const journal = surveillerJournal();
  try {
    const periodes = toutVaBien(60);
    const perimee = dependances(periodes, LUNDI);
    assert.equal((await verifierSauvegardes(perimee.dep)).statut, 'perimee');
    assert.equal(perimee.envoyes.length, 1);
    assert.equal(perimee.envoyes[0].titre, 'Sauvegardes : à vérifier');

    const sansPlanification = toutVaBien(4);
    sansPlanification[U_PLANIFICATIONS] = { corps: { backupSchedules: [quotidienne()] } };
    const manquante = dependances(sansPlanification, LUNDI);
    assert.equal((await verifierSauvegardes(manquante.dep)).statut, 'planification-absente');
    assert.match(manquante.envoyes[0].corps, /Planification absente : hebdomadaire/);

    const refus = dependances({ [U_PLANIFICATIONS]: { statut: 403, corps: { error: { message: 'Permission denied' } } } }, LUNDI);
    assert.equal((await verifierSauvegardes(refus.dep)).statut, 'illisible');
    assert.match(refus.envoyes[0].corps, /HTTP 403/);

    assert.equal(journal.ecrits.filter((e) => e.niveau === 'error').length, 3);
  } finally {
    journal.restaurer();
  }
});

test('contrôle complet : première sauvegarde attendue = pas d\'alerte', async () => {
  const journal = surveillerJournal();
  try {
    const jeunes = {
      [U_PLANIFICATIONS]: { corps: { backupSchedules: [quotidienne({ createTime: il_y_a(3) }), hebdomadaire({ createTime: il_y_a(3) })] } },
      [U_BASE]: { corps: { locationId: 'nam5' } },
      [U_SAUVEGARDES]: { corps: {} },
    };
    const { dep, envoyes } = dependances(jeunes, LUNDI);
    assert.equal((await verifierSauvegardes(dep)).statut, 'attente');
    assert.deepEqual(envoyes, []);
  } finally {
    journal.restaurer();
  }
});

test('contrôle complet : alerte qui n\'atteint aucun téléphone = dit au journal que personne n\'a été prévenu', async () => {
  const journal = surveillerJournal();
  try {
    const { dep } = dependances(toutVaBien(60), LUNDI, 0);
    await verifierSauvegardes(dep);
    assert.ok(journal.ecrits.some((e) => e.niveau === 'error' && /non remise : aucun appareil Admin/.test(e.texte)));
  } finally {
    journal.restaurer();
  }
});
