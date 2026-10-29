/**
 * Essai du PARCOURS COMPLET de Sprint contre le bac à sable RÉEL d'Orange
 * Money (données de test, aucun argent réel), sur l'émulateur Firestore :
 * aucune donnée de production, rien de publié. Lancé par le flux « Essai
 * Orange Money (bac à sable) » via `firebase emulators:exec` ; ce n'est pas
 * un test automatique (`npm test` ne le lance pas).
 *
 * Lit ORANGE_CLIENT_ID, ORANGE_CLIENT_SECRET et ORANGE_CODE_MARCHAND dans
 * l'environnement. Orange Money est ouvert pour l'essai seulement (le
 * serveur publié le refuse toujours). Étapes :
 *
 *   1. une course payée par Orange Money : demande de paiement chez Orange
 *      avec la vraie référence de la commande, commande en attente ;
 *   2. une recharge du portefeuille par Orange Money (référence « rch_… ») ;
 *   3. le lien de paiement : ce que répond la page d'Orange (statut HTTP,
 *      adresse et titre, sans le lien lui-même) ;
 *   4. la recherche chez Orange par référence : aucun paiement (personne n'a
 *      payé) ;
 *   5. la surveillance : les 2 demandes relues chez Orange, rien appliqué ;
 *   6. les notifications : sans la bonne clé, refusée (401) sans interroger
 *      Orange ; avec la clé mais une transaction inconnue d'Orange, relue chez
 *      Orange et rien appliqué (202) ;
 *   7. bilan : aucune course créée, aucun solde crédité.
 *
 * Rend une annotation GitHub par étape et n'affiche jamais les identifiants,
 * le jeton, le code marchand ni les liens de paiement (masqués dès lecture).
 */
import { randomBytes } from 'node:crypto';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { estimer } from '../src/commandes';
import { calculDistance } from '../src/distances';
import { FournisseurSimule } from '../src/fournisseurs';
import { ErreurOrangeMoney } from '../src/orange_money';
import {
  configurerOrange,
  FournisseurOrangeMoney,
  fournisseursDuMoyen,
  rattraperOrange,
  repondreNotificationOrange,
} from '../src/paiement_orange';
import { creerPaiement } from '../src/paiements';
import { creerRecharge } from '../src/portefeuille';

type Niveau = 'notice' | 'warning' | 'error';

/** Échappement des commandes de workflow GitHub (titre et message). */
const echapper = (texte: string, titre = false) => {
  const s = texte.replace(/%/g, '%25').replace(/\r/g, '%0D').replace(/\n/g, '%0A');
  return titre ? s.replace(/:/g, '%3A').replace(/,/g, '%2C') : s;
};
const annoncer = (niveau: Niveau, titre: string, message: string) =>
  console.log(`::${niveau} title=${echapper(titre, true)}::${echapper(message)}`);
const masquer = (...valeurs: Array<string | null | undefined>) => {
  for (const valeur of valeurs) if (valeur) console.log(`::add-mask::${valeur}`);
};
const raison = (e: unknown) => (e instanceof ErreurOrangeMoney ? e.message : `${(e as Error).name} : ${(e as Error).message}`);

const PLATEAU = { latitude: 14.6928, longitude: -17.4467 };
const ALMADIES = { latitude: 14.7456, longitude: -17.5134 };

/** Chaque saut de redirection du lien de paiement : statut et hôte seulement. */
async function explorerLien(lien: string): Promise<string> {
  const etapes: string[] = [];
  let adresse = lien;
  for (let saut = 0; saut < 5; saut++) {
    const url = new URL(adresse);
    if (url.protocol !== 'https:' && url.protocol !== 'http:') {
      etapes.push(`ouvre une app (${url.protocol})`);
      break;
    }
    const reponse = await fetch(url, { redirect: 'manual', signal: AbortSignal.timeout(15000) });
    const cible = reponse.headers.get('location');
    if (reponse.status >= 300 && reponse.status < 400 && cible) {
      etapes.push(`HTTP ${reponse.status} depuis ${url.host}`);
      adresse = new URL(cible, url).toString();
      masquer(adresse);
      continue;
    }
    const type = reponse.headers.get('content-type') ?? '?';
    let titre = '';
    if (type.includes('text/html')) {
      const html = (await reponse.text()).slice(0, 200_000);
      titre = (html.match(/<title[^>]*>([^<]{0,120})<\/title>/i)?.[1] ?? '').replace(/\s+/g, ' ').trim();
    }
    etapes.push(`HTTP ${reponse.status} depuis ${url.host} (${type.split(';')[0]}${titre ? `, titre « ${titre} »` : ''})`);
    break;
  }
  return etapes.join(' → ');
}

