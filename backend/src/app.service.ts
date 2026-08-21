import { Injectable } from '@nestjs/common';

@Injectable()
export class AppService {
  health() {
    return { service: 'Spid API', status: 'ok' };
  }
}
