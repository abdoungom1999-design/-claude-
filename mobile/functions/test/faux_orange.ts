// Faux Orange Money pour les tests (aucun réseau) : jeton, QR codes et
// recherche de transactions, avec un état que les tests font évoluer
// (paiement réussi, refusé, d'un autre marchand...).
import { ClientOrangeMoney, URL_ORANGE_MONEY, type StatutTransaction } from '../src/orange_money';

export const CODE_MARCHAND_TEST = '123456';

export interface FausseTransaction {
  transactionId: string;
  reference?: string;
  status: StatutTransaction;
  amount: { value: number; unit: string };
  partner: { id: string; idType: string };
  type: string;
}

export interface QrDemande {
  reference: string;
  montantFcfa: number;
  code: string;
  name: string;
  validity: number;
  isSingleUse: unknown;
}

export class FauxOrange {
  readonly transactions: FausseTransaction[] = [];
  readonly qrCodes: QrDemande[] = [];
  /** Requêtes reçues (méthode et chemin), dans l'ordre. */
  readonly requetes: string[] = [];
  /** Réponse forcée pour les prochaines recherches (panne, quota dépassé...). */
  panneRecherche?: number;
  private suivant = 1;

  /** Le client paie (ou échoue à payer) la demande [reference] ; renvoie l'identifiant Orange. */
  payer(
    reference: string | undefined,
    montantFcfa: number,
    { statut = 'SUCCESS', code = CODE_MARCHAND_TEST, type = 'MERCHANT_PAYMENT', devise = 'XOF' }: {
      statut?: StatutTransaction;
      code?: string;
      type?: string;
      devise?: string;
    } = {},
  ): string {
    const transactionId = `MP261029.1200.A${String(this.suivant++).padStart(5, '0')}`;
    this.transactions.push({
      transactionId,
      reference,
      status: statut,
      amount: { value: montantFcfa, unit: devise },
      partner: { id: code, idType: 'CODE' },
      type,
    });
    return transactionId;
  }

  /** Corps d'une notification telle qu'Orange l'enverrait pour [transactionId]. */
  notification(transactionId: string, modifs: Record<string, unknown> = {}): Buffer {
    const t = this.transactions.find((x) => x.transactionId === transactionId);
    if (t === undefined) throw new Error(`transaction ${transactionId} inconnue`);
    return Buffer.from(
      JSON.stringify({
        transactionId: t.transactionId,
        reference: t.reference,
        status: t.status === 'SUCCESS' ? 'SUCCESS' : 'FAILED',
        amount: t.amount,
        partner: t.partner,
        customer: { idType: 'MSISDN', id: '771234567' },
        type: t.type,
        channel: 'API',
        paymentMethod: 'QRCODE',
        ...modifs,
      }),
    );
  }

  readonly fetcher = (async (adresse: string | URL | Request, init?: RequestInit) => {
    const url = new URL(String(adresse));
    const methode = init?.method ?? 'GET';
    this.requetes.push(`${methode} ${url.pathname}`);
    const json = (corps: unknown, status = 200) =>
      new Response(JSON.stringify(corps), { status, headers: { 'Content-Type': 'application/json' } });
    if (url.pathname === '/oauth/v1/token') return json({ access_token: 'jeton', token_type: 'bearer', expires_in: 3600 });
    if (methode === 'POST' && url.pathname === '/api/eWallet/v4/qrcode') {
      const c = JSON.parse(String(init?.body)) as {
        reference: string;
        amount: { value: number };
        code: string;
        name: string;
        validity: number;
        restrictions?: { isSingleUse?: unknown };
      };
      this.qrCodes.push({
        reference: c.reference,
        montantFcfa: c.amount.value,
        code: c.code,
        name: c.name,
        validity: c.validity,
        isSingleUse: c.restrictions?.isSingleUse,
      });
      return json({
        qrId: `qr${this.qrCodes.length}`,
        deepLinks: {
          MAXIT: `https://sugu.orange-sonatel.com/mp/maxit${this.qrCodes.length}`,
          OM: `https://sugu.orange-sonatel.com/mp/om${this.qrCodes.length}`,
        },
        shortLink: `https://sugu.orange-sonatel.com/mp/${this.qrCodes.length}`,
        qrCode: 'iVBORw0KGgo=',
        validity: c.validity,
      });
    }
    if (methode === 'GET' && url.pathname === '/api/eWallet/v1/transactions') {
      if (this.panneRecherche !== undefined) return json({ title: 'Panne', detail: 'Panne simulée' }, this.panneRecherche);
      const id = url.searchParams.get('transactionId');
      const reference = url.searchParams.get('reference');
      return json(
        this.transactions.filter(
          (t) => (id === null || t.transactionId === id) && (reference === null || t.reference === reference),
        ),
      );
    }
    return json({ title: 'Not Found' }, 404);
  }) as typeof fetch;

  /**
   * Client branché sur ce faux Orange. Adresse de production par défaut : le
   * marchand payé y est contrôlé strictement ; celle du bac à sable l'assouplit
   * (voir `paieSprint`). Aucune requête ne quitte le test.
   */
  client(urlBase: string = URL_ORANGE_MONEY.production): ClientOrangeMoney {
    return new ClientOrangeMoney({
      urlBase,
      idClient: 'id-de-test',
      secretClient: 'secret-de-test',
      fetcher: this.fetcher,
    });
  }
}
