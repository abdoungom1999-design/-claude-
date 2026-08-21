export type UserRole = 'CLIENT' | 'CONDUCTEUR' | 'ADMIN';

export interface JwtPayload {
  sub: string;
  role: UserRole;
}

export interface AuthenticatedRequestUser extends JwtPayload {
  refreshToken?: string;
}
