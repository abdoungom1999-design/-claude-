import { test, mock } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import {
  BASE_DE_DONNEES,
  DROITS_REQUIS,
  DROITS_RESTAURATION,
  PLANIFICATIONS,
  ROLES_FONCTION,
  decrireStatistiques,
  ecartsDeRetention,
  evaluerFraicheur,
  formaterAge,
  planificationsACreer,
  principal,
  resumeMarkdown,
  retentionEnSecondes,
  sauvegardesDeLaBase,
  statistiquesDe,
  typeDePlanification,
  verifierDroits,
} from '../sauvegardes.mjs';

const MAINTENANT = new Date('2026-10-10T07:00:00Z');
const il_y_a = (heures) => new Date(MAINTENANT.getTime() - heures * 3_600_000).toISOString();

const quotidienne = (extra = {}) => ({ name: `${BASE_DE_DONNEES}/backupSchedules/q`, retention: '1209600s', dailyRecurrence: {}, createTime: il_y_a(200), ...extra });
const hebdomadaire = (extra = {}) => ({ name: `${BASE_DE_DONNEES}/backupSchedules/h`, retention: '8467200s', weeklyRecurrence: { day: 'SUNDAY' }, createTime: il_y_a(200), ...extra });
const sauvegarde = (heures, extra = {}) => ({
  name: `projects/sprint-vtc/locations/eur3/backups/b${heures}`,
  database: BASE_DE_DONNEES,
  snapshotTime: il_y_a(heures),
  expireTime: il_y_a(-300),
  state: 'READY',
  stats: { sizeBytes: '2500000', documentCount: '1234' },
  ...extra,
});

/** Faux serveur Google : réponses par « METHODE adresse » ; garde la trace des appels. */
function fauxGoogle(routes) {
  const appels = [];
  const fetcher = async (url, options = {}) => {
    const methode = options.method ?? 'GET';
    const cle = `${methode} ${url}`;
    const corps = options.body ? JSON.parse(options.body) : undefined;
    appels.push({ methode, url, corps, autorisation: options.headers?.authorization });
    // Une route peut être une fonction du corps de la demande (réponse qui dépend de ce qui est demandé).
    const route = typeof routes[cle] === 'function' ? routes[cle](corps) : routes[cle];
    const reponse = route ?? { statut: 404, corps: { error: { message: `route inconnue : ${cle}` } } };
    return new Response(JSON.stringify(reponse.corps ?? {}), { status: reponse.statut ?? 200 });
  };
  return { fetcher, appels };
}

const FIRESTORE = 'https://firestore.googleapis.com/v1';
const URL_PLANIFICATIONS = `${FIRESTORE}/${BASE_DE_DONNEES}/backupSchedules`;
const URL_BASE = `${FIRESTORE}/${BASE_DE_DONNEES}`;
const URL_SAUVEGARDES = `${FIRESTORE}/projects/sprint-vtc/locations/eur3/backups`;
const URL_DROITS = 'https://cloudresourcemanager.googleapis.com/v1/projects/sprint-vtc:testIamPermissions';
const JETON = 'jeton-de-test-ne-jamais-afficher';

/** Exécute une commande en capturant ce qu'elle affiche. */
async function lancer(argv, routes, { env = {}, maintenant = MAINTENANT } = {}) {
  const { fetcher, appels } = fauxGoogle(routes);
  const sortie = [];
  const journal = mock.method(console, 'log', (...morceaux) => sortie.push(morceaux.join(' ')));
  const erreurs = mock.method(console, 'error', (...morceaux) => sortie.push(morceaux.join(' ')));
  try {
    const code = await principal(argv, { fetcher, env: { JETON_GOOGLE: JETON, ...env }, maintenant });
    return { code, sortie: sortie.join('\n'), appels };
  } finally {
    journal.mock.restore();
    erreurs.mock.restore();
  }
}

test('les deux planifications voulues : une par jour (14 jours), une par semaine (14 semaines, le dimanche)', () => {
  assert.deepEqual(
    PLANIFICATIONS.map((p) => [p.type, p.retentionSecondes, p.recurrence]),
    [
      ['quotidienne', 1209600, { dailyRecurrence: {} }],
      ['hebdomadaire', 8467200, { weeklyRecurrence: { day: 'SUNDAY' } }],
    ],
  );
  // 14 semaines est le maximum accepté par Firestore.
  assert.equal(8467200, 14 * 7 * 24 * 3600);
});

