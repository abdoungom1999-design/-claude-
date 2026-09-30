import { randomBytes } from 'node:crypto';
import type { Firestore } from 'firebase-admin/firestore';

/**
 * Faux Wave : secret de signature et pages HTML de la page de paiement
 * simulée. Aucune somme réelle n'est jamais débitée.
 */

/**
 * Secret de signature des webhooks simulés. Créé au premier besoin dans
 * `config/paiementSimule`, collection fermée à l'app par les règles :
 * seul le serveur le lit. Rien à configurer à la main.
 */
export async function secretSimulation(db: Firestore): Promise<string> {
  const ref = db.collection('config').doc('paiementSimule');
  const existant = await ref.get();
  const secret = existant.get('secret');
  if (typeof secret === 'string' && secret.length >= 32) return secret;
  try {
    const nouveau = randomBytes(32).toString('hex');
    await ref.create({ secret: nouveau });
    return nouveau;
  } catch {
    // Créé au même moment par une autre instance : on prend le sien.
    return (await ref.get()).get('secret') as string;
  }
}

export function echapper(texte: unknown): string {
  return String(texte ?? '').replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
}

function gabarit(titre: string, contenu: string): string {
  return `<!doctype html>
<html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex">
<title>${echapper(titre)}</title>
<style>
body{margin:0;font-family:system-ui,-apple-system,sans-serif;background:#eef6fb;color:#1a1a1a}
main{max-width:420px;margin:0 auto;padding:24px 16px}
.bandeau{background:#fff3cd;color:#664d03;border-radius:8px;padding:10px 12px;font-size:14px;margin-bottom:16px}
.carte{background:#fff;border-radius:12px;padding:20px;box-shadow:0 1px 4px rgba(0,0,0,.08)}
h1{font-size:20px;margin:0 0 4px;color:#1dc8ff}
.montant{font-size:32px;font-weight:700;margin:12px 0}
p{margin:6px 0;line-height:1.4}
.trajet{color:#555;font-size:14px}
button{width:100%;padding:14px;border:0;border-radius:10px;font-size:16px;font-weight:600;margin-top:12px;cursor:pointer}
.payer{background:#1dc8ff;color:#fff}
.refuser{background:#eee;color:#333}
</style></head>
<body><main>${contenu}</main></body></html>`;
}

const BANDEAU = '<div class="bandeau">Paiement de test (simulation) : aucune somme n’est débitée.</div>';

export interface CommandeAffichee {
  prixFcfa: number;
  adresseDepart: string;
  adresseArrivee: string;
  statut: string;
  methodePaiement: string;
}

function fcfa(montant: number): string {
  return `${String(montant).replace(/\B(?=(\d{3})+(?!\d))/g, ' ')} FCFA`;
}

/** Page de paiement simulée (Wave ou Orange Money, selon la commande). */
export function pagePaiement(sessionId: string, commande: CommandeAffichee): string {
  if (commande.statut !== 'en_attente_paiement') {
    return pageMessage('Paiement déjà traité', 'Cette demande de paiement n’est plus en attente. Retournez sur Sprint.');
  }
  const session = echapper(sessionId);
  const operateur = commande.methodePaiement === 'ORANGE_MONEY' ? 'Orange Money' : 'Wave';
  return gabarit(
    `${operateur} (simulation)`,
    `${BANDEAU}<div class="carte">
<h1>${operateur}</h1>
<p>Sprint vous demande :</p>
<div class="montant">${echapper(fcfa(commande.prixFcfa))}</div>
<p class="trajet">${echapper(commande.adresseArrivee ? `${commande.adresseDepart} → ${commande.adresseArrivee}` : commande.adresseDepart)}</p>
<form method="post">
<input type="hidden" name="session" value="${session}">
<button class="payer" name="choix" value="payer">Payer</button>
<button class="refuser" name="choix" value="refuser">Refuser le paiement</button>
</form></div>`,
  );
}

export function pageMessage(titre: string, message: string): string {
  return gabarit(titre, `${BANDEAU}<div class="carte"><h1>${echapper(titre)}</h1><p>${echapper(message)}</p></div>`);
}
