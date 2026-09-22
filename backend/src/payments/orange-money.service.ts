import { HttpService } from '@nestjs/axios';
import {
  BadGatewayException,
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { firstValueFrom } from 'rxjs';
import { verifierSignatureHmacGenerique } from './webhook-signature.util';

export interface SessionPaiementOrangeMoney {
  id: string;
  urlPaiement: string;
}

/**
 * Client de l'API Orange Money Web Payment : authentification OAuth2
 * (client_credentials), création de session de paiement et vérification
 * de la signature des webhooks. Les conventions exactes varient selon le
 * pays/l'offre Orange Money ; structure basée sur le modèle standard
 * publié par Orange Developer — à valider/ajuster contre la
 * documentation en vigueur une fois des identifiants réels obtenus
 * (aucune clé Orange Money n'est disponible dans cet environnement).
 */
@Injectable()
export class OrangeMoneyService {
  constructor(
    private readonly httpService: HttpService,
    private readonly configService: ConfigService,
  ) {}

  private tokenCache: { valeur: string; expireA: number } | null = null;

  estConfigure(): boolean {
    return !!(
      this.configService.get<string>('payments.orangeMoney.clientId') &&
      this.configService.get<string>('payments.orangeMoney.clientSecret') &&
      this.configService.get<string>('payments.orangeMoney.merchantKey')
    );
  }

  private async obtenirToken(): Promise<string> {
    if (this.tokenCache && this.tokenCache.expireA > Date.now()) {
      return this.tokenCache.valeur;
    }

    const clientId = this.configService.get<string>(
      'payments.orangeMoney.clientId',
    );
    const clientSecret = this.configService.get<string>(
      'payments.orangeMoney.clientSecret',
    );
    const authUrl = this.configService.get<string>(
      'payments.orangeMoney.authUrl',
    )!;
    const identifiants = Buffer.from(`${clientId}:${clientSecret}`).toString(
      'base64',
    );

    try {
      const { data } = await firstValueFrom(
        this.httpService.post(authUrl, 'grant_type=client_credentials', {
          headers: {
            Authorization: `Basic ${identifiants}`,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        }),
      );

      this.tokenCache = {
        valeur: data.access_token,
        expireA: Date.now() + (data.expires_in - 30) * 1000,
      };
      return this.tokenCache.valeur;
    } catch {
      throw new BadGatewayException(
        "Impossible de s'authentifier auprès d'Orange Money",
      );
    }
  }

  async creerSessionPaiement(
    courseId: string,
    montantFcfa: number,
  ): Promise<SessionPaiementOrangeMoney> {
    if (!this.estConfigure()) {
      throw new ServiceUnavailableException(
        "Le paiement Orange Money n'est pas configuré sur ce serveur",
      );
    }

    const token = await this.obtenirToken();
    const apiUrl = this.configService.get<string>(
      'payments.orangeMoney.apiUrl',
    );
    const merchantKey = this.configService.get<string>(
      'payments.orangeMoney.merchantKey',
    );
    const publicUrl = this.configService.get<string>('app.publicUrl');

    try {
      const { data } = await firstValueFrom(
        this.httpService.post(
          `${apiUrl}/webpayment`,
          {
            merchant_key: merchantKey,
            currency: 'XOF',
            order_id: courseId,
            amount: Math.round(montantFcfa),
            return_url: this.configService.get<string>(
              'payments.orangeMoney.returnUrl',
            ),
            cancel_url: this.configService.get<string>(
              'payments.orangeMoney.cancelUrl',
            ),
            notif_url: `${publicUrl}/payments/webhooks/orange-money`,
            lang: 'fr',
          },
          { headers: { Authorization: `Bearer ${token}` } },
        ),
      );

      return {
        id: data.pay_token ?? data.order_id,
        urlPaiement: data.payment_url,
      };
    } catch {
      throw new BadGatewayException(
        'Impossible de créer la session de paiement Orange Money',
      );
    }
  }

  verifierSignatureWebhook(
    corpsBrut: Buffer,
    enTete: string | undefined,
  ): boolean {
    const secret = this.configService.get<string>(
      'payments.orangeMoney.webhookSecret',
    );
    if (!secret) return false;
    return verifierSignatureHmacGenerique(corpsBrut, enTete, secret);
  }
}
