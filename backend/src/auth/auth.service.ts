import {
  ConflictException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as argon2 from 'argon2';
import { PrismaService } from '../prisma/prisma.service';
import { AdminLoginDto } from './dto/admin-login.dto';
import { LoginDto } from './dto/login.dto';
import { RegisterClientDto } from './dto/register-client.dto';
import { RegisterConducteurDto } from './dto/register-conducteur.dto';
import {
  AuthenticatedRequestUser,
  JwtPayload,
  UserRole,
} from './types/jwt-payload.type';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
  ) {}

  private hashSecret(valeur: string): Promise<string> {
    return argon2.hash(valeur, { type: argon2.argon2id });
  }

  private verifySecret(hash: string, valeur: string): Promise<boolean> {
    return argon2.verify(hash, valeur);
  }

  private async genererTokens(payload: JwtPayload): Promise<TokenPair> {
    const [accessToken, refreshToken] = await Promise.all([
      this.jwtService.signAsync(payload, {
        secret: this.configService.get<string>('jwt.accessSecret'),
        expiresIn: this.configService.get<number>('jwt.accessExpiresInSeconds'),
      }),
      this.jwtService.signAsync(payload, {
        secret: this.configService.get<string>('jwt.refreshSecret'),
        expiresIn: this.configService.get<number>(
          'jwt.refreshExpiresInSeconds',
        ),
      }),
    ]);
    return { accessToken, refreshToken };
  }

  private async sauvegarderRefreshToken(
    role: UserRole,
    id: string,
    refreshToken: string,
  ): Promise<void> {
    const refreshTokenHash = await this.hashSecret(refreshToken);
    switch (role) {
      case 'CLIENT':
        await this.prisma.client.update({
          where: { id },
          data: { refreshTokenHash },
        });
        break;
      case 'CONDUCTEUR':
        await this.prisma.conducteur.update({
          where: { id },
          data: { refreshTokenHash },
        });
        break;
      case 'ADMIN':
        await this.prisma.admin.update({
          where: { id },
          data: { refreshTokenHash },
        });
        break;
    }
  }

  async registerClient(dto: RegisterClientDto): Promise<TokenPair> {
    const existant = await this.prisma.client.findUnique({
      where: { telephone: dto.telephone },
    });
    if (existant) {
      throw new ConflictException('Ce numéro de téléphone est déjà utilisé');
    }

    const motDePasseHash = await this.hashSecret(dto.motDePasse);
    const client = await this.prisma.client.create({
      data: {
        nom: dto.nom,
        telephone: dto.telephone,
        motDePasseHash,
      },
    });

    const tokens = await this.genererTokens({ sub: client.id, role: 'CLIENT' });
    await this.sauvegarderRefreshToken(
      'CLIENT',
      client.id,
      tokens.refreshToken,
    );
    return tokens;
  }

  async registerConducteur(dto: RegisterConducteurDto): Promise<TokenPair> {
    const existant = await this.prisma.conducteur.findUnique({
      where: { telephone: dto.telephone },
    });
    if (existant) {
      throw new ConflictException('Ce numéro de téléphone est déjà utilisé');
    }

    const motDePasseHash = await this.hashSecret(dto.motDePasse);
    const conducteur = await this.prisma.conducteur.create({
      data: {
        nom: dto.nom,
        telephone: dto.telephone,
        motDePasseHash,
        vehiculeId: dto.vehiculeId,
      },
    });

    const tokens = await this.genererTokens({
      sub: conducteur.id,
      role: 'CONDUCTEUR',
    });
    await this.sauvegarderRefreshToken(
      'CONDUCTEUR',
      conducteur.id,
      tokens.refreshToken,
    );
    return tokens;
  }

  async loginClient(dto: LoginDto): Promise<TokenPair> {
    const client = await this.prisma.client.findUnique({
      where: { telephone: dto.telephone },
    });
    if (
      !client ||
      !(await this.verifySecret(client.motDePasseHash, dto.motDePasse))
    ) {
      throw new UnauthorizedException('Identifiants invalides');
    }

    const tokens = await this.genererTokens({ sub: client.id, role: 'CLIENT' });
    await this.sauvegarderRefreshToken(
      'CLIENT',
      client.id,
      tokens.refreshToken,
    );
    return tokens;
  }

  async loginConducteur(dto: LoginDto): Promise<TokenPair> {
    const conducteur = await this.prisma.conducteur.findUnique({
      where: { telephone: dto.telephone },
    });
    if (
      !conducteur ||
      !(await this.verifySecret(conducteur.motDePasseHash, dto.motDePasse))
    ) {
      throw new UnauthorizedException('Identifiants invalides');
    }

    const tokens = await this.genererTokens({
      sub: conducteur.id,
      role: 'CONDUCTEUR',
    });
    await this.sauvegarderRefreshToken(
      'CONDUCTEUR',
      conducteur.id,
      tokens.refreshToken,
    );
    return tokens;
  }

  async loginAdmin(dto: AdminLoginDto): Promise<TokenPair> {
    const admin = await this.prisma.admin.findUnique({
      where: { email: dto.email },
    });
    if (
      !admin ||
      !(await this.verifySecret(admin.passwordHash, dto.motDePasse))
    ) {
      throw new UnauthorizedException('Identifiants invalides');
    }

    const tokens = await this.genererTokens({ sub: admin.id, role: 'ADMIN' });
    await this.sauvegarderRefreshToken('ADMIN', admin.id, tokens.refreshToken);
    return tokens;
  }

  async refreshTokens(user: AuthenticatedRequestUser): Promise<TokenPair> {
    if (!user.refreshToken) {
      throw new UnauthorizedException('Refresh token manquant');
    }

    const refreshTokenHash = await this.getRefreshTokenHash(
      user.role,
      user.sub,
    );
    if (
      !refreshTokenHash ||
      !(await this.verifySecret(refreshTokenHash, user.refreshToken))
    ) {
      throw new UnauthorizedException('Refresh token invalide');
    }

    const tokens = await this.genererTokens({ sub: user.sub, role: user.role });
    await this.sauvegarderRefreshToken(
      user.role,
      user.sub,
      tokens.refreshToken,
    );
    return tokens;
  }

  async logout(user: JwtPayload): Promise<void> {
    switch (user.role) {
      case 'CLIENT':
        await this.prisma.client.update({
          where: { id: user.sub },
          data: { refreshTokenHash: null },
        });
        break;
      case 'CONDUCTEUR':
        await this.prisma.conducteur.update({
          where: { id: user.sub },
          data: { refreshTokenHash: null },
        });
        break;
      case 'ADMIN':
        await this.prisma.admin.update({
          where: { id: user.sub },
          data: { refreshTokenHash: null },
        });
        break;
    }
  }

  private async getRefreshTokenHash(
    role: UserRole,
    id: string,
  ): Promise<string | null> {
    switch (role) {
      case 'CLIENT': {
        const client = await this.prisma.client.findUnique({ where: { id } });
        return client?.refreshTokenHash ?? null;
      }
      case 'CONDUCTEUR': {
        const conducteur = await this.prisma.conducteur.findUnique({
          where: { id },
        });
        return conducteur?.refreshTokenHash ?? null;
      }
      case 'ADMIN': {
        const admin = await this.prisma.admin.findUnique({ where: { id } });
        return admin?.refreshTokenHash ?? null;
      }
    }
  }
}