test('genre d\'une planification et durée de conservation lues dans la réponse de Google', () => {
  assert.equal(typeDePlanification(quotidienne()), 'quotidienne');
  assert.equal(typeDePlanification(hebdomadaire()), 'hebdomadaire');
  assert.equal(typeDePlanification({ retention: '60s' }), null);
  assert.equal(typeDePlanification(null), null);
  assert.equal(retentionEnSecondes('1209600s'), 1209600);
  assert.equal(retentionEnSecondes('3.5s'), 3.5);
  for (const mauvais of ['', '14d', 'abc', undefined, null, '-5s']) assert.ok(Number.isNaN(retentionEnSecondes(mauvais)), String(mauvais));
});

test('seules les planifications absentes sont à créer', () => {
  assert.deepEqual(planificationsACreer([]).map((p) => p.type), ['quotidienne', 'hebdomadaire']);
  assert.deepEqual(planificationsACreer([quotidienne()]).map((p) => p.type), ['hebdomadaire']);
  assert.deepEqual(planificationsACreer([hebdomadaire()]).map((p) => p.type), ['quotidienne']);
  assert.deepEqual(planificationsACreer([quotidienne(), hebdomadaire()]), []);
});

test('une durée de conservation différente est signalée, jamais corrigée', () => {
  assert.deepEqual(ecartsDeRetention([quotidienne(), hebdomadaire()]), []);
  assert.deepEqual(ecartsDeRetention([quotidienne({ retention: '604800s' }), hebdomadaire()]), [
    { type: 'quotidienne', actuelle: '604800s', voulue: '1209600s' },
  ]);
  assert.deepEqual(ecartsDeRetention([]), []);
});

test('seules les sauvegardes prêtes de cette base comptent, la plus récente d\'abord', () => {
  const liste = sauvegardesDeLaBase([
    sauvegarde(50),
    sauvegarde(5),
    sauvegarde(1, { state: 'CREATING' }),
    sauvegarde(2, { database: 'projects/sprint-vtc/databases/autre' }),
    sauvegarde(3, { state: 'NOT_AVAILABLE' }),
    sauvegarde(30),
  ]);
  assert.deepEqual(liste.map((s) => s.name.split('/').pop()), ['b5', 'b30', 'b50']);
});

test('verdict : une sauvegarde de moins de 36 h, c\'est bon', () => {
  const v = evaluerFraicheur({ planifications: [quotidienne(), hebdomadaire()], sauvegardes: [sauvegarde(5)], maintenant: MAINTENANT });
  assert.equal(v.statut, 'ok');
  assert.match(v.message, /il y a 5 h/);
  const limite = evaluerFraicheur({ planifications: [quotidienne(), hebdomadaire()], sauvegardes: [sauvegarde(36)], maintenant: MAINTENANT });
  assert.equal(limite.statut, 'ok');
});

test('verdict : une sauvegarde de plus de 36 h est périmée', () => {
  const v = evaluerFraicheur({ planifications: [quotidienne(), hebdomadaire()], sauvegardes: [sauvegarde(60)], maintenant: MAINTENANT });
  assert.equal(v.statut, 'perimee');
  assert.match(v.message, /2 j 12 h/);
});

test('verdict : une date illisible n\'est jamais prise pour une sauvegarde récente', () => {
  const v = evaluerFraicheur({
    planifications: [quotidienne(), hebdomadaire()],
    sauvegardes: [sauvegarde(1, { snapshotTime: 'pas une date' })],
    maintenant: MAINTENANT,
  });
  assert.equal(v.statut, 'perimee');
  assert.match(v.message, /illisible/);
});

test('verdict : aucune sauvegarde juste après la création des planifications = on attend', () => {
  const planifications = [quotidienne({ createTime: il_y_a(2) }), hebdomadaire({ createTime: il_y_a(2) })];
  const v = evaluerFraicheur({ planifications, sauvegardes: [], maintenant: MAINTENANT });
  assert.equal(v.statut, 'attente');
});

test('verdict : aucune sauvegarde alors que les planifications ont plus de 36 h = problème', () => {
  const v = evaluerFraicheur({ planifications: [quotidienne(), hebdomadaire()], sauvegardes: [], maintenant: MAINTENANT });
  assert.equal(v.statut, 'absente');
  // Dates de création illisibles : on ne présume pas que tout va bien.
  const illisible = evaluerFraicheur({
    planifications: [quotidienne({ createTime: 'x' }), hebdomadaire({ createTime: 'y' })],
    sauvegardes: [],
    maintenant: MAINTENANT,
  });
  assert.equal(illisible.statut, 'absente');
});

