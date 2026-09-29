// Tests des règles Firestore (../firestore.rules) sur l'émulateur Firestore.
// Lancement : npm install && npm test (Java requis pour l'émulateur).
import { after, before, beforeEach, describe, test } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  addDoc,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
  increment,
  deleteField,
} from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-sprint',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});

after(() => env.cleanup());

const TEL_CLIENT = '+221770000009';
const TEL_CHAUFFEUR = '+221770000001';

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const utilisateurs = {
      admin: { role: 'admin', email: 'admin@test.sn' },
      client: { role: 'client', nom: 'Awa', email: 'client@test.sn', telephone: TEL_CLIENT },
      autreClient: { role: 'client', nom: 'Fatou', email: 'autreClient@test.sn', telephone: '+221770000010' },
      chauffeur: {
        role: 'conducteur', nom: 'Moussa', email: 'chauffeur@test.sn', telephone: TEL_CHAUFFEUR,
        statutValidation: 'valide', estValide: true,
      },
      enAttente: { role: 'conducteur', email: 'enAttente@test.sn', statutValidation: 'en_attente' },
      suspendu: { role: 'conducteur', email: 'suspendu@test.sn', statutValidation: 'valide', statutCompte: 'suspendu' },
      banni: { role: 'conducteur', email: 'banni@test.sn', statutValidation: 'valide', statutCompte: 'banni' },
    };
    for (const [uid, data] of Object.entries(utilisateurs)) {
      await setDoc(doc(db, 'users', uid), data);
    }
    await setDoc(doc(db, 'courses', 'c1'), { clientId: 'client', chauffeurId: null, statut: 'en_attente', prixFcfa: 2000 });
    await setDoc(doc(db, 'profils_publics', 'chauffeur'), { nom: 'Moussa', telephone: TEL_CHAUFFEUR, role: 'conducteur', disponible: true });
  });
});

const en = (uid) => env.authenticatedContext(uid, { email: `${uid}@test.sn` }).firestore();

/**
 * Le chauffeur "chauffeur" a accepté la course "ca" du client "client"
 * (avec sa liaison), dans l'état demandé. Réécrit la course : peut
 * être rappelée dans un test pour la faire évoluer.
 */
async function poserCourseAcceptee(extra = {}, { courseId = 'ca', client = 'client', chauffeur = 'chauffeur' } = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'courses', courseId), {
      clientId: client, chauffeurId: chauffeur, statut: 'acceptee', prixFcfa: 2000, ...extra,
    });
    await setDoc(doc(db, 'liaisons', `${client}_${chauffeur}`), { clientId: client, chauffeurId: chauffeur, courseId });
    await setDoc(doc(db, 'profils_publics', client), { nom: 'Awa Ndiaye', telephone: TEL_CLIENT, role: 'client' });
  });
}
const anonyme = () => env.unauthenticatedContext().firestore();

describe('users (profil privé)', () => {
  test('inscription client avec les champs de base : acceptée', async () => {
    await assertSucceeds(setDoc(doc(en('nouveau'), 'users', 'nouveau'), {
      role: 'client', nom: 'Ali', email: 'nouveau@test.sn', telephone: '+221771111111', statut: 'ACTIF',
    }));
  });

  test('inscription conducteur non validé : acceptée', async () => {
    await assertSucceeds(setDoc(doc(en('nouveau'), 'users', 'nouveau'), {
      role: 'conducteur', nom: 'Ali', email: 'nouveau@test.sn', telephone: '+221771111111',
      vehiculeId: 'Yamaha', plaqueImmatriculation: 'DK-1', statut: 'HORS_LIGNE', estValide: false,
    }));
  });

  test('se créer avec le rôle admin : refusé', async () => {
    await assertFails(setDoc(doc(en('nouveau'), 'users', 'nouveau'), { role: 'admin', email: 'nouveau@test.sn' }));
  });

  test('se créer déjà validé, ou avec un statut de modération : refusé', async () => {
    const base = { role: 'conducteur', email: 'nouveau@test.sn' };
    await assertFails(setDoc(doc(en('nouveau'), 'users', 'nouveau'), { ...base, estValide: true }));
    await assertFails(setDoc(doc(en('nouveau'), 'users', 'nouveau'), { ...base, statutValidation: 'valide' }));
    await assertFails(setDoc(doc(en('nouveau'), 'users', 'nouveau'), { ...base, statutCompte: 'actif' }));
  });

  test('créer le profil de quelqu\'un d\'autre : refusé', async () => {
    await assertFails(setDoc(doc(en('nouveau'), 'users', 'autre'), { role: 'client', email: 'nouveau@test.sn' }));
  });

  test('modifier son nom, son téléphone, envoyer une pièce : accepté', async () => {
    await assertSucceeds(updateDoc(doc(en('client'), 'users', 'client'), { nom: 'Awa D.', telephone: '+221779999999' }));
    await assertSucceeds(updateDoc(doc(en('enAttente'), 'users', 'enAttente'), {
      'documents.permis': 'data:image/jpeg;base64,xx', statutValidation: 'en_attente',
    }));
  });

  test('un chauffeur banni ne peut pas lever sa sanction : refusé', async () => {
    await assertFails(updateDoc(doc(en('banni'), 'users', 'banni'), { statutCompte: 'actif' }));
  });

  test('un chauffeur ne peut pas valider son propre dossier : refusé', async () => {
    await assertFails(updateDoc(doc(en('enAttente'), 'users', 'enAttente'), { statutValidation: 'valide' }));
    await assertFails(updateDoc(doc(en('enAttente'), 'users', 'enAttente'), { estValide: true }));
  });

  test('se promouvoir admin : refusé', async () => {
    await assertFails(updateDoc(doc(en('client'), 'users', 'client'), { role: 'admin' }));
  });

  test('lire le profil privé d\'un autre utilisateur (pièces KYC) : refusé', async () => {
    await assertFails(getDoc(doc(en('client'), 'users', 'chauffeur')));
    await assertFails(getDoc(doc(anonyme(), 'users', 'chauffeur')));
  });

  test('lister les utilisateurs sans être admin : refusé', async () => {
    await assertFails(getDocs(query(collection(en('client'), 'users'), where('role', '==', 'conducteur'))));
  });

  test('l\'ancienne recherche de téléphone non connectée : refusée', async () => {
    await assertFails(getDocs(query(collection(anonyme(), 'users'), where('telephone', '==', TEL_CLIENT))));
  });

  test('admin : lit, liste, valide, suspend et bannit', async () => {
    const db = en('admin');
    await assertSucceeds(getDoc(doc(db, 'users', 'chauffeur')));
    await assertSucceeds(getDocs(query(collection(db, 'users'), where('role', '==', 'conducteur'))));
    await assertSucceeds(updateDoc(doc(db, 'users', 'enAttente'), { statutValidation: 'valide', estValide: true }));
    await assertSucceeds(updateDoc(doc(db, 'users', 'chauffeur'), { statutCompte: 'suspendu' }));
    await assertSucceeds(updateDoc(doc(db, 'users', 'chauffeur'), { statutCompte: 'banni' }));
  });

  test('suppression d\'un compte par son propriétaire : refusée', async () => {
    await assertFails(deleteDoc(doc(en('client'), 'users', 'client')));
  });
});

