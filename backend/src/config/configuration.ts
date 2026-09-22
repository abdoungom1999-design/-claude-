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
    waveWebhookSecret: process.env.WAVE_WEBHOOK_SECRET,
    orangeMoneyApiKey: process.env.ORANGE_MONEY_API_KEY,
    orangeMoneyApiUrl: process.env.ORANGE_MONEY_API_URL,
    orangeMoneyWebhookSecret: process.env.ORANGE_MONEY_WEBHOOK_SECRET,
  },
  pricing: {
    // Vitesse moyenne retenue pour estimer la durée du trajet en
    // l'absence d'un vrai moteur d'itinéraire (pas de clé API de routage).
    vitesseMoyenneKmh: parseFloat(
      process.env.PRICING_VITESSE_MOYENNE_KMH ?? '22',
    ),
    passager: {
      prisEnCharge: parseInt(
        process.env.PRICING_PASSAGER_PRISE_EN_CHARGE ?? '500',
        10,
      ),
      parKm: parseInt(process.env.PRICING_PASSAGER_PAR_KM ?? '150', 10),
      parMinute: parseInt(process.env.PRICING_PASSAGER_PAR_MINUTE ?? '50', 10),
      prixMinimum: parseInt(
        process.env.PRICING_PASSAGER_PRIX_MINIMUM ?? '500',
        10,
      ),
    },
    colis: {
      prisEnCharge: parseInt(
        process.env.PRICING_COLIS_PRISE_EN_CHARGE ?? '700',
        10,
      ),
      parKm: parseInt(process.env.PRICING_COLIS_PAR_KM ?? '200', 10),
      parMinute: parseInt(process.env.PRICING_COLIS_PAR_MINUTE ?? '40', 10),
      prixMinimum: parseInt(
        process.env.PRICING_COLIS_PRIX_MINIMUM ?? '700',
        10,
      ),
    },
  },
});