test('verdict : une planification manquante passe avant tout', () => {
  const v = evaluerFraicheur({ planifications: [quotidienne()], sauvegardes: [sauvegarde(1)], maintenant: MAINTENANT });
  assert.equal(v.statut, 'planification-absente');
  assert.deepEqual(v.manquantes, ['hebdomadaire']);
});

test('âge lisible', () => {
  assert.equal(formaterAge(0.2), '0 h');
  assert.equal(formaterAge(5), '5 h');
  assert.equal(formaterAge(24), '1 j 0 h');
  assert.equal(formaterAge(60), '2 j 12 h');
});

test('droits : tout accordé, ou la liste exacte de ce qui manque, ou un refus de Google', async () => {
  const tous = fauxGoogle({ [`POST ${URL_DROITS}`]: { corps: { permissions: DROITS_REQUIS } } });
  assert.deepEqual(await verifierDroits(tous.fetcher, JETON), { manquants: [] });
  assert.deepEqual(tous.appels[0].corps, { permissions: DROITS_REQUIS });
  assert.equal(tous.appels[0].autorisation, `Bearer ${JETON}`);

  const partiels = fauxGoogle({ [`POST ${URL_DROITS}`]: { corps: { permissions: ['datastore.backups.list', 'datastore.backups.get'] } } });
  assert.deepEqual((await verifierDroits(partiels.fetcher, JETON)).manquants, [
    'datastore.backupSchedules.create',
    'datastore.backupSchedules.list',
    'datastore.backupSchedules.get',
  ]);

  const aucun = fauxGoogle({ [`POST ${URL_DROITS}`]: { corps: {} } });
  assert.equal((await verifierDroits(aucun.fetcher, JETON)).manquants.length, DROITS_REQUIS.length);

  const refus = fauxGoogle({ [`POST ${URL_DROITS}`]: { statut: 403, corps: { error: { message: 'API désactivée' } } } });
  const bilan = await verifierDroits(refus.fetcher, JETON);
  assert.match(bilan.erreur, /HTTP 403.*API désactivée/);
});

test('commande droits : code 0 si tout est accordé, 1 avec le rôle à ajouter sinon', async () => {
  const ok = await lancer(['droits'], { [`POST ${URL_DROITS}`]: { corps: { permissions: DROITS_REQUIS } } });
  assert.equal(ok.code, 0);
  assert.match(ok.sortie, /5\/5 accordés/);

  const ko = await lancer(['droits'], { [`POST ${URL_DROITS}`]: { corps: { permissions: ['datastore.backups.list'] } } });
  assert.equal(ko.code, 1);
  assert.match(ko.sortie, /::error title=Droits manquants pour les sauvegardes::/);
  assert.match(ko.sortie, /datastore\.backupSchedules\.create/);
  assert.match(ko.sortie, /roles\/datastore\.backupSchedulesAdmin/);
  assert.match(ko.sortie, /roles\/datastore\.backupsViewer/);
});

test('planifier : crée les deux planifications avec les bons paramètres quand aucune n\'existe', async () => {
  const r = await lancer(['planifier'], {
    [`GET ${URL_PLANIFICATIONS}`]: { corps: {} },
    [`POST ${URL_PLANIFICATIONS}`]: { corps: { name: 'x' } },
  });
  assert.equal(r.code, 0);
  const creations = r.appels.filter((a) => a.methode === 'POST');
  assert.deepEqual(creations.map((a) => a.corps), [
    { retention: '1209600s', dailyRecurrence: {} },
    { retention: '8467200s', weeklyRecurrence: { day: 'SUNDAY' } },
  ]);
  assert.match(r.sortie, /Créée : quotidienne/);
  assert.match(r.sortie, /Créée : hebdomadaire/);
});

