/**
 * Essai RÉEL contre Orange Money, lancé par le flux « Essai Orange Money »
 * (`.github/workflows/essai-orange-money.yml`) ; ce n'est pas un test
 * automatique (`npm test` ne le lance pas). Environnement choisi au
 * lancement (ORANGE_ENVIRONNEMENT) :
 * - `bacASable` : données de test, aucun argent réel ;
 * - `production` : identifiants de production. L'essai n'y paie RIEN : jeton,
 *   une demande de paiement de 100 FCFA que personne ne paie (elle expire
 *   seule au bout de 5 minutes) et lectures ; ni numéros de test ni clé
 *   publique (bac à sable seulement).
 *
 * Lit ORANGE_ENVIRONNEMENT, ORANGE_CLIENT_ID, ORANGE_CLIENT_SECRET et,
 * facultatifs, ORANGE_CODE_MARCHAND, ORANGE_CLE_NOTIFICATION et
 * ORANGE_URL_NOTIFICATION (ces deux derniers : adresse des notifications de
 * Sprint à enregistrer chez Orange) et ORANGE_TRANSACTION_A_SUIVRE (un
 * paiement réel à relire, lecture seule : la demande de 100 FCFA est alors
 * sautée) dans l'environnement. Rend une annotation
 * GitHub par étape. N'affiche jamais les identifiants, le jeton, les numéros
 * et codes PIN de test, la clé des notifications ni les liens de paiement
 * complets : tout est masqué dans le journal dès réception.
 */
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import type { EnvironnementOrangeMoney } from '../src/methodes_paiement';
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

/** Forme d'une réponse JSON : types, clés et tailles, jamais les valeurs. */
function forme(valeur: unknown, profondeur = 0): string {
  if (Array.isArray(valeur)) {
    return `tableau[${valeur.length}]${valeur.length > 0 && profondeur < 3 ? ` de ${forme(valeur[0], profondeur + 1)}` : ''}`;
  }
  if (valeur !== null && typeof valeur === 'object') {
    const objet = valeur as Record<string, unknown>;
    return `{${Object.keys(objet)
      .map((cle) => (profondeur < 3 ? `${cle}: ${forme(objet[cle], profondeur + 1)}` : cle))
      .join(', ')}}`;
  }
  return valeur === null ? 'null' : typeof valeur;
}

/**
 * Diagnostic : réponse BRUTE d'Orange à une lecture (statut et forme, et si
 * l'adresse [cherchee], publique, y figure), pour comparer à la spécification.
 */
async function reponseBrute(om: ClientOrangeMoney, urlBase: string, chemin: string, cherchee: string): Promise<string> {
  const reponse = await fetch(`${urlBase}${chemin}`, {
    headers: { Authorization: `Bearer ${await om.jeton()}`, 'Content-Type': 'application/json', Accept: 'application/json' },
    signal: AbortSignal.timeout(15000),
  });
  const texte = await reponse.text();
  let corps: unknown;
  try {
    corps = JSON.parse(texte);
  } catch {
    corps = undefined;
  }
  return (
    `HTTP ${reponse.status}, ${corps === undefined ? `texte de ${texte.length} caractère(s)` : forme(corps)}` +
    `, adresse de Sprint présente : ${texte.includes(cherchee) ? 'oui' : 'non'}`
  );
}

const pause = (ms: number) => new Promise((resoudre) => setTimeout(resoudre, ms));

/** Forme d'un identifiant, sans sa valeur : longueur et sorte de caractères. */
function formeCle(valeur: string): string {
  const sorte = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(valeur)
    ? 'format UUID'
    : /^[0-9a-f]+$/i.test(valeur)
      ? 'hexadécimal'
      : /^[A-Za-z0-9]+$/.test(valeur)
        ? 'lettres et chiffres'
        : /^[A-Za-z0-9+/=_-]+$/.test(valeur)
          ? 'lettres, chiffres et + / = _ -'
          : 'autres caractères';
  return valeur ? `${valeur.length} caractères, ${sorte}` : 'vide';
}

/** Forme d'une référence, sans sa valeur : longueur, début, et ce qu'elle semble être. */
function formeReference(ref: string): string {
  const debut = /^[A-Za-z0-9_-]{4}/.test(ref) ? ref.slice(0, 4) : '?';
  const sorte = ref.startsWith('rch_')
    ? 'recharge Sprint'
    : /^[0-9a-f]{24}$/.test(ref)
      ? 'commande Sprint (24 hexadécimaux)'
      : /rch_/i.test(ref)
        ? 'contient « rch_ » ailleurs qu\'au début'
        : /^MP\d/.test(ref)
          ? 'identifiant Orange (MP…)'
          : 'autre forme';
  return `${ref.length} caractères, début « ${debut} », ${sorte}`;
}