describe('profils_publics', () => {
  test('publier son propre profil public : accepté', async () => {
    await assertSucceeds(setDoc(doc(en('client'), 'profils_publics', 'client'), { nom: 'Awa', telephone: TEL_CLIENT, role: 'client' }));
  });

  test('se déclarer disponible ou changer de rôle soi-même : refusé', async () => {
    await assertFails(setDoc(doc(en('client'), 'profils_publics', 'client'), { nom: 'Awa', telephone: TEL_CLIENT, role: 'conducteur' }));
    await assertFails(setDoc(doc(en('enAttente'), 'profils_publics', 'enAttente'), { nom: 'X', telephone: '1', role: 'conducteur', disponible: true }));
    await assertFails(updateDoc(doc(en('chauffeur'), 'profils_publics', 'chauffeur'), { disponible: false }));
  });

  test('lire son propre profil : accepté ; non connecté : refusé', async () => {
    await assertSucceeds(getDoc(doc(en('chauffeur'), 'profils_publics', 'chauffeur')));
    await assertFails(getDoc(doc(anonyme(), 'profils_publics', 'chauffeur')));
  });

  test('resynchroniser son profil (merge) sans toucher à "disponible" : accepté', async () => {
    await assertSucceeds(setDoc(doc(en('chauffeur'), 'profils_publics', 'chauffeur'),
      { nom: 'Moussa Diop', telephone: TEL_CHAUFFEUR, role: 'conducteur' }, { merge: true }));
  });

  test('l\'admin règle la disponibilité : accepté', async () => {
    await assertSucceeds(updateDoc(doc(en('admin'), 'profils_publics', 'chauffeur'), { disponible: false }));
  });
});

describe('annuaire_telephones (connexion par téléphone)', () => {
  test('publier sa propre entrée : accepté ; lecture unitaire publique : acceptée', async () => {
    await assertSucceeds(setDoc(doc(en('client'), 'annuaire_telephones', `client_${TEL_CLIENT}`), { uid: 'client', email: 'client@test.sn' }));
    await assertSucceeds(getDoc(doc(anonyme(), 'annuaire_telephones', `client_${TEL_CLIENT}`)));
  });

  test('lister l\'annuaire : refusé', async () => {
    await assertFails(getDocs(collection(anonyme(), 'annuaire_telephones')));
    await assertFails(getDocs(collection(en('client'), 'annuaire_telephones')));
  });

  test('publier une entrée pour un autre numéro, un autre rôle ou un autre email : refusé', async () => {
    const db = en('client');
    await assertFails(setDoc(doc(db, 'annuaire_telephones', 'client_+221700000000'), { uid: 'client', email: 'client@test.sn' }));
    await assertFails(setDoc(doc(db, 'annuaire_telephones', `conducteur_${TEL_CLIENT}`), { uid: 'client', email: 'client@test.sn' }));
    await assertFails(setDoc(doc(db, 'annuaire_telephones', `client_${TEL_CLIENT}`), { uid: 'client', email: 'pirate@test.sn' }));
    await assertFails(setDoc(doc(db, 'annuaire_telephones', `client_${TEL_CLIENT}`), { uid: 'autreClient', email: 'client@test.sn' }));
  });

  test('changement de numéro : nouvelle entrée acceptée, ancienne supprimable par son propriétaire', async () => {
    const ancienne = `client_${TEL_CLIENT}`;
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'annuaire_telephones', ancienne), { uid: 'client', email: 'client@test.sn' }));
    const db = en('client');
    await assertSucceeds(updateDoc(doc(db, 'users', 'client'), { telephone: '+221760000000' }));
    await assertSucceeds(setDoc(doc(db, 'annuaire_telephones', 'client_+221760000000'), { uid: 'client', email: 'client@test.sn' }));
    await assertSucceeds(deleteDoc(doc(db, 'annuaire_telephones', ancienne)));
  });

  test('l\'admin rattrape l\'annuaire des comptes existants : accepté', async () => {
    await assertSucceeds(setDoc(doc(en('admin'), 'annuaire_telephones', `conducteur_${TEL_CHAUFFEUR}`), { uid: 'chauffeur', email: 'chauffeur@test.sn' }));
    await assertFails(setDoc(doc(en('chauffeur'), 'annuaire_telephones', `client_${TEL_CLIENT}`), { uid: 'client', email: 'client@test.sn' }));
  });

  test('écraser ou supprimer l\'entrée de quelqu\'un d\'autre : refusé', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'annuaire_telephones', `client_${TEL_CLIENT}`), { uid: 'client', email: 'client@test.sn' }));
    await assertFails(setDoc(doc(en('autreClient'), 'annuaire_telephones', `client_${TEL_CLIENT}`), { uid: 'autreClient', email: 'autreClient@test.sn' }));
    await assertFails(deleteDoc(doc(en('autreClient'), 'annuaire_telephones', `client_${TEL_CLIENT}`)));
  });
});

describe('courses', () => {
  const nouvelleCourse = (clientId, extra = {}) => ({
    clientId, chauffeurId: null, statut: 'en_attente', type: 'PASSAGER', prixFcfa: 2100,
    methodePaiement: 'WAVE', timestamp: serverTimestamp(), ...extra,
  });

  test('créer une course depuis l\'app, même parfaitement formée : refusé à tous (Cloud Function seule)', async () => {
    for (const uid of ['client', 'chauffeur', 'admin']) {
      await assertFails(addDoc(collection(en(uid), 'courses'), nouvelleCourse(uid)));
      await assertFails(setDoc(doc(en(uid), 'courses', `x-${uid}`), nouvelleCourse(uid)));
    }
    await assertFails(addDoc(collection(en('client'), 'courses'), nouvelleCourse('client', { prixFcfa: 100 })));
  });

  test('le client ne modifie jamais sa course ni son prix, même en attente', async () => {
    const db = en('client');
    await assertFails(updateDoc(doc(db, 'courses', 'c1'), { prixFcfa: 100 }));
    await assertFails(updateDoc(doc(db, 'courses', 'c1'), { statut: 'annulee', prixFcfa: 100 }));
    await assertFails(updateDoc(doc(db, 'courses', 'c1'), { adresseArrivee: 'Ailleurs' }));
    await assertFails(setDoc(doc(db, 'courses', 'c1'), { clientId: 'client', chauffeurId: null, statut: 'en_attente', prixFcfa: 100 }));
  });

  test('radar : un chauffeur actif voit les courses en attente', async () => {
    await assertSucceeds(getDocs(query(collection(en('chauffeur'), 'courses'), where('statut', '==', 'en_attente'))));
  });

  test('radar : chauffeur suspendu, banni, non validé ou client : refusé', async () => {
    for (const uid of ['suspendu', 'banni', 'enAttente', 'client']) {
      await assertFails(getDocs(query(collection(en(uid), 'courses'), where('statut', '==', 'en_attente'))));
    }
  });

  test('lister toutes les courses sans filtre : refusé', async () => {
    await assertFails(getDocs(collection(en('chauffeur'), 'courses')));
  });

  test('un chauffeur actif accepte une course libre (transaction) : accepté', async () => {
    const db = en('chauffeur');
    await assertSucceeds(runTransaction(db, async (t) => {
      const ref = doc(db, 'courses', 'c1');
      await t.get(ref);
      t.update(ref, { chauffeurId: 'chauffeur', statut: 'acceptee' });
    }));
  });

  test('un chauffeur banni ou suspendu accepte une course : refusé', async () => {
    for (const uid of ['banni', 'suspendu']) {
      await assertFails(updateDoc(doc(en(uid), 'courses', 'c1'), { chauffeurId: uid, statut: 'acceptee' }));
    }
  });

  test('attribuer la course à un autre chauffeur ou modifier le prix : refusé', async () => {
    const db = en('chauffeur');
    await assertFails(updateDoc(doc(db, 'courses', 'c1'), { chauffeurId: 'suspendu', statut: 'acceptee' }));
    await assertFails(updateDoc(doc(db, 'courses', 'c1'), { chauffeurId: 'chauffeur', statut: 'acceptee', prixFcfa: 1 }));
  });

  test('reprendre une course déjà acceptée : refusé', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      updateDoc(doc(ctx.firestore(), 'courses', 'c1'), { chauffeurId: 'autre', statut: 'acceptee' }));
    await assertFails(updateDoc(doc(en('chauffeur'), 'courses', 'c1'), { chauffeurId: 'chauffeur', statut: 'acceptee' }));
  });

  test('annuler depuis l\'app, sans passer par le serveur (donc sans remboursement) : refusé', async () => {
    await assertFails(updateDoc(doc(en('autreClient'), 'courses', 'c1'), { statut: 'annulee' }));
    await assertFails(updateDoc(doc(en('client'), 'courses', 'c1'), { statut: 'annulee' }));
    await assertFails(updateDoc(doc(en('client'), 'courses', 'c1'), { statut: 'annulee', annuleePar: 'client' }));
  });

  test('lire la course d\'un autre client : refusé', async () => {
    await assertSucceeds(getDoc(doc(en('client'), 'courses', 'c1')));
    await assertFails(getDoc(doc(en('autreClient'), 'courses', 'c1')));
  });
});

