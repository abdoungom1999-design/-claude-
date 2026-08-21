import { Inject, Injectable } from '@nestjs/common';
import Redis from 'ioredis';
import { REDIS_CLIENT, REDIS_KEYS } from './redis.constants';

export interface PositionConducteur {
  latitude: number;
  longitude: number;
}

@Injectable()
export class RedisService {
  constructor(@Inject(REDIS_CLIENT) private readonly client: Redis) {}

  get raw(): Redis {
    return this.client;
  }

  async set(key: string, value: string, ttlSeconds?: number): Promise<void> {
    if (ttlSeconds) {
      await this.client.set(key, value, 'EX', ttlSeconds);
    } else {
      await this.client.set(key, value);
    }
  }

  async get(key: string): Promise<string | null> {
    return this.client.get(key);
  }

  async del(key: string): Promise<void> {
    await this.client.del(key);
  }

  async majPositionConducteur(
    conducteurId: string,
    position: PositionConducteur,
  ): Promise<void> {
    await this.client.geoadd(
      REDIS_KEYS.conducteursGeoIndex,
      position.longitude,
      position.latitude,
      conducteurId,
    );
    await this.set(
      REDIS_KEYS.conducteurPosition(conducteurId),
      JSON.stringify(position),
    );
  }

  async conducteursProches(
    position: PositionConducteur,
    rayonKm: number,
  ): Promise<string[]> {
    const resultats = await this.client.geosearch(
      REDIS_KEYS.conducteursGeoIndex,
      'FROMLONLAT',
      position.longitude,
      position.latitude,
      'BYRADIUS',
      rayonKm,
      'km',
      'ASC',
    );
    return resultats as string[];
  }
}