test('planifier : ne crée que ce qui manque, ne touche à rien d\'existant', async () => {
  const r = await lancer(['planifier'], {
    [`GET ${URL_PLANIFICATIONS}`]: { corps: { backupSchedules: [quotidienne()] } },
    [`POST ${URL_PLANIFICATIONS}`]: { corps: { name: 'x' } },
  });
  assert.equal(r.code, 0);
  assert.deepEqual(r.appels.filter((a) => a.methode === 'POST').map((a) => a.corps), [{ retention: '8467200s', weeklyRecurrence: { day: 'SUNDAY' } }]);
  assert.match(r.sortie, /Déjà en place : quotidienne/);
  assert.equal(r.appels.some((a) => ['PATCH', 'PUT', 'DELETE'].includes(a.methode)), false);
});

test('planifier : tout est en place, rien n\'est écrit ; une durée différente est seulement signalée', async () => {
  const r = await lancer(['planifier'], {
    [`GET ${URL_PLANIFICATIONS}`]: { corps: { backupSchedules: [quotidienne({ retention: '604800s' }), hebdomadaire()] } },
  });
  assert.equal(r.code, 0);
  assert.deepEqual(r.appels.map((a) => a.methode), ['GET']);
  assert.match(r.sortie, /::warning title=Durée de conservation différente::/);
});

test('planifier : un refus de Google (droits) donne code 1 et la marche à suivre', async () => {
  const lecture = await lancer(['planifier'], {
    [`GET ${URL_PLANIFICATIONS}`]: { statut: 403, corps: { error: { message: 'Permission denied' } } },
  });
  assert.equal(lecture.code, 1);
  assert.match(lecture.sortie, /HTTP 403.*Permission denied/);
  assert.match(lecture.sortie, /roles\/datastore\.backupSchedulesAdmin/);

  const creation = await lancer(['planifier'], {
    [`GET ${URL_PLANIFICATIONS}`]: { corps: {} },
    [`POST ${URL_PLANIFICATIONS}`]: { statut: 403, corps: { error: { message: 'Permission denied' } } },
  });
  assert.equal(creation.code, 1);
  assert.match(creation.sortie, /::error title=Planification non créée::/);
});

test('verifier : sauvegarde récente = code 0, résumé écrit pour la page du run', async () => {
  const dossier = mkdtempSync(path.join(tmpdir(), 'sauvegardes-'));
  const resume = path.join(dossier, 'resume.md');
  try {
    const r = await lancer(
      ['verifier'],
      {
        [`GET ${URL_PLANIFICATIONS}`]: { corps: { backupSchedules: [quotidienne(), hebdomadaire()] } },
        [`GET ${URL_BASE}`]: { corps: { locationId: 'eur3' } },
        [`GET ${URL_SAUVEGARDES}`]: { corps: { backups: [sauvegarde(30), sauvegarde(6)] } },
      },
      { env: { GITHUB_STEP_SUMMARY: resume } },
    );
    assert.equal(r.code, 0);
    assert.match(r.sortie, /2 prête\(s\)\. Dernière sauvegarde il y a 6 h/);
    assert.match(r.sortie, /2\.5 Mo\s+1234 documents/);
    const texte = readFileSync(resume, 'utf8');
    assert.match(texte, /Sauvegardes de la base Firestore · OK/);
    assert.match(texte, /\| Instantané \(UTC\)/);
    assert.match(texte, /eur3/);
  } finally {
    rmSync(dossier, { recursive: true, force: true });
  }
});

test('statistiques d\'une sauvegarde : taille en Mo et documents, ou rien tant que Google ne les donne pas', () => {
  assert.deepEqual(statistiquesDe(sauvegarde(1)), { taille: '2.5 Mo', documents: 1234 });
  for (const stats of [undefined, null, {}, { sizeBytes: 'abc' }, { sizeBytes: null, documentCount: '' }, { sizeBytes: -5, documentCount: '-1' }]) {
    assert.deepEqual(statistiquesDe({ stats }), { taille: null, documents: null }, JSON.stringify(stats));
  }
  assert.deepEqual(statistiquesDe(undefined), { taille: null, documents: null });
  assert.deepEqual(statistiquesDe({ stats: { documentCount: '42' } }), { taille: null, documents: 42 });

  assert.equal(decrireStatistiques(sauvegarde(1)), '2.5 Mo  1234 documents');
  assert.equal(decrireStatistiques({}), 'taille et nombre de documents non communiqués par Google');
  assert.equal(decrireStatistiques({ stats: { documentCount: '42' } }), 'taille inconnue  42 documents');
  assert.equal(decrireStatistiques({ stats: { sizeBytes: '1500000' } }), '1.5 Mo  ? documents');
});

