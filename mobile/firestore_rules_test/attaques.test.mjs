// Attaques simulées, rejouées à chaque publication (phase E de la sécurité).
//
// Chaque test joue UNE attaque contre les vraies règles de la base
// (../firestore.rules), sur l'émulateur, avec des données fictives :
//  - les familles d'attaques : l'attaque DOIT être refusée. Le test échoue
//    dès qu'une modification des règles la laisse passer ;
//  - les contrôles : les gestes légitimes DOIVENT fonctionner. Sans eux, un
//    refus ne prouverait rien (donnée absente, règle cassée, mauvais test).
//
// Pour ajouter une attaque : une ligne dans le tableau de sa famille.
// Projet d'émulateur à part : ce fichier tourne en parallèle de
// regles.test.mjs sans que l'un efface les données de l'autre.
import { after, before, describe, test } from 'node:test';
import { readFileSync } from 'node:fs';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  addDoc, collection, deleteDoc, doc, getDoc, getDocs, query, serverTimestamp, setDoc, Timestamp, updateDoc, where,
} from 'firebase/firestore';

let env;
const en = (uid) => env.authenticatedContext(uid, { email: `${uid}@test.sn` }).firestore();
const anonyme = () => env.unauthenticatedContext().firestore();

/** Données fictives de départ. Appelée avant les tests, et de nouveau si une attaque réussit (voir `famille`). */
async function semer() {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const poser = (chemin, donnees) => setDoc(doc(db, chemin), donnees);
    // Comptes : deux clients, un chauffeur validé, un dossier en attente, un chauffeur suspendu, un admin.
    await poser('users/admin', { role: 'admin', email: 'admin@test.sn' });
    await poser('users/awa', { role: 'client', nom: 'Awa', email: 'awa@test.sn', telephone: '+221770000001' });
    await poser('users/fatou', { role: 'client', nom: 'Fatou', email: 'fatou@test.sn', telephone: '+221770000002' });
    await poser('users/moussa', {
      role: 'conducteur', nom: 'Moussa', email: 'moussa@test.sn', telephone: '+221770000003', statutValidation: 'valide', estValide: true,
    });
    await poser('users/ibou', { role: 'conducteur', nom: 'Ibou', email: 'ibou@test.sn', statutValidation: 'en_attente' });
    await poser('users/suspendu', { role: 'conducteur', nom: 'Sam', email: 'suspendu@test.sn', statutValidation: 'valide', statutCompte: 'suspendu' });
    await poser('profils_publics/moussa', { nom: 'Moussa', telephone: '+221770000003', role: 'conducteur', disponible: true });
    await poser('profils_publics/awa', { nom: 'Awa', telephone: '+221770000001', role: 'client' });
    await poser('profils_publics/fatou', { nom: 'Fatou', telephone: '+221770000002', role: 'client' });
    // Courses : une en attente de chauffeur, une en cours (Fatou et Moussa), une terminée.
    await poser('courses/attente_fatou', {
      clientId: 'fatou', chauffeurId: null, statut: 'en_attente', prixFcfa: 2300, departArrondi: true,
      latitudeDepart: 14.6925, longitudeDepart: -17.4468,
    });
    await poser('courses/cours_fatou', { clientId: 'fatou', chauffeurId: 'moussa', statut: 'en_cours', prixFcfa: 2300 });
    await poser('courses/cours_fatou/prive/depart', { latitude: 14.69251, longitude: -17.44682 });
    await poser('courses/finie_fatou', { clientId: 'fatou', chauffeurId: 'moussa', statut: 'terminee', prixFcfa: 2300, termineeLe: new Date() });
    await poser('liaisons/fatou_moussa', { clientId: 'fatou', chauffeurId: 'moussa', courseId: 'cours_fatou' });
    await poser('chats/fatou_moussa', { participants: ['fatou', 'moussa'], dernierMessage: 'Je suis là' });
    // Argent : commande, portefeuille et livre de comptes, retrait, recharge.
    await poser('commandes/cmd_fatou', { clientId: 'fatou', statut: 'payee', prixFcfa: 2300 });
    await poser('portefeuilles/fatou', { soldeFcfa: 50000, payerAvecSolde: false });
    await poser('portefeuilles/fatou/mouvements/m1', { type: 'recharge', montantFcfa: 50000 });
    await poser('retraits/r1', { clientId: 'fatou', montantFcfa: 10000 });
    await poser('recharges/rch1', { clientId: 'fatou', montantFcfa: 50000, statut: 'reussie' });
    await poser('reglements/reg1', { chauffeurId: 'moussa', montantFcfa: 5000, sens: 'plateforme_vers_chauffeur' });
    // Divers : position, aide, évaluation, annuaire, configuration du serveur, journal, jetons de notification.
    await poser('positions_chauffeurs/moussa', { latitude: 14.69, longitude: -17.44, majLe: Timestamp.now() });
    await poser('tickets/aide_fatou', { clientId: 'fatou', statut: 'ouvert' });
    await poser('tickets/aide_fatou/messages/t1', { auteurId: 'fatou', auteurRole: 'client', texte: 'Bonjour' });
    await poser('evaluations/finie_fatou', { courseId: 'finie_fatou', chauffeurId: 'moussa', clientId: 'fatou', note: 5 });
    await poser('annuaire_telephones/client_+221770000002', { uid: 'fatou', email: 'fatou@test.sn' });
    await poser('config/paiementSimule', { secret: 'x' });
    await poser('journal_admin/j1', { action: 'ajustement' });
    await poser('controle_admin/admin_2026-11-13', { adminId: 'admin', jour: '2026-11-13', creditsFcfa: 5000, versementsFcfa: 0, operations: 1 });
    await poser('appareils/fatou/jetons/t1', { plateforme: 'android' });
    // Deux compteurs prêts à recevoir +60 s : l'un pour le contrôle, l'autre pour l'attaque (le contrôle remet l'heure à zéro).
    await poser('temps_en_ligne/moussa_2026-09-27', { chauffeurId: 'moussa', date: '2026-09-27', secondes: 600, majLe: new Date(Date.now() - 120000) });
    await poser('temps_en_ligne/moussa_2026-09-28', { chauffeurId: 'moussa', date: '2026-09-28', secondes: 600, majLe: new Date(Date.now() - 120000) });
    await poser('courses/finie_fatou/prive/depart', { latitude: 14.69251, longitude: -17.44682 });
  });
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-sprint-attaques',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
  await semer();
});

