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

  test('lecture par un utilisateur connecté (chat, appel) : acceptée ; non connecté : refusée', async () => {
    await assertSucceeds(getDoc(doc(en('client'), 'profils_publics', 'chauffeur')));
    await assertSucceeds(getDocs(query(collection(en('client'), 'profils_publics'),
      where('role', '==', 'conducteur'), where('disponible', '==', true))));
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
});
