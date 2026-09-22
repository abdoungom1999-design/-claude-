import { HttpModule } from '@nestjs/axios';
import { Module } from '@nestjs/common';
import { OrangeMoneyService } from './orange-money.service';
import { PaymentCheckoutController } from './payment-checkout.controller';
import { PaymentsController } from './payments.controller';
import { PaymentsService } from './payments.service';
import { WaveService } from './wave.service';

@Module({
  imports: [HttpModule],
  controllers: [PaymentsController, PaymentCheckoutController],
  providers: [PaymentsService, WaveService, OrangeMoneyService],
})
export class PaymentsModule {}
