export default () => ({
  port: parseInt(process.env.PORT ?? '3000', 10),
  app: {
    // URL publiquement accessible de cette API, utilisée pour construire
    // l'URL de notification (notif_url) transmise à Orange Money.
    publicUrl: process.env.APP_PUBLIC_URL ?? 'http://localhost:3000',
  },
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
    wave: {
      apiUrl: process.env.WAVE_API_URL ?? 'https://api.wave.com/v1',
      apiKey: process.env.WAVE_API_KEY,
      webhookSecret: process.env.WAVE_WEBHOOK_SECRET,
      successUrl: process.env.WAVE_SUCCESS_URL ?? 'sprint://paiement/succes',
      errorUrl: process.env.WAVE_ERROR_URL ?? 'sprint://paiement/echec',
    },
    orangeMoney: {
      authUrl:
        process.env.ORANGE_MONEY_AUTH_URL ??
        'https://api.orange.com/oauth/v3/token',
      apiUrl:
        process.env.ORANGE_MONEY_API_URL ??
        'https://api.orange.com/orange-money-webpay/sn/v1',
      clientId: process.env.ORANGE_MONEY_CLIENT_ID,
      clientSecret: process.env.ORANGE_MONEY_CLIENT_SECRET,
      merchantKey: process.env.ORANGE_MONEY_MERCHANT_KEY,
      webhookSecret: process.env.ORANGE_MONEY_WEBHOOK_SECRET,
      returnUrl:
        process.env.ORANGE_MONEY_RETURN_URL ?? 'sprint://paiement/succes',
      cancelUrl:
        process.env.ORANGE_MONEY_CANCEL_URL ?? 'sprint://paiement/echec',
    },
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
