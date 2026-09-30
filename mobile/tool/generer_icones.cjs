// Régénère toutes les images dérivées du logo Sprint (icônes Android, PWA et
// iPhone, écran de démarrage) à partir de assets/logo/source-1024.jpg.
//
//   cd mobile/tool && npm install && node generer_icones.cjs
//
// Le logo source est une image 1024 x 1024 : une tuile de marbre noir aux
// coins arrondis posée sur une plaque grise. Seule la tuile sert : les
// mesures ci-dessous (position, rayon des coins, position du « S ») sont
// celles de cette image ; à refaire si le fichier source change.
const sharp = require('sharp');
const potrace = require('potrace');
const fs = require('node:fs');
const path = require('node:path');

const RACINE = path.resolve(__dirname, '..');
const SOURCE = path.join(RACINE, 'assets/logo/source-1024.jpg');

// Tuile dans l'image source.
const TUILE = { left: 202, top: 204, taille: 614, rayon: 128 };
// « S » : centre et distance du point le plus éloigné (zone à garder entière
// dans les icônes rondes des téléphones).
const S = { x: 504, y: 510, rayon: 246, boite: { left: 340, top: 327, right: 668, bottom: 694 } };
// Carré plein cadre pris dans la tuile (à l'abri des coins arrondis).
const CARRE = { left: 248, top: 250, taille: 522 };

const ONYX = '#0B0B0C';
// Couleur moyenne du marbre noir de la tuile (aplat de fond des icônes rondes).
const MARBRE = '#15181C';
const ecrire = (chemin, tampon) => {
  const complet = path.join(RACINE, chemin);
  fs.mkdirSync(path.dirname(complet), { recursive: true });
  fs.writeFileSync(complet, tampon);
  console.log('  ', chemin, tampon.length, 'octets');
};

/** Tuile aux coins arrondis, fond transparent autour. */
async function tuile(taille, format = 'png') {
  const masque = Buffer.from(
    `<svg width="${TUILE.taille}" height="${TUILE.taille}"><rect x="2" y="2" width="${TUILE.taille - 4}" height="${TUILE.taille - 4}" rx="${TUILE.rayon - 2}" fill="#fff"/></svg>`,
  );
  const decoupe = await sharp(SOURCE)
    .extract({ left: TUILE.left, top: TUILE.top, width: TUILE.taille, height: TUILE.taille })
    .ensureAlpha()
    .composite([{ input: masque, blend: 'dest-in' }])
    .png()
    .toBuffer();
  const image = sharp(decoupe).resize(taille, taille, { kernel: 'lanczos3' });
  return format === 'webp' ? image.webp({ quality: 88, alphaQuality: 100 }).toBuffer() : image.png({ compressionLevel: 9 }).toBuffer();
}

/** Carré plein cadre (sans transparence). */
const carre = (taille) =>
  sharp(SOURCE)
    .extract({ left: CARRE.left, top: CARRE.top, width: CARRE.taille, height: CARRE.taille })
    .resize(taille, taille, { kernel: 'lanczos3' })
    .removeAlpha()
    .png({ compressionLevel: 9 })
    .toBuffer();

/**
 * Icône dont le « S » tient dans un cercle de [rayonS] (part de la taille) :
 * le marbre est réduit et se fond, par un dégradé circulaire, dans un aplat
 * de la couleur du marbre. Sert aux icônes adaptatives Android et
 * « maskable » du web, que le téléphone découpe en rond ou en carré arrondi :
 * le « S » reste entier, sans bord de carré visible.
 */
async function etendu(taille, rayonS) {
  const demi = 285; // demi-côté du morceau de source utilisé (hors liseré de la tuile)
  const debut = 250; // le fondu commence juste après le point le plus éloigné du « S » (246)
  const fin = 290;
  const k = (rayonS * taille) / S.rayon; // pixels de sortie par pixel de source
  const largeur = Math.round(2 * demi * k);
  const art = await sharp(SOURCE)
    .extract({ left: S.x - demi, top: S.y - demi, width: 2 * demi, height: 2 * demi })
    .resize(largeur, largeur, { kernel: 'lanczos3' })
    .removeAlpha()
    .toBuffer();
  // Masque circulaire : opaque jusqu'à [debut], transparent à [fin].
  const masque = Buffer.alloc(largeur * largeur);
  for (let y = 0; y < largeur; y++) {
    for (let x = 0; x < largeur; x++) {
      const r = Math.hypot(x - largeur / 2, y - largeur / 2) / k;
      masque[y * largeur + x] = Math.round(255 * Math.min(1, Math.max(0, (fin - r) / (fin - debut))));
    }
  }
  const artAlpha = await sharp(art).joinChannel(masque, { raw: { width: largeur, height: largeur, channels: 1 } }).png().toBuffer();
  const pos = Math.round((taille - largeur) / 2);
  return sharp({ create: { width: taille, height: taille, channels: 3, background: MARBRE } })
    .composite([{ input: artAlpha, left: pos, top: pos }])
    .removeAlpha()
    .png({ compressionLevel: 9 })
    .toBuffer();
}

