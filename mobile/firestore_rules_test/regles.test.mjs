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
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
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
    timestamp: serverTimestamp(), ...extra,
  });

  test('un client crée sa course : accepté', async () => {
    await assertSucceeds(addDoc(collection(en('client'), 'courses'), nouvelleCourse('client')));
  });

  test('créer une course au nom d\'un autre, déjà acceptée ou déjà attribuée : refusé', async () => {
    const db = en('client');
    await assertFails(addDoc(collection(db, 'courses'), nouvelleCourse('autreClient')));
    await assertFails(addDoc(collection(db, 'courses'), nouvelleCourse('client', { statut: 'acceptee' })));
    await assertFails(addDoc(collection(db, 'courses'), nouvelleCourse('client', { chauffeurId: 'chauffeur' })));
  });

  test('créer une course avec un champ inconnu ou une date falsifiée : refusé', async () => {
    const db = en('client');
    await assertFails(addDoc(collection(db, 'courses'), nouvelleCourse('client', { paiementConfirme: true })));
    await assertFails(addDoc(collection(db, 'courses'), nouvelleCourse('client', { timestamp: new Date(2020, 0, 1) })));
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

  test('le client annule sa course en attente : accepté ; un autre client : refusé', async () => {
    await assertFails(updateDoc(doc(en('autreClient'), 'courses', 'c1'), { statut: 'annulee' }));
    await assertSucceeds(updateDoc(doc(en('client'), 'courses', 'c1'), { statut: 'annulee' }));
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
    await assertSucceeds(updateDoc(doc(db, 'courses', 'c2'), { statut: 'terminee' }));
  });

  test('sauter une étape, revenir en arrière ou toucher au prix : refusé', async () => {
    const db = en('chauffeur');
    await assertFails(updateDoc(doc(db, 'courses', 'c2'), { statut: 'terminee' }));
    await assertFails(updateDoc(doc(db, 'courses', 'c2'), { statut: 'en_cours', prixFcfa: 99999 }));
    await assertSucceeds(updateDoc(doc(db, 'courses', 'c2'), { statut: 'en_cours' }));
    await assertFails(updateDoc(doc(db, 'courses', 'c2'), { statut: 'acceptee' }));
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

  test('coordonnées de prise en charge enregistrées avec la course', async () => {
    const base = { clientId: 'client', chauffeurId: null, statut: 'en_attente', type: 'PASSAGER', prixFcfa: 3000, timestamp: serverTimestamp() };
    await assertSucceeds(addDoc(collection(en('client'), 'courses'),
      { ...base, latitudeDepart: 14.668, longitudeDepart: -17.438, latitudeArrivee: 14.745, longitudeArrivee: -17.517 }));
    await assertFails(addDoc(collection(en('client'), 'courses'), { ...base, latitudeDepart: 'Plateau' }));
  });

  test('véhicule du profil public : écrit par l\'admin, pas par le chauffeur', async () => {
    await assertFails(updateDoc(doc(en('chauffeur'), 'profils_publics', 'chauffeur'), { plaqueImmatriculation: 'DK-0000-ZZ' }));
    await assertSucceeds(updateDoc(doc(en('admin'), 'profils_publics', 'chauffeur'), { vehiculeId: 'Yamaha', plaqueImmatriculation: 'DK-1234-AB' }));
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