after(() => env.cleanup());

/**
 * Une famille d'attaques : chacune doit être refusée PAR LES RÈGLES (assertFails
 * n'accepte qu'un refus d'autorisation, pas une erreur de requête). Une attaque
 * qui réussit modifie les données : on les remet à neuf avant la suivante, pour
 * qu'une règle affaiblie ne fasse échouer que son propre test.
 */
function famille(titre, attaques) {
  describe(titre, () => {
    for (const [attaque, action] of attaques) {
      test(attaque, async () => {
        try {
          await assertFails(action());
        } catch (erreur) {
          await semer();
          throw erreur;
        }
      });
    }
  });
}

// Message d'un chauffeur dans une conversation ouverte : seul ce qui est
// testé change d'un cas à l'autre, le reste est valide.
const message = (extra = {}) => ({ senderId: 'moussa', text: 'Bonjour', timestamp: serverTimestamp(), ...extra });
const ajouterMessage = (extra) => addDoc(collection(en('moussa'), 'chats', 'fatou_moussa', 'messages'), message(extra));
const adresseStorage = 'https://firebasestorage.googleapis.com/v0/b/sprint-vtc.firebasestorage.app/o/kyc_documents%2Fibou%2Fpermis.jpg?alt=media&token=3f1c2b6e';
const GROS = 'x'.repeat(500000);

