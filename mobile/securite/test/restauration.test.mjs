import { test, mock } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { BASE_DE_DONNEES, DROITS_RESTAURATION } from '../sauvegardes.mjs';
import {
  collectionsDesRegles,
  comparerComptages,
  compterDocuments,
  idBaseEssai,
  principal,
  restaurer,
  supprimerBaseEssai,
  verifierBaseEssai,
} from '../restauration.mjs';

const FIRESTORE = 'https://firestore.googleapis.com/v1';
const JETON = 'jeton-de-test-ne-jamais-afficher';
const RUN = '4242';
const ID_ESSAI = `restauration-essai-${RUN}`;
const SAUVEGARDE = {
  name: 'projects/sprint-vtc/locations/nam5/backups/b1',
  database: BASE_DE_DONNEES,
  snapshotTime: '2026-10-09T15:24:08.043109Z',
  expireTime: '2026-10-23T15:24:08.043109Z',
  state: 'READY',
};
const URL_DROITS = 'https://cloudresourcemanager.googleapis.com/v1/projects/sprint-vtc:testIamPermissions';
const URL_EN_LIGNE = `${FIRESTORE}/${BASE_DE_DONNEES}`;
const URL_ESSAI = `${FIRESTORE}/projects/sprint-vtc/databases/${ID_ESSAI}`;
const URL_SAUVEGARDES = `${FIRESTORE}/projects/sprint-vtc/locations/nam5/backups`;
const URL_RESTAURER = `${FIRESTORE}/projects/sprint-vtc/databases:restore`;
const OPERATION = `projects/sprint-vtc/databases/${ID_ESSAI}/operations/op1`;
const URL_OPERATION = `${FIRESTORE}/${OPERATION}`;
const REGLES = `
  service cloud.firestore {
    match /databases/{database}/documents {
      match /users/{uid} {}
      match /courses/{courseId} { match /prive/{docId} {} }
      match /appareils/{uid}/jetons/{jeton} {}
    }
  }`;

/**
 * Faux Google : une route par « METHODE adresse », objet ou fonction (corps, n° d'appel) ;
 * une liste est une suite de réponses (la dernière se répète). Trace de tous les appels.
 */
function fauxGoogle(routes) {
  const appels = [];
  const compteurs = {};
  const fetcher = async (url, options = {}) => {
    const methode = options.method ?? 'GET';
    const cle = `${methode} ${url}`;
    const corps = options.body ? JSON.parse(options.body) : undefined;
    appels.push({ methode, url, corps });
    compteurs[cle] = (compteurs[cle] ?? 0) + 1;
    let route = routes[cle];
    if (Array.isArray(route)) route = route[Math.min(compteurs[cle], route.length) - 1];
    if (typeof route === 'function') route = route(corps, compteurs[cle]);
    const reponse = route ?? { statut: 404, corps: { error: { message: `route inconnue : ${cle}` } } };
    return new Response(JSON.stringify(reponse.corps ?? {}), { status: reponse.statut ?? 200 });
  };
  return { fetcher, appels };
}

const droitsAccordes = (accordes = DROITS_RESTAURATION.map(([d]) => d)) => (corps) => ({
  corps: { permissions: corps.permissions.filter((p) => accordes.includes(p)) },
});

/** Comptages : { users: 3 } ; une collection absente de la table compte 0 (champ omis par Google). */
const comptages = (table) => (corps) => {
  const nom = corps.structuredAggregationQuery.structuredQuery.from[0].collectionId;
  const n = table[nom];
  return { corps: [{ result: { aggregateFields: n === undefined || n === 0 ? {} : { n: { integerValue: String(n) } } }, readTime: 'x' }] };
};

const racines = (noms) => ({ corps: { collectionIds: noms } });

