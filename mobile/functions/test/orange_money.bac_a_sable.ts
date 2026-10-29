/**
 * Essai RÉEL contre le bac à sable d'Orange Money (données de test, aucun
 * argent réel), lancé par le flux « Essai Orange Money (bac à sable) »
 * (`.github/workflows/essai-orange-money.yml`) ; ce n'est pas un test
 * automatique (`npm test` ne le lance pas).
 *
 * Lit ORANGE_CLIENT_ID, ORANGE_CLIENT_SECRET et, facultatifs,
 * ORANGE_CODE_MARCHAND, ORANGE_CLE_NOTIFICATION et ORANGE_URL_NOTIFICATION
 * (ces deux derniers : adresse des notifications de Sprint à enregistrer chez
 * Orange) dans l'environnement. Rend une annotation GitHub par étape.
 * N'affiche jamais les identifiants, le jeton, les numéros et codes PIN de
 * test, la clé des notifications ni les liens de paiement complets : tout est
 * masqué dans le journal dès réception.
 */
import { ClientOrangeMoney, ErreurOrangeMoney, URL_ORANGE_MONEY } from '../src/orange_money';

type Niveau = 'notice' | 'warning' | 'error';

/** Échappement des commandes de workflow GitHub (titre et message). */
const echapper = (texte: string, titre = false) => {
  const s = texte.replace(/%/g, '%25').replace(/\r/g, '%0D').replace(/\n/g, '%0A');
  return titre ? s.replace(/:/g, '%3A').replace(/,/g, '%2C') : s;
};
const annoncer = (niveau: Niveau, titre: string, message: string) =>
  console.log(`::${niveau} title=${echapper(titre, true)}::${echapper(message)}`);
const masquer = (...valeurs: Array<string | undefined>) => {
  for (const valeur of valeurs) if (valeur) console.log(`::add-mask::${valeur}`);
};
const raison = (e: unknown) => (e instanceof ErreurOrangeMoney ? e.message : `Erreur inattendue : ${(e as Error).message}`);
const hote = (lien: string) => {
  try {
    return new URL(lien).host;
  } catch {
    return 'adresse illisible';
  }
};

const NAVIGATEURS = {
  ordinateur: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36',
  Android: 'Mozilla/5.0 (Linux; Android 14; SM-A145F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36',
};

/**
 * Ce que répond un lien de paiement à un navigateur : statut, redirections
 * (hôte ou type d'adresse seulement) et début du texte de la page, où toute
 * adresse est remplacée par son type (le lien de paiement n'est jamais
 * affiché) et tout nombre de 6 chiffres ou plus masqué (code marchand,
 * numéro de téléphone).
 */
async function explorer(lien: string, agent: string): Promise<string> {
  const etapes: string[] = [];
  let adresse = lien;
  for (let saut = 0; saut < 5; saut++) {
    const url = new URL(adresse);
    if (url.protocol !== 'https:' && url.protocol !== 'http:') {
      etapes.push(`ouvre une app (${url.protocol})`);
      break;
    }
    const reponse = await fetch(url, { redirect: 'manual', headers: { 'User-Agent': agent }, signal: AbortSignal.timeout(15000) });
    const cible = reponse.headers.get('location');
    if (reponse.status >= 300 && reponse.status < 400 && cible) {
      etapes.push(`HTTP ${reponse.status} (${url.host})`);
      adresse = new URL(cible, url).toString();
      masquer(adresse);
      continue;
    }
    const type = (reponse.headers.get('content-type') ?? '?').split(';')[0];
    const texte = (await reponse.text())
      .slice(0, 20_000)
      .replace(/<(script|style)[^>]*>[\s\S]*?<\/\1>/gi, ' ')
      .replace(/<[^>]+>/g, ' ')
      .replace(/([a-z][a-z0-9+.-]*):\/\/\S+/gi, '<lien $1>')
      .replace(/\d{6,}/g, '<nombre>')
      .replace(/\s+/g, ' ')
      .trim()
      .slice(0, 160);
    etapes.push(`HTTP ${reponse.status} (${url.host}, ${type})${texte ? ` « ${texte} »` : ''}`);
    break;
  }
  return etapes.join(' → ');
}