describe('contrôles : les gestes légitimes fonctionnent (sans eux, les refus ne prouvent rien)', () => {
  test('un client lit sa course, sa commande, son portefeuille, son livre de comptes, son retrait, sa recharge et son aide', async () => {
    const db = en('fatou');
    for (const chemin of [
      'courses/cours_fatou', 'commandes/cmd_fatou', 'portefeuilles/fatou', 'portefeuilles/fatou/mouvements/m1',
      'retraits/r1', 'recharges/rch1', 'tickets/aide_fatou', 'users/fatou', 'courses/cours_fatou/prive/depart',
    ]) {
      await assertSucceeds(getDoc(doc(db, chemin)));
    }
  });

  test('le chauffeur d\'une course en cours lit la course, le départ exact et le profil du client', async () => {
    const db = en('moussa');
    for (const chemin of ['courses/cours_fatou', 'courses/cours_fatou/prive/depart', 'profils_publics/fatou']) {
      await assertSucceeds(getDoc(doc(db, chemin)));
    }
  });

  test('le client suit la position de son chauffeur pendant la course', async () => {
    await assertSucceeds(getDoc(doc(en('fatou'), 'positions_chauffeurs', 'moussa')));
  });

  test('un chauffeur validé voit les courses en attente (le radar) ; un administrateur voit tout', async () => {
    await assertSucceeds(getDocs(query(collection(en('moussa'), 'courses'), where('statut', '==', 'en_attente'))));
    for (const chemin of ['users/fatou', 'journal_admin/j1', 'portefeuilles/fatou', 'retraits/r1']) {
      await assertSucceeds(getDoc(doc(en('admin'), chemin)));
    }
  });

  test('un message normal dans une conversation ouverte part ; la préférence « payer avec mon solde » aussi', async () => {
    await assertSucceeds(ajouterMessage());
    await assertSucceeds(updateDoc(doc(en('fatou'), 'portefeuilles', 'fatou'), { payerAvecSolde: true }));
  });

  test('une inscription et un envoi de pièce, comme le fait l\'app', async () => {
    await assertSucceeds(setDoc(doc(en('inscrit'), 'users', 'inscrit'), {
      role: 'client', nom: 'Ali', email: 'inscrit@test.sn', telephone: '+221771111111', statut: 'ACTIF', creeLe: serverTimestamp(),
    }));
    await assertSucceeds(updateDoc(doc(en('ibou'), 'users', 'ibou'), { 'documents.permis': adresseStorage, statutValidation: 'en_attente' }));
  });

  test('un chauffeur actif compte ses minutes en ligne', async () => {
    await assertSucceeds(updateDoc(doc(en('moussa'), 'temps_en_ligne', 'moussa_2026-09-27'), {
      secondes: 660, majLe: serverTimestamp(),
    }));
  });
});

