import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';

/**
 * Fournisseurs de paiement mobile money. Le reste du serveur ne connaît
 * que [FournisseurPaiement] : passer du faux Wave (simulation) au vrai
 * Wave ne change ni les commandes, ni le webhook, ni l'app.
 *
 * Format des webhooks (identique pour la simulation et Wave) : corps
 * JSON façon Wave Checkout, signé dans l'en-tête `Wave-Signature`
 * ("t=<horodatage>,v1=<hmac_sha256_hex>" de "<horodatage>.<corps>").
 * Format issu de la documentation publique de Wave, à revalider contre
 * la documentation fournie avec les clés marchandes.
 */

export type NomFournisseur = 'simulation' | 'wave';

export interface SessionPaiement {
  sessionId: string;
  /** Lien à ouvrir par le client pour payer. */
  lienPaiement: string;
}

export interface EvenementPaiement {
  sessionId: string;
  /** Identifiant de notre commande (client_reference). */
  commandeId: string;
  reussi: boolean;
  montantFcfa: number;
  devise: string;
}

export interface FournisseurPaiement {
  readonly nom: NomFournisseur;
  creerSession(commandeId: string, montantFcfa: number): Promise<SessionPaiement>;
  /** Vérifie la signature et lit l'événement ; lève [ErreurSignature]. */
  lireWebhook(corpsBrut: Buffer, signature: string | undefined, maintenant: Date): EvenementPaiement;
  rembourser(sessionId: string, montantFcfa: number): Promise<void>;
}

export class ErreurSignature extends Error {}
export class ErreurFournisseur extends Error {}

/** Au-delà, un webhook est refusé (protection contre le rejeu). */
const TOLERANCE_SECONDES = 300;

export function signer(corps: string, secret: string, maintenant: Date): string {
  const t = Math.floor(maintenant.getTime() / 1000);
  const v1 = createHmac('sha256', secret).update(`${t}.${corps}`).digest('hex');
  return `t=${t},v1=${v1}`;
}

export function verifierSignature(corpsBrut: Buffer, entete: string | undefined, secret: string, maintenant: Date): void {
  if (!entete) throw new ErreurSignature('Signature absente.');
  const parties = Object.fromEntries(
    entete.split(',').map((p) => {
      const i = p.indexOf('=');
      return [p.slice(0, i).trim(), p.slice(i + 1).trim()];
    }),
  );
  const t = Number(parties.t);
  const recue = parties.v1 ?? '';
  if (!Number.isFinite(t) || !/^[0-9a-f]{64}$/.test(recue)) throw new ErreurSignature('Signature mal formée.');
  if (Math.abs(maintenant.getTime() / 1000 - t) > TOLERANCE_SECONDES) throw new ErreurSignature('Signature expirée.');
  const attendue = createHmac('sha256', secret).update(`${t}.${corpsBrut.toString('utf8')}`).digest('hex');
  if (!timingSafeEqual(Buffer.from(attendue, 'hex'), Buffer.from(recue, 'hex'))) {
    throw new ErreurSignature('Signature invalide.');
  }
}

/** Corps d'un webhook façon Wave Checkout. */
export function corpsWebhook(sessionId: string, commandeId: string, reussi: boolean, montantFcfa: number): string {
  return JSON.stringify({
    type: reussi ? 'checkout.session.completed' : 'checkout.session.payment_failed',
    data: {
      id: sessionId,
      client_reference: commandeId,
      amount: String(montantFcfa),
      currency: 'XOF',
      payment_status: reussi ? 'succeeded' : 'cancelled',
    },
  });
}

