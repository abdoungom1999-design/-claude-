import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { setGlobalOptions } from 'firebase-functions/v2';
import { onCall, onRequest } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { defineSecret } from 'firebase-functions/params';
import { coordonneesAdresse as coordonneesCore, rechercherAdresses as rechercherCore } from './adresses';
import {
  ajusterPortefeuille as ajusterCore,
  rembourserCourseAdmin as rembourserCore,
  sanctionnerCompte as sanctionnerCore,
} from './admin';
import { estimer } from './commandes';
import { chauffeursProches as chauffeursProchesCore } from './proximite';
import { calculDistance } from './distances';
import { corpsWebhook, ErreurSignature, FournisseurSimule, signer, type FournisseurPaiement } from './fournisseurs';
import { ClientGoogle } from './google';
import {
  annulerCourse as annulerCourseCore,
  creerPaiement as creerPaiementCore,
  surveiller,
  traiterEvenement,
} from './paiements';
import {
  creerRecharge as creerRechargeCore,
  estReferenceRecharge,
  surveillerRecharges,
  traiterEvenementRecharge,
} from './portefeuille';
import { MessagerieFcm, notifierAcceptation as notifierAcceptationCore, notifierMessage as notifierMessageCore } from './notifications';
import { pageMessage, pagePaiement, secretSimulation } from './simulation';

// Région la plus proche de Dakar et de Firestore (eur3, voir
// FIREBASE_SETUP.md). À garder identique dans l'app (`FonctionsCloud`).
// maxInstances : plafond de coût en cas d'abus.
const REGION = 'europe-west1';
setGlobalOptions({ region: REGION, maxInstances: 10 });

initializeApp();

/** Envoi des notifications push (Firebase Cloud Messaging). */
const messagerie = new MessagerieFcm();

/** Clé Google Maps Platform (Places + Routes), dans Secret Manager. */
const cleGoogle = defineSecret('GOOGLE_MAPS_API_KEY');
const options = { secrets: [cleGoogle] };

function google(): ClientGoogle | null {
  const cle = cleGoogle.value().trim();
  return cle ? new ClientGoogle(cle) : null;
}

const distance = () => calculDistance(getFirestore(), google(), () => new Date());

/** Adresse publique des fonctions HTTP (émulateur ou Google Cloud). */
function urlFonction(nom: string): string {
  const projet = process.env.GCLOUD_PROJECT ?? JSON.parse(process.env.FIREBASE_CONFIG ?? '{}').projectId;
  return process.env.FUNCTIONS_EMULATOR === 'true'
    ? `http://127.0.0.1:5001/${projet}/${REGION}/${nom}`
    : `https://${REGION}-${projet}.cloudfunctions.net/${nom}`;
}

let simulation: Promise<FournisseurSimule> | undefined;

/**
 * Fournisseur de paiement en service. Aujourd'hui le faux Wave ; le vrai
 * ([FournisseurWave]) prendra sa place quand les clés marchandes seront
 * dans Secret Manager (WAVE_API_KEY, WAVE_WEBHOOK_SECRET).
 */
function fournisseur(): Promise<FournisseurPaiement> {
  simulation ??= secretSimulation(getFirestore())
    .then((secret) => new FournisseurSimule(secret, urlFonction('pagePaiementSimule')))
    .catch((e) => {
      simulation = undefined;
      throw e;
    });
  return simulation;
}

/** Prix d'un trajet, sur la distance par la route. */
export const estimerPrix = onCall(options, (requete) =>
  estimer(distance(), requete.auth?.uid, requete.data, new Date()),
);

/**
 * Demande de paiement : prix recalculé par le serveur, commande en
 * attente et lien de paiement. La course n'existera qu'une fois le
 * paiement confirmé par le fournisseur (webhookPaiement).
 */
export const creerPaiement = onCall(options, async (requete) =>
  creerPaiementCore(getFirestore(), distance(), await fournisseur(), requete.auth?.uid, requete.data, new Date(), messagerie),
);

/**
 * Portefeuille : demande de recharge (Wave ou Orange Money). Le solde n'est
 * crédité que par le webhook signé du fournisseur, jamais par l'app.
 */
