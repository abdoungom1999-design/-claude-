import { mock, test } from 'node:test';
import assert from 'node:assert/strict';
import type { Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { depouillerReponses, LIENS, messageFcm, pousser, SITE, type EnvoiPush, type Messagerie } from '../src/notifications';

const push: EnvoiPush = {
  titre: 'Moussa Diop',
  corps: 'Je suis devant la pharmacie',
  canal: 'messages',
  lien: LIENS.messagesClient,
  donnees: { type: 'message', courseId: 'c1' },
  dureeVieSecondes: 3600,
};

test('message FCM : le texte de la notification est celui du message, pour Android comme pour le site', () => {
  const m = messageFcm(['a', 'b'], push);
  assert.deepEqual(m.tokens, ['a', 'b']);
  assert.deepEqual(m.notification, { title: 'Moussa Diop', body: 'Je suis devant la pharmacie' });
  assert.deepEqual(m.data, { type: 'message', courseId: 'c1' });
});

test('partie Android : priorité haute, canal choisi, durée de vie', () => {
  const { android } = messageFcm(['a'], push);
  assert.equal(android?.priority, 'high');
  assert.equal(android?.ttl, 3600 * 1000);
  assert.equal(android?.notification?.channelId, 'messages');
});

test('partie site (navigateur, iPhone) : lien absolu en https, icône, priorité haute, durée de vie', () => {
  const { webpush } = messageFcm(['a'], push);
  assert.equal(webpush?.fcmOptions?.link, `${SITE}/#/accueil/messages`);
  assert.ok(webpush?.fcmOptions?.link?.startsWith('https://'));
  assert.equal(webpush?.notification?.['icon'], `${SITE}/icons/Icon-192.png`);
  assert.equal(webpush?.headers?.Urgency, 'high');
  assert.equal(webpush?.headers?.TTL, '3600');
});

test('course : durée de vie courte pour la partie site aussi', () => {
  const m = messageFcm(['a'], { ...push, canal: 'courses', lien: LIENS.chauffeur, dureeVieSecondes: 120 });
  assert.equal(m.webpush?.headers?.TTL, '120');
  assert.equal(m.android?.notification?.channelId, 'courses');
  assert.equal(m.webpush?.fcmOptions?.link, `${SITE}/#/conducteur`);
});

test('réponses de Google : jetons morts à supprimer, autres échecs comptés par code, jamais un jeton', () => {
  const jetons = ['jetonVivant', 'jetonMort', 'jetonPanne', 'jetonMalForme', 'jetonSansErreur'];
  const lu = depouillerReponses(jetons, [
    { success: true },
    { success: false, error: { code: 'messaging/registration-token-not-registered' } },
    { success: false, error: { code: 'messaging/internal-error' } },
    { success: false, error: { code: 'messaging/invalid-argument' } },
    { success: false },
  ]);
  assert.equal(lu.envoyes, 1);
  // Seuls les jetons déclarés morts par Google sont à supprimer : une panne passagère n'en fait pas partie.
  assert.deepEqual(lu.invalides, ['jetonMort', 'jetonMalForme']);
  assert.deepEqual(lu.echecs, {
    'messaging/registration-token-not-registered': 1,
    'messaging/internal-error': 1,
    'messaging/invalid-argument': 1,
    inconnu: 1,
  });
  assert.equal(jetons.some((jeton) => JSON.stringify(lu.echecs).includes(jeton)), false);

  assert.deepEqual(depouillerReponses(['a', 'b'], [{ success: true }, { success: true }]), { envoyes: 2, invalides: [], echecs: {} });
});

/** Un Firestore minimal : les jetons de chaque compte, et la liste de ce qui a été supprimé. */
function faussesBases(jetonsParCompte: Record<string, string[]>) {
  const supprimes: string[] = [];
  const db = {
    collection: (chemin: string) => ({
      get: async () => {
        const uid = chemin.split('/')[1];
        return { docs: (jetonsParCompte[uid] ?? []).map((id) => ({ id })) };
      },
    }),
    doc: (chemin: string) => ({
      delete: async () => {
        supprimes.push(chemin);
      },
    }),
  } as unknown as Firestore;
  return { db, supprimes };
}

function surveillerAvertissements() {
  const ecrits: { texte: string; donnees?: unknown }[] = [];
  const espion = mock.method(logger, 'warn', (texte: string, donnees?: unknown) => {
    ecrits.push({ texte, donnees });
  });
  return { ecrits, restaurer: () => espion.mock.restore() };
}

test('envoi : un appareil refusé par Google est supprimé et dit au journal (codes et nombres seulement)', async () => {
  const { db, supprimes } = faussesBases({ admin1: ['jetonVivant', 'jetonMort'] });
  const messagerie: Messagerie = {
    envoyer: async () => ({
      envoyes: 1,
      invalides: ['jetonMort'],
      echecs: { 'messaging/registration-token-not-registered': 1 },
    }),
  };
  const journal = surveillerAvertissements();
  try {
    assert.equal(await pousser(db, messagerie, ['admin1'], push), 1);
  } finally {
    journal.restaurer();
  }
  assert.deepEqual(supprimes, ['appareils/admin1/jetons/jetonMort']);
  assert.equal(journal.ecrits.length, 1);
  assert.match(journal.ecrits[0].texte, /des appareils n'ont pas été atteints/);
  assert.deepEqual(journal.ecrits[0].donnees, {
    appareils: 2,
    envoyes: 1,
    echecs: { 'messaging/registration-token-not-registered': 1 },
    jetonsSupprimes: 1,
  });
  const ecrit = JSON.stringify(journal.ecrits);
  assert.equal(ecrit.includes('jetonVivant') || ecrit.includes('jetonMort') || ecrit.includes('admin1'), false);
});

test('envoi : une panne passagère de Google est dite au journal mais ne supprime aucun appareil', async () => {
  const { db, supprimes } = faussesBases({ admin1: ['jetonA', 'jetonB'] });
  const messagerie: Messagerie = {
    envoyer: async () => ({ envoyes: 1, invalides: [], echecs: { 'messaging/internal-error': 1 } }),
  };
  const journal = surveillerAvertissements();
  try {
    assert.equal(await pousser(db, messagerie, ['admin1'], push), 1);
  } finally {
    journal.restaurer();
  }
  assert.deepEqual(supprimes, []);
  assert.equal(journal.ecrits.length, 1);
});

test('envoi : tout est passé, ou une messagerie sans décompte = rien à dire au journal', async () => {
  const { db } = faussesBases({ admin1: ['jetonA'] });
  const journal = surveillerAvertissements();
  try {
    assert.equal(await pousser(db, { envoyer: async () => ({ envoyes: 1, invalides: [], echecs: {} }) }, ['admin1'], push), 1);
    assert.equal(await pousser(db, { envoyer: async () => ({ envoyes: 1, invalides: [] }) }, ['admin1'], push), 1);
  } finally {
    journal.restaurer();
  }
  assert.deepEqual(journal.ecrits, []);
});