famille('un client contre les données d\'un autre client (BOLA / IDOR)', [
  ['lit la course d\'un autre client', () => getDoc(doc(en('awa'), 'courses', 'cours_fatou'))],
  ['liste les courses d\'un autre client (requête filtrée sur lui)', () => getDocs(query(collection(en('awa'), 'courses'), where('clientId', '==', 'fatou')))],
  ['liste toutes les courses (requête sans filtre)', () => getDocs(collection(en('awa'), 'courses'))],
  ['change le prix de la course d\'un autre client', () => updateDoc(doc(en('awa'), 'courses', 'cours_fatou'), { prixFcfa: 1 })],
  ['annule ou modifie le statut de la course d\'un autre client', () => updateDoc(doc(en('awa'), 'courses', 'attente_fatou'), { statut: 'annulee' })],
  ['lit la position exacte du départ d\'un autre client', () => getDoc(doc(en('awa'), 'courses', 'cours_fatou', 'prive', 'depart'))],
  ['lit la commande de paiement d\'un autre client', () => getDoc(doc(en('awa'), 'commandes', 'cmd_fatou'))],
  ['lit le portefeuille d\'un autre client', () => getDoc(doc(en('awa'), 'portefeuilles', 'fatou'))],
  ['lit le livre de comptes d\'un autre client', () => getDoc(doc(en('awa'), 'portefeuilles', 'fatou', 'mouvements', 'm1'))],
  ['lit les retraits d\'un autre client', () => getDoc(doc(en('awa'), 'retraits', 'r1'))],
  ['lit les recharges d\'un autre client', () => getDoc(doc(en('awa'), 'recharges', 'rch1'))],
  ['lit le profil privé d\'un autre client (téléphone, e-mail)', () => getDoc(doc(en('awa'), 'users', 'fatou'))],
  ['lit le profil public d\'un autre client', () => getDoc(doc(en('awa'), 'profils_publics', 'fatou'))],
  ['lit le ticket d\'aide d\'un autre client', () => getDoc(doc(en('awa'), 'tickets', 'aide_fatou'))],
  ['lit les messages du ticket d\'aide d\'un autre client', () => getDoc(doc(en('awa'), 'tickets', 'aide_fatou', 'messages', 't1'))],
  ['lit les jetons de notification d\'un autre client', () => getDoc(doc(en('awa'), 'appareils', 'fatou', 'jetons', 't1'))],
  ['lit la conversation d\'un autre client avec son chauffeur', () => getDoc(doc(en('awa'), 'chats', 'fatou_moussa'))],
  ['lit les messages d\'un autre client avec son chauffeur', () => getDocs(collection(en('awa'), 'chats', 'fatou_moussa', 'messages'))],
  ['lit la position du chauffeur d\'un autre client', () => getDoc(doc(en('awa'), 'positions_chauffeurs', 'moussa'))],
  ['lit l\'évaluation laissée par un autre client', () => getDoc(doc(en('awa'), 'evaluations', 'finie_fatou'))],
  ['écrit dans la conversation d\'un autre client', () => addDoc(collection(en('awa'), 'chats', 'fatou_moussa', 'messages'), { senderId: 'awa', text: 'x', timestamp: serverTimestamp() })],
  ['écrit un message dans le ticket d\'aide d\'un autre client', () => addDoc(collection(en('awa'), 'tickets', 'aide_fatou', 'messages'), {
    auteurId: 'awa', auteurRole: 'client', texte: 'x', creeLe: serverTimestamp(),
  })],
  ['modifie le profil privé d\'un autre client', () => updateDoc(doc(en('awa'), 'users', 'fatou'), { nom: 'Pirate' })],
  ['supprime le profil d\'un autre client', () => deleteDoc(doc(en('awa'), 'users', 'fatou'))],
  ['dépose ses jetons de notification chez un autre client', () => setDoc(doc(en('awa'), 'appareils', 'fatou', 'jetons', 'pirate'), { plateforme: 'android', majLe: serverTimestamp() })],
  ['supprime les jetons de notification d\'un autre client', () => deleteDoc(doc(en('awa'), 'appareils', 'fatou', 'jetons', 't1'))],
]);

famille('argent : ce qu\'un client ou un chauffeur tente d\'écrire lui-même', [
  ['s\'attribue un solde de 1 000 000 FCFA', () => updateDoc(doc(en('fatou'), 'portefeuilles', 'fatou'), { soldeFcfa: 1000000 })],
  ['crée son portefeuille avec un solde', () => setDoc(doc(en('awa'), 'portefeuilles', 'awa'), { soldeFcfa: 999999, payerAvecSolde: true })],
  ['modifie le solde en même temps que sa préférence', () => updateDoc(doc(en('fatou'), 'portefeuilles', 'fatou'), { payerAvecSolde: true, soldeFcfa: 999999 })],
  ['s\'ajoute un mouvement de recharge', () => setDoc(doc(en('fatou'), 'portefeuilles', 'fatou', 'mouvements', 'faux'), { type: 'recharge', montantFcfa: 100000 })],
  ['efface une ligne de son livre de comptes', () => deleteDoc(doc(en('fatou'), 'portefeuilles', 'fatou', 'mouvements', 'm1'))],
  ['crée elle-même une course à prix choisi', () => setDoc(doc(en('awa'), 'courses', 'gratuite'), { clientId: 'awa', statut: 'en_attente', prixFcfa: 1 })],
  ['crée une commande déjà « payée »', () => setDoc(doc(en('awa'), 'commandes', 'fausse'), { clientId: 'awa', statut: 'payee', prixFcfa: 1 })],
  ['crée une recharge déjà « réussie »', () => setDoc(doc(en('awa'), 'recharges', 'fausse'), { clientId: 'awa', statut: 'reussie', montantFcfa: 100000 })],
  ['crée un retrait à son nom', () => setDoc(doc(en('fatou'), 'retraits', 'faux'), { clientId: 'fatou', montantFcfa: 50000 })],
  ['modifie le montant de son retrait', () => updateDoc(doc(en('fatou'), 'retraits', 'r1'), { montantFcfa: 999999 })],
  ['baisse le prix de sa course (chauffeur)', () => updateDoc(doc(en('moussa'), 'courses', 'cours_fatou'), { prixFcfa: 1 })],
  ['termine sa course avec une commission de 0 (chauffeur)', () => updateDoc(doc(en('moussa'), 'courses', 'cours_fatou'), { statut: 'terminee', termineeLe: serverTimestamp(), commissionFcfa: 0 })],
  ['termine sa course avec une fausse heure de fin (chauffeur)', () => updateDoc(doc(en('moussa'), 'courses', 'cours_fatou'), { statut: 'terminee', termineeLe: new Date('2030-01-01'), commissionFcfa: 230 })],
  ['s\'écrit un règlement de 100 000 FCFA (chauffeur)', () => setDoc(doc(en('moussa'), 'reglements', 'r'), { chauffeurId: 'moussa', montantFcfa: 100000, sens: 'plateforme_vers_chauffeur', creeLe: serverTimestamp() })],
  ['modifie un règlement existant (chauffeur)', () => updateDoc(doc(en('moussa'), 'reglements', 'reg1'), { montantFcfa: 999999 })],
  ['lit les règlements d\'un autre chauffeur', () => getDoc(doc(en('ibou'), 'reglements', 'reg1'))],
  ['change le montant d\'une commande payée', () => updateDoc(doc(en('fatou'), 'commandes', 'cmd_fatou'), { prixFcfa: 1 })],
]);

