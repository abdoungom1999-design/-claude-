/**
 * Envoi d'e-mails par l'API Resend (https://api.resend.com/emails), appelée
 * directement par le serveur : aucune extension Firebase, aucune collection
 * intermédiaire. L'expéditeur est le domaine officiel `sprintvtc.sn`, vérifié
 * chez Resend par le client.
 *
 * La clé d'API (`RESEND_API_KEY`) vit dans Secret Manager, jamais dans le code,
 * l'app, GitHub, les journaux ni un message. Ce module ne la voit que par son
 * constructeur et ne l'écrit nulle part : une erreur ne la contient jamais.
 */

export const URL_RESEND = 'https://api.resend.com/emails';

/** Au-delà, l'envoi est abandonné (le déclencheur ne doit pas rester suspendu). */
export const DELAI_RESEND_MS = 10_000;

export interface CourrielResend {
  /** Expéditeur, ex. « SPRINT <contact@sprintvtc.sn> ». */
  from: string;
  to: string[];
  subject: string;
  html: string;
  text: string;
  reply_to?: string;
}

/** Ce que le serveur demande à un service d'envoi (remplaçable dans les tests). */
export interface EnvoiCourriel {
  /**
   * Envoie le message. [cleIdempotence] : un même envoi rejoué (nouvelle
   * livraison de l'événement, nouvel essai) n'est accepté qu'une fois par
   * Resend pendant 24 heures. Renvoie l'identifiant du message chez Resend.
   */
  envoyer(courriel: CourrielResend, cleIdempotence: string): Promise<{ id: string }>;
}

/**
 * Échec d'envoi. [code] dit pourquoi, sans rien de secret :
 * `resend/401` (clé refusée), `resend/403` (domaine ou clé non autorisée),
 * `resend/422` (message refusé : champ invalide), `resend/429` (trop
 * d'envois), `resend/5xx`, `resend/reseau` (injoignable), `resend/delai`
 * (pas de réponse à temps), `resend/reponse` (réponse illisible).
 */
export class ErreurResend extends Error {
  constructor(
    readonly code: string,
    /** Nom d'erreur donné par Resend (`validation_error`…), s'il y en a un. */
    readonly nomResend?: string,
  ) {
    super(code + (nomResend ? ` (${nomResend})` : ''));
    this.name = 'ErreurResend';
  }
}

type Fetch = (url: string, init: { method: string; headers: Record<string, string>; body: string; signal: AbortSignal }) => Promise<{
  ok: boolean;
  status: number;
  json(): Promise<unknown>;
}>;

const objet = (v: unknown): Record<string, unknown> => (typeof v === 'object' && v !== null && !Array.isArray(v) ? (v as Record<string, unknown>) : {});

export class ClientResend implements EnvoiCourriel {
  /**
   * @param cle clé d'API Resend, telle que lue dans Secret Manager ; les espaces
   *   et retours à la ligne collés avec elle sont retirés.
   */
  constructor(
    cle: string,
    private readonly appel: Fetch = fetch as unknown as Fetch,
    private readonly delaiMs: number = DELAI_RESEND_MS,
  ) {
    this.cle = cle.replace(/[\s​-‍﻿]/g, '');
  }

  private readonly cle: string;

  /** Vrai si une clé non vide est disponible. */
  get disponible(): boolean {
    return this.cle.length > 0;
  }

  async envoyer(courriel: CourrielResend, cleIdempotence: string): Promise<{ id: string }> {
    if (!this.disponible) throw new ErreurResend('resend/cle_absente');
    const controleur = new AbortController();
    const minuteur = setTimeout(() => controleur.abort(), this.delaiMs);
    try {
      const reponse = await this.appel(URL_RESEND, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.cle}`,
          'Content-Type': 'application/json',
          'Idempotency-Key': cleIdempotence,
          'User-Agent': 'sprint-functions/1.0',
        },
        body: JSON.stringify(courriel),
        signal: controleur.signal,
      });
      let corps: Record<string, unknown> = {};
      try {
        corps = objet(await reponse.json());
      } catch {
        // Réponse sans JSON : traitée plus bas selon le code HTTP.
      }
      if (!reponse.ok) {
        const nom = typeof corps.name === 'string' ? corps.name : undefined;
        throw new ErreurResend(`resend/${reponse.status}`, nom);
      }
      if (typeof corps.id !== 'string' || corps.id === '') throw new ErreurResend('resend/reponse');
      return { id: corps.id };
    } catch (e) {
      if (e instanceof ErreurResend) throw e;
      if (e instanceof Error && e.name === 'AbortError') throw new ErreurResend('resend/delai');
      throw new ErreurResend('resend/reseau');
    } finally {
      clearTimeout(minuteur);
    }
  }
}
