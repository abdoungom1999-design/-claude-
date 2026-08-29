import {
  Body,
  Controller,
  Headers,
  HttpCode,
  HttpStatus,
  Post,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PaiementWebhookDto } from './dto/paiement-webhook.dto';
import { PaymentsService } from './payments.service';

@Controller('payments/webhooks')
export class PaymentsController {
  constructor(
    private readonly paymentsService: PaymentsService,
    private readonly configService: ConfigService,
  ) {}

  @Post('wave')
  @HttpCode(HttpStatus.OK)
  async webhookWave(
    @Headers('x-webhook-token') token: string | undefined,
    @Body() dto: PaiementWebhookDto,
  ) {
    this.verifierToken(
      token,
      this.configService.get<string>('payments.waveWebhookSecret'),
    );
    await this.paymentsService.traiterWebhookWave(dto);
    return { received: true };
  }

  @Post('orange-money')
  @HttpCode(HttpStatus.OK)
  async webhookOrangeMoney(
    @Headers('x-webhook-token') token: string | undefined,
    @Body() dto: PaiementWebhookDto,
  ) {
    this.verifierToken(
      token,
      this.configService.get<string>('payments.orangeMoneyWebhookSecret'),
    );
    await this.paymentsService.traiterWebhookOrangeMoney(dto);
    return { received: true };
  }

  /**
   * Vérification par secret partagé, en attendant la vérification de
   * signature HMAC réelle (nécessite le corps brut de la requête) une fois
   * les identifiants du prestataire disponibles.
   */
  private verifierToken(recu: string | undefined, attendu: string | undefined) {
    if (!attendu || recu !== attendu) {
      throw new UnauthorizedException('Webhook non authentifié');
    }
  }
}
