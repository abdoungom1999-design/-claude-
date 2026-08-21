export default () => ({
  port: parseInt(process.env.PORT ?? '3000', 10),
  database: {
    url: process.env.DATABASE_URL,
  },
  redis: {
    url: process.env.REDIS_URL ?? 'redis://localhost:6379',
  },
  jwt: {
    accessSecret: process.env.JWT_ACCESS_SECRET,
    accessExpiresInSeconds: parseInt(
      process.env.JWT_ACCESS_EXPIRES_IN_SECONDS ?? '900',
      10,
    ),
    refreshSecret: process.env.JWT_REFRESH_SECRET,
    refreshExpiresInSeconds: parseInt(
      process.env.JWT_REFRESH_EXPIRES_IN_SECONDS ?? '604800',
      10,
    ),
  },
  throttler: {
    ttlMs: parseInt(process.env.THROTTLE_TTL_MS ?? '60000', 10),
    limit: parseInt(process.env.THROTTLE_LIMIT ?? '20', 10),
  },
  payments: {
    waveApiKey: process.env.WAVE_API_KEY,
    waveApiUrl: process.env.WAVE_API_URL,
    orangeMoneyApiKey: process.env.ORANGE_MONEY_API_KEY,
    orangeMoneyApiUrl: process.env.ORANGE_MONEY_API_URL,
  },
});