describe('courses : cycle de vie côté chauffeur', () => {
  beforeEach(() => env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), 'courses', 'c2'), { clientId: 'client', chauffeurId: 'chauffeur', statut: 'acceptee', prixFcfa: 2000 })));

  test('le chauffeur attribué : client à bord puis course terminée : accepté', async () => {
    const db = en('chauffeur');
    await assertSucceeds(updateDoc(doc(db, 'courses', 'c2'), { statut: 'en_cours' }));
    await assertSucceeds(updateDoc(doc(db, 'courses', 'c2'),
      { statut: 'terminee', termineeLe: serverTimestamp(), commissionFcfa: 300 }));
  });

  test('sauter une étape, revenir en arrière ou toucher au prix : refusé', async () => {
    const db = en('chauffeur');
    await assertFails(updateDoc(doc(db, 'courses', 'c2'), { statut: 'terminee' }));
    await assertFails(updateDoc(doc(db, 'courses', 'c2'), { statut: 'en_cours', prixFcfa: 99999 }));
    await assertSucceeds(updateDoc(doc(db, 'courses', 'c2'), { statut: 'en_cours' }));
    await assertFails(updateDoc(doc(db, 'courses', 'c2'), { statut: 'acceptee' }));
  });

  test('le chauffeur annule directement, même avec un motif valide : refusé (serveur seul, remboursement)', async () => {
    const annuler = (motif) => ({ statut: 'annulee', annuleePar: 'chauffeur', motifAnnulation: motif });
    const db = en('chauffeur');
    await assertFails(updateDoc(doc(db, 'courses', 'c2'), annuler('client_introuvable')));
    await assertFails(updateDoc(doc(db, 'courses', 'c2'), annuler('panne')));
    await assertFails(updateDoc(doc(db, 'courses', 'c2'), { statut: 'annulee' }));
    await assertFails(updateDoc(doc(en('client'), 'courses', 'c2'), annuler('panne')));
  });

  test('un autre chauffeur fait avancer la course : refusé', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'users', 'chauffeur2'), { role: 'conducteur', statutValidation: 'valide' }));
    await assertFails(updateDoc(doc(en('chauffeur2'), 'courses', 'c2'), { statut: 'en_cours' }));
  });

  test('le chauffeur liste ses courses attribuées ; pas celles des autres', async () => {
    await assertSucceeds(getDocs(query(collection(en('chauffeur'), 'courses'),
      where('chauffeurId', '==', 'chauffeur'), where('statut', 'in', ['acceptee', 'en_cours']))));
    await assertFails(getDocs(query(collection(en('chauffeur'), 'courses'), where('chauffeurId', '==', 'autre'))));
  });

  test('l\'admin liste les courses en cours : accepté ; un client : refusé', async () => {
    const enCours = (db) => getDocs(query(collection(db, 'courses'), where('statut', 'in', ['acceptee', 'en_cours'])));
    await assertSucceeds(enCours(en('admin')));
    await assertFails(enCours(en('client')));
  });

  test('Dashboard admin : dernières courses et liste des clients ; refusé à un client ou un chauffeur', async () => {
    const dernieres = (db) => getDocs(query(collection(db, 'courses'), orderBy('timestamp', 'desc'), limit(10)));
    const clients = (db) => getDocs(query(collection(db, 'users'), where('role', '==', 'client')));
    await assertSucceeds(dernieres(en('admin')));
    await assertSucceeds(clients(en('admin')));
    for (const uid of ['client', 'chauffeur']) {
      await assertFails(dernieres(en(uid)));
      await assertFails(clients(en(uid)));
    }
  });
});

describe('support : tickets par course', () => {
  beforeEach(() => env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'courses', 'c9'), { clientId: 'client', chauffeurId: 'chauffeur', statut: 'terminee', prixFcfa: 2000 });
    await setDoc(doc(db, 'courses', 'c10'), { clientId: 'autreClient', chauffeurId: 'chauffeur', statut: 'terminee', prixFcfa: 2000 });
  }));

  const ticket = (extra = {}) => ({
    courseId: 'c9', clientId: 'client', chauffeurId: 'chauffeur', categorie: 'chauffeur', statut: 'ouvert',
    creeLe: serverTimestamp(), majLe: serverTimestamp(), dernierMessage: 'Le chauffeur était impoli',
    nonLuAdmin: true, nonLuClient: false, ...extra,
  });
  const message = (auteurId, auteurRole, texte = 'Bonjour') => ({ auteurId, auteurRole, texte, creeLe: serverTimestamp() });

  /** Ticket + premier message, dans la même écriture (comme l'app). */
  async function ouvrir(db, extra = {}) {
    const batch = writeBatch(db);
    batch.set(doc(db, 'tickets', 'c9'), ticket(extra));
    batch.set(doc(db, 'tickets', 'c9', 'messages', 'm1'), message('client', 'client', 'Le chauffeur était impoli'));
    return batch.commit();
  }

  test('le client ouvre un ticket sur sa course, avec son premier message', async () => {
    await assertSucceeds(ouvrir(en('client')));
    await assertSucceeds(getDoc(doc(en('client'), 'tickets', 'c9')));
    await assertSucceeds(getDocs(collection(en('client'), 'tickets', 'c9', 'messages')));
    await assertSucceeds(getDocs(query(collection(en('client'), 'tickets'), where('clientId', '==', 'client'))));
  });

  test('savoir si un ticket existe déjà (document absent) : accepté', async () => {
    await assertSucceeds(getDoc(doc(en('client'), 'tickets', 'c9')));
  });

  test('ticket sur la course d\'un autre, au nom d\'un autre, faux chauffeur, catégorie ou statut inventés : refusé', async () => {
    const db = en('client');
    await assertFails(setDoc(doc(db, 'tickets', 'c10'), ticket({ courseId: 'c10' })));
    await assertFails(setDoc(doc(en('autreClient'), 'tickets', 'c9'), ticket({ clientId: 'autreClient' })));
    await assertFails(setDoc(doc(db, 'tickets', 'c9'), ticket({ chauffeurId: 'suspendu' })));
    await assertFails(setDoc(doc(db, 'tickets', 'c9'), ticket({ categorie: 'remboursement_immediat' })));
    await assertFails(setDoc(doc(db, 'tickets', 'c9'), ticket({ statut: 'resolu' })));
    await assertFails(setDoc(doc(db, 'tickets', 'c9'), ticket({ priorite: 'haute' })));
  });

  test('un autre client ou le chauffeur ne lisent ni le ticket ni la conversation', async () => {
    await ouvrir(en('client'));
    for (const uid of ['autreClient', 'chauffeur']) {
      await assertFails(getDoc(doc(en(uid), 'tickets', 'c9')));
      await assertFails(getDocs(collection(en(uid), 'tickets', 'c9', 'messages')));
      await assertFails(setDoc(doc(en(uid), 'tickets', 'c9', 'messages', 'x'), message(uid, 'client')));
    }
    await assertFails(getDocs(collection(en('autreClient'), 'tickets')));
  });

  test('le client répond (le ticket repasse ouvert) mais ne peut ni se faire passer pour l\'Admin ni clore', async () => {
    await ouvrir(en('client'));
    await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), 'tickets', 'c9'), { statut: 'resolu' }));
    const db = en('client');
    const batch = writeBatch(db);
    batch.set(doc(db, 'tickets', 'c9', 'messages', 'm2'), message('client', 'client', 'Toujours pas réglé'));
    batch.update(doc(db, 'tickets', 'c9'), {
      majLe: serverTimestamp(), dernierMessage: 'Toujours pas réglé', nonLuAdmin: true, nonLuClient: false, statut: 'ouvert',
    });
    await assertSucceeds(batch.commit());
    await assertFails(setDoc(doc(db, 'tickets', 'c9', 'messages', 'm3'), message('client', 'admin')));
    await assertFails(setDoc(doc(db, 'tickets', 'c9', 'messages', 'm4'), message('admin', 'admin')));
    await assertFails(updateDoc(doc(db, 'tickets', 'c9'), { statut: 'resolu' }));
    await assertFails(updateDoc(doc(db, 'tickets', 'c9'), { categorie: 'securite' }));
    await assertSucceeds(updateDoc(doc(db, 'tickets', 'c9'), { nonLuClient: false }));
    await assertFails(updateDoc(doc(db, 'tickets', 'c9', 'messages', 'm1'), { texte: 'modifié' }));
  });

  test('message vide ou trop long : refusé', async () => {
    await ouvrir(en('client'));
    await assertFails(setDoc(doc(en('client'), 'tickets', 'c9', 'messages', 'v'), message('client', 'client', '')));
    await assertFails(setDoc(doc(en('client'), 'tickets', 'c9', 'messages', 'l'), message('client', 'client', 'x'.repeat(1001))));
  });

  test('l\'Admin voit toute la file, répond et clôt', async () => {
    await ouvrir(en('client'));
    const db = en('admin');
    await assertSucceeds(getDocs(query(collection(db, 'tickets'), orderBy('majLe', 'desc'))));
    await assertSucceeds(getDocs(collection(db, 'tickets', 'c9', 'messages')));
    await assertSucceeds(setDoc(doc(db, 'tickets', 'c9', 'messages', 'r1'), message('admin', 'admin', 'Nous regardons.')));
    await assertSucceeds(updateDoc(doc(db, 'tickets', 'c9'), { statut: 'resolu', nonLuAdmin: false, nonLuClient: true }));
  });

  test('journal des actions Admin : lisible par l\'Admin seul, écrit par le serveur seul', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'journal_admin', 'j1'), { action: 'remboursement' }));
    await assertSucceeds(getDocs(collection(en('admin'), 'journal_admin')));
    await assertFails(getDocs(collection(en('client'), 'journal_admin')));
    await assertFails(setDoc(doc(en('admin'), 'journal_admin', 'j2'), { action: 'faux' }));
  });
});

