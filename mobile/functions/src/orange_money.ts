import { createHash, timingSafeEqual } from 'node:crypto';

/**
 * Client de l'API Orange Money de Sonatel (portail
 * https://developer.orange-sonatel.com, spécification OpenAPI « Orange Money
 * API » v1.1.0 du 22 octobre 2026, transmise par le client).
 *
 * Branché aux paiements par `paiement_orange.ts`, ouvert selon
 * `methodes_paiement.ts` (qui y a accès, et dans quel environnement). Sert
 * aussi aux essais réels du flux « Essai Orange Money »
 * (`test/orange_money.essai_reel.ts`, `test/orange_money.parcours_reel.ts`).
 *
 * - Jeton OAuth 2.0 (« client credentials ») : `POST /oauth/v1/token`, en
 *   formulaire. Gardé jusqu'à une minute avant son expiration, renouvelé une
 *   fois si l'API répond 401.
 * - Paiement : `POST /api/eWallet/v4/qrcode` rend un QR code et les liens qui
 *   ouvrent Max It ou Orange Money. Le paiement est asynchrone : Orange
 *   notifie l'adresse `X-Callback-Url` (ou celle enregistrée par
 *   `POST /api/notification/v1/merchantcallback`).
 * - Notification : authentifiée par « Authorization: Basic {apiKey} », un
 *   secret partagé que nous choisissons à l'enregistrement. L'en-tête
 *   `X-Sonatel-Signature` est annoncé mais son calcul n'est pas documenté :
 *   on ne fait donc jamais confiance au seul contenu d'une notification, on
 *   relit le statut auprès d'Orange ([ClientOrangeMoney.statutTransaction])
 *   avant de considérer un paiement comme reçu.
 *
 * Aucun secret (identifiants, jeton, clé de notification) n'apparaît jamais
 * dans un message d'erreur.
 */

export const URL_ORANGE_MONEY = {
  /** Données de test seulement, limité à 60 requêtes par minute. */
  bacASable: 'https://api.sandbox.orange-sonatel.com',
  /** Argent réel. */
  production: 'https://api.orange-sonatel.com',
} as const;

/** Statuts d'une transaction (`GET /api/eWallet/v1/transactions/{id}/status`). */
export const STATUTS_TRANSACTION = [
  'ACCEPTED',
  'CANCELLED',
  'FAILED',
  'INITIATED',
  'PENDING',
  'PRE_INITIATED',
  'REJECTED',
  'SUCCESS',
] as const;
export type StatutTransaction = (typeof STATUTS_TRANSACTION)[number];

/** Validité maximale d'un QR code acceptée par Orange (24 h). */
export const VALIDITE_MAX_SECONDES = 86400;

export class ErreurOrangeMoney extends Error {
  constructor(
    message: string,
    /** Statut HTTP renvoyé par Orange (absent si Orange était injoignable). */
    readonly statutHttp?: number,
    /** Code d'erreur métier d'Orange (ex. « 2000 », « 4004 »). */
    readonly code?: string,
  ) {
    super(message);
  }
}

/** Notification refusée : authentification absente ou fausse, ou contenu illisible. */
export class ErreurNotificationOrange extends Error {}

export interface QrCodeOrangeMoney {
  qrId?: string;
  /** Lien qui ouvre Max It sur le paiement. */
  lienMaxIt?: string;
  /** Lien qui ouvre l'app Orange Money sur le paiement. */
  lienOrangeMoney?: string;
  /** Lien court vers la page de paiement. */
  lienCourt?: string;
  /** Image PNG du QR code, en Base64. */
  imageBase64?: string;
  validiteSecondes?: number;
  /** Fin de validité (date ISO). */
  finValidite?: string;
}

export interface DemandeQrCode {
  /** Code marchand à 6 chiffres. */
  codeMarchand: string;
  /** Nom affiché au client. */
  nomMarchand: string;
  montantFcfa: number;
  /** Notre référence (renvoyée telle quelle dans la notification). */
  reference: string;
  /** Durée de validité du QR code ; 15 minutes par défaut. */
  validiteSecondes?: number;
  /** Adresse HTTPS de notification, pour ce paiement seulement. */
  urlNotification?: string;
  /** Pages où renvoyer le client après un paiement réussi ou annulé. */
  urlSucces?: string;
  urlAnnulation?: string;
  /** Au plus 10 couples clé/valeur texte. */
  metadonnees?: Record<string, string>;
  /** Un seul paiement possible avec ce QR code (vrai par défaut). */
  usageUnique?: boolean;
}

