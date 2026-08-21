import {
  Body,
  Controller,
  HttpCode,
  HttpStatus,
  Post,
  UseGuards,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { AuthService, TokenPair } from './auth.service';
import { AdminLoginDto } from './dto/admin-login.dto';
import { LoginDto } from './dto/login.dto';
import { RegisterClientDto } from './dto/register-client.dto';
import { RegisterConducteurDto } from './dto/register-conducteur.dto';
import { JwtAccessGuard } from './guards/jwt-access.guard';
import { JwtRefreshGuard } from './guards/jwt-refresh.guard';
import { AuthenticatedRequestUser, JwtPayload } from './types/jwt-payload.type';

const THROTTLE_AUTH = { default: { limit: 5, ttl: 60_000 } };

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Throttle(THROTTLE_AUTH)
  @Post('client/register')
  registerClient(@Body() dto: RegisterClientDto): Promise<TokenPair> {
    return this.authService.registerClient(dto);
  }

  @Throttle(THROTTLE_AUTH)
  @Post('client/login')
  @HttpCode(HttpStatus.OK)
  loginClient(@Body() dto: LoginDto): Promise<TokenPair> {
    return this.authService.loginClient(dto);
  }

  @Throttle(THROTTLE_AUTH)
  @Post('conducteur/register')
  registerConducteur(@Body() dto: RegisterConducteurDto): Promise<TokenPair> {
    return this.authService.registerConducteur(dto);
  }

  @Throttle(THROTTLE_AUTH)
  @Post('conducteur/login')
  @HttpCode(HttpStatus.OK)
  loginConducteur(@Body() dto: LoginDto): Promise<TokenPair> {
    return this.authService.loginConducteur(dto);
  }

  @Throttle(THROTTLE_AUTH)
  @Post('admin/login')
  @HttpCode(HttpStatus.OK)
  loginAdmin(@Body() dto: AdminLoginDto): Promise<TokenPair> {
    return this.authService.loginAdmin(dto);
  }

  @UseGuards(JwtRefreshGuard)
  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  refresh(@CurrentUser() user: AuthenticatedRequestUser): Promise<TokenPair> {
    return this.authService.refreshTokens(user);
  }

  @UseGuards(JwtAccessGuard)
  @Post('logout')
  @HttpCode(HttpStatus.NO_CONTENT)
  logout(@CurrentUser() user: JwtPayload): Promise<void> {
    return this.authService.logout(user);
  }
}