describe('commandes (paiement) et config serveur', () => {
  beforeEach(() => env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'commandes', 'k1'), {
      clientId: 'client', statut: 'en_attente_paiement', prixFcfa: 2300, sessionPaiementId: 'sim_1', lienPaiement: 'https://page',
    });
    await setDoc(doc(db, 'config', 'paiementSimule'), { secret: 'x'.repeat(64) });
  }));

  test('le client suit sa commande pendant qu\'il paie ; l\'admin aussi', async () => {
    await assertSucceeds(getDoc(doc(en('client'), 'commandes', 'k1')));
    await assertSucceeds(getDoc(doc(en('admin'), 'commandes', 'k1')));
    await assertSucceeds(getDocs(query(collection(en('client'), 'commandes'), where('clientId', '==', 'client'))));
  });

  test('un autre client, un chauffeur ou un anonyme ne la lit pas', async () => {
    for (const db of [en('autreClient'), en('chauffeur'), anonyme()]) {
      await assertFails(getDoc(doc(db, 'commandes', 'k1')));
    }
    await assertFails(getDocs(collection(en('client'), 'commandes')));
  });

  test('personne ne crée ni ne se déclare payé depuis l\'app, même l\'admin', async () => {
    for (const uid of ['client', 'admin']) {
      await assertFails(updateDoc(doc(en(uid), 'commandes', 'k1'), { statut: 'payee' }));
      await assertFails(setDoc(doc(en(uid), 'commandes', `n-${uid}`), { clientId: uid, statut: 'payee', prixFcfa: 1 }));
      await assertFails(deleteDoc(doc(en(uid), 'commandes', 'k1')));
    }
  });

  test('le secret du paiement simulé est illisible depuis l\'app, même pour l\'admin', async () => {
    for (const db of [en('client'), en('admin'), anonyme()]) {
      await assertFails(getDoc(doc(db, 'config', 'paiementSimule')));
      await assertFails(setDoc(doc(db, 'config', 'paiementSimule'), { secret: 'pirate' }));
    }
  });
});

describe('positions_chauffeurs (carte en direct)', () => {
  const position = (extra = {}) => ({
    latitude: 14.69, longitude: -17.44, precision: 12, cap: 90, vitesse: 8, majLe: serverTimestamp(), ...extra,
  });

  test('un chauffeur actif publie sa position ; l\'admin la lit', async () => {
    await assertSucceeds(setDoc(doc(en('chauffeur'), 'positions_chauffeurs', 'chauffeur'), position()));
    await assertSucceeds(getDoc(doc(en('admin'), 'positions_chauffeurs', 'chauffeur')));
    await assertSucceeds(getDocs(collection(en('admin'), 'positions_chauffeurs')));
  });

  test('personne d\'autre que l\'admin ne lit les positions', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'positions_chauffeurs', 'chauffeur'), { latitude: 14.69, longitude: -17.44 }));
    await assertFails(getDoc(doc(en('client'), 'positions_chauffeurs', 'chauffeur')));
    await assertFails(getDoc(doc(en('chauffeur'), 'positions_chauffeurs', 'chauffeur')));
    await assertFails(getDocs(collection(en('client'), 'positions_chauffeurs')));
    await assertFails(getDoc(doc(anonyme(), 'positions_chauffeurs', 'chauffeur')));
  });

  test('chauffeur non validé, suspendu ou banni : publication refusée', async () => {
    for (const uid of ['enAttente', 'suspendu', 'banni', 'client']) {
      await assertFails(setDoc(doc(en(uid), 'positions_chauffeurs', uid), position()));
    }
  });

  test('publier pour un autre, hors limites, date falsifiée ou champ inconnu : refusé', async () => {
    const db = en('chauffeur');
    await assertFails(setDoc(doc(db, 'positions_chauffeurs', 'enAttente'), position()));
    await assertFails(setDoc(doc(db, 'positions_chauffeurs', 'chauffeur'), position({ latitude: 91 })));
    await assertFails(setDoc(doc(db, 'positions_chauffeurs', 'chauffeur'), position({ majLe: new Date(2020, 0, 1) })));
    await assertFails(setDoc(doc(db, 'positions_chauffeurs', 'chauffeur'), position({ enCourse: true })));
  });

  test('passer hors ligne supprime sa position ; pas celle d\'un autre', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'positions_chauffeurs', 'chauffeur'), { latitude: 14.69, longitude: -17.44 });
      await setDoc(doc(db, 'positions_chauffeurs', 'suspendu'), { latitude: 14.69, longitude: -17.44 });
    });
    await assertFails(deleteDoc(doc(en('chauffeur'), 'positions_chauffeurs', 'suspendu')));
    await assertSucceeds(deleteDoc(doc(en('chauffeur'), 'positions_chauffeurs', 'chauffeur')));
    await assertSucceeds(deleteDoc(doc(en('suspendu'), 'positions_chauffeurs', 'suspendu')));
  });
});

