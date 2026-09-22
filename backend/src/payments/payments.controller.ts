import {
  Body,
  Controller,
  Headers,
  HttpCode,
  HttpStatus,
  Post,
  RawBodyRequest,
  Req,
} from '@nestjs/common';
import { Request } from 'express';
import { PaiementWebhookDto } from './dto/paiement-webhook.dto';
import { PaymentsService } from './payments.service';

@Controller('payments/webhooks')
export class PaymentsController {
  constructor(private readonly paymentsService: PaymentsService) {}

  @Post('wave')
  @HttpCode(HttpStatus.OK)
  async webhookWave(
    @Req() request: RawBodyRequest<Request>,
    @Headers('wave-signature') signature: string | undefined,
    @Body() dto: PaiementWebhookDto,
  ) {
    await this.paymentsService.traiterWebhookWave(
      request.rawBody!,
      signature,
      dto,
    );
    return { received: true };
  }

  @Post('orange-money')
  @HttpCode(HttpStatus.OK)
  async webhookOrangeMoney(
    @Req() request: RawBodyRequest<Request>,
    @Headers('x-om-signature') signature: string | undefined,
    @Body() dto: PaiementWebhookDto,
  ) {
    await this.paymentsService.traiterWebhookOrangeMoney(
      request.rawBody!,
      signature,
      dto,
    );
    return { received: true };
  }
}
