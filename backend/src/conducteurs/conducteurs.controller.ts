import { Body, Controller, Get, Patch, UseGuards } from '@nestjs/common';
import { JwtAccessGuard } from '../auth/guards/jwt-access.guard';
import { JwtPayload } from '../auth/types/jwt-payload.type';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { RolesGuard } from '../common/guards/roles.guard';
import { ConducteursService } from './conducteurs.service';
import { UpdatePositionDto } from './dto/update-position.dto';
import { UpdateStatutDto } from './dto/update-statut.dto';

@Controller('conducteurs')
@UseGuards(JwtAccessGuard, RolesGuard)
@Roles('CONDUCTEUR')
export class ConducteursController {
  constructor(private readonly conducteursService: ConducteursService) {}

  @Get('me')
  me(@CurrentUser() user: JwtPayload) {
    return this.conducteursService.findById(user.sub);
  }

  @Patch('me/statut')
  mettreAJourStatut(
    @CurrentUser() user: JwtPayload,
    @Body() dto: UpdateStatutDto,
  ) {
    return this.conducteursService.mettreAJourStatut(user.sub, dto);
  }

  @Patch('me/position')
  mettreAJourPosition(
    @CurrentUser() user: JwtPayload,
    @Body() dto: UpdatePositionDto,
  ) {
    return this.conducteursService.mettreAJourPosition(user.sub, dto);
  }
}