describe('suivi d\'approche (client)', () => {
  // c2 : course du client, attribuée au chauffeur, en approche.
  beforeEach(() => env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'courses', 'c2'), { clientId: 'client', chauffeurId: 'chauffeur', statut: 'acceptee' });
    await setDoc(doc(db, 'courses', 'c3'), { clientId: 'autreClient', chauffeurId: 'chauffeur', statut: 'terminee' });
    await setDoc(doc(db, 'positions_chauffeurs', 'chauffeur'), { latitude: 14.69, longitude: -17.44, courseId: 'c2' });
  }));

  test('le client de la course voit la position de son chauffeur', async () => {
    await assertSucceeds(getDoc(doc(en('client'), 'positions_chauffeurs', 'chauffeur')));
  });

  test('un autre client, même en changeant courseId, ne la voit pas', async () => {
    await assertFails(getDoc(doc(en('autreClient'), 'positions_chauffeurs', 'chauffeur')));
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'positions_chauffeurs', 'chauffeur'), { latitude: 14.69, longitude: -17.44, courseId: 'c3' }));
    await assertFails(getDoc(doc(en('autreClient'), 'positions_chauffeurs', 'chauffeur')));
  });

  test('course terminée ou position sans course : plus de suivi', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'courses', 'c2'), { clientId: 'client', chauffeurId: 'chauffeur', statut: 'terminee' }));
    await assertFails(getDoc(doc(en('client'), 'positions_chauffeurs', 'chauffeur')));
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'positions_chauffeurs', 'chauffeur'), { latitude: 14.69, longitude: -17.44 }));
    await assertFails(getDoc(doc(en('client'), 'positions_chauffeurs', 'chauffeur')));
  });

  test('dès l\'acceptation : lisible via la liaison, même si la position n\'a pas encore de courseId', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'liaisons', 'client_chauffeur'), { clientId: 'client', chauffeurId: 'chauffeur', courseId: 'c2' });
      // Position publiée avant l'acceptation : aucun courseId.
      await setDoc(doc(db, 'positions_chauffeurs', 'chauffeur'), { latitude: 14.69, longitude: -17.44 });
    });
    await assertSucceeds(getDoc(doc(en('client'), 'positions_chauffeurs', 'chauffeur')));
  });

  test('la liaison ne donne ni au mauvais client, ni après la course, ni sur le listage', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'liaisons', 'client_chauffeur'), { clientId: 'client', chauffeurId: 'chauffeur', courseId: 'c2' });
      await setDoc(doc(db, 'positions_chauffeurs', 'chauffeur'), { latitude: 14.69, longitude: -17.44 });
    });
    // Un autre client n'a aucune liaison avec ce chauffeur.
    await assertFails(getDoc(doc(en('autreClient'), 'positions_chauffeurs', 'chauffeur')));
    // Le chauffeur d'une autre course n'est pas visible non plus.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'positions_chauffeurs', 'autreChauffeur'), { latitude: 14.7, longitude: -17.4 });
    });
    await assertFails(getDoc(doc(en('client'), 'positions_chauffeurs', 'autreChauffeur')));
    await assertFails(getDocs(collection(en('client'), 'positions_chauffeurs')));
    // Course terminée : la liaison (qui reste) ne suffit plus.
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'courses', 'c2'), { clientId: 'client', chauffeurId: 'chauffeur', statut: 'terminee' }));
    await assertFails(getDoc(doc(en('client'), 'positions_chauffeurs', 'chauffeur')));
  });

  test('liaison pointant vers une course d\'un autre chauffeur : aucun suivi', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'courses', 'c9'), { clientId: 'client', chauffeurId: 'autreChauffeur', statut: 'en_cours' });
      await setDoc(doc(db, 'liaisons', 'client_chauffeur'), { clientId: 'client', chauffeurId: 'chauffeur', courseId: 'c9' });
      await setDoc(doc(db, 'positions_chauffeurs', 'chauffeur'), { latitude: 14.69, longitude: -17.44 });
    });
    await assertFails(getDoc(doc(en('client'), 'positions_chauffeurs', 'chauffeur')));
  });

  test('position pas encore publiée : lecture possible (document vide), pas de listage', async () => {
    await assertSucceeds(getDoc(doc(en('client'), 'positions_chauffeurs', 'inconnu')));
    await assertFails(getDocs(collection(en('client'), 'positions_chauffeurs')));
  });

  test('le chauffeur rattache sa position à sa course', async () => {
    await assertSucceeds(setDoc(doc(en('chauffeur'), 'positions_chauffeurs', 'chauffeur'),
      { latitude: 14.7, longitude: -17.45, majLe: serverTimestamp(), courseId: 'c2' }));
    await assertFails(setDoc(doc(en('chauffeur'), 'positions_chauffeurs', 'chauffeur'),
      { latitude: 14.7, longitude: -17.45, majLe: serverTimestamp(), courseId: 42 }));
  });

  test('véhicule du profil public : écrit par l\'admin, pas par le chauffeur', async () => {
    await assertFails(updateDoc(doc(en('chauffeur'), 'profils_publics', 'chauffeur'), { plaqueImmatriculation: 'DK-0000-ZZ' }));
    await assertSucceeds(updateDoc(doc(en('admin'), 'profils_publics', 'chauffeur'), { vehiculeId: 'Yamaha', plaqueImmatriculation: 'DK-1234-AB' }));
  });
});

