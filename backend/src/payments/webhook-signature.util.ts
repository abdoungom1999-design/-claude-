import { createHmac, timingSafeEqual } from 'crypto';

function comparerEnTempsConstant(a: string, b: string): boolean {
  const bufA = Buffer.from(a, 'utf8');
  const bufB = Buffer.from(b, 'utf8');
  if (bufA.length !== bufB.length) return false;
  return timingSafeEqual(bufA, bufB);
}

/**
 * Vérifie une signature au format Wave (en-tête `Wave-Signature` :
 * "t=<timestamp>,v1=<hmac_hex>"), calculée sur `${timestamp}.${corpsBrut}`
 * — schéma inspiré de Stripe. Rejette aussi les événements trop anciens
 * (protection contre le rejeu).
 *
 * Format basé sur la documentation publique de Wave ; à revalider contre
 * la documentation en vigueur au moment de l'intégration réelle.
 */
export function verifierSignatureWave(
  corpsBrut: Buffer,
  enTeteSignature: string | undefined,
  secret: string,
  toleranceSecondes = 300,
): boolean {
  if (!enTeteSignature) return false;

  const parties: Record<string, string> = {};
  for (const partie of enTeteSignature.split(',')) {
    const [cle, valeur] = partie.split('=');
    if (cle && valeur) parties[cle] = valeur;
  }

  const timestamp = parties.t;
  const signature = parties.v1;
  if (!timestamp || !signature) return false;

  const age = Math.abs(Date.now() / 1000 - Number(timestamp));
  if (!Number.isFinite(age) || age > toleranceSecondes) return false;

  const payload = `${timestamp}.${corpsBrut.toString('utf8')}`;
  const signatureAttendue = createHmac('sha256', secret)
    .update(payload)
    .digest('hex');

  return comparerEnTempsConstant(signatureAttendue, signature);
}

/**
 * Vérifie une signature HMAC-SHA256 générique calculée directement sur le
 * corps brut de la requête, transmise en hexadécimal dans un en-tête
 * dédié. Schéma par défaut retenu pour Orange Money (les conventions
 * exactes varient selon le pays/l'offre) — à ajuster si la documentation
 * fournie par Orange impose un format différent.
 */
export function verifierSignatureHmacGenerique(
  corpsBrut: Buffer,
  signatureRecue: string | undefined,
  secret: string,
): boolean {
  if (!signatureRecue) return false;
  const signatureAttendue = createHmac('sha256', secret)
    .update(corpsBrut)
    .digest('hex');
  return comparerEnTempsConstant(signatureAttendue, signatureRecue);
}