async function principal(): Promise<number> {
  const idClient = process.env.ORANGE_CLIENT_ID ?? '';
  const secretClient = process.env.ORANGE_CLIENT_SECRET ?? '';
  const codeMarchand = (process.env.ORANGE_CODE_MARCHAND ?? '').trim();
  const cleNotification = (process.env.ORANGE_CLE_NOTIFICATION ?? '').trim();
  const urlNotification = (process.env.ORANGE_URL_NOTIFICATION ?? '').trim();
  masquer(idClient, secretClient, codeMarchand, cleNotification);

  let om: ClientOrangeMoney;
  try {
    om = new ClientOrangeMoney({ urlBase: URL_ORANGE_MONEY.bacASable, idClient, secretClient });
  } catch (e) {
    annoncer('error', '0. Identifiants', raison(e));
    return 1;
  }
  let echecs = 0;

  // 1. Jeton d'accès : la preuve que les identifiants de test sont acceptés par Orange.
  try {
    masquer(await om.jeton());
    annoncer('notice', '1. Jeton d\'accès', 'Orange accepte les identifiants de test : jeton obtenu.');
  } catch (e) {
    annoncer('error', '1. Jeton d\'accès', raison(e));
    return 1; // sans jeton, aucune autre étape ne peut réussir
  }

  // 2. Numéros de test du bac à sable (un client, un marchand).
  try {
    const cartes = await om.cartesSimDeTest({ clients: 1, marchands: 1 });
    for (const carte of cartes) masquer(carte.numero, carte.codePin);
    const types = cartes.map((c) => c.type ?? '?').join(', ') || 'aucun';
    annoncer('notice', '2. Numéros de test', `${cartes.length} numéro(s) de test attribué(s) (${types}), avec leur code PIN de test.`);
  } catch (e) {
    echecs += 1;
    annoncer('error', '2. Numéros de test', raison(e));
  }

  // 3. Clé publique (chiffrement des codes PIN, utile pour les dépôts d'argent).
  try {
    const cle = await om.clePublique();
    annoncer('notice', '3. Clé publique', `Clé RSA de ${cle.tailleBits || '?'} bits reçue.`);
  } catch (e) {
    echecs += 1;
    annoncer('error', '3. Clé publique', raison(e));
  }

  // 4. Demande de paiement de test : QR code et liens (100 FCFA, valable 5 minutes, jamais payée).
  if (!codeMarchand) {
    annoncer('warning', '4. QR code de paiement', 'Aucun code marchand fourni au lancement : étape sautée.');
  } else {
    try {
      const qr = await om.genererQrCode({
        codeMarchand,
        nomMarchand: 'Sprint',
        montantFcfa: 100,
        reference: `essai-sprint-${Date.now()}`,
        validiteSecondes: 300,
      });
      masquer(qr.lienMaxIt, qr.lienOrangeMoney, qr.lienCourt, qr.qrId);
      annoncer(
        'notice',
        '4. QR code de paiement',
        [
          `lien Max It : ${qr.lienMaxIt ? `oui (${hote(qr.lienMaxIt)})` : 'non'}`,
          `lien Orange Money : ${qr.lienOrangeMoney ? 'oui' : 'non'}`,
          `lien court : ${qr.lienCourt ? 'oui' : 'non'}`,
          `image : ${qr.imageBase64 ? `oui (${Math.round((qr.imageBase64.length * 3) / 4 / 1024)} Ko)` : 'non'}`,
          `validité : ${qr.validiteSecondes ?? '?'} s`,
        ].join(' · '),
      );
      // Ce que voit un client qui ouvre les liens (sans payer) : sur ordinateur et sur Android.
      for (const [nom, lienQr] of [['Max It', qr.lienMaxIt], ['Orange Money', qr.lienOrangeMoney]] as const) {
        if (!lienQr) continue;
        for (const [appareil, agent] of Object.entries(NAVIGATEURS)) {
          try {
            annoncer('notice', `4 bis. Lien ${nom} (${appareil})`, await explorer(lienQr, agent));
          } catch (e) {
            annoncer('warning', `4 bis. Lien ${nom} (${appareil})`, `Injoignable depuis la CI : ${raison(e)}`);
          }
        }
      }
    } catch (e) {
      echecs += 1;
      annoncer('error', '4. QR code de paiement', raison(e));
    }
  }

  // 5. Adresse des notifications de Sprint : enregistrée si demandé (préparation), puis relue chez Orange.
  if (cleNotification && urlNotification) {
    if (!codeMarchand) {
      echecs += 1;
      annoncer('error', '5. Adresse des notifications', 'Code marchand nécessaire pour l\'enregistrer.');
    } else {
      try {
        await om.enregistrerNotification({ codeMarchand, nomMarchand: 'Sprint', url: urlNotification, cleApi: cleNotification });
        annoncer('notice', '5. Adresse des notifications', `Enregistrée chez Orange, avec sa clé : ${urlNotification}`);
      } catch (e) {
        echecs += 1;
        annoncer('error', '5. Adresse des notifications', raison(e));
      }
    }
  }
  try {
    const adresses = await om.notificationsEnregistrees();
    const sprint = urlNotification ? adresses.some((a) => a.url === urlNotification) : undefined;
    if (sprint === false) echecs += 1;
    annoncer(
      sprint === false ? 'error' : 'notice',
      '6. Adresses de notification',
      `${adresses.length} adresse(s) enregistrée(s) chez Orange` +
        (sprint === undefined ? '.' : `, dont celle de Sprint : ${sprint ? 'oui' : 'NON'}.`),
    );
  } catch (e) {
    echecs += 1;
    annoncer('error', '6. Adresses de notification', raison(e));
  }

  return echecs === 0 ? 0 : 1;
}

principal().then(
  (code) => {
    process.exitCode = code;
  },
  (e: unknown) => {
    annoncer('error', 'Essai', `Erreur inattendue : ${(e as Error).message}`);
    process.exitCode = 1;
  },
);