export const creerRecharge = onCall(async (requete) =>
  creerRechargeCore(getFirestore(), await fournisseur(), requete.auth?.uid, requete.data, new Date()),
);

/** Confirmation signée du fournisseur de paiement. */
export const webhookPaiement = onRequest(async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).send('POST uniquement.');
    return;
  }
  try {
    const f = await fournisseur();
    let evenement;
    try {
      evenement = f.lireWebhook(req.rawBody ?? Buffer.alloc(0), req.get('wave-signature'), new Date());
    } catch (e) {
      if (e instanceof ErreurSignature) {
        logger.warn('Webhook refusé', { raison: e.message });
        res.status(401).send('Signature invalide.');
        return;
      }
      throw e;
    }
    // Les recharges du portefeuille ("rch_…") ont leur propre traitement.
    const resultat = estReferenceRecharge(evenement.commandeId)
      ? await traiterEvenementRecharge(getFirestore(), evenement, new Date())
      : await traiterEvenement(getFirestore(), f, evenement, new Date(), messagerie);
    logger.info('Webhook de paiement', { reference: evenement.commandeId, resultat });
    res.status(200).json({ resultat });
  } catch (e) {
    // 500 : le fournisseur renverra l'événement plus tard.
    logger.error('Webhook de paiement en erreur', e);
    res.status(500).send('Erreur interne.');
  }
});

const MESSAGES_RESULTAT: Record<string, [string, string]> = {
  course_creee: ['Paiement accepté', 'Merci ! Retournez sur Sprint : votre demande est envoyée aux chauffeurs.'],
  echec_enregistre: ['Paiement refusé', 'Aucune course n’a été commandée. Retournez sur Sprint.'],
  rembourse: ['Demande expirée', 'Le délai de paiement était dépassé : vous avez été remboursé. Recommandez depuis Sprint.'],
  deja_traite: ['Paiement déjà traité', 'Cette demande de paiement a déjà été traitée. Retournez sur Sprint.'],
  recharge_creditee: ['Recharge effectuée', 'Merci ! Votre portefeuille Sprint a été crédité. Retournez sur Sprint.'],
  echec_enregistre_recharge: ['Recharge refusée', 'Votre portefeuille n’a pas été crédité. Retournez sur Sprint.'],
  anomalie: ['Paiement à vérifier', 'Le paiement n’a pas pu être validé. Contactez le support Sprint.'],
};

/**
 * Page de paiement du faux Wave : le client y choisit "Payer" ou
 * "Refuser" ; elle envoie alors au webhook un événement signé, exactement
 * comme Wave. Aucune somme réelle.
 */
export const pagePaiementSimule = onRequest(async (req, res) => {
  res.set({ 'Cache-Control': 'no-store', 'X-Frame-Options': 'DENY', 'Content-Type': 'text/html; charset=utf-8' });
  const envoyer = (statut: number, html: string) => {
    res.status(statut).send(html);
  };
  const session = String((req.method === 'POST' ? req.body?.session : req.query.session) ?? '');
  if (!/^sim_[0-9a-f]{24}$/.test(session) || (req.method !== 'GET' && req.method !== 'POST')) {
    envoyer(400, pageMessage('Lien invalide', 'Ce lien de paiement est invalide.'));
    return;
  }
  try {
    const db = getFirestore();
    const trouvees = await db.collection('commandes').where('sessionPaiementId', '==', session).limit(1).get();
    let commande = trouvees.docs[0];
    let recharge = false;
    if (!commande) {
      const recharges = await db.collection('recharges').where('sessionPaiementId', '==', session).limit(1).get();
      commande = recharges.docs[0];
      recharge = true;
    }
    if (!commande) {
      envoyer(404, pageMessage('Lien invalide', 'Cette demande de paiement est introuvable.'));
      return;
    }
    const c = commande.data();
    const montantFcfa: number = recharge ? c.montantFcfa : c.prixFcfa;
    if (req.method === 'GET') {
      envoyer(200, pagePaiement(session, {
        prixFcfa: montantFcfa,
        adresseDepart: recharge ? 'Recharge du portefeuille Sprint' : c.adresseDepart,
        adresseArrivee: recharge ? '' : c.adresseArrivee,
        statut: recharge ? (c.statut === 'en_attente' ? 'en_attente_paiement' : c.statut) : c.statut,
        methodePaiement: c.methodePaiement,
      }));
      return;
    }

    const payer = req.body?.choix === 'payer';
    const corps = corpsWebhook(session, commande.id, payer, montantFcfa);
    const secret = await secretSimulation(db);
    const reponse = await fetch(urlFonction('webhookPaiement'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Wave-Signature': signer(corps, secret, new Date()) },
      body: corps,
      signal: AbortSignal.timeout(15000),
    });
    if (!reponse.ok) throw new Error(`webhook ${reponse.status}`);
    const { resultat } = (await reponse.json()) as { resultat: string };
    const cle = recharge && resultat === 'echec_enregistre' ? 'echec_enregistre_recharge' : resultat;
    const [titre, message] = MESSAGES_RESULTAT[cle] ?? MESSAGES_RESULTAT.anomalie;
    envoyer(200, pageMessage(titre, message));
  } catch (e) {
    logger.error('Page de paiement simulée en erreur', e);
    envoyer(500, pageMessage('Erreur', 'Le paiement n’a pas pu être traité. Réessayez depuis Sprint.'));
  }
});

