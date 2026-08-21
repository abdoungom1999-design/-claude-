import { Controller, Get, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { RolesGuard } from '../common/guards/roles.guard';
import { JwtAccessGuard } from '../auth/guards/jwt-access.guard';
import { JwtPayload } from '../auth/types/jwt-payload.type';
import { ClientsService } from './clients.service';

@Controller('clients')
@UseGuards(JwtAccessGuard, RolesGuard)
export class ClientsController {
  constructor(private readonly clientsService: ClientsService) {}

  @Get('me')
  @Roles('CLIENT')
  me(@CurrentUser() user: JwtPayload) {
    return this.clientsService.findById(user.sub);
  }
}