describe('evaluations et note moyenne', () => {
  beforeEach(() => env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'courses', 'fin'), { clientId: 'client', chauffeurId: 'chauffeur', statut: 'terminee' });
    await setDoc(doc(db, 'courses', 'fin2'), { clientId: 'client', chauffeurId: 'chauffeur', statut: 'terminee' });
    await setDoc(doc(db, 'courses', 'route'), { clientId: 'client', chauffeurId: 'chauffeur', statut: 'en_cours' });
    await setDoc(doc(db, 'courses', 'autre'), { clientId: 'autreClient', chauffeurId: 'chauffeur', statut: 'terminee' });
    await setDoc(doc(db, 'profils_publics', 'chauffeur'),
      { nom: 'Moussa', telephone: TEL_CHAUFFEUR, role: 'conducteur', disponible: true, noteSomme: 9, noteNombre: 2 });
  }));

  const evaluation = (courseId, extra = {}) => ({
    courseId, chauffeurId: 'chauffeur', clientId: 'client', note: 5, commentaire: 'Très bien', creeLe: serverTimestamp(), ...extra,
  });

  const evaluer = (uid, courseId, { note = 5, extra = {}, profil } = {}) => {
    const db = en(uid);
    const lot = writeBatch(db);
    lot.set(doc(db, 'evaluations', courseId), evaluation(courseId, { note, ...extra }));
    lot.update(doc(db, 'profils_publics', 'chauffeur'),
      profil ?? { noteSomme: increment(note), noteNombre: increment(1), derniereEvaluation: courseId });
    return lot.commit();
  };

  test('le client note sa course terminée et la moyenne est mise à jour', async () => {
    await assertSucceeds(evaluer('client', 'fin', { note: 4 }));
    let profil;
    await env.withSecurityRulesDisabled(async (ctx) => {
      profil = (await getDoc(doc(ctx.firestore(), 'profils_publics', 'chauffeur'))).data();
    });
    if (profil.noteSomme !== 13 || profil.noteNombre !== 3) throw new Error(JSON.stringify(profil));
  });

  test('une seule évaluation par course, jamais modifiable', async () => {
    await assertSucceeds(evaluer('client', 'fin'));
    await assertFails(evaluer('client', 'fin'));
    await assertFails(updateDoc(doc(en('client'), 'evaluations', 'fin'), { note: 1 }));
  });

  test('évaluation sans mise à jour de la moyenne, ou moyenne sans évaluation : refusé', async () => {
    await assertFails(setDoc(doc(en('client'), 'evaluations', 'fin'), evaluation('fin')));
    await assertFails(updateDoc(doc(en('client'), 'profils_publics', 'chauffeur'),
      { noteSomme: increment(5), noteNombre: increment(1), derniereEvaluation: 'fin' }));
  });

  test('gonfler la moyenne (mauvais total, plusieurs avis d\'un coup) : refusé', async () => {
    await assertFails(evaluer('client', 'fin', { note: 1, profil: { noteSomme: increment(5), noteNombre: increment(1), derniereEvaluation: 'fin' } }));
    await assertFails(evaluer('client', 'fin', { profil: { noteSomme: increment(10), noteNombre: increment(2), derniereEvaluation: 'fin' } }));
    await assertFails(evaluer('client', 'fin', { profil: { noteSomme: increment(5), noteNombre: increment(1), derniereEvaluation: 'fin', disponible: false } }));
  });

  test('note hors 1-5, non entière ou commentaire trop long : refusé', async () => {
    await assertFails(evaluer('client', 'fin', { note: 6 }));
    await assertFails(evaluer('client', 'fin', { note: 0 }));
    await assertFails(evaluer('client', 'fin', { note: 4.5 }));
    await assertFails(evaluer('client', 'fin', { extra: { commentaire: 'x'.repeat(501) } }));
  });

  test('course pas terminée, course d\'un autre, ou chauffeur qui se note lui-même : refusé', async () => {
    await assertFails(evaluer('client', 'route'));
    await assertFails(evaluer('client', 'autre'));
    await assertFails(evaluer('chauffeur', 'fin', { extra: { clientId: 'chauffeur' } }));
  });

  test('lecture : le client et le chauffeur concernés, pas les autres', async () => {
    await assertSucceeds(evaluer('client', 'fin'));
    await assertSucceeds(getDoc(doc(en('client'), 'evaluations', 'fin')));
    await assertSucceeds(getDocs(query(collection(en('chauffeur'), 'evaluations'), where('chauffeurId', '==', 'chauffeur'))));
    await assertFails(getDoc(doc(en('autreClient'), 'evaluations', 'fin')));
    await assertSucceeds(getDoc(doc(en('client'), 'evaluations', 'fin2'))); // pas encore notée : document vide
  });

  test('"Courses à noter" : le client liste ses courses terminées et ses évaluations, pas celles des autres', async () => {
    const db = en('client');
    await assertSucceeds(getDocs(query(collection(db, 'courses'),
      where('clientId', '==', 'client'), where('statut', '==', 'terminee'))));
    await assertSucceeds(getDocs(query(collection(db, 'evaluations'), where('clientId', '==', 'client'))));
    await assertFails(getDocs(query(collection(db, 'courses'),
      where('clientId', '==', 'autreClient'), where('statut', '==', 'terminee'))));
    await assertFails(getDocs(query(collection(db, 'evaluations'), where('clientId', '==', 'autreClient'))));
  });

  test('le chauffeur ne peut pas toucher à sa propre note', async () => {
    await assertFails(updateDoc(doc(en('chauffeur'), 'profils_publics', 'chauffeur'), { noteSomme: 50, noteNombre: 10 }));
  });
});

describe('finances', () => {
  beforeEach(() => env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), 'courses', 'f1'), { clientId: 'client', chauffeurId: 'chauffeur', statut: 'en_cours', prixFcfa: 3100 })));

  const terminer = (commission, extra = {}) =>
    updateDoc(doc(en('chauffeur'), 'courses', 'f1'), { statut: 'terminee', termineeLe: serverTimestamp(), commissionFcfa: commission, ...extra });

  test('fin de course : commission = 15 % arrondi à l\'inférieur (3 100 -> 465)', async () => {
    await assertSucceeds(terminer(465));
  });

  test('commission sous-évaluée, absente, ou prix modifié à la fin : refusé', async () => {
    await assertFails(terminer(0));
    await assertFails(terminer(464));
    await assertFails(updateDoc(doc(en('chauffeur'), 'courses', 'f1'), { statut: 'terminee', termineeLe: serverTimestamp() }));
    await assertFails(terminer(465, { prixFcfa: 100 }));
  });

  test('course remboursée au client : ni le chauffeur ni le client ne peuvent effacer la marque', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'courses', 'f1'), {
      clientId: 'client', chauffeurId: 'chauffeur', statut: 'terminee', prixFcfa: 3100, commissionFcfa: 465,
      rembourseeLe: new Date(), rembourseePar: 'admin', partChauffeurRetireeFcfa: 2635,
    }));
    for (const qui of ['chauffeur', 'client']) {
      await assertFails(updateDoc(doc(en(qui), 'courses', 'f1'), { rembourseeLe: deleteField() }));
      await assertFails(updateDoc(doc(en(qui), 'courses', 'f1'), { partChauffeurRetireeFcfa: 0 }));
    }
  });

  test('versements : saisis par l\'admin, lus par le chauffeur concerné seulement', async () => {
    const reglement = { chauffeurId: 'chauffeur', montantFcfa: 5000, sens: 'plateforme_vers_chauffeur', note: 'Virement Wave', creeLe: serverTimestamp() };
    await assertSucceeds(setDoc(doc(en('admin'), 'reglements', 'r1'), reglement));
    await assertFails(setDoc(doc(en('chauffeur'), 'reglements', 'r2'), reglement));
    await assertSucceeds(getDocs(query(collection(en('chauffeur'), 'reglements'), where('chauffeurId', '==', 'chauffeur'))));
    await assertFails(getDocs(query(collection(en('client'), 'reglements'), where('chauffeurId', '==', 'chauffeur'))));
    await assertFails(updateDoc(doc(en('admin'), 'reglements', 'r1'), { montantFcfa: 1 }));
    await assertFails(setDoc(doc(en('admin'), 'reglements', 'r3'), { ...reglement, montantFcfa: -100 }));
    // Plus de dette du chauffeur envers la plateforme.
    await assertFails(setDoc(doc(en('admin'), 'reglements', 'r4'), { ...reglement, sens: 'chauffeur_vers_plateforme' }));
  });

  test('temps en ligne : +60 s par minute, pour soi, pas de rafale', async () => {
    const db = en('chauffeur');
    const ref = doc(db, 'temps_en_ligne', 'chauffeur_2026-09-27');
    await assertSucceeds(setDoc(ref, { chauffeurId: 'chauffeur', date: '2026-09-27', secondes: 60, majLe: serverTimestamp() }));
    // Seconde écriture immédiate : trop tôt (moins de 50 s).
    await assertFails(updateDoc(ref, { secondes: increment(60), majLe: serverTimestamp() }));
    await env.withSecurityRulesDisabled((ctx) =>
      updateDoc(doc(ctx.firestore(), 'temps_en_ligne', 'chauffeur_2026-09-27'), { majLe: new Date(Date.now() - 120000) }));
    await assertFails(updateDoc(ref, { secondes: increment(3600), majLe: serverTimestamp() }));
    await assertSucceeds(updateDoc(ref, { secondes: increment(60), majLe: serverTimestamp() }));
    await assertFails(setDoc(doc(en('chauffeur'), 'temps_en_ligne', 'suspendu_2026-09-27'),
      { chauffeurId: 'suspendu', date: '2026-09-27', secondes: 60, majLe: serverTimestamp() }));
    await assertFails(getDoc(doc(en('client'), 'temps_en_ligne', 'chauffeur_2026-09-27')));
  });
});