export function lireEvenement(corpsBrut: Buffer): EvenementPaiement {
  let evenement: { type?: unknown; data?: Record<string, unknown> };
  try {
    evenement = JSON.parse(corpsBrut.toString('utf8'));
  } catch {
    throw new ErreurSignature('Corps illisible.');
  }
  const d = evenement.data ?? {};
  if (typeof d.id !== 'string' || typeof d.client_reference !== 'string') {
    throw new ErreurSignature('Événement incomplet.');
  }
  const reussi = evenement.type === 'checkout.session.completed' && d.payment_status === 'succeeded';
  return {
    sessionId: d.id,
    commandeId: d.client_reference,
    reussi,
    montantFcfa: Number(d.amount),
    devise: String(d.currency ?? ''),
  };
}

/**
 * Faux Wave : aucune somme réelle. Le lien mène à une page de paiement
 * simulée (fonction `pagePaiementSimule`) qui envoie au webhook un
 * événement signé exactement comme Wave le ferait.
 */
export class FournisseurSimule implements FournisseurPaiement {
  readonly nom = 'simulation';

  constructor(
    private readonly secret: string,
    private readonly urlPage: string,
    private readonly remboursements: string[] = [],
  ) {}

  async creerSession(): Promise<SessionPaiement> {
    const sessionId = `sim_${randomBytes(12).toString('hex')}`;
    return { sessionId, lienPaiement: `${this.urlPage}?session=${sessionId}` };
  }

  lireWebhook(corpsBrut: Buffer, signature: string | undefined, maintenant: Date): EvenementPaiement {
    verifierSignature(corpsBrut, signature, this.secret, maintenant);
    return lireEvenement(corpsBrut);
  }

  async rembourser(sessionId: string): Promise<void> {
    // Rien à rendre : aucune somme n'a été débitée. Gardé pour les tests.
    this.remboursements.push(sessionId);
  }
}

/**
 * Vrai Wave (API Checkout). Prêt, mais pas encore branché : il le sera
 * quand les clés marchandes (WAVE_API_KEY, WAVE_WEBHOOK_SECRET) seront
 * dans Secret Manager.
 */
export class FournisseurWave implements FournisseurPaiement {
  readonly nom = 'wave';

  constructor(
    private readonly cleApi: string,
    private readonly secretWebhook: string,
    private readonly urlRetour: string,
    private readonly fetcher: typeof fetch = fetch,
  ) {}

  private async appeler(chemin: string, corps: unknown): Promise<Record<string, unknown>> {
    let reponse: Response;
    try {
      reponse = await this.fetcher(`https://api.wave.com/v1${chemin}`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${this.cleApi}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(corps),
        signal: AbortSignal.timeout(10000),
      });
    } catch (e) {
      throw new ErreurFournisseur(`Wave injoignable : ${(e as Error).message}`);
    }
    // Jamais la clé dans les messages d'erreur.
    if (!reponse.ok) throw new ErreurFournisseur(`Wave a répondu ${reponse.status}.`);
    return (await reponse.json().catch(() => ({}))) as Record<string, unknown>;
  }

  async creerSession(commandeId: string, montantFcfa: number): Promise<SessionPaiement> {
    const donnees = await this.appeler('/checkout/sessions', {
      amount: String(montantFcfa),
      currency: 'XOF',
      client_reference: commandeId,
      success_url: `${this.urlRetour}?commande=${commandeId}&resultat=succes`,
      error_url: `${this.urlRetour}?commande=${commandeId}&resultat=echec`,
    });
    if (typeof donnees.id !== 'string' || typeof donnees.wave_launch_url !== 'string') {
      throw new ErreurFournisseur('Réponse Wave incomplète.');
    }
    return { sessionId: donnees.id, lienPaiement: donnees.wave_launch_url };
  }

  lireWebhook(corpsBrut: Buffer, signature: string | undefined, maintenant: Date): EvenementPaiement {
    verifierSignature(corpsBrut, signature, this.secretWebhook, maintenant);
    return lireEvenement(corpsBrut);
  }

  async rembourser(sessionId: string): Promise<void> {
    await this.appeler(`/checkout/sessions/${encodeURIComponent(sessionId)}/refund`, {});
  }
}