export interface NotificationOrangeMoney {
  transactionId: string;
  /** Notre référence, renvoyée par Orange. */
  reference?: string;
  /** Seul `SUCCESS` vaut paiement, et seulement après relecture du statut. */
  statut: 'SUCCESS' | 'FAILED';
  montantFcfa: number;
  /** Code marchand payé. */
  codeMarchand?: string;
  /** `MERCHANT_PAYMENT`, `WEB_PAYMENT` ou `CASHIN`. */
  type: string;
}

/** Transaction telle qu'Orange l'a enregistrée (recherche) : c'est elle qui fait foi. */
export interface TransactionOrangeMoney {
  transactionId: string;
  /** Notre référence (commande ou recharge). */
  reference?: string;
  statut?: StatutTransaction;
  montantFcfa?: number;
  devise?: string;
  /** Code marchand payé. */
  codeMarchand?: string;
  /** `MERCHANT_PAYMENT`, `WEB_PAYMENT` ou `CASHIN`. */
  type?: string;
}

export interface CarteSimDeTest {
  numero: string;
  codePin?: string;
  /** `MERCHANT`, `RETAILER`, `CUSTOMER` ou `HYBRID`. */
  type?: string;
  expireLe?: string;
}

export interface ClePublique {
  cle: string;
  idCle: string;
  tailleBits: number;
}

export interface NotificationEnregistree {
  codeMarchand: string;
  nom?: string;
  url: string;
}

export interface OptionsClientOrangeMoney {
  urlBase: string;
  idClient: string;
  secretClient: string;
  fetcher?: typeof fetch;
  /** Horloge en millisecondes (tests). */
  maintenant?: () => number;
  /** Délai maximal d'une requête ; 15 s par défaut. */
  delaiMs?: number;
}

const CODE_MARCHAND = /^\d{6}$/;
/** Identifiant de transaction Orange (ex. « MP220928.1029.C58502 »). */
const ID_TRANSACTION = /^[A-Za-z0-9.]{1,40}$/;
/** Nos références (commandes : 24 caractères hexadécimaux ; recharges : « rch_… ») ; 50 au plus chez Orange. */
const REFERENCE = /^[A-Za-z0-9_-]{1,50}$/;

const texte = (v: unknown): string | undefined => (typeof v === 'string' && v.length > 0 ? v : undefined);
const nombre = (v: unknown): number | undefined => (typeof v === 'number' && Number.isFinite(v) ? v : undefined);

/** Erreur lisible tirée d'une réponse d'Orange (RFC 7807 ou erreur OAuth). */
export async function erreurDepuisReponse(reponse: Response): Promise<ErreurOrangeMoney> {
  const corps = (await reponse.json().catch(() => ({}))) as Record<string, unknown>;
  const code = texte(corps.code) ?? (typeof corps.code === 'number' ? String(corps.code) : undefined) ?? texte(corps.error);
  const detail = texte(corps.detail) ?? texte(corps.error_description) ?? texte(corps.title);
  const violations = Array.isArray(corps.violations)
    ? corps.violations
        .map((v) => {
          const violation = v as Record<string, unknown>;
          return [texte(violation.field), texte(violation.message)].filter(Boolean).join(' : ');
        })
        .filter(Boolean)
    : [];
  let message = `Orange Money a répondu ${reponse.status}`;
  if (code !== undefined) message += ` (code ${code})`;
  if (detail !== undefined) message += ` : ${detail}`;
  if (violations.length > 0) message += ` [${violations.join(' ; ')}]`;
  return new ErreurOrangeMoney(message.endsWith('.') ? message : `${message}.`, reponse.status, code);
}

export class ClientOrangeMoney {
  private jetonEnCache?: { valeur: string; expireA: number };
  private readonly fetcher: typeof fetch;
  private readonly maintenant: () => number;
  private readonly delaiMs: number;

  constructor(private readonly options: OptionsClientOrangeMoney) {
    if (!options.idClient || !options.secretClient) {
      throw new ErreurOrangeMoney('Identifiants Orange Money absents.');
    }
    this.fetcher = options.fetcher ?? fetch;
    this.maintenant = options.maintenant ?? Date.now;
    this.delaiMs = options.delaiMs ?? 15000;
  }

  get estBacASable(): boolean {
    return this.options.urlBase === URL_ORANGE_MONEY.bacASable;
  }

  private async envoyer(chemin: string, init: RequestInit): Promise<Response> {
    try {
      return await this.fetcher(`${this.options.urlBase}${chemin}`, { ...init, signal: AbortSignal.timeout(this.delaiMs) });
    } catch (e) {
      throw new ErreurOrangeMoney(`Orange Money injoignable : ${(e as Error).name === 'TimeoutError' ? 'délai dépassé' : (e as Error).message}.`);
    }
  }