describe('chats', () => {
  const chatId = ['chauffeur', 'client'].sort().join('_');

  // Le chauffeur a accepté une course du client : c'est ce qui ouvre la conversation.
  beforeEach(() => poserCourseAcceptee());

  test('un participant crée le chat et envoie un message : accepté', async () => {
    const db = en('client');
    await assertSucceeds(setDoc(doc(db, 'chats', chatId), { participants: ['client', 'chauffeur'], dernierMessage: 'Bonjour' }, { merge: true }));
    await assertSucceeds(addDoc(collection(db, 'chats', chatId, 'messages'), { senderId: 'client', text: 'Bonjour' }));
  });

  test('lire les messages avant même la création du chat : accepté pour un participant', async () => {
    await assertSucceeds(getDocs(collection(en('chauffeur'), 'chats', chatId, 'messages')));
  });

  test('un non-participant lit ou écrit dans le chat : refusé', async () => {
    const db = en('autreClient');
    await assertFails(getDocs(collection(db, 'chats', chatId, 'messages')));
    await assertFails(addDoc(collection(db, 'chats', chatId, 'messages'), { senderId: 'autreClient', text: 'x' }));
    await assertFails(setDoc(doc(db, 'chats', chatId), { participants: ['client', 'chauffeur'] }));
  });

  test('usurper l\'expéditeur ou ajouter un intrus aux participants : refusé', async () => {
    const db = en('client');
    await assertFails(addDoc(collection(db, 'chats', chatId, 'messages'), { senderId: 'chauffeur', text: 'x' }));
    await assertFails(setDoc(doc(db, 'chats', chatId), { participants: ['client', 'autreClient'] }));
  });

  test('lister ses propres conversations : accepté', async () => {
    await assertSucceeds(getDocs(query(collection(en('chauffeur'), 'chats'), where('participants', 'array-contains', 'chauffeur'))));
  });

  test('course terminée, annulée ou sans liaison : on ne peut plus écrire, l\'historique reste lisible', async () => {
    await assertSucceeds(addDoc(collection(en('client'), 'chats', chatId, 'messages'), { senderId: 'client', text: 'Bonjour' }));
    await poserCourseAcceptee({ statut: 'terminee', termineeLe: new Date() });
    await assertFails(addDoc(collection(en('client'), 'chats', chatId, 'messages'), { senderId: 'client', text: 'Encore là ?' }));
    await assertFails(addDoc(collection(en('chauffeur'), 'chats', chatId, 'messages'), { senderId: 'chauffeur', text: 'Oui' }));
    await assertFails(setDoc(doc(en('client'), 'chats', chatId), { participants: ['client', 'chauffeur'], dernierMessage: 'x' }, { merge: true }));
    await assertSucceeds(getDocs(collection(en('client'), 'chats', chatId, 'messages')));

    await poserCourseAcceptee({ statut: 'annulee' });
    await assertFails(addDoc(collection(en('client'), 'chats', chatId, 'messages'), { senderId: 'client', text: 'x' }));
  });

  test('aucune conversation avec un chauffeur qui n\'a pas de course en cours avec soi', async () => {
    // "client" n'a jamais eu de course avec "suspendu" (ni avec aucun autre chauffeur).
    const autre = ['client', 'suspendu'].sort().join('_');
    await assertFails(setDoc(doc(en('client'), 'chats', autre), { participants: ['client', 'suspendu'], dernierMessage: 'x' }, { merge: true }));
    await assertFails(addDoc(collection(en('client'), 'chats', autre, 'messages'), { senderId: 'client', text: 'x' }));
    // Ni un autre client avec le chauffeur de "client".
    const intrus = ['autreClient', 'chauffeur'].sort().join('_');
    await assertFails(addDoc(collection(en('autreClient'), 'chats', intrus, 'messages'), { senderId: 'autreClient', text: 'x' }));
  });
});