test('verifier : sauvegarde prête sans statistiques (Google ne les donne pas encore) = code 0, jamais « NaN »', async () => {
  const dossier = mkdtempSync(path.join(tmpdir(), 'sauvegardes-'));
  const resume = path.join(dossier, 'resume.md');
  try {
    const r = await lancer(
      ['verifier'],
      {
        [`GET ${URL_PLANIFICATIONS}`]: { corps: { backupSchedules: [quotidienne(), hebdomadaire()] } },
        [`GET ${URL_BASE}`]: { corps: { locationId: 'eur3' } },
        // stats absent de la réponse : JSON.stringify écarte la valeur undefined.
        [`GET ${URL_SAUVEGARDES}`]: { corps: { backups: [sauvegarde(21, { stats: undefined })] } },
      },
      { env: { GITHUB_STEP_SUMMARY: resume } },
    );
    assert.equal(r.code, 0);
    assert.match(r.sortie, /1 prête\(s\)\. Dernière sauvegarde il y a 21 h/);
    assert.match(r.sortie, /taille et nombre de documents non communiqués par Google/);
    assert.match(r.sortie, /état READY ; champs reçus : database, expireTime, name, snapshotTime, state\./);
    assert.match(r.sortie, /::notice title=Taille de la sauvegarde non communiquée::/);
    assert.doesNotMatch(r.sortie, /NaN/);

    const texte = readFileSync(resume, 'utf8');
    assert.match(texte, /Sauvegardes de la base Firestore · OK/);
    assert.match(texte, /\| non communiquée \| non communiqué \|/);
    assert.match(texte, /entièrement copiée/);
    assert.doesNotMatch(texte, /NaN/);
  } finally {
    rmSync(dossier, { recursive: true, force: true });
  }
});

test('verifier : avec les statistiques, pas de notice ni de mention « non communiqué »', async () => {
  const r = await lancer(['verifier'], {
    [`GET ${URL_PLANIFICATIONS}`]: { corps: { backupSchedules: [quotidienne(), hebdomadaire()] } },
    [`GET ${URL_BASE}`]: { corps: { locationId: 'eur3' } },
    [`GET ${URL_SAUVEGARDES}`]: { corps: { backups: [sauvegarde(5)] } },
  });
  assert.equal(r.code, 0);
  assert.match(r.sortie, /2\.5 Mo\s+1234 documents/);
  assert.match(r.sortie, /champs reçus : database, expireTime, name, snapshotTime, state, stats\./);
  assert.doesNotMatch(r.sortie, /non communiqu|::notice/);
});

test('verifier : sauvegarde périmée, absente ou planification manquante = code 1 avec une erreur visible', async () => {
  const base = {
    [`GET ${URL_BASE}`]: { corps: { locationId: 'eur3' } },
  };
  const perimee = await lancer(['verifier'], {
    ...base,
    [`GET ${URL_PLANIFICATIONS}`]: { corps: { backupSchedules: [quotidienne(), hebdomadaire()] } },
    [`GET ${URL_SAUVEGARDES}`]: { corps: { backups: [sauvegarde(80)] } },
  });
  assert.equal(perimee.code, 1);
  assert.match(perimee.sortie, /::error title=Sauvegardes Firestore à vérifier::/);

  const absente = await lancer(['verifier'], {
    ...base,
    [`GET ${URL_PLANIFICATIONS}`]: { corps: { backupSchedules: [quotidienne(), hebdomadaire()] } },
    [`GET ${URL_SAUVEGARDES}`]: { corps: {} },
  });
  assert.equal(absente.code, 1);

  const sansPlanification = await lancer(['verifier'], {
    ...base,
    [`GET ${URL_PLANIFICATIONS}`]: { corps: {} },
    [`GET ${URL_SAUVEGARDES}`]: { corps: { backups: [sauvegarde(2)] } },
  });
  assert.equal(sansPlanification.code, 1);
  assert.match(sansPlanification.sortie, /Planification absente : quotidienne, hebdomadaire/);
});

test('verifier : première sauvegarde pas encore prise = code 0 avec une simple notice', async () => {
  const jeunes = [quotidienne({ createTime: il_y_a(3) }), hebdomadaire({ createTime: il_y_a(3) })];
  const r = await lancer(['verifier'], {
    [`GET ${URL_PLANIFICATIONS}`]: { corps: { backupSchedules: jeunes } },
    [`GET ${URL_BASE}`]: { corps: { locationId: 'eur3' } },
    [`GET ${URL_SAUVEGARDES}`]: { corps: {} },
  });
  assert.equal(r.code, 0);
  assert.match(r.sortie, /::notice title=Première sauvegarde attendue::/);
});