famille('élévation de privilèges', [
  ['un client se déclare admin', () => updateDoc(doc(en('awa'), 'users', 'awa'), { role: 'admin' })],
  ['un client se déclare chauffeur', () => updateDoc(doc(en('awa'), 'users', 'awa'), { role: 'conducteur' })],
  ['un dossier en attente se déclare validé', () => updateDoc(doc(en('ibou'), 'users', 'ibou'), { statutValidation: 'valide' })],
  ['un dossier en attente se déclare validé (estValide)', () => updateDoc(doc(en('ibou'), 'users', 'ibou'), { estValide: true })],
  ['un chauffeur suspendu lève sa suspension', () => updateDoc(doc(en('suspendu'), 'users', 'suspendu'), { statutCompte: 'actif' })],
  ['un client se déclare testeur Orange Money', () => updateDoc(doc(en('awa'), 'users', 'awa'), { testeurOrangeMoney: true })],
  ['un inconnu crée un compte admin', () => setDoc(doc(en('nouveau'), 'users', 'nouveau'), { role: 'admin', email: 'nouveau@test.sn' })],
  ['un inconnu s\'inscrit avec un solde', () => setDoc(doc(en('nouveau'), 'users', 'nouveau'), { role: 'client', email: 'nouveau@test.sn', soldeFcfa: 100000 })],
  ['un inconnu s\'inscrit déjà validé', () => setDoc(doc(en('nouveau'), 'users', 'nouveau'), { role: 'conducteur', email: 'nouveau@test.sn', estValide: true })],
  ['un inconnu s\'inscrit avec un dossier validé', () => setDoc(doc(en('nouveau'), 'users', 'nouveau'), { role: 'conducteur', email: 'nouveau@test.sn', statutValidation: 'valide' })],
  ['un inconnu crée le profil de quelqu\'un d\'autre', () => setDoc(doc(en('nouveau'), 'users', 'victime'), { role: 'client', email: 'nouveau@test.sn' })],
  ['un client écrit le profil public d\'un chauffeur (« disponible »)', () => updateDoc(doc(en('awa'), 'profils_publics', 'moussa'), { disponible: true })],
  ['un client se publie un profil public de chauffeur', () => setDoc(doc(en('awa'), 'profils_publics', 'awa'), { nom: 'Awa', telephone: '+221770000001', role: 'conducteur' })],
  ['un client pose une note de 5 étoiles sur un chauffeur', () => updateDoc(doc(en('awa'), 'profils_publics', 'moussa'), { noteSomme: 500, noteNombre: 100 })],
  ['un client lit la configuration du serveur', () => getDoc(doc(en('awa'), 'config', 'paiementSimule'))],
  ['un client écrit la configuration du serveur', () => setDoc(doc(en('awa'), 'config', 'paiementSimule'), { secret: 'y' })],
  ['un client lit le journal des actions de l\'Admin', () => getDoc(doc(en('awa'), 'journal_admin', 'j1'))],
  ['un client écrit dans le journal des actions de l\'Admin', () => setDoc(doc(en('awa'), 'journal_admin', 'faux'), { action: 'ajustement' })],
  ['un client lit les compteurs de contrôle des Admin', () => getDoc(doc(en('awa'), 'controle_admin', 'admin_2026-11-13'))],
  ['un client écrit un compteur de contrôle des Admin', () => setDoc(doc(en('awa'), 'controle_admin', 'faux_2026-11-13'), { creditsFcfa: 0 })],
  ['un Admin remet à zéro son compteur du jour depuis l\'app (le serveur seul l\'écrit)', () => setDoc(doc(en('admin'), 'controle_admin', 'admin_2026-11-13'), { creditsFcfa: 0, operations: 0 })],
  ['un Admin efface une ligne du journal de ses actions depuis l\'app', () => deleteDoc(doc(en('admin'), 'journal_admin', 'j1'))],
  ['un Admin réécrit une ligne du journal de ses actions depuis l\'app', () => updateDoc(doc(en('admin'), 'journal_admin', 'j1'), { action: 'rien' })],
  ['un client se fait passer pour l\'Admin dans un ticket', () => addDoc(collection(en('fatou'), 'tickets', 'aide_fatou', 'messages'), {
    auteurId: 'fatou', auteurRole: 'admin', texte: 'Remboursement accordé', creeLe: serverTimestamp(),
  })],
  ['un client se crée une liaison avec un chauffeur (pour lire son profil et lui écrire)', () => setDoc(doc(en('awa'), 'liaisons', 'awa_moussa'), {
    clientId: 'awa', chauffeurId: 'moussa', courseId: 'cours_fatou', creeLe: serverTimestamp(),
  })],
  ['un chauffeur se crée une liaison avec un client dont la course n\'est pas la sienne', () => setDoc(doc(en('moussa'), 'liaisons', 'awa_moussa'), {
    clientId: 'awa', chauffeurId: 'moussa', courseId: 'attente_fatou', creeLe: serverTimestamp(),
  })],
  ['un dossier en attente prend une course', () => updateDoc(doc(en('ibou'), 'courses', 'attente_fatou'), { statut: 'acceptee', chauffeurId: 'ibou' })],
  ['un chauffeur suspendu prend une course', () => updateDoc(doc(en('suspendu'), 'courses', 'attente_fatou'), { statut: 'acceptee', chauffeurId: 'suspendu' })],
  ['un chauffeur prend une course au nom d\'un autre', () => updateDoc(doc(en('moussa'), 'courses', 'attente_fatou'), { statut: 'acceptee', chauffeurId: 'ibou' })],
  ['un chauffeur prend une course et change son prix', () => updateDoc(doc(en('moussa'), 'courses', 'attente_fatou'), { statut: 'acceptee', chauffeurId: 'moussa', prixFcfa: 1 })],
  ['un chauffeur termine la course d\'un autre', () => updateDoc(doc(en('ibou'), 'courses', 'cours_fatou'), { statut: 'terminee', termineeLe: serverTimestamp(), commissionFcfa: 230 })],
]);

