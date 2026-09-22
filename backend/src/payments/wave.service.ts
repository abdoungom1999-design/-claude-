import { HttpService } from '@nestjs/axios';
import {
  BadGatewayException,
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { firstValueFrom } from 'rxjs';
import { verifierSignatureWave } from './webhook-signature.util';

export interface SessionCheckoutWave {
  id: string;
  urlPaiement: string;
}

/**
 * Client de l'API Wave Checkout : création de session de paiement et
 * vérification de la signature des webhooks. Structure basée sur la
 * documentation publique de Wave (sessions de paiement, en-tête
 * `Wave-Signature` façon Stripe) — à valider/ajuster contre la
 * documentation en vigueur une fois des identifiants réels obtenus
 * (aucune clé Wave n'est disponible dans cet environnement).
 */
@Injectable()
export class WaveService {
  constructor(
    private readonly httpService: HttpService,
    private readonly configService: ConfigService,
  ) {}

  private get apiKey(): string | undefined {
    return this.configService.get<string>('payments.wave.apiKey');
  }

  private get apiUrl(): string {
    return this.configService.get<string>('payments.wave.apiUrl')!;
  }

  estConfigure(): boolean {
    return !!this.apiKey;
  }

  async creerSessionCheckout(
    courseId: string,
    montantFcfa: number,
  ): Promise<SessionCheckoutWave> {
    if (!this.estConfigure()) {
      throw new ServiceUnavailableException(
        "Le paiement Wave n'est pas configuré sur ce serveur",
      );
    }

    try {
      const { data } = await firstValueFrom(
        this.httpService.post(
          `${this.apiUrl}/checkout/sessions`,
          {
            amount: String(Math.round(montantFcfa)),
            currency: 'XOF',
            client_reference: courseId,
            success_url: this.configService.get<string>(
              'payments.wave.successUrl',
            ),
            error_url: this.configService.get<string>('payments.wave.errorUrl'),
          },
          { headers: { Authorization: `Bearer ${this.apiKey}` } },
        ),
      );

      return { id: data.id, urlPaiement: data.wave_launch_url };
    } catch {
      // Ne jamais relayer l'erreur brute d'axios : elle peut contenir la
      // clé API dans la configuration de la requête d'origine.
      throw new BadGatewayException(
        'Impossible de créer la session de paiement Wave',
      );
    }
  }

  verifierSignatureWebhook(
    corpsBrut: Buffer,
    enTete: string | undefined,
  ): boolean {
    const secret = this.configService.get<string>(
      'payments.wave.webhookSecret',
    );
    if (!secret) return false;
    return verifierSignatureWave(corpsBrut, enTete, secret);
  }
}