/** Routes d'un essai qui se passe bien : 3 utilisateurs sauvegardés, 5 en ligne depuis (le journal Admin en compte 1 en ligne). */
function routesEssai({ restauree = { users: 3, courses: 2, chats: 4, jetons: 6, journal_admin: 1 }, enLigne = { users: 5, courses: 2, chats: 4, jetons: 7 }, extra = {} } = {}) {
  return {
    [`POST ${URL_DROITS}`]: droitsAccordes(),
    [`GET ${URL_EN_LIGNE}`]: { corps: { locationId: 'nam5' } },
    [`GET ${URL_SAUVEGARDES}`]: { corps: { backups: [SAUVEGARDE] } },
    [`GET ${URL_ESSAI}`]: { statut: 404, corps: { error: { message: 'not found' } } },
    [`POST ${URL_RESTAURER}`]: { corps: { name: OPERATION } },
    [`GET ${URL_OPERATION}`]: [{ corps: { name: OPERATION, done: false } }, { corps: { name: OPERATION, done: true, response: {} } }],
    [`POST ${URL_ESSAI}/documents:listCollectionIds`]: racines(['users', 'courses', 'chats']),
    [`POST ${URL_EN_LIGNE}/documents:listCollectionIds`]: racines(['users', 'courses', 'chats', 'journal_admin']),
    [`POST ${URL_ESSAI}/documents:runAggregationQuery`]: comptages(restauree),
    [`POST ${URL_EN_LIGNE}/documents:runAggregationQuery`]: comptages({ ...enLigne, journal_admin: 1 }),
    ...extra,
  };
}

async function lancer(argv, routes, { env = {}, regles = REGLES } = {}) {
  const { fetcher, appels } = fauxGoogle(routes);
  const sortie = [];
  const pauses = [];
  const journal = mock.method(console, 'log', (...morceaux) => sortie.push(morceaux.join(' ')));
  const erreurs = mock.method(console, 'error', (...morceaux) => sortie.push(morceaux.join(' ')));
  try {
    const code = await principal(argv, {
      fetcher,
      env: { JETON_GOOGLE: JETON, GITHUB_RUN_ID: RUN, ...env },
      pause: async (ms) => {
        pauses.push(ms);
      },
      lireRegles: () => regles,
    });
    return { code, sortie: sortie.join('\n'), appels, pauses };
  } finally {
    journal.mock.restore();
    erreurs.mock.restore();
  }
}

// ---------------------------------------------------------------------
// Garde-fous
// ---------------------------------------------------------------------

test('la base d\'essai porte le numéro du run, et rien d\'autre n\'est accepté', () => {
  assert.equal(idBaseEssai({ GITHUB_RUN_ID: '38060001234' }), 'restauration-essai-38060001234');
  assert.throws(() => idBaseEssai({}), /GITHUB_RUN_ID/);
  assert.throws(() => idBaseEssai({ GITHUB_RUN_ID: '12a' }), /GITHUB_RUN_ID/);

  assert.equal(verifierBaseEssai('restauration-essai-1'), 'restauration-essai-1');
  for (const interdit of ['(default)', 'default', '', 'restauration-essai-', 'restauration-essai-abc', 'autre-123', 'restauration-essai-12/../..', ' restauration-essai-12', 'restauration-essai-12 ', undefined, null]) {
    assert.throws(() => verifierBaseEssai(interdit), /n'est pas une base d'essai/, String(interdit));
  }
});

test('collections lues dans les règles : racines et sous-collections, sans databases ni documents', () => {
  assert.deepEqual(collectionsDesRegles(REGLES), ['appareils', 'courses', 'jetons', 'prive', 'users']);
  assert.deepEqual(collectionsDesRegles(''), []);
});

test('comparaison : écarts normaux, collection vide suspecte, base vide non concluante', () => {
  const ok = comparerComptages({ users: 3, courses: 2, chats: 4 }, { users: 5, courses: 2, chats: 1 });
  assert.equal(ok.verdict, 'ok');
  assert.deepEqual(
    ok.lignes.map((l) => [l.nom, l.restauree, l.enLigne, l.ecart, l.statut]),
    [
      ['chats', 4, 1, -3, 'moins-en-ligne'],
      ['courses', 2, 2, 0, 'identique'],
      ['users', 3, 5, 2, 'plus-en-ligne'],
    ],
  );
  assert.equal(ok.totalRestauree, 9);
  assert.equal(ok.totalEnLigne, 8);

  const suspect = comparerComptages({ users: 3 }, { users: 3, courses: 10 });
  assert.equal(suspect.verdict, 'suspect');
  assert.equal(suspect.lignes.find((l) => l.nom === 'courses').statut, 'vide');

  assert.equal(comparerComptages({}, {}).verdict, 'inconcluant');
  assert.equal(comparerComptages({ users: 0 }, { users: 0 }).verdict, 'inconcluant');
  // Rien en ligne mais des documents restaurés : pas suspect (l'inverse du cas précédent).
  assert.equal(comparerComptages({ users: 2 }, {}).verdict, 'ok');
});