/** Champs d'un document Sprint affichables sans rien révéler de la personne (ni identifiant, ni adresse, ni nom). */
const CHAMPS_SURS = [
  'statut', 'type', 'methodePaiement', 'fournisseur', 'prixFcfa', 'montantFcfa', 'motifRemboursement', 'motifAnnulation',
  'annuleePar', 'creeLe', 'payeeLe', 'timestamp', 'annuleeLe', 'termineeLe', 'expireLe',
];

/** Champs sûrs d'un document, en texte (dates en UTC). */
function champsSurs(doc: FirebaseFirestore.DocumentSnapshot): string {
  const champs = CHAMPS_SURS.flatMap((champ) => {
    const v = doc.get(champ) as unknown;
    if (v === undefined || v === null) return [];
    return [`${champ} ${v instanceof Timestamp ? v.toDate().toISOString().slice(0, 19).replace('T', ' ') + ' UTC' : String(v)}`];
  });
  return champs.join(', ') || 'document sans champ affichable';
}

/**
 * Production, suivi d'un paiement : ce que la VRAIE base de Sprint a fait de cette référence (lecture
 * seule, champs sûrs seulement) : commande ou course payée, recharge créditée.
 */
async function documentsSprint(reference: string): Promise<string[]> {
  const app = initializeApp({ projectId: 'sprint-vtc' }, 'suivi');
  try {
    const db = getFirestore(app);
    const lignes: string[] = [];
    for (const chemin of [`commandes/${reference}`, `courses/${reference}`, `recharges/${reference}`, `recharges/rch_${reference}`]) {
      const doc = await db.doc(chemin).get();
      const nom = chemin.split('/')[0] + (chemin.includes('rch_') ? ' (rch_ + référence)' : '');
      if (!doc.exists) {
        lignes.push(`${nom} : aucun document`);
        continue;
      }
      lignes.push(`${nom} : ${champsSurs(doc)}`);
      if (nom !== 'commandes') continue;
      // La course créée par ce paiement (son propre identifiant), et un éventuel remboursement sur le solde.
      const courseId = doc.get('courseId') as string | undefined;
      if (courseId) {
        const course = await db.doc(`courses/${courseId}`).get();
        lignes.push(
          `course créée par ce paiement : ${course.exists ? `${champsSurs(course)}, chauffeur attribué : ${course.get('chauffeurId') ? 'oui' : 'non'}` : 'introuvable'}`,
        );
      }
      const clientId = doc.get('clientId') as string | undefined;
      if (clientId) {
        const rendu = await db.doc(`portefeuilles/${clientId}/mouvements/remboursement_${reference}`).get();
        lignes.push(`remboursement sur le solde Sprint : ${rendu.exists ? champsSurs(rendu) : 'aucun'}`);
      }
    }
    return lignes;
  } finally {
    await deleteApp(app);
  }
}

/** Champs texte ou nombre d'une réponse JSON, à toute profondeur (chemins « a.b.c »). */
function champsTexte(valeur: unknown, prefixe = '', profondeur = 0): Array<[string, string]> {
  if (valeur === null || typeof valeur !== 'object' || profondeur > 4) return [];
  return Object.entries(valeur as Record<string, unknown>).flatMap(([cle, v]): Array<[string, string]> => {
    const chemin = prefixe ? `${prefixe}.${cle}` : cle;
    return typeof v === 'string' || typeof v === 'number' ? [[chemin, String(v)]] : champsTexte(v, chemin, profondeur + 1);
  });
}

/**
 * Diagnostic d'un refus de jeton : réponse BRUTE d'Orange (statut, en-têtes
 * utiles, champs du corps), les identifiants remplacés par « <identifiant> »
 * et tout nombre de 6 chiffres ou plus masqué ; un jeton accordé n'est
 * jamais affiché.
 */
