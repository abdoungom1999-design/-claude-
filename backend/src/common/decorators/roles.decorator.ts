import { SetMetadata } from '@nestjs/common';
import { UserRole } from '../../auth/types/jwt-payload.type';

export const ROLES_KEY = 'roles';
export const Roles = (...roles: UserRole[]) => SetMetadata(ROLES_KEY, roles);
