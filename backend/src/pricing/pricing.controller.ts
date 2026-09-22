import {
  Body,
  Controller,
  HttpCode,
  HttpStatus,
  Post,
  UseGuards,
} from '@nestjs/common';
import { JwtAccessGuard } from '../auth/guards/jwt-access.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { RolesGuard } from '../common/guards/roles.guard';
import { EstimerPrixDto } from './dto/estimer-prix.dto';
import { PricingService } from './pricing.service';

@Controller('pricing')
@UseGuards(JwtAccessGuard, RolesGuard)
@Roles('CLIENT')
export class PricingController {
  constructor(private readonly pricingService: PricingService) {}

  @Post('estimer')
  @HttpCode(HttpStatus.OK)
  estimer(@Body() dto: EstimerPrixDto) {
    return this.pricingService.estimer(dto.type, dto.distanceKm);
  }
}