async function diagnosticJeton(urlBase: string, init: RequestInit, identifiants: string[]): Promise<string> {
  const reponse = await fetch(`${urlBase}/oauth/v1/token`, { ...init, signal: AbortSignal.timeout(15000) });
  const brut = await reponse.text();
  let corps: unknown;
  try {
    corps = JSON.parse(brut);
  } catch {
    corps = undefined;
  }
  if (reponse.ok) {
    const jeton = (corps as Record<string, unknown> | undefined)?.access_token;
    if (typeof jeton === 'string') masquer(jeton);
    return `HTTP ${reponse.status} : jeton accordé de cette façon.`;
  }
  const propre = (texte: string) => {
    let r = texte;
    for (const v of identifiants) if (v) r = r.split(v).join('<identifiant>');
    return r.replace(/\d{6,}/g, '<nombre>').replace(/\s+/g, ' ').trim().slice(0, 200);
  };
  // Chemins pointés plutôt que des accolades (le journal de GitHub masque « { » et « } »).
  const champs = champsTexte(corps)
    .map(([chemin, v]) => `${chemin} = « ${propre(v)} »`)
    .join(', ');
  const authentifier = reponse.headers.get('www-authenticate');
  return [
    `HTTP ${reponse.status}`,
    `type ${(reponse.headers.get('content-type') ?? '?').split(';')[0]}`,
    authentifier ? `WWW-Authenticate « ${propre(authentifier)} »` : '',
    corps === undefined
      ? `corps : ${brut.length} caractère(s)${brut ? ` « ${propre(brut.replace(/<[^>]+>/g, ' '))} »` : ''}`
      : `corps : ${champs || forme(corps)}`,
  ]
    .filter(Boolean)
    .join(' · ');
}