  /** Jeton d'accès, réutilisé jusqu'à une minute avant son expiration. */
  async jeton(): Promise<string> {
    const enCache = this.jetonEnCache;
    if (enCache && this.maintenant() < enCache.expireA) return enCache.valeur;
    const reponse = await this.envoyer('/oauth/v1/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'application/json' },
      body: new URLSearchParams({
        client_id: this.options.idClient,
        client_secret: this.options.secretClient,
        grant_type: 'client_credentials',
      }).toString(),
    });
    if (!reponse.ok) throw await erreurDepuisReponse(reponse);
    const corps = (await reponse.json().catch(() => ({}))) as Record<string, unknown>;
    const valeur = texte(corps.access_token);
    if (valeur === undefined) throw new ErreurOrangeMoney('Réponse d\'Orange sans jeton d\'accès.', reponse.status);
    const dureeSecondes = nombre(corps.expires_in) ?? 3600;
    const marge = Math.min(60, dureeSecondes / 2);
    this.jetonEnCache = { valeur, expireA: this.maintenant() + (dureeSecondes - marge) * 1000 };
    return valeur;
  }

  /** Appel authentifié ; un 401 fait renouveler le jeton une seule fois. */
  private async appeler(
    methode: 'GET' | 'POST',
    chemin: string,
    { corps, entetes = {} }: { corps?: unknown; entetes?: Record<string, string> } = {},
    dejaReessaye = false,
  ): Promise<unknown> {
    const jeton = await this.jeton();
    const reponse = await this.envoyer(chemin, {
      method: methode,
      // Orange exige « Content-Type: application/json » même sans corps
      // (une lecture sans lui est refusée : 415, code 68 ; essai du bac à sable, 29 octobre 2026).
      headers: { Authorization: `Bearer ${jeton}`, Accept: 'application/json', 'Content-Type': 'application/json', ...entetes },
      body: corps === undefined ? undefined : JSON.stringify(corps),
    });
    if (reponse.status === 401 && !dejaReessaye) {
      this.jetonEnCache = undefined;
      return this.appeler(methode, chemin, { corps, entetes }, true);
    }
    if (!reponse.ok) throw await erreurDepuisReponse(reponse);
    const brut = await reponse.text();
    if (brut.trim() === '') return {};
    try {
      return JSON.parse(brut) as unknown;
    } catch {
      throw new ErreurOrangeMoney('Réponse d\'Orange illisible.', reponse.status);
    }
  }

  /** QR code et liens Max It / Orange Money pour un paiement marchand. */
  async genererQrCode(demande: DemandeQrCode): Promise<QrCodeOrangeMoney> {
    if (!CODE_MARCHAND.test(demande.codeMarchand)) throw new ErreurOrangeMoney('Code marchand invalide (6 chiffres attendus).');
    if (!demande.nomMarchand.trim()) throw new ErreurOrangeMoney('Nom du marchand manquant.');
    if (!Number.isInteger(demande.montantFcfa) || demande.montantFcfa < 1) {
      throw new ErreurOrangeMoney('Montant invalide (nombre entier de FCFA, au moins 1).');
    }
    if (!demande.reference.trim()) throw new ErreurOrangeMoney('Référence manquante.');
    const validite = demande.validiteSecondes ?? 900;
    if (!Number.isInteger(validite) || validite < 1 || validite > VALIDITE_MAX_SECONDES) {
      throw new ErreurOrangeMoney(`Validité invalide (de 1 à ${VALIDITE_MAX_SECONDES} secondes).`);
    }
    for (const url of [demande.urlNotification, demande.urlSucces, demande.urlAnnulation]) {
      if (url !== undefined && !url.startsWith('https://')) throw new ErreurOrangeMoney('Adresse HTTPS attendue.');
    }
    const metadonnees = demande.metadonnees ?? {};
    if (Object.keys(metadonnees).length > 10) throw new ErreurOrangeMoney('Au plus 10 métadonnées.');

    const reponse = (await this.appeler('POST', '/api/eWallet/v4/qrcode', {
      corps: {
        code: demande.codeMarchand,
        name: demande.nomMarchand,
        amount: { value: demande.montantFcfa, unit: 'XOF' },
        reference: demande.reference,
        validity: validite,
        ...(demande.urlSucces ? { callbackSuccessUrl: demande.urlSucces } : {}),
        ...(demande.urlAnnulation ? { callbackCancelUrl: demande.urlAnnulation } : {}),
        ...(Object.keys(metadonnees).length > 0 ? { metadata: metadonnees } : {}),
        restrictions: { isSingleUse: demande.usageUnique ?? true },
      },
      entetes: demande.urlNotification ? { 'X-Callback-Url': demande.urlNotification } : {},
    })) as Record<string, unknown>;

    const liens = (reponse.deepLinks ?? {}) as Record<string, unknown>;
    const validitePour = (reponse.validFor ?? {}) as Record<string, unknown>;
    const qr: QrCodeOrangeMoney = {
      qrId: texte(reponse.qrId),
      lienMaxIt: texte(liens.MAXIT) ?? texte(reponse.deepLink),
      lienOrangeMoney: texte(liens.OM),
      lienCourt: texte(reponse.shortLink),
      imageBase64: texte(reponse.qrCode),
      validiteSecondes: nombre(reponse.validity),
      finValidite: texte(validitePour.endDateTime),
    };
    if (!qr.lienMaxIt && !qr.lienOrangeMoney && !qr.lienCourt && !qr.imageBase64) {
      throw new ErreurOrangeMoney('Réponse d\'Orange sans QR code ni lien de paiement.');
    }
    return qr;
  }

  /** Statut d'une transaction, qui fait foi (à relire avant de créditer). */
  async statutTransaction(transactionId: string): Promise<StatutTransaction> {
    if (!ID_TRANSACTION.test(transactionId)) throw new ErreurOrangeMoney('Identifiant de transaction invalide.');
    const reponse = (await this.appeler(
      'GET',
      `/api/eWallet/v1/transactions/${encodeURIComponent(transactionId)}/status`,
    )) as Record<string, unknown>;
    const statut = STATUTS_TRANSACTION.find((s) => s === reponse.status);
    if (statut === undefined) throw new ErreurOrangeMoney('Statut de transaction inconnu.');
    return statut;
  }

  /**
   * Transactions enregistrées chez Orange, par identifiant ou par notre
   * référence. Sert à vérifier une notification (son contenu ne fait pas foi)
   * et à rattraper un paiement dont la notification s'est perdue.
   */
  async rechercherTransactions(filtre: { transactionId?: string; reference?: string }): Promise<TransactionOrangeMoney[]> {
    if (filtre.transactionId === undefined && filtre.reference === undefined) {
      throw new ErreurOrangeMoney('Recherche de transaction sans critère.');
    }
    if (filtre.transactionId !== undefined && !ID_TRANSACTION.test(filtre.transactionId)) {
      throw new ErreurOrangeMoney('Identifiant de transaction invalide.');
    }
    if (filtre.reference !== undefined && !REFERENCE.test(filtre.reference)) throw new ErreurOrangeMoney('Référence invalide.');
    const requete = new URLSearchParams({ size: '20' });
    if (filtre.transactionId !== undefined) requete.set('transactionId', filtre.transactionId);
    if (filtre.reference !== undefined) requete.set('reference', filtre.reference);
    const reponse = await this.appeler('GET', `/api/eWallet/v1/transactions?${requete}`);
    if (!Array.isArray(reponse)) return [];
    return reponse.flatMap((element) => {
      const t = element as Record<string, unknown>;
      const transactionId = texte(t.transactionId);
      if (transactionId === undefined) return [];
      const montant = (t.amount ?? {}) as Record<string, unknown>;
      const partenaire = (t.partner ?? {}) as Record<string, unknown>;
      return [
        {
          transactionId,
          reference: texte(t.reference),
          statut: STATUTS_TRANSACTION.find((s) => s === t.status),
          montantFcfa: nombre(montant.value),
          devise: texte(montant.unit),
          codeMarchand: texte(partenaire.id),
          type: texte(t.type),
        },
      ];
    });
  }

  /** Enregistre (durablement) l'adresse qui recevra les notifications de ce code marchand. */
  async enregistrerNotification({ codeMarchand, nomMarchand, url, cleApi }: {
    codeMarchand: string;
    nomMarchand: string;
    url: string;
    cleApi: string;
  }): Promise<void> {
    if (!CODE_MARCHAND.test(codeMarchand)) throw new ErreurOrangeMoney('Code marchand invalide (6 chiffres attendus).');
    if (!url.startsWith('https://')) throw new ErreurOrangeMoney('Adresse HTTPS attendue.');
    if (cleApi.length < 32) throw new ErreurOrangeMoney('Clé de notification trop courte (32 caractères au moins).');
    await this.appeler('POST', '/api/notification/v1/merchantcallback', {
      corps: { code: codeMarchand, name: nomMarchand, callbackUrl: url, apiKey: cleApi },
    });
  }

  /** Adresses de notification enregistrées (la clé n'est jamais renvoyée par Orange). */
  async notificationsEnregistrees(codeMarchand?: string): Promise<NotificationEnregistree[]> {
    const requete = codeMarchand === undefined ? '' : `?code=${encodeURIComponent(codeMarchand)}`;
    const reponse = await this.appeler('GET', `/api/notification/v1/merchantcallback${requete}`);
    if (!Array.isArray(reponse)) return [];
    return reponse.flatMap((element) => {
      const e = element as Record<string, unknown>;
      const code = texte(e.code);
      const url = texte(e.callbackUrl);
      return code && url ? [{ codeMarchand: code, nom: texte(e.name), url }] : [];
    });
  }

  /** Clé publique RSA d'Orange (pour chiffrer un code PIN, ex. dépôt d'argent). */
  async clePublique(): Promise<ClePublique> {
    const reponse = (await this.appeler('GET', '/api/account/v1/publicKeys')) as Record<string, unknown>;
    const cle = texte(reponse.key);
    if (cle === undefined) throw new ErreurOrangeMoney('Réponse d\'Orange sans clé publique.');
    return { cle, idCle: texte(reponse.keyId) ?? '', tailleBits: nombre(reponse.keySize) ?? 0 };
  }

  /** Numéros de test (bac à sable seulement), avec leur code PIN de test. */
  async cartesSimDeTest({ clients = 1, marchands = 0, distributeurs = 0 } = {}): Promise<CarteSimDeTest[]> {
    if (!this.estBacASable) throw new ErreurOrangeMoney('Numéros de test : bac à sable seulement.');
    const requete = new URLSearchParams({
      nbCustomers: String(clients),
      nbMerchants: String(marchands),
      nbRetailers: String(distributeurs),
    });
    const reponse = await this.appeler('GET', `/api/assignments/v1/partner/sim-cards?${requete}`);
    if (!Array.isArray(reponse)) return [];
    return reponse.flatMap((element) => {
      const e = element as Record<string, unknown>;
      const numero = texte(e.msisdn);
      return numero ? [{ numero, codePin: texte(e.pinCode), type: texte(e.type), expireLe: texte(e.expiresAt) }] : [];
    });
  }
}