/** Annulation par le client (en attente) ou le chauffeur (avec motif), puis remboursement. */
export const annulerCourse = onCall(async (requete) =>
  annulerCourseCore(getFirestore(), await fournisseur(), requete.auth?.uid, requete.data, new Date(), messagerie),
);

/** Admin : remboursement intégral d'une course (support). */
export const rembourserCourseAdmin = onCall(async (requete) =>
  rembourserCore(getFirestore(), await fournisseur(), requete.auth?.uid, requete.data, new Date()),
);

/** Admin : crédit ou débit manuel du portefeuille d'un client (motivé, journalisé). */
export const ajusterPortefeuille = onCall(async (requete) =>
  ajusterCore(getFirestore(), requete.auth?.uid, requete.data, new Date()),
);

/** Admin : suspension, bannissement ou réactivation d'un compte. */
export const sanctionnerCompte = onCall(async (requete) =>
  sanctionnerCore(getFirestore(), await fournisseur(), requete.auth?.uid, requete.data, new Date()),
);

/** Paiements jamais finalisés et courses restées sans chauffeur. */
export const surveillerCommandes = onSchedule(
  { schedule: 'every 5 minutes', timeZone: 'Africa/Dakar', retryCount: 0 },
  async () => {
    const bilan = await surveiller(getFirestore(), await fournisseur(), new Date(), messagerie);
    const rechargesExpirees = await surveillerRecharges(getFirestore(), new Date());
    if (bilan.expirees || bilan.sansChauffeur || rechargesExpirees) {
      logger.info('Surveillance des commandes', { ...bilan, rechargesExpirees });
    }
  },
);

/** Autocomplétion d'adresses (Google Places). */
export const rechercherAdresses = onCall(options, (requete) =>
  rechercherCore(google(), requete.auth?.uid, requete.data),
);

/** Coordonnées de l'adresse choisie (Google Places). */
export const coordonneesAdresse = onCall(options, (requete) =>
  coordonneesCore(google(), requete.auth?.uid, requete.data),
);

/** Accueil client : chauffeurs disponibles alentour, anonymes et arrondis à 150 m. */
export const chauffeursProches = onCall((requete) =>
  chauffeursProchesCore(getFirestore(), requete.auth?.uid, requete.data, new Date()),
);

/** Push : prévient l'autre partie d'un message qui vient d'être envoyé (texte relu côté serveur). */
export const notifierMessage = onCall((requete) =>
  notifierMessageCore(getFirestore(), messagerie, requete.auth?.uid, requete.data, new Date()),
);

/** Push : prévient le client que son chauffeur a accepté la course. */
export const notifierAcceptation = onCall((requete) =>
  notifierAcceptationCore(getFirestore(), messagerie, requete.auth?.uid, requete.data, new Date()),
);