async function principal(): Promise<number> {
  const lu = process.env.ORANGE_ENVIRONNEMENT;
  const idClient = process.env.ORANGE_CLIENT_ID ?? '';
  const secretClient = process.env.ORANGE_CLIENT_SECRET ?? '';
  const codeMarchand = (process.env.ORANGE_CODE_MARCHAND ?? '').trim();
  const cleNotification = (process.env.ORANGE_CLE_NOTIFICATION ?? '').trim();
  const urlNotification = (process.env.ORANGE_URL_NOTIFICATION ?? '').trim();
  const aSuivre = (process.env.ORANGE_TRANSACTION_A_SUIVRE ?? '').trim();
  masquer(idClient, secretClient, codeMarchand, cleNotification);
  if (lu !== 'bacASable' && lu !== 'production') {
    annoncer('error', '0. Environnement', 'ORANGE_ENVIRONNEMENT : « bacASable » ou « production » attendu.');
    return 1;
  }
  const environnement: EnvironnementOrangeMoney = lu;
  const production = environnement === 'production';
  const urlBase = URL_ORANGE_MONEY[environnement];

  let om: ClientOrangeMoney;
  try {
    om = new ClientOrangeMoney({ urlBase, idClient, secretClient });
  } catch (e) {
    annoncer('error', '0. Identifiants', raison(e));
    return 1;
  }
  let echecs = 0;

  // 1. Jeton d'accès : la preuve que les identifiants de cet environnement sont acceptés par Orange.
  try {
    const debutJeton = Date.now();
    masquer(await om.jeton());
    annoncer(
      'notice',
      '1. Jeton d\'accès',
      `Orange accepte les identifiants ${production ? 'de PRODUCTION' : 'de test'} (${new URL(urlBase).host}) : jeton obtenu en ${Date.now() - debutJeton} ms.`,
    );
  } catch (e) {
    annoncer('error', '1. Jeton d\'accès', raison(e));
    // Diagnostic, sans aucune valeur : forme des identifiants (comparée au bac à sable en production),
    // puis réponse brute d'Orange, identifiants dans le formulaire puis dans l'en-tête « Basic ».
    const idBac = process.env.ORANGE_CLIENT_ID_BAC ?? '';
    const secretBac = process.env.ORANGE_CLIENT_SECRET_BAC ?? '';
    masquer(idBac, secretBac);
    const [fId, fSecret, fIdBac, fSecretBac] = [idClient, secretClient, idBac, secretBac].map(formeCle);
    annoncer(
      'notice',
      '1 bis. Forme des identifiants',
      `Clé ID : ${fId} · Clé secrète : ${fSecret}` +
        (idClient === secretClient ? ' · Clé ID et Clé secrète IDENTIQUES' : '') +
        (production && idBac && secretBac
          ? ` · bac à sable : Clé ID ${fIdBac}, Clé secrète ${fSecretBac}` +
            ` · copiées du bac à sable : Clé ID ${idClient === idBac ? 'OUI' : 'non'}, Clé secrète ${secretClient === secretBac ? 'OUI' : 'non'}` +
            ` · formes croisées (Clé ID et Clé secrète inversées ?) : ${fIdBac !== fSecretBac && fId === fSecretBac && fSecret === fIdBac ? 'OUI, probablement' : 'non'}`
          : ''),
    );
    const variantes: Array<[string, RequestInit]> = [
      [
        'identifiants dans le formulaire',
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'application/json' },
          body: new URLSearchParams({ client_id: idClient, client_secret: secretClient, grant_type: 'client_credentials' }).toString(),
        },
      ],
      [
        'identifiants dans l\'en-tête Basic',
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            Accept: 'application/json',
            Authorization: `Basic ${Buffer.from(`${idClient}:${secretClient}`).toString('base64')}`,
          },
          body: new URLSearchParams({ grant_type: 'client_credentials' }).toString(),
        },
      ],
    ];
    masquer(Buffer.from(`${idClient}:${secretClient}`).toString('base64'));
    for (const [nom, init] of variantes) {
      try {
        annoncer('notice', `1 ter. Jeton, ${nom}`, await diagnosticJeton(urlBase, init, [idClient, secretClient]));
      } catch (erreur) {
        annoncer('warning', `1 ter. Jeton, ${nom}`, raison(erreur));
      }
    }
    return 1; // sans jeton, aucune autre étape ne peut réussir
  }

  if (!production) {
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
  }

  // 4. Demande de paiement : QR code et liens (100 FCFA, valable 5 minutes, à usage unique, jamais payée).
  if (aSuivre) {
    annoncer('notice', '4. QR code de paiement', 'Suivi d\'un paiement : aucune nouvelle demande.');
  } else if (!codeMarchand) {
    annoncer('warning', '4. QR code de paiement', 'Aucun code marchand fourni au lancement : étape sautée.');
  } else {
    try {
      const debutQr = Date.now();
      const qr = await om.genererQrCode({
        codeMarchand,
        nomMarchand: 'Sprint',
        montantFcfa: 100,
        reference: `essai-sprint-${Date.now()}`,
        validiteSecondes: 300,
        usageUnique: true,
      });
      const dureeQr = Date.now() - debutQr;
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
          `créée par Orange en ${dureeQr} ms`,
        ].join(' · ') + (production ? ' · demande réelle de 100 FCFA que personne ne paie : elle expire seule.' : ''),
      );
      // Ce que voit un client qui ouvre les liens (sans payer) : sur ordinateur et sur Android (bac à sable).
      for (const [nom, lienQr] of [['Max It', qr.lienMaxIt], ['Orange Money', qr.lienOrangeMoney]] as const) {
        if (!lienQr || production) continue;
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
        // Orange ajoute une entrée à chaque enregistrement (rien ne se supprime) : pas de doublon.
        const deja = (await om.notificationsEnregistrees()).filter((a) => a.url === urlNotification && a.codeMarchand === codeMarchand);
        if (deja.length > 0) {
          annoncer('notice', '5. Adresse des notifications', `Déjà enregistrée chez Orange (${deja.length} fois) : rien de nouveau.`);
        } else {
          await om.enregistrerNotification({ codeMarchand, nomMarchand: 'Sprint', url: urlNotification, cleApi: cleNotification });
          annoncer('notice', '5. Adresse des notifications', `Enregistrée chez Orange, avec sa clé : ${urlNotification}`);
        }
      } catch (e) {
        echecs += 1;
        annoncer('error', '5. Adresse des notifications', raison(e));
      }
    }
  }
  try {
    let adresses = await om.notificationsEnregistrees();
    let sprint = urlNotification ? adresses.some((a) => a.url === urlNotification) : undefined;
    // L'enregistrement peut mettre quelques secondes à apparaître : deux nouvelles lectures.
    for (let essai = 0; sprint === false && essai < 2; essai++) {
      await pause(5000);
      adresses = await om.notificationsEnregistrees();
      sprint = adresses.some((a) => a.url === urlNotification);
    }
    if (sprint === false) {
      echecs += 1;
      for (const chemin of [
        '/api/notification/v1/merchantcallback',
        `/api/notification/v1/merchantcallback?code=${encodeURIComponent(codeMarchand)}`,
        `/api/notification/v1/merchantcallback?code=${encodeURIComponent(codeMarchand)}&page=0&size=20`,
      ]) {
        const titre = `6 bis. Réponse brute ${chemin.includes('page=') ? '(code, page 0)' : chemin.includes('code=') ? '(code)' : '(sans filtre)'}`;
        try {
          annoncer('notice', titre, await reponseBrute(om, urlBase, chemin, urlNotification));
        } catch (e) {
          annoncer('warning', titre, raison(e));
        }
      }
    }
    // Adresses (publiques) et marchand concerné ; le code marchand lui-même n'est jamais affiché.
    const detail = adresses
      .map((a) => `${a.url} (${a.codeMarchand === codeMarchand ? 'code de Sprint' : 'autre code'}${a.nom ? `, « ${a.nom} »` : ''})`)
      .join(' ; ');
    annoncer(
      sprint === false ? 'error' : 'notice',
      '6. Adresses de notification',
      `${adresses.length} adresse(s) enregistrée(s) chez Orange` +
        (sprint === undefined ? '' : `, dont celle de Sprint : ${sprint ? 'oui' : 'NON'}`) +
        (detail ? ` : ${detail}.` : '.'),
    );
  } catch (e) {
    echecs += 1;
    annoncer('error', '6. Adresses de notification', raison(e));
  }

  // 7. Suivi d'un paiement réel, lu chez Orange (lecture seule : rien n'est appliqué). Jamais le
  // client payeur (son numéro), ni le code marchand, ni la référence complète.
  if (aSuivre) {
    try {
      const trouvees = await om.rechercherTransactions({ transactionId: aSuivre });
      if (trouvees.length === 0) {
        echecs += 1;
        annoncer('error', '7. Suivi du paiement', 'Orange ne connaît aucune transaction avec cet identifiant dans cet environnement.');
      }
      const memes = trouvees.filter((t) => t.transactionId === aSuivre).length;
      annoncer('notice', '7. Suivi du paiement', `${trouvees.length} transaction(s) renvoyée(s) par Orange, dont ${memes} avec cet identifiant.`);
      for (const t of trouvees) {
        masquer(t.reference);
        const marchand = t.codeMarchand === undefined ? 'sans code' : t.codeMarchand === codeMarchand ? 'code de Sprint' : 'AUTRE code';
        annoncer(
          'notice',
          `7. Suivi du paiement (${t.transactionId === aSuivre ? 'celle demandée' : 'AUTRE transaction'})`,
          [
            `statut : ${t.statut ?? 'absent'}`,
            `montant : ${t.montantFcfa ?? '?'} ${t.devise ?? ''}`.trim(),
            `type : ${t.type ?? 'absent'}`,
            `marchand payé : ${t.typePartenaire ?? 'nature absente'}, ${marchand}`,
            `référence : ${t.reference ? formeReference(t.reference) : 'absente'}`,
          ].join(' · '),
        );
      }
      // Ce que la base de Sprint en a fait (production seulement, lecture seule).
      for (const t of trouvees) {
        if (!production || !t.reference) continue;
        try {
          for (const ligne of await documentsSprint(t.reference)) annoncer('notice', '7 ter. Base de Sprint', ligne);
        } catch (e) {
          annoncer('warning', '7 ter. Base de Sprint', `Lecture impossible : ${(e as Error).message}`);
        }
      }
      // Réponse brute : où est notre référence ? Chemins des champs seulement (jamais ceux du client payeur),
      // et ceux dont la valeur contient « rch_ » ou une référence de commande.
      const brute = await fetch(
        `${urlBase}/api/eWallet/v1/transactions?${new URLSearchParams({ size: '20', transactionId: aSuivre })}`,
        { headers: { Authorization: `Bearer ${await om.jeton()}`, Accept: 'application/json' }, signal: AbortSignal.timeout(15000) },
      );
      const liste = (await brute.json().catch(() => undefined)) as unknown;
      const elements = Array.isArray(liste) ? liste : [];
      elements.forEach((element, i) => {
        const champs = champsTexte(element).filter(([chemin]) => !chemin.startsWith('customer'));
        for (const [, v] of champs) if (/rch_|^[0-9a-f]{24}$/i.test(v)) masquer(v);
        const avecReference = champs.filter(([, v]) => /rch_/i.test(v) || /^[0-9a-f]{24}$/.test(v)).map(([chemin]) => chemin);
        // Horodatages d'Orange (sans rien de personnel) : à comparer à ceux de Sprint (7 ter).
        const dates = champs
          .filter(([chemin]) => /(^|\.)(requestDate|createdAt|updatedAt|dispatched)$/.test(chemin))
          .map(([chemin, v]) => `${chemin} ${v}`);
        annoncer(
          'notice',
          `7 bis. Transaction brute n° ${i + 1}`,
          `HTTP ${brute.status} · champs : ${champs.map(([chemin]) => chemin).join(', ')} · notre référence dans : ${avecReference.join(', ') || 'aucun champ'}` +
            ` · horodatages d'Orange : ${dates.join(', ') || 'aucun'}`,
        );
      });
    } catch (e) {
      echecs += 1;
      annoncer('error', '7. Suivi du paiement', raison(e));
    }
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