test('verifier : emplacement de la base inconnu = on cherche dans tous les emplacements', async () => {
  const r = await lancer(['verifier'], {
    [`GET ${URL_PLANIFICATIONS}`]: { corps: { backupSchedules: [quotidienne(), hebdomadaire()] } },
    [`GET ${URL_BASE}`]: { statut: 403, corps: { error: { message: 'refusé' } } },
    [`GET ${FIRESTORE}/projects/sprint-vtc/locations/-/backups`]: { corps: { backups: [sauvegarde(4)] } },
  });
  assert.equal(r.code, 0);
  assert.ok(r.appels.some((a) => a.url.endsWith('/locations/-/backups')));
});

test('verifier : Google injoignable ou refus = code 1, jamais un faux « tout va bien »', async () => {
  const r = await lancer(['verifier'], {
    [`GET ${URL_PLANIFICATIONS}`]: { corps: { backupSchedules: [quotidienne(), hebdomadaire()] } },
    [`GET ${URL_BASE}`]: { corps: { locationId: 'eur3' } },
    [`GET ${URL_SAUVEGARDES}`]: { statut: 500, corps: { error: { message: 'panne' } } },
  });
  assert.equal(r.code, 1);
  assert.match(r.sortie, /HTTP 500/);
});

test('le résumé nomme un problème sans sauvegarde ni planification', () => {
  const evaluation = evaluerFraicheur({ planifications: [], sauvegardes: [], maintenant: MAINTENANT });
  const texte = resumeMarkdown({ planifications: [], sauvegardes: [], evaluation, emplacement: 'eur3' });
  assert.match(texte, /PROBLÈME/);
  assert.match(texte, /quotidienne : ABSENTE/);
  assert.match(texte, /Aucune pour le moment/);
});

const URL_DROITS_PROJET = 'https://cloudresourcemanager.googleapis.com/v1/projects/sprint-vtc:testIamPermissions';
const URL_POLITIQUE = 'https://cloudresourcemanager.googleapis.com/v1/projects/sprint-vtc:getIamPolicy';
const URL_FONCTION = 'https://run.googleapis.com/v2/projects/sprint-vtc/locations/europe-west1/services/surveillercommandes';
const COMPTE_FONCTIONS = '671806634534-compute@developer.gserviceaccount.com';

/** Faux Google pour le diagnostic : le compte de déploiement n'a que les droits listés. */
const routesDiagnostic = ({ accordes = [], roles = [], extra = {} } = {}) => ({
  [`GET ${URL_FONCTION}`]: { corps: { template: { serviceAccount: COMPTE_FONCTIONS } } },
  [`POST ${URL_POLITIQUE}`]: {
    corps: {
      bindings: [
        { role: 'roles/editor', members: [`serviceAccount:${COMPTE_FONCTIONS}`, 'user:autre@example.com'] },
        ...roles.map((role) => ({ role, members: [`serviceAccount:${COMPTE_FONCTIONS}`] })),
        // Une liaison avec condition ne vaut pas un rôle accordé sans condition.
        { role: 'roles/datastore.backupSchedulesViewer', condition: { expression: 'false' }, members: [`serviceAccount:${COMPTE_FONCTIONS}`] },
      ],
    },
  },
  [`POST ${URL_DROITS_PROJET}`]: (corps) => ({ corps: { permissions: corps.permissions.filter((p) => accordes.includes(p)) } }),
  ...extra,
});