/** Silhouette du « S » (blanc, sans fond) en chemin vectoriel, pour l'icône de notification. */
async function silhouette() {
  const { left, top, right, bottom } = S.boite;
  const marge = 8;
  const w = right - left + 2 * marge;
  const h = bottom - top + 2 * marge;
  const brut = await sharp(SOURCE).extract({ left: left - marge, top: top - marge, width: w, height: h }).raw().toBuffer();
  const masque = Buffer.alloc(w * h);
  for (let i = 0; i < w * h; i++) {
    const r = brut[i * 3], g = brut[i * 3 + 1], b = brut[i * 3 + 2];
    const lum = 0.3 * r + 0.59 * g + 0.11 * b;
    masque[i] = lum > 110 && Math.max(r, g, b) - Math.min(r, g, b) < 60 ? 255 : 0;
  }
  // Lissage : ferme les petits trous du biseau de verre et arrondit le contour.
  const lisse = await sharp(masque, { raw: { width: w, height: h, channels: 1 } })
    .blur(3)
    .threshold(110)
    .png()
    .toBuffer();
  const svg = await new Promise((resolve, reject) =>
    potrace.trace(lisse, { turdSize: 60, optTolerance: 0.6, alphaMax: 1.1, blackOnWhite: false }, (e, s) => (e ? reject(e) : resolve(s))),
  );
  const chemin = [...svg.matchAll(/ d="([^"]+)"/g)].map((m) => m[1]).join(' ');
  return { chemin: chemin.replace(/\s+/g, ' ').trim(), w, h };
}

(async () => {
  console.log('Web');
  ecrire('web/icons/Icon-192.png', await carre(192));
  ecrire('web/icons/Icon-512.png', await carre(512));
  ecrire('web/icons/Icon-maskable-192.png', await etendu(192, 0.36));
  ecrire('web/icons/Icon-maskable-512.png', await etendu(512, 0.36));
  ecrire('web/icons/apple-touch-icon.png', await carre(180));
  ecrire('web/favicon.png', await tuile(64));

  console.log('Écran de démarrage');
  ecrire('assets/logo/tuile.png', await tuile(512));
  const webp = await tuile(384, 'webp');
  const uri = `data:image/webp;base64,${webp.toString('base64')}`;
  const index = path.join(RACINE, 'web/index.html');
  const html = fs.readFileSync(index, 'utf8');
  const remplace = html.replace(/(<img id="demarrage-logo"[^>]*? src=")[^"]*(")/, `$1${uri}$2`);
  if (remplace === html && !html.includes(uri)) throw new Error('balise #demarrage-logo introuvable dans web/index.html');
  fs.writeFileSync(index, remplace);

  // Images de démarrage iPhone : tuile centrée dans la zone visible (sous la barre d'état).
  const tailles = [[430, 932, 3, 59], [393, 852, 3, 54], [428, 926, 3, 47], [390, 844, 3, 47], [375, 812, 3, 44], [414, 896, 3, 44], [414, 896, 2, 48], [414, 736, 3, 20], [375, 667, 2, 20], [320, 568, 2, 20], [402, 874, 3, 62], [440, 956, 3, 62]];
  for (const [w, h, r, barre] of tailles) {
    const cote = 128 * r;
    const logo = await tuile(cote);
    const centreY = Math.round(((h + barre) / 2) * r);
    const image = sharp({ create: { width: w * r, height: h * r, channels: 3, background: ONYX } })
      .composite([{ input: logo, left: Math.round((w * r - cote) / 2), top: Math.round(centreY - cote / 2) }])
      .png({ compressionLevel: 9 });
    ecrire(`web/splash/ios-${w}x${h}@${r}x.png`, await image.toBuffer());
  }

  console.log('Android');
  const res = 'android/app/src/main/res';
  for (const [dossier, px] of [['mdpi', 48], ['hdpi', 72], ['xhdpi', 96], ['xxhdpi', 144], ['xxxhdpi', 192]]) {
    ecrire(`${res}/mipmap-${dossier}/ic_launcher.png`, await tuile(px));
  }
  for (const [dossier, px] of [['mdpi', 108], ['hdpi', 162], ['xhdpi', 216], ['xxhdpi', 324], ['xxxhdpi', 432]]) {
    ecrire(`${res}/mipmap-${dossier}/ic_launcher_foreground.png`, await etendu(px, 0.30));
  }
  ecrire(`${res}/drawable-nodpi/splash_logo.png`, await tuile(512));

  const { chemin, w, h } = await silhouette();
  const echelle = 19 / Math.max(w, h);
  const dx = (24 - w * echelle) / 2;
  const dy = (24 - h * echelle) / 2;
  const xml = `<?xml version="1.0" encoding="utf-8"?>
<!-- Petite icône des notifications (blanche, sans fond : Android la teinte
     avec la couleur de Sprint) : silhouette du « S » du logo. Générée par
     tool/generer_icones.cjs. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <group
        android:translateX="${dx.toFixed(3)}"
        android:translateY="${dy.toFixed(3)}"
        android:scaleX="${echelle.toFixed(5)}"
        android:scaleY="${echelle.toFixed(5)}">
        <path
            android:fillColor="#FFFFFFFF"
            android:pathData="${chemin}" />
    </group>
</vector>
`;
  ecrire(`${res}/drawable/ic_stat_sprint.xml`, Buffer.from(xml));
  console.log('Terminé.');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
