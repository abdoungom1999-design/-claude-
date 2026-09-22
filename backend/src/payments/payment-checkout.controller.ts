import { Body, Controller, Post, UseGuards } from '@nestjs/common';
import { JwtAccessGuard } from '../auth/guards/jwt-access.guard';
import { JwtPayload } from '../auth/types/jwt-payload.type';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { RolesGuard } from '../common/guards/roles.guard';
import { InitierPaiementDto } from './dto/initier-paiement.dto';
import { PaymentsService } from './payments.service';

@Controller('payments')
@UseGuards(JwtAccessGuard, RolesGuard)
@Roles('CLIENT')
export class PaymentCheckoutController {
  constructor(private readonly paymentsService: PaymentsService) {}

  @Post('wave/initier')
  initierWave(
    @CurrentUser() user: JwtPayload,
    @Body() dto: InitierPaiementDto,
  ) {
    return this.paymentsService.initierWave(user.sub, dto.courseId);
  }

  @Post('orange-money/initier')
  initierOrangeMoney(
    @CurrentUser() user: JwtPayload,
    @Body() dto: InitierPaiementDto,
  ) {
    return this.paymentsService.initierOrangeMoney(user.sub, dto.courseId);
  }
}