test('diagnostic : nomme le compte des fonctions, les rôles qui lui manquent et les droits de restauration absents', async () => {
  const r = await lancer(
    ['diagnostic'],
    routesDiagnostic({
      accordes: ['datastore.databases.list', 'datastore.databases.getMetadata', 'datastore.entities.get'],
      roles: ['roles/datastore.backupsViewer'],
    }),
  );
  assert.equal(r.code, 0);
  assert.match(r.sortie, new RegExp(`lu sur « surveillercommandes », europe-west1\\) : ${COMPTE_FONCTIONS}`));
  assert.match(r.sortie, /Ses rôles sur le projet : roles\/datastore\.backupsViewer, roles\/editor/);
  assert.match(r.sortie, /présent {2}roles\/datastore\.backupsViewer/);
  assert.match(r.sortie, /ABSENT {3}roles\/datastore\.backupSchedulesViewer/);
  assert.match(r.sortie, /accordé {2}datastore\.databases\.list/);
  assert.match(r.sortie, /manquant datastore\.backups\.restoreDatabase \(restaurer une sauvegarde dans une nouvelle base\)/);
  assert.match(r.sortie, /manquant datastore\.databases\.delete/);
  // Une permission testée à la fois, et rien n'est écrit chez Google.
  const tests = r.appels.filter((a) => a.url === URL_DROITS_PROJET);
  assert.equal(tests.length, DROITS_RESTAURATION.length);
  assert.ok(tests.every((a) => a.corps.permissions.length === 1));
  assert.deepEqual(new Set(r.appels.map((a) => a.methode)), new Set(['GET', 'POST']));
  assert.ok(r.appels.filter((a) => a.methode === 'POST').every((a) => a.url === URL_DROITS_PROJET || a.url === URL_POLITIQUE));
  const notice = r.sortie.split('\n').find((ligne) => ligne.startsWith('::notice title=Diagnostic des droits'));
  assert.ok(notice);
  assert.match(notice, /rôles à donner à ce compte : roles\/datastore\.backupSchedulesViewer ;/);
  assert.match(notice, /droits de restauration manquants au compte de déploiement : datastore\.backups\.restoreDatabase, /);
  assert.equal(r.sortie.includes(JETON), false);
});

test('diagnostic : tout est en place = « aucun » partout', async () => {
  const r = await lancer(
    ['diagnostic'],
    routesDiagnostic({ accordes: DROITS_RESTAURATION.map(([droit]) => droit), roles: ROLES_FONCTION }),
  );
  assert.equal(r.code, 0);
  for (const role of ROLES_FONCTION) assert.match(r.sortie, new RegExp(`présent {2}${role.replace('.', '\\.')}`));
  assert.doesNotMatch(r.sortie, /^ {2}(ABSENT|manquant|inconnu)/m);
  assert.match(r.sortie, /rôles à donner à ce compte : aucun ;/);
  assert.match(r.sortie, /droits de restauration manquants au compte de déploiement : aucun$/m);
});

test('diagnostic : lectures refusées ou permission inconnue = dit « illisible » / « inconnu », sans planter', async () => {
  const r = await lancer(['diagnostic'], {
    [`GET ${URL_FONCTION}`]: { statut: 403, corps: { error: { message: 'Permission denied' } } },
    [`POST ${URL_DROITS_PROJET}`]: (corps) =>
      corps.permissions[0] === 'datastore.operations.list'
        ? { statut: 400, corps: { error: { message: 'Permission datastore.operations.list is not valid' } } }
        : { corps: {} },
  });
  assert.equal(r.code, 0);
  assert.match(r.sortie, /Compte qui exécute les Cloud Functions : illisible\. .*HTTP 403.*Permission denied/);
  assert.match(r.sortie, /inconnu {2}datastore\.operations\.list .*HTTP 400/);
  assert.match(r.sortie, /compte des fonctions : illisible ; rôles à donner à ce compte : non vérifiés/);
  assert.doesNotMatch(r.sortie, /undefined|NaN/);

  const sansPolitique = await lancer(['diagnostic'], routesDiagnostic({ extra: { [`POST ${URL_POLITIQUE}`]: { statut: 403, corps: { error: { message: 'refusé' } } } } }));
  assert.equal(sansPolitique.code, 0);
  assert.match(sansPolitique.sortie, /Ses rôles sur le projet : illisibles\. .*HTTP 403/);
  assert.match(sansPolitique.sortie, /rôles à donner à ce compte : non vérifiés/);
});

test('commande inconnue ou jeton absent : code 2, et le jeton n\'est jamais affiché', async () => {
  assert.equal((await lancer(['nimporte'], {})).code, 2);
  assert.equal((await lancer(['verifier'], {}, { env: { JETON_GOOGLE: '' } })).code, 2);

  const r = await lancer(['planifier'], {
    [`GET ${URL_PLANIFICATIONS}`]: { statut: 403, corps: { error: { message: 'refusé' } } },
  });
  assert.equal(r.sortie.includes(JETON), false);
});