famille('aspiration de masse (listes complètes, annuaires, positions)', [
  ['non connecté : liste des utilisateurs', () => getDocs(collection(anonyme(), 'users'))],
  ['non connecté : liste des profils publics', () => getDocs(collection(anonyme(), 'profils_publics'))],
  ['non connecté : liste des courses', () => getDocs(collection(anonyme(), 'courses'))],
  ['non connecté : positions des chauffeurs', () => getDocs(collection(anonyme(), 'positions_chauffeurs'))],
  ['non connecté : annuaire des téléphones', () => getDocs(collection(anonyme(), 'annuaire_telephones'))],
  ['non connecté : lecture d\'un profil public', () => getDoc(doc(anonyme(), 'profils_publics', 'moussa'))],
  ['non connecté : recherche d\'un numéro de téléphone', () => getDocs(query(collection(anonyme(), 'users'), where('telephone', '==', '+221770000002')))],
  ['client : liste des profils publics', () => getDocs(collection(en('awa'), 'profils_publics'))],
  ['client : liste des positions des chauffeurs', () => getDocs(collection(en('awa'), 'positions_chauffeurs'))],
  ['client : un numéro de l\'annuaire de connexion', () => getDoc(doc(en('awa'), 'annuaire_telephones', 'client_+221770000002'))],
  ['client : liste de l\'annuaire de connexion', () => getDocs(collection(en('awa'), 'annuaire_telephones'))],
  ['client : liste de tous les utilisateurs', () => getDocs(collection(en('awa'), 'users'))],
  ['client : courses en attente de tous les clients', () => getDocs(query(collection(en('awa'), 'courses'), where('statut', '==', 'en_attente')))],
  ['client : tous les tickets d\'aide', () => getDocs(collection(en('awa'), 'tickets'))],
  ['client : tous les retraits', () => getDocs(collection(en('awa'), 'retraits'))],
  ['client : toutes les conversations', () => getDocs(collection(en('awa'), 'chats'))],
  ['client : toutes les évaluations', () => getDocs(collection(en('awa'), 'evaluations'))],
  ['dossier en attente : courses en attente', () => getDocs(query(collection(en('ibou'), 'courses'), where('statut', '==', 'en_attente')))],
  ['chauffeur suspendu : courses en attente', () => getDocs(query(collection(en('suspendu'), 'courses'), where('statut', '==', 'en_attente')))],
  ['chauffeur validé : positions de ses collègues', () => getDocs(collection(en('moussa'), 'positions_chauffeurs'))],
  ['chauffeur validé : liste des profils publics', () => getDocs(collection(en('moussa'), 'profils_publics'))],
  ['chauffeur validé : liste des utilisateurs', () => getDocs(collection(en('moussa'), 'users'))],
  ['chauffeur validé : position exacte du départ d\'une course en attente', () => getDoc(doc(en('moussa'), 'courses', 'attente_fatou', 'prive', 'depart'))],
  ['chauffeur validé : départ exact d\'une course terminée (il perd l\'accès à la fin)', () => getDoc(doc(en('moussa'), 'courses', 'finie_fatou', 'prive', 'depart'))],
  ['chauffeur validé : profil d\'un client sans course en cours avec lui', () => getDoc(doc(en('moussa'), 'profils_publics', 'awa'))],
]);