// ---------------------------------------------------------------------
// Appels Google
// ---------------------------------------------------------------------

test('comptage : requête de comptage seule, valeur lue en texte, zéro omis par Google', async () => {
  const { fetcher, appels } = fauxGoogle({ [`POST ${URL_ESSAI}/documents:runAggregationQuery`]: comptages({ users: 12 }) });
  assert.deepEqual(await compterDocuments(fetcher, JETON, ID_ESSAI, 'users'), { n: 12 });
  assert.deepEqual(await compterDocuments(fetcher, JETON, ID_ESSAI, 'vide'), { n: 0 });
  assert.deepEqual(appels[0].corps, {
    structuredAggregationQuery: {
      structuredQuery: { from: [{ collectionId: 'users', allDescendants: true }] },
      aggregations: [{ alias: 'n', count: {} }],
    },
  });

  const refus = fauxGoogle({ [`POST ${URL_ESSAI}/documents:runAggregationQuery`]: { statut: 403, corps: { error: { message: 'Permission denied' } } } });
  const r = await compterDocuments(refus.fetcher, JETON, ID_ESSAI, 'users');
  assert.match(r.erreur, /Comptage de « users » dans restauration-essai-4242 impossible \(HTTP 403\) : Permission denied/);
});

test('restauration : demande la sauvegarde choisie dans la base d\'essai, attend la fin de l\'opération', async () => {
  const { fetcher, appels } = fauxGoogle(routesEssai());
  const pauses = [];
  const r = await restaurer(fetcher, JETON, ID_ESSAI, SAUVEGARDE, async (ms) => pauses.push(ms));
  assert.deepEqual(r, { fini: true });
  assert.deepEqual(appels[0], { methode: 'POST', url: URL_RESTAURER, corps: { databaseId: ID_ESSAI, backup: SAUVEGARDE.name } });
  assert.equal(appels.filter((a) => a.url === URL_OPERATION).length, 2);
  assert.deepEqual(pauses, [15000], 'une attente entre les deux lectures');
});