async function principal(): Promise<number> {
  const idClient = process.env.ORANGE_CLIENT_ID ?? '';
  const secretClient = process.env.ORANGE_CLIENT_SECRET ?? '';
  const codeMarchand = (process.env.ORANGE_CODE_MARCHAND ?? '').trim();
  masquer(idClient, secretClient, codeMarchand);
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    annoncer('error', 'Parcours', 'À lancer sur l\'émulateur Firestore (firebase emulators:exec) : jamais sur la vraie base.');
    return 1;
  }
  const config = configurerOrange({ idClient, secretClient, codeMarchand });
  if (config === null) {
    annoncer('error', 'Parcours', 'Identifiants de test ou code marchand (6 chiffres) manquants : parcours impossible.');
    return 1;
  }

  const app = initializeApp({ projectId: 'demo-sprint' });
  const db = getFirestore(app);
  let echecs = 0;
  const echec = (titre: string, message: string) => {
    echecs += 1;
    annoncer('error', titre, message);
  };
  try {
    const maintenant = new Date();
    await db.doc('users/client-essai').set({ role: 'client', nom: 'Client d\'essai' });
    // Le faux Wave ne sert qu'aux remboursements hors solde : jamais pour Orange Money.
    const simule = new FournisseurSimule(randomBytes(16).toString('hex'), 'https://essai.invalid/page');
    const fournisseurs = fournisseursDuMoyen(simule, () => new FournisseurOrangeMoney(config));
    const calcul = calculDistance(db, null, () => maintenant);

    // 1. Course payée par Orange Money (prix du serveur, sans Google : estimation).
    let commandeId = '';
    let lien = '';
    try {
      const trajet = { type: 'PASSAGER', depart: PLATEAU, arrivee: ALMADIES };
      const { prixFcfa } = await estimer(calcul, 'client-essai', trajet, maintenant);
      const r = await creerPaiement(
        db,
        calcul,
        fournisseurs,
        'client-essai',
        { ...trajet, adresseDepart: 'Plateau (essai)', adresseArrivee: 'Almadies (essai)', methodePaiement: 'ORANGE_MONEY', prixAttendu: prixFcfa },
        maintenant,
        undefined,
        'tous',
      );
      commandeId = r.commandeId;
      lien = r.lienPaiement ?? '';
      masquer(lien);
      const c = (await db.doc(`commandes/${commandeId}`).get()).data() ?? {};
      const ok = c.statut === 'en_attente_paiement' && c.fournisseur === 'orange_money' && c.sessionPaiementId === `om_${commandeId}`;
      (ok ? annoncer : echec)(
        ok ? 'notice' : 'error',
        '1. Course payée par Orange Money',
        `${ok ? 'Demande acceptée par Orange' : 'Commande inattendue'} : ${prixFcfa} FCFA, commande en attente de paiement, ` +
          `lien de paiement ${lien ? `reçu (${new URL(lien).host})` : 'absent'}, relecture prévue pendant 1 heure.`,
      );
    } catch (e) {
      echec('1. Course payée par Orange Money', raison(e));
    }

    // 2. Recharge du portefeuille par Orange Money.
    let rechargeId = '';
    try {
      const r = await creerRecharge(db, fournisseurs, 'client-essai', { montantFcfa: 500, methodePaiement: 'ORANGE_MONEY' }, maintenant, 'tous');
      rechargeId = r.rechargeId;
      masquer(r.lienPaiement);
      annoncer('notice', '2. Recharge par Orange Money', `Demande de 500 FCFA acceptée par Orange (référence « rch_… »), recharge en attente.`);
    } catch (e) {
      echec('2. Recharge par Orange Money', raison(e));
    }

    // 3. Ce que répond la page de paiement (le client n'y paie pas : rien n'est débité).
    if (lien) {
      try {
        annoncer('notice', '3. Lien de paiement', await explorerLien(lien));
      } catch (e) {
        annoncer('warning', '3. Lien de paiement', `Page injoignable depuis la CI : ${raison(e)}`);
      }
    }

    // 4. Recherche chez Orange par la référence de la commande.
    if (commandeId) {
      try {
        const trouvees = await config.client.rechercherTransactions({ reference: commandeId });
        annoncer('notice', '4. Recherche par référence', `Orange répond : ${trouvees.length} paiement(s) pour cette commande (0 attendu, personne n'a payé).`);
      } catch (e) {
        echec('4. Recherche par référence', raison(e));
      }
    }

    // 5. Surveillance : relecture des demandes sans nouvelles.
    try {
      const bilan = await rattraperOrange(db, config, simule, new Date());
      const attendu = (commandeId ? 1 : 0) + (rechargeId ? 1 : 0);
      const ok = bilan.verifiees === attendu && bilan.appliquees === 0 && bilan.erreurs === 0;
      (ok ? annoncer : echec)(
        ok ? 'notice' : 'error',
        '5. Surveillance',
        `${bilan.verifiees} demande(s) relue(s) chez Orange, ${bilan.appliquees} paiement(s) appliqué(s), ${bilan.erreurs} erreur(s).`,
      );
    } catch (e) {
      echec('5. Surveillance', raison(e));
    }

    // 6. Notifications : la clé d'abord, puis la relecture chez Orange.
    try {
      const cle = randomBytes(32).toString('hex');
      const corps = Buffer.from(
        JSON.stringify({
          transactionId: 'MP000000.0000.A00000',
          reference: commandeId || 'essai',
          status: 'SUCCESS',
          amount: { value: 100, unit: 'XOF' },
          type: 'MERCHANT_PAYMENT',
        }),
      );
      const notifier = (autorisation: string) =>
        repondreNotificationOrange(db, config, cle, { methode: 'POST', autorisation, corpsBrut: corps }, async () => simule, new Date());
      const fausse = await notifier('Basic une-fausse-cle');
      const inconnue = await notifier(`Basic ${cle}`);
      const ok = fausse.statut === 401 && inconnue.statut === 202 && inconnue.resultat === 'non_confirmee';
      (ok ? annoncer : echec)(
        ok ? 'notice' : 'error',
        '6. Notifications',
        `sans la bonne clé : HTTP ${fausse.statut} (refusée, Orange pas interrogé) · avec la clé, transaction inconnue d'Orange : ` +
          `HTTP ${inconnue.statut}, ${inconnue.resultat === 'non_confirmee' ? 'relue chez Orange, rien appliqué' : inconnue.resultat ?? inconnue.corps}.`,
      );
    } catch (e) {
      echec('6. Notifications', raison(e));
    }

    // 7. Bilan : rien n'a été payé, donc ni course ni crédit.
    const courses = (await db.collection('courses').get()).size;
    const solde = ((await db.doc('portefeuilles/client-essai').get()).get('soldeFcfa') as number | undefined) ?? 0;
    (courses === 0 && solde === 0 ? annoncer : echec)(
      courses === 0 && solde === 0 ? 'notice' : 'error',
      '7. Bilan',
      `${courses} course créée, solde ${solde} FCFA : rien n'est accordé sans paiement confirmé par Orange.`,
    );
  } finally {
    await deleteApp(app);
  }
  return echecs === 0 ? 0 : 1;
}

principal().then(
  (code) => {
    process.exitCode = code;
  },
  (e: unknown) => {
    annoncer('error', 'Parcours', `Erreur inattendue : ${(e as Error).message}`);
    process.exitCode = 1;
  },
);