famille('abus de taille et de volume (phase B)', [
  ['un client crée un compteur de temps en ligne', () => setDoc(doc(en('awa'), 'temps_en_ligne', 'awa_1999-01-01'), { chauffeurId: 'awa', date: '1999-01-01', secondes: 60, majLe: serverTimestamp() })],
  ['un client crée un second compteur à une autre date', () => setDoc(doc(en('awa'), 'temps_en_ligne', 'awa_2000-01-01'), { chauffeurId: 'awa', date: '2000-01-01', secondes: 60, majLe: serverTimestamp() })],
  ['un dossier en attente crée un compteur de temps en ligne', () => setDoc(doc(en('ibou'), 'temps_en_ligne', 'ibou_2026-09-27'), { chauffeurId: 'ibou', date: '2026-09-27', secondes: 60, majLe: serverTimestamp() })],
  ['un chauffeur suspendu compte ses minutes en ligne', () => setDoc(doc(en('suspendu'), 'temps_en_ligne', 'suspendu_2026-09-27'), { chauffeurId: 'suspendu', date: '2026-09-27', secondes: 60, majLe: serverTimestamp() })],
  ['un chauffeur gonfle son temps en ligne d\'une heure d\'un coup', () => updateDoc(doc(en('moussa'), 'temps_en_ligne', 'moussa_2026-09-28'), { secondes: 4200, majLe: serverTimestamp() })],
  ['un client écrit un champ « documents » de 500 Ko dans son profil', () => updateDoc(doc(en('awa'), 'users', 'awa'), { documents: { permis: GROS } })],
  ['un dossier en attente envoie une pièce de 500 Ko qui n\'est pas une image', () => updateDoc(doc(en('ibou'), 'users', 'ibou'), { 'documents.permis': GROS, statutValidation: 'en_attente' })],
  ['un dossier en attente envoie une pièce hébergée ailleurs que dans Storage', () => updateDoc(doc(en('ibou'), 'users', 'ibou'), { 'documents.permis': 'https://pirate.example/pixel.gif', statutValidation: 'en_attente' })],
  ['un dossier en attente envoie une pièce sous un nom inconnu', () => updateDoc(doc(en('ibou'), 'users', 'ibou'), { 'documents.pirate': adresseStorage, statutValidation: 'en_attente' })],
  ['un chauffeur envoie un message de 500 Ko', () => ajouterMessage({ text: GROS })],
  ['un chauffeur envoie un message de 2001 signes', () => ajouterMessage({ text: 'x'.repeat(2001) })],
  ['un chauffeur envoie un message daté de 2099', () => ajouterMessage({ timestamp: new Date('2099-01-01T00:00:00Z') })],
  ['un chauffeur envoie un message dont le texte est un objet', () => ajouterMessage({ text: { a: 1 } })],
  ['un chauffeur envoie un message avec un champ en plus', () => ajouterMessage({ pieceJointe: 'x' })],
  ['un chauffeur écrit un message au nom du client', () => ajouterMessage({ senderId: 'fatou' })],
  ['un chauffeur écrit un « dernier message » de 500 Ko', () => setDoc(doc(en('moussa'), 'chats', 'fatou_moussa'), { participants: ['fatou', 'moussa'], dernierMessage: GROS }, { merge: true })],
  ['un chauffeur ajoute un intrus aux participants d\'une conversation', () => setDoc(doc(en('moussa'), 'chats', 'fatou_moussa'), { participants: ['moussa', 'awa'] }, { merge: true })],
  ['une inscription avec un nom de 500 Ko', () => setDoc(doc(en('nouveau'), 'users', 'nouveau'), { role: 'client', nom: GROS, email: 'nouveau@test.sn', telephone: '+221771111111' })],
  ['une inscription avec un téléphone de 500 Ko', () => setDoc(doc(en('nouveau'), 'users', 'nouveau'), { role: 'client', nom: 'Ali', email: 'nouveau@test.sn', telephone: GROS })],
  ['une inscription avec un statut de 500 Ko', () => setDoc(doc(en('nouveau'), 'users', 'nouveau'), { role: 'client', nom: 'Ali', email: 'nouveau@test.sn', statut: GROS })],
  ['un profil dont le nom passe à 500 Ko', () => updateDoc(doc(en('awa'), 'users', 'awa'), { nom: GROS })],
  ['un profil dont le téléphone passe à 500 Ko', () => updateDoc(doc(en('awa'), 'users', 'awa'), { telephone: GROS })],
  ['un profil public avec un téléphone de 500 Ko', () => updateDoc(doc(en('awa'), 'profils_publics', 'awa'), { telephone: GROS })],
  ['un chauffeur publie une position hors du globe', () => setDoc(doc(en('moussa'), 'positions_chauffeurs', 'moussa'), { latitude: 200, longitude: 0, majLe: serverTimestamp() })],
  ['un chauffeur publie une position datée du futur', () => setDoc(doc(en('moussa'), 'positions_chauffeurs', 'moussa'), { latitude: 14.7, longitude: -17.4, majLe: new Date('2099-01-01') })],
  ['un dossier en attente publie une position', () => setDoc(doc(en('ibou'), 'positions_chauffeurs', 'ibou'), { latitude: 14.7, longitude: -17.4, majLe: serverTimestamp() })],
  ['un client publie la position d\'un chauffeur', () => setDoc(doc(en('awa'), 'positions_chauffeurs', 'moussa'), { latitude: 14.7, longitude: -17.4, majLe: serverTimestamp() })],
]);