// ---------------------------------------------------------------------
// Confidentialité : un client ne voit et ne contacte que le chauffeur de
// sa course en cours (et inversement). Aucune liste de chauffeurs.
// ---------------------------------------------------------------------
describe('confidentialité : contact limité à la course en cours', () => {
  const JOUR = 24 * 3600 * 1000;

  describe('profils publics', () => {
    beforeEach(async () => {
      await poserCourseAcceptee();
      // Un autre client avec un autre chauffeur (course en cours aussi).
      await env.withSecurityRulesDisabled((ctx) =>
        setDoc(doc(ctx.firestore(), 'profils_publics', 'suspendu'), { nom: 'Ibou', telephone: '+221770000077', role: 'conducteur' }));
      await poserCourseAcceptee({}, { courseId: 'cb', client: 'autreClient', chauffeur: 'suspendu' });
    });

    test('aucune liste de chauffeurs ni de clients : refusée à tous, sauf à l\'admin', async () => {
      const chauffeurs = (db) => getDocs(query(collection(db, 'profils_publics'), where('role', '==', 'conducteur'), where('disponible', '==', true)));
      await assertFails(chauffeurs(en('client')));
      await assertFails(chauffeurs(en('autreClient')));
      await assertFails(chauffeurs(en('chauffeur')));
      await assertFails(getDocs(collection(en('client'), 'profils_publics')));
      await assertFails(getDocs(collection(en('chauffeur'), 'profils_publics')));
      await assertFails(getDocs(collection(anonyme(), 'profils_publics')));
      await assertSucceeds(chauffeurs(en('admin')));
    });

    test('le client lit le chauffeur de sa course en cours, et le chauffeur son client', async () => {
      await assertSucceeds(getDoc(doc(en('client'), 'profils_publics', 'chauffeur')));
      await assertSucceeds(getDoc(doc(en('chauffeur'), 'profils_publics', 'client')));
    });

    test('client à bord : l\'accès continue', async () => {
      await poserCourseAcceptee({ statut: 'en_cours' });
      await assertSucceeds(getDoc(doc(en('client'), 'profils_publics', 'chauffeur')));
    });

    test('un autre chauffeur ou un autre client, même en connaissant l\'identifiant : refusé', async () => {
      await assertFails(getDoc(doc(en('autreClient'), 'profils_publics', 'chauffeur')));
      await assertFails(getDoc(doc(en('client'), 'profils_publics', 'suspendu')));
      await assertFails(getDoc(doc(en('suspendu'), 'profils_publics', 'client')));
      await assertFails(getDoc(doc(en('enAttente'), 'profils_publics', 'client')));
      await assertFails(getDoc(doc(anonyme(), 'profils_publics', 'chauffeur')));
    });

    test('sans course : un client qui n\'a jamais commandé ne voit personne', async () => {
      await env.withSecurityRulesDisabled((ctx) =>
        setDoc(doc(ctx.firestore(), 'users', 'nouveau'), { role: 'client', email: 'nouveau@test.sn' }));
      await assertFails(getDoc(doc(en('nouveau'), 'profils_publics', 'chauffeur')));
    });

    test('course annulée : accès retiré aussitôt', async () => {
      await poserCourseAcceptee({ statut: 'annulee' });
      await assertFails(getDoc(doc(en('client'), 'profils_publics', 'chauffeur')));
      await assertFails(getDoc(doc(en('chauffeur'), 'profils_publics', 'client')));
    });

    test('course terminée : un jour de grâce (pour noter), puis plus rien', async () => {
      await poserCourseAcceptee({ statut: 'terminee', termineeLe: new Date() });
      await assertSucceeds(getDoc(doc(en('client'), 'profils_publics', 'chauffeur')));
      await poserCourseAcceptee({ statut: 'terminee', termineeLe: new Date(Date.now() - 3 * JOUR) });
      await assertFails(getDoc(doc(en('client'), 'profils_publics', 'chauffeur')));
      await assertFails(getDoc(doc(en('chauffeur'), 'profils_publics', 'client')));
      // Course terminée sans date de fin (donnée ancienne) : pas d'accès.
      await poserCourseAcceptee({ statut: 'terminee' });
      await assertFails(getDoc(doc(en('client'), 'profils_publics', 'chauffeur')));
    });

    test('noter son chauffeur ne demande aucune lecture de son profil', async () => {
      await poserCourseAcceptee({ statut: 'terminee', termineeLe: new Date(Date.now() - 3 * JOUR) });
      const db = en('client');
      const lot = writeBatch(db);
      lot.set(doc(db, 'evaluations', 'ca'), {
        courseId: 'ca', chauffeurId: 'chauffeur', clientId: 'client', note: 5, creeLe: serverTimestamp(),
      });
      lot.update(doc(db, 'profils_publics', 'chauffeur'), {
        noteSomme: increment(5), noteNombre: increment(1), derniereEvaluation: 'ca',
      });
      await assertSucceeds(lot.commit());
    });

    test('l\'admin lit n\'importe quel profil', async () => {
      await assertSucceeds(getDoc(doc(en('admin'), 'profils_publics', 'chauffeur')));
      await assertSucceeds(getDoc(doc(en('admin'), 'profils_publics', 'client')));
    });
  });

  describe('liaison créée par le chauffeur à l\'acceptation', () => {
    const liaison = (extra = {}) => ({
      clientId: 'client', chauffeurId: 'chauffeur', courseId: 'c1', creeLe: serverTimestamp(), ...extra,
    });
    const accepter = (donneesLiaison, idLiaison = 'client_chauffeur') => {
      const db = en('chauffeur');
      const lot = writeBatch(db);
      lot.update(doc(db, 'courses', 'c1'), { statut: 'acceptee', chauffeurId: 'chauffeur' });
      lot.set(doc(db, 'liaisons', idLiaison), donneesLiaison);
      return lot.commit();
    };

    test('acceptation + liaison dans la même écriture : accepté, le client voit alors son chauffeur', async () => {
      await assertSucceeds(accepter(liaison()));
      await assertSucceeds(getDoc(doc(en('client'), 'profils_publics', 'chauffeur')));
      await assertSucceeds(getDoc(doc(en('chauffeur'), 'profils_publics', 'client')));
      const chatId = ['chauffeur', 'client'].sort().join('_');
      await assertSucceeds(addDoc(collection(en('client'), 'chats', chatId, 'messages'), { senderId: 'client', text: 'Bonjour' }));
    });

    test('acceptation par transaction, exactement comme l\'app : lecture, mise à jour, liaison', async () => {
      const db = en('chauffeur');
      const course = doc(db, 'courses', 'c1');
      const accepte = await runTransaction(db, async (transaction) => {
        const instantane = await transaction.get(course);
        if (instantane.data().statut !== 'en_attente') return false;
        transaction.update(course, { chauffeurId: 'chauffeur', statut: 'acceptee' });
        transaction.set(doc(db, 'liaisons', `${instantane.data().clientId}_chauffeur`), liaison());
        return true;
      });
      if (!accepte) throw new Error('transaction refusée');
      await assertSucceeds(getDoc(doc(en('client'), 'profils_publics', 'chauffeur')));
      await assertSucceeds(getDoc(doc(en('chauffeur'), 'profils_publics', 'client')));
    });

    test('l\'ordre inverse de l\'identifiant fonctionne aussi', async () => {
      await assertSucceeds(accepter(liaison(), 'chauffeur_client'));
      await assertSucceeds(getDoc(doc(en('client'), 'profils_publics', 'chauffeur')));
    });

    test('accepter sans liaison ne donne aucun accès', async () => {
      await assertSucceeds(updateDoc(doc(en('chauffeur'), 'courses', 'c1'), { statut: 'acceptee', chauffeurId: 'chauffeur' }));
      await assertFails(getDoc(doc(en('client'), 'profils_publics', 'chauffeur')));
    });

    test('nouvelle course avec le même client : la liaison se met à jour', async () => {
      await poserCourseAcceptee({ statut: 'terminee', termineeLe: new Date(Date.now() - 3 * JOUR) });
      await assertFails(getDoc(doc(en('client'), 'profils_publics', 'chauffeur')));
      await assertSucceeds(accepter(liaison()));
      await assertSucceeds(getDoc(doc(en('client'), 'profils_publics', 'chauffeur')));
    });

    test('un client ne peut pas se créer de liaison, ni un chauffeur pour la course d\'un autre', async () => {
      await assertFails(setDoc(doc(en('client'), 'liaisons', 'client_chauffeur'), liaison()));
      await assertFails(setDoc(doc(en('client'), 'liaisons', 'client_suspendu'), liaison({ chauffeurId: 'suspendu' })));
      // Course déjà prise par un autre chauffeur.
      await env.withSecurityRulesDisabled((ctx) =>
        setDoc(doc(ctx.firestore(), 'courses', 'c1'), { clientId: 'client', chauffeurId: 'suspendu', statut: 'acceptee', prixFcfa: 2000 }));
      await assertFails(setDoc(doc(en('chauffeur'), 'liaisons', 'client_chauffeur'), liaison()));
    });

    test('liaison forgée : mauvais client, mauvaise course, mauvais identifiant, champ en trop, date truquée', async () => {
      await assertFails(accepter(liaison({ clientId: 'autreClient' }), 'autreClient_chauffeur'));
      await assertFails(accepter(liaison({ courseId: 'inexistante' })));
      await assertFails(accepter(liaison(), 'client_suspendu'));
      await assertFails(accepter(liaison(), 'autreClient_chauffeur'));
      await assertFails(accepter(liaison({ role: 'admin' })));
      await assertFails(accepter(liaison({ creeLe: new Date('2020-01-01') })));
      await assertFails(accepter(liaison({ chauffeurId: 'suspendu' })));
    });

    test('pas de liaison pour une course terminée, annulée ou encore en attente', async () => {
      for (const statut of ['terminee', 'annulee']) {
        await env.withSecurityRulesDisabled((ctx) =>
          setDoc(doc(ctx.firestore(), 'courses', 'c1'), { clientId: 'client', chauffeurId: 'chauffeur', statut, prixFcfa: 2000 }));
        await assertFails(setDoc(doc(en('chauffeur'), 'liaisons', 'client_chauffeur'), liaison()));
      }
      // c1 revient en attente, sans chauffeur : personne ne peut s'y lier sans l'accepter.
      await env.withSecurityRulesDisabled((ctx) =>
        setDoc(doc(ctx.firestore(), 'courses', 'c1'), { clientId: 'client', chauffeurId: null, statut: 'en_attente', prixFcfa: 2000 }));
      await assertFails(setDoc(doc(en('chauffeur'), 'liaisons', 'client_chauffeur'), liaison()));
    });

    test('un chauffeur suspendu ne peut pas accepter donc ne peut pas se lier', async () => {
      const db = en('suspendu');
      const lot = writeBatch(db);
      lot.update(doc(db, 'courses', 'c1'), { statut: 'acceptee', chauffeurId: 'suspendu' });
      lot.set(doc(db, 'liaisons', 'client_suspendu'), liaison({ chauffeurId: 'suspendu' }));
      await assertFails(lot.commit());
    });

    test('les liaisons ne sont lisibles que par l\'admin', async () => {
      await assertSucceeds(accepter(liaison()));
      await assertFails(getDoc(doc(en('client'), 'liaisons', 'client_chauffeur')));
      await assertFails(getDoc(doc(en('chauffeur'), 'liaisons', 'client_chauffeur')));
      await assertFails(getDocs(collection(en('client'), 'liaisons')));
      await assertSucceeds(getDoc(doc(en('admin'), 'liaisons', 'client_chauffeur')));
      await assertFails(deleteDoc(doc(en('client'), 'liaisons', 'client_chauffeur')));
    });
  });
});