test('restauration : refus de Google, opération en erreur ou jamais finie = erreur claire, jamais de base en ligne', async () => {
  const refus = fauxGoogle({ [`POST ${URL_RESTAURER}`]: { statut: 403, corps: { error: { message: 'Permission denied' } } } });
  assert.match((await restaurer(refus.fetcher, JETON, ID_ESSAI, SAUVEGARDE, async () => {})).erreur, /Restauration refusée \(HTTP 403\) : Permission denied/);

  const enErreur = fauxGoogle({
    [`POST ${URL_RESTAURER}`]: { corps: { name: OPERATION } },
    [`GET ${URL_OPERATION}`]: { corps: { done: true, error: { code: 9, message: 'quota dépassé' } } },
  });
  assert.match((await restaurer(enErreur.fetcher, JETON, ID_ESSAI, SAUVEGARDE, async () => {})).erreur, /Google a refusé l'opération : quota dépassé/);

  const sansNom = fauxGoogle({ [`POST ${URL_RESTAURER}`]: { corps: {} } });
  assert.match((await restaurer(sansNom.fetcher, JETON, ID_ESSAI, SAUVEGARDE, async () => {})).erreur, /n'a pas nommé l'opération/);

  const interminable = fauxGoogle({
    [`POST ${URL_RESTAURER}`]: { corps: { name: OPERATION } },
    [`GET ${URL_OPERATION}`]: { corps: { done: false } },
  });
  const pauses = [];
  const r = await restaurer(interminable.fetcher, JETON, ID_ESSAI, SAUVEGARDE, async (ms) => pauses.push(ms));
  assert.match(r.erreur, /pas terminée après 30 minutes/);
  assert.equal(pauses.length, 120);

  // Une base qui n'est pas une base d'essai n'est même pas demandée à Google.
  const { fetcher, appels } = fauxGoogle({});
  await assert.rejects(() => restaurer(fetcher, JETON, '(default)', SAUVEGARDE, async () => {}), /n'est pas une base d'essai/);
  assert.equal(appels.length, 0);
});

test('suppression : la base d\'essai seulement, puis on attend qu\'elle ait disparu', async () => {
  const { fetcher, appels } = fauxGoogle({
    [`GET ${URL_ESSAI}`]: [{ corps: { name: ID_ESSAI } }, { corps: { name: ID_ESSAI } }, { statut: 404 }],
    [`DELETE ${URL_ESSAI}`]: { corps: { name: 'op-suppression' } },
  });
  const pauses = [];
  assert.deepEqual(await supprimerBaseEssai(fetcher, JETON, ID_ESSAI, async (ms) => pauses.push(ms)), { supprimee: true });
  assert.deepEqual(appels.map((a) => a.methode), ['GET', 'DELETE', 'GET', 'GET']);
  assert.ok(appels.every((a) => a.url === URL_ESSAI));
  assert.deepEqual(pauses, [10000, 10000]);
});

test('suppression : déjà absente = rien à faire ; refus ou base qui reste = erreur ; la base en ligne est refusée sans appel', async () => {
  const absente = fauxGoogle({ [`GET ${URL_ESSAI}`]: { statut: 404 } });
  assert.deepEqual(await supprimerBaseEssai(absente.fetcher, JETON, ID_ESSAI, async () => {}), { dejaAbsente: true });
  assert.deepEqual(absente.appels.map((a) => a.methode), ['GET']);

  const refus = fauxGoogle({ [`GET ${URL_ESSAI}`]: { corps: {} }, [`DELETE ${URL_ESSAI}`]: { statut: 403, corps: { error: { message: 'Permission denied' } } } });
  assert.match((await supprimerBaseEssai(refus.fetcher, JETON, ID_ESSAI, async () => {})).erreur, /Suppression de restauration-essai-4242 refusée \(HTTP 403\)/);

  const reste = fauxGoogle({ [`GET ${URL_ESSAI}`]: { corps: {} }, [`DELETE ${URL_ESSAI}`]: { corps: {} } });
  assert.match((await supprimerBaseEssai(reste.fetcher, JETON, ID_ESSAI, async () => {})).erreur, /existe encore 10 minutes après/);

  const aucun = fauxGoogle({});
  for (const interdit of ['(default)', 'default', 'restauration-essai-']) {
    await assert.rejects(() => supprimerBaseEssai(aucun.fetcher, JETON, interdit, async () => {}), /n'est pas une base d'essai/);
  }
  assert.equal(aucun.appels.length, 0);
});

// ---------------------------------------------------------------------
// Commandes
// ---------------------------------------------------------------------

test('essai : droits vérifiés, restauration, comptages des deux bases, tableau, code 0 ; la base en ligne n\'est que lue', async () => {
  const dossier = mkdtempSync(path.join(tmpdir(), 'restauration-'));
  const resume = path.join(dossier, 'resume.md');
  try {
    const r = await lancer(['essai'], routesEssai(), { env: { GITHUB_STEP_SUMMARY: resume } });
    assert.equal(r.code, 0, r.sortie);

    // Ordre : droits, sauvegardes, base d'essai absente, restauration, opération, collections, comptages.
    const sequence = r.appels.map((a) => `${a.methode} ${a.url.replace(FIRESTORE, '').replace('https://cloudresourcemanager.googleapis.com/v1', '')}`);
    assert.equal(sequence.filter((s) => s.endsWith(':testIamPermissions')).length, DROITS_RESTAURATION.length);
    const premierRestore = sequence.indexOf('POST /projects/sprint-vtc/databases:restore');
    assert.ok(premierRestore > sequence.findIndex((s) => s.endsWith('/backups')), 'sauvegardes lues avant la restauration');
    assert.ok(premierRestore > sequence.lastIndexOf('POST /projects/sprint-vtc:testIamPermissions'), 'droits vérifiés avant de créer quoi que ce soit');

    // La base en ligne : lectures seulement.
    const surEnLigne = r.appels.filter((a) => a.url.includes('/databases/(default)'));
    assert.ok(surEnLigne.length > 0);
    for (const a of surEnLigne) {
      const lecture = a.methode === 'GET' || a.url.endsWith('documents:runAggregationQuery') || a.url.endsWith('documents:listCollectionIds');
      assert.ok(lecture, `${a.methode} ${a.url}`);
    }
    assert.equal(r.appels.some((a) => a.methode === 'DELETE' || a.methode === 'PATCH' || a.methode === 'PUT'), false, 'l\'essai ne supprime rien : c\'est l\'étape suivante');

    // Collections comptées : celles des règles + racines trouvées dans les deux bases.
    const comptees = new Set(r.appels.filter((a) => a.corps?.structuredAggregationQuery).map((a) => a.corps.structuredAggregationQuery.structuredQuery.from[0].collectionId));
    assert.deepEqual([...comptees].sort(), ['appareils', 'chats', 'courses', 'jetons', 'journal_admin', 'prive', 'users']);

    assert.match(r.sortie, /Sauvegarde à restaurer : 2026-10-09T15:24:08\.043109Z \(nam5\)/);
    assert.match(r.sortie, /users\s+3\s+5\s+2\s+créés depuis la sauvegarde/);
    assert.match(r.sortie, /TOTAL\s+16\s+19/);
    assert.match(r.sortie, /::notice title=Restauration réussie::16 documents restaurés \(7 collections\)/);
    assert.equal(r.sortie.includes(JETON), false);

    const texte = readFileSync(resume, 'utf8');
    assert.match(texte, /Essai de restauration · RÉUSSI/);
    assert.match(texte, /`restauration-essai-4242`/);
    assert.match(texte, /\| users \| 3 \| 5 \| \+2 \| créés depuis la sauvegarde \|/);
  } finally {
    rmSync(dossier, { recursive: true, force: true });
  }
});

test('essai : un droit manquant (suppression) = rien n\'est créé, code 1', async () => {
  const sansSuppression = DROITS_RESTAURATION.map(([d]) => d).filter((d) => d !== 'datastore.databases.delete');
  const r = await lancer(['essai'], routesEssai({ extra: { [`POST ${URL_DROITS}`]: droitsAccordes(sansSuppression) } }));
  assert.equal(r.code, 1);
  assert.match(r.sortie, /::error title=Droits manquants pour la restauration::.*datastore\.databases\.delete.*Rien n'a été créé/);
  assert.equal(r.appels.some((a) => a.url === URL_RESTAURER), false);
});

test('essai : pas de sauvegarde, base d\'essai déjà là, restauration refusée = code 1 avec la raison', async () => {
  const aucune = await lancer(['essai'], routesEssai({ extra: { [`GET ${URL_SAUVEGARDES}`]: { corps: {} } } }));
  assert.equal(aucune.code, 1);
  assert.match(aucune.sortie, /Aucune sauvegarde à restaurer/);

  const deja = await lancer(['essai'], routesEssai({ extra: { [`GET ${URL_ESSAI}`]: { corps: {} } } }));
  assert.equal(deja.code, 1);
  assert.match(deja.sortie, /restauration-essai-4242 existe déjà/);
  assert.equal(deja.appels.some((a) => a.url === URL_RESTAURER), false);

  const refus = await lancer(['essai'], routesEssai({ extra: { [`POST ${URL_RESTAURER}`]: { statut: 403, corps: { error: { message: 'Permission denied' } } } } }));
  assert.equal(refus.code, 1);
  assert.match(refus.sortie, /::error title=Restauration échouée::Restauration refusée \(HTTP 403\)/);
  assert.equal(refus.appels.some((a) => a.url.endsWith('documents:runAggregationQuery')), false, 'rien n\'est compté');
});

test('essai : une collection vide après restauration = « à regarder », code 1 ; base vide partout = non concluant', async () => {
  const suspect = await lancer(['essai'], routesEssai({ restauree: { users: 3, courses: 0, chats: 4 } }));
  assert.equal(suspect.code, 1);
  assert.match(suspect.sortie, /::error title=Restauration à regarder::.*courses/);
  assert.match(suspect.sortie, /courses\s+0\s+2\s+2\s+VIDE dans la restauration/);

  const vide = await lancer(['essai'], routesEssai({ restauree: {}, enLigne: {} , extra: { [`POST ${URL_EN_LIGNE}/documents:runAggregationQuery`]: comptages({}) } }));
  assert.equal(vide.code, 1);
  assert.match(vide.sortie, /::warning title=Essai non concluant::/);
});

test('essai : un comptage qui échoue est signalé sans faire croire à une base vide', async () => {
  const r = await lancer(
    ['essai'],
    routesEssai({
      extra: {
        [`POST ${URL_ESSAI}/documents:runAggregationQuery`]: (corps) =>
          corps.structuredAggregationQuery.structuredQuery.from[0].collectionId === 'chats'
            ? { statut: 500, corps: { error: { message: 'panne' } } }
            : comptages({ users: 3, courses: 2 })(corps),
      },
    }),
  );
  assert.match(r.sortie, /::warning title=Comptages incomplets::Non comptées : chats \(restaurée\)/);
  // « chats » n'a qu'un comptage (en ligne) : il apparaît comme absent de la restauration, donc signalé « vide ».
  assert.equal(r.code, 1);
});

test('essai : hors GitHub Actions (pas de numéro de run) = refusé', async () => {
  const r = await lancer(['essai'], routesEssai(), { env: { GITHUB_RUN_ID: '' } });
  assert.equal(r.code, 1);
  assert.match(r.sortie, /::error title=Essai de restauration impossible::.*GITHUB_RUN_ID/);
  assert.equal(r.appels.length, 0);
});

test('nettoyer : supprime la base d\'essai de ce run, ou dit qu\'il n\'y a rien à supprimer', async () => {
  const presente = await lancer(['nettoyer'], {
    [`GET ${URL_ESSAI}`]: [{ corps: {} }, { statut: 404 }],
    [`DELETE ${URL_ESSAI}`]: { corps: {} },
  });
  assert.equal(presente.code, 0);
  assert.match(presente.sortie, /La base restauration-essai-4242 est supprimée/);

  const absente = await lancer(['nettoyer'], { [`GET ${URL_ESSAI}`]: { statut: 404 } });
  assert.equal(absente.code, 0);
  assert.match(absente.sortie, /n'existe pas \(rien à supprimer\)/);
});

test('nettoyer : suppression refusée = code 1 et la marche à suivre à la main', async () => {
  const r = await lancer(['nettoyer'], {
    [`GET ${URL_ESSAI}`]: { corps: {} },
    [`DELETE ${URL_ESSAI}`]: { statut: 403, corps: { error: { message: 'Permission denied' } } },
  });
  assert.equal(r.code, 1);
  assert.match(r.sortie, /::error title=Base d'essai non supprimée::.*HTTP 403.*Supprimez-la à la main : Google Cloud > Firestore > Bases de données > restauration-essai-4242/);
});

test('lister : signale les bases d\'essai restées en place, sans rien supprimer', async () => {
  const r = await lancer(['lister'], {
    [`GET ${FIRESTORE}/projects/sprint-vtc/databases`]: {
      corps: { databases: [{ name: 'projects/sprint-vtc/databases/(default)' }, { name: 'projects/sprint-vtc/databases/restauration-essai-17' }] },
    },
  });
  assert.equal(r.code, 0);
  assert.match(r.sortie, /Bases du projet : \(default\), restauration-essai-17\./);
  assert.match(r.sortie, /::warning title=Bases d'essai restées en place::restauration-essai-17\./);
  assert.deepEqual(r.appels.map((a) => a.methode), ['GET']);
});

test('commande inconnue ou jeton absent : code 2, et le jeton n\'est jamais affiché', async () => {
  assert.equal((await lancer(['nimporte'], {})).code, 2);
  assert.equal((await lancer(['essai'], {}, { env: { JETON_GOOGLE: '' } })).code, 2);
  const r = await lancer(['nettoyer'], { [`GET ${URL_ESSAI}`]: { statut: 403, corps: { error: { message: 'refusé' } } } });
  assert.equal(r.code, 1);
  assert.equal(r.sortie.includes(JETON), false);
});