/** Comparaison en temps constant (les deux valeurs sont d'abord ramenées à la même longueur). */
function egaux(a: string, b: string): boolean {
  const empreinte = (v: string) => createHash('sha256').update(v, 'utf8').digest();
  return timingSafeEqual(empreinte(a), empreinte(b)) && a.length === b.length;
}

/**
 * Lit une notification d'Orange après avoir vérifié qu'elle vient bien
 * d'Orange (« Authorization: Basic {cleApi} », la clé que nous avons
 * enregistrée). Elle ne fait PAS foi à elle seule : relire la transaction
 * avec [ClientOrangeMoney.rechercherTransactions] avant de considérer le
 * paiement comme reçu (voir `paiement_orange.ts`). Lève
 * [ErreurNotificationOrange].
 */
export function lireNotification(
  autorisation: string | undefined,
  corpsBrut: Buffer,
  cleApi: string,
): NotificationOrangeMoney {
  if (!cleApi) throw new ErreurNotificationOrange('Clé de notification non configurée.');
  if (autorisation === undefined || !egaux(autorisation.trim(), `Basic ${cleApi}`)) {
    throw new ErreurNotificationOrange('Notification non authentifiée.');
  }
  let corps: Record<string, unknown>;
  try {
    corps = JSON.parse(corpsBrut.toString('utf8')) as Record<string, unknown>;
  } catch {
    throw new ErreurNotificationOrange('Notification illisible.');
  }
  const transactionId = texte(corps.transactionId);
  const statut = corps.status === 'SUCCESS' || corps.status === 'FAILED' ? corps.status : undefined;
  const montant = nombre(((corps.amount ?? {}) as Record<string, unknown>).value);
  const type = texte(corps.type);
  if (transactionId === undefined || !ID_TRANSACTION.test(transactionId)) throw new ErreurNotificationOrange('Transaction absente.');
  if (statut === undefined) throw new ErreurNotificationOrange('Statut absent ou inconnu.');
  if (montant === undefined || !Number.isInteger(montant) || montant < 1) throw new ErreurNotificationOrange('Montant invalide.');
  if (type === undefined) throw new ErreurNotificationOrange('Type absent.');
  return {
    transactionId,
    reference: texte(corps.reference),
    statut,
    montantFcfa: montant,
    codeMarchand: texte(((corps.partner ?? {}) as Record<string, unknown>).id),
    type,
  };
}
