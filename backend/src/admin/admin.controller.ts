import { Controller, Get, Param, Patch, UseGuards } from '@nestjs/common';
import { JwtAccessGuard } from '../auth/guards/jwt-access.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { RolesGuard } from '../common/guards/roles.guard';
import { AdminService } from './admin.service';

@Controller('admin')
@UseGuards(JwtAccessGuard, RolesGuard)
@Roles('ADMIN')
export class AdminController {
  constructor(private readonly adminService: AdminService) {}

  @Get('clients')
  listerClients() {
    return this.adminService.listerClients();
  }

  @Get('conducteurs')
  listerConducteurs() {
    return this.adminService.listerConducteurs();
  }

  @Patch('conducteurs/:id/valider')
  validerConducteur(@Param('id') id: string) {
    return this.adminService.validerConducteur(id);
  }
}
