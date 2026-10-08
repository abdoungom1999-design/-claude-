import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  classer,
  commitsDeDesign,
  controlerIntegrite,
  controlerLignes,
  estLotDeDesign,
  lignesDuDiff,
  lotDuCommit,
  lotEntre,
} from '../outils_design.mjs';

const SCRIPT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'outils_design.mjs');

// ---- classement des fichiers -----------------------------------------------------------

test('zone autorisée : l’apparence de l’app, et rien d’autre', () => {
  const autorises = [
    'mobile/lib/features/compte/presentation/compte_tab_page.dart',
    'mobile/lib/features/admin/presentation/sections/admin_finances_section.dart',
    'mobile/lib/core/widgets/primary_button.dart',
    'mobile/lib/core/theme/app_colors.dart',
    'mobile/assets/promo/course.jpg',
    'mobile/web/icons/Icon-192.png',
    'mobile/web/splash/ios-390x844@3x.png',
    'mobile/web/favicon.png',
    'mobile/web/index.html',
    'mobile/android/app/src/main/res/mipmap-hdpi/ic_launcher.png',
    'mobile/test/onyx_vert_test.dart',
  ];
  for (const chemin of autorises) assert.equal(classer(chemin).zone, 'autorisee', chemin);
});

test('zone interdite : serveur, règles, secrets, accès aux données, chaîne de publication', () => {
  const interdits = [
    'mobile/functions/src/index.ts',
    'mobile/functions/src/fournisseurs.ts',
    'mobile/firestore.rules',
    'mobile/storage.rules',
    'mobile/firestore_rules_test/regles.test.mjs',
    'mobile/firebase.json',
    'mobile/hebergement/assembler.sh',
    '.github/workflows/flutter-web.yml',
    'mobile/securite/garde_fuites.mjs',
    '.claude/skills/ui-ux-pro-max/SKILL.md',
    '.mcp.json',
    'mobile/.mcp.json',
    'mobile/lib/features/auth/data/auth_repository.dart',
    'mobile/lib/features/portefeuille/data/portefeuille_repository.dart',
    'mobile/lib/core/firebase/firebase_service.dart',
    'mobile/lib/core/network/api_client.dart',
    'mobile/lib/firebase_options.dart',
    'mobile/pubspec.yaml',
    'mobile/pubspec.lock',
    'mobile/web/firebase-messaging-sw.js',
    'mobile/test/palette_onyx_vert_test.dart',
    'mobile/.env',
    'mobile/functions/.env.local',
    'mobile/android/app/google-services.json',
    'mobile/android/key.properties',
    'mobile/android/app/upload.jks',
    'mobile/assets/comptes/sprint-service-account.json',
  ];
  for (const chemin of interdits) assert.equal(classer(chemin).zone, 'interdite', chemin);
});

test('liste blanche : ce qui n’est écrit nulle part est refusé aussi', () => {
  for (const chemin of [
    'mobile/lib/core/router/app_router.dart',
    'mobile/lib/core/models/course.dart',
    'mobile/lib/main.dart',
    'mobile/lib/core/navigation/home_shell_page.dart',
    'mobile/web/manifest.json',
    'mobile/android/app/src/main/AndroidManifest.xml',
    'mobile/android/app/build.gradle',
    'README.md',
  ]) {
    assert.equal(classer(chemin).zone, 'hors_zone', chemin);
  }
});

test('chemins piégés : jamais autorisés', () => {
  for (const chemin of [
    'mobile/lib/core/widgets/../../../functions/src/index.ts',
    '/etc/passwd',
    'mobile/lib/core/widgets/a\0.dart',
  ]) {
    assert.equal(classer(chemin).zone, 'interdite', JSON.stringify(chemin));
  }
  assert.equal(classer('./mobile/lib/core/widgets/stat_tile.dart').zone, 'autorisee');
  assert.equal(classer('mobile\\lib\\core\\widgets\\stat_tile.dart').zone, 'autorisee');
});

test('paiement, recharge, connexion : autorisés mais signalés comme cas limites', () => {
  for (const chemin of [
    'mobile/lib/core/widgets/payment_method_sheet.dart',
    'mobile/lib/core/widgets/wallet_card.dart',
    'mobile/lib/features/portefeuille/presentation/recharge_portefeuille_page.dart',
    'mobile/lib/features/auth/presentation/login_page.dart',
    'mobile/lib/core/widgets/auth_scaffold.dart',
  ]) {
    const z = classer(chemin);
    assert.equal(z.zone, 'autorisee', chemin);
    assert.equal(z.limite, true, chemin);
  }
  assert.equal(classer('mobile/lib/core/widgets/stat_tile.dart').limite, false);
});

// ---- lignes d'un lot -------------------------------------------------------------------

const diffDe = (...fichiers) =>
  fichiers
    .map(
      ({ chemin, ajoutees = [], retirees = [] }) =>
        `diff --git a/${chemin} b/${chemin}\n--- a/${chemin}\n+++ b/${chemin}\n@@ -1,${retirees.length} +1,${ajoutees.length} @@\n` +
        retirees.map((l) => `-${l}`).join('\n') +
        (retirees.length ? '\n' : '') +
        ajoutees.map((l) => `+${l}`).join('\n') +
        (ajoutees.length ? '\n' : ''),
    )
    .join('');

test('une ligne nouvelle qui appelle le serveur ou la base est refusée', () => {
  const chemin = 'mobile/lib/features/compte/presentation/compte_tab_page.dart';
  for (const [ligne, motif] of [
    ["final f = FirebaseFunctions.instanceFor(region: 'x');", 'Cloud Function'],
    ["import 'package:cloud_firestore/cloud_firestore.dart';", 'Firestore'],
    ['final u = FirebaseAuth.instance.currentUser;', 'authentification'],
    ["final r = await http.get(Uri.parse('https://exemple.com'));", 'requête réseau'],
    ["import 'package:http/http.dart' as http;", 'requête réseau'],
    ["const cle = String.fromEnvironment('X');", 'compilation'],
  ]) {
    const trouvailles = controlerLignes(diffDe({ chemin, ajoutees: [`  ${ligne}`] }));
    assert.equal(trouvailles.length, 1, ligne);
    assert.ok(trouvailles[0].motif.includes(motif), `${ligne} → ${trouvailles[0].motif}`);
  }
});

test('du code d’apparence ne déclenche rien', () => {
  const chemin = 'mobile/lib/core/widgets/stat_tile.dart';
  const ajoutees = [
    '  padding: const EdgeInsets.all(16),',
    '  color: AppColors.bleu,',
    "  child: Text('Course terminée', style: Theme.of(context).textTheme.titleMedium),",
    '  duration: const Duration(milliseconds: 200),',
  ];
  assert.deepEqual(controlerLignes(diffDe({ chemin, ajoutees })), []);
});

test('un déplacement de code (même ligne retirée ailleurs) n’est pas du code nouveau', () => {
  const ligne = '  final u = FirebaseAuth.instance.currentUser;';
  const diff = diffDe(
    { chemin: 'mobile/lib/features/compte/presentation/ancienne_page.dart', retirees: [ligne] },
    { chemin: 'mobile/lib/features/compte/presentation/nouvelle_page.dart', ajoutees: [`      ${ligne.trim()}`] },
  );
  assert.deepEqual(controlerLignes(diff), []);
});

test('moyens de paiement : ni ajoutés ni retirés, mais une réindentation passe', () => {
  const chemin = 'mobile/lib/core/widgets/payment_method_sheet.dart';
  const boucle = 'for (final m in moyensMobileMoneyDisponibles)';
  // Réindentation : même ligne retirée puis ajoutée.
  assert.deepEqual(controlerLignes(diffDe({ chemin, retirees: [`  ${boucle}`], ajoutees: [`      ${boucle}`] })), []);
  // Retrait pur.
  const retrait = controlerLignes(diffDe({ chemin, retirees: [`  ${boucle}`] }));
  assert.equal(retrait.length, 1);
  assert.equal(retrait[0].sens, 'retirée');
  // Nouvel usage.
  const ajout = controlerLignes(diffDe({ chemin, ajoutees: ['  final tous = moyensMobileMoneyDisponibles + autres;'] }));
  assert.equal(ajout.length, 1);
});

test('Orange Money ne se rouvre pas par un lot de design', () => {
  const chemin = 'mobile/lib/core/widgets/payment_method_selector.dart';
  for (const ligne of ['  _Choix(PaymentMethod.orangeMoney),', '  case PaymentMethod.orangeMoney:', "  'ORANGE_MONEY',"]) {
    assert.equal(controlerLignes(diffDe({ chemin, ajoutees: [ligne] })).length, 1, ligne);
  }
  // Le texte « Orange Money » dans un libellé n'est pas un moyen de paiement.
  assert.deepEqual(controlerLignes(diffDe({ chemin, ajoutees: ["  const Text('Orange Money bientôt disponible'),"] })), []);
});

test('web/index.html : du style oui, du script ou une adresse externe non', () => {
  const chemin = 'mobile/web/index.html';
  assert.deepEqual(controlerLignes(diffDe({ chemin, ajoutees: ['  .splash { background: #0B0B0C; }'] })), []);
  for (const ligne of [
    '  <script src="x.js"></script>',
    "  fetch('/api')",
    '  <img src="https://exemple.com/a.png">',
    '  <div onclick="x()">',
    '  navigator.serviceWorker.register("sw.js")',
  ]) {
    assert.ok(controlerLignes(diffDe({ chemin, ajoutees: [ligne] })).length >= 1, ligne);
  }
});

test('les lignes des fichiers non Dart ne sont pas jugées comme du Dart', () => {
  const chemin = 'mobile/assets/promo/LISEZ-MOI.txt';
  assert.deepEqual(controlerLignes(diffDe({ chemin, ajoutees: ['FirebaseAuth et moyensMobileMoneyDisponibles'] })), []);
});

test('lignesDuDiff : numéro de ligne du fichier d’arrivée', () => {
  const diff = 'diff --git a/mobile/lib/core/widgets/a.dart b/mobile/lib/core/widgets/a.dart\n--- a/mobile/lib/core/widgets/a.dart\n+++ b/mobile/lib/core/widgets/a.dart\n@@ -10,0 +11,2 @@\n+une\n+deux\n';
  const { nouvelles } = lignesDuDiff(diff);
  assert.deepEqual(nouvelles.map((l) => [l.texte, l.ligne]), [['une', 11], ['deux', 12]]);
});

// ---- avec un vrai dépôt git ------------------------------------------------------------

function depot() {
  const dossier = mkdtempSync(path.join(tmpdir(), 'zone-'));
  const git = (...args) => {
    const r = spawnSync('git', ['-C', dossier, '-c', 'user.name=Test', '-c', 'user.email=test@exemple.com', '-c', 'commit.gpgsign=false', ...args], { encoding: 'utf8' });
    assert.equal(r.status, 0, `git ${args.join(' ')} : ${r.stderr}`);
    return r.stdout.trim();
  };
  git('init', '-q', '-b', 'main');
  const ecrire = (chemin, contenu, mode) => {
    const complet = path.join(dossier, chemin);
    mkdirSync(path.dirname(complet), { recursive: true });
    writeFileSync(complet, contenu);
    if (mode) chmodSync(complet, mode);
  };
  const valider = (message, fichiers) => {
    for (const [chemin, contenu] of Object.entries(fichiers)) {
      if (contenu === null) git('rm', '-q', '-f', chemin);
      else {
        ecrire(chemin, contenu);
        git('add', chemin);
      }
    }
    git('commit', '-q', '-m', message);
    return git('rev-parse', 'HEAD');
  };
  return { dossier, git, ecrire, valider, nettoyer: () => rmSync(dossier, { recursive: true, force: true }) };
}

test('commits : seuls les commits déclarés « Lot-Design: oui » sont jugés', () => {
  const d = depot();
  try {
    const base = d.valider('Départ', { 'mobile/lib/core/widgets/a.dart': 'class A {}\n', 'mobile/functions/src/index.ts': 'export {};\n' });
    const bon = d.valider('Habillage\n\nLot-Design: oui\n', { 'mobile/lib/core/widgets/a.dart': 'class A { final int v = 1; }\n' });
    const mauvais = d.valider('Touche au serveur\n\nLot-Design: oui\n', { 'mobile/functions/src/index.ts': 'export const x = 1;\n' });
    const libre = d.valider('Changement serveur non déclaré', { 'mobile/functions/src/index.ts': 'export const x = 2;\n' });
    const tete = libre;
    assert.deepEqual(commitsDeDesign(d.dossier, base, tete), [bon, mauvais]);
    assert.equal(lotDuCommit(d.dossier, bon).conforme, true);
    const refus = lotDuCommit(d.dossier, mauvais);
    assert.equal(refus.conforme, false);
    assert.equal(refus.interdites, 1);
    // Le lot entier, déclaré ou non, se juge aussi avec « diff ».
    assert.equal(lotEntre(d.dossier, base, bon).conforme, true);
    assert.equal(lotEntre(d.dossier, base, tete).conforme, false);
  } finally {
    d.nettoyer();
  }
});

test('lot : suppression d’un test, test de logique et palette refusés ; test d’interface accepté', () => {
  const d = depot();
  try {
    const widget = "import 'package:flutter_test/flutter_test.dart';\nvoid main() { testWidgets('ok', (t) async {}); }\n";
    const logique = "import 'package:flutter_test/flutter_test.dart';\nvoid main() { test('calcul', () {}); }\n";
    const base = d.valider('Départ', {
      'mobile/test/accueil_test.dart': widget,
      'mobile/test/calcul_test.dart': logique,
      'mobile/test/supprime_test.dart': widget,
    });
    d.valider('Lot\n\nLot-Design: oui\n', {
      'mobile/test/accueil_test.dart': `${widget}// retouché\n`,
      'mobile/test/calcul_test.dart': `${logique}// retouché\n`,
      'mobile/test/supprime_test.dart': null,
      'mobile/test/palette_onyx_vert_test.dart': logique,
    });
    const bilan = lotEntre(d.dossier, base, 'HEAD');
    const parChemin = Object.fromEntries(bilan.fichiers.map((f) => [path.basename(f.chemin), f]));
    assert.equal(parChemin['accueil_test.dart'].zone, 'autorisee');
    assert.equal(parChemin['calcul_test.dart'].zone, 'interdite');
    assert.match(parChemin['calcul_test.dart'].raison, /logique/);
    assert.equal(parChemin['supprime_test.dart'].zone, 'interdite');
    assert.match(parChemin['supprime_test.dart'].raison, /suppression/);
    assert.equal(parChemin['palette_onyx_vert_test.dart'].zone, 'interdite');
    assert.equal(bilan.conforme, false);
  } finally {
    d.nettoyer();
  }
});

test('ligne de commande : codes de sortie de diff et de commits', () => {
  const d = depot();
  try {
    const base = d.valider('Départ', { 'mobile/lib/core/widgets/a.dart': 'class A {}\n' });
    const bon = d.valider('Habillage\n\nLot-Design: oui\n', { 'mobile/lib/core/widgets/a.dart': 'class A { final int v = 1; }\n' });
    const mauvais = d.valider('Hors zone\n\nLot-Design: oui\n', { 'mobile/pubspec.yaml': 'name: x\n' });
    const lancer = (...args) => spawnSync('node', [SCRIPT, ...args], { cwd: d.dossier, encoding: 'utf8' });
    assert.equal(lancer('diff', base, bon).status, 0);
    const refus = lancer('diff', base, mauvais);
    assert.equal(refus.status, 1);
    assert.match(refus.stdout, /INTERDIT .*mobile\/pubspec\.yaml/);
    assert.match(refus.stdout, /::error title=Lot de design hors zone/);
    assert.equal(lancer('commits', base, bon).status, 0);
    assert.equal(lancer('commits', base, mauvais).status, 1);
    // Aucun commit de départ (nouvelle branche) : on le dit, sans bloquer.
    const sansBase = lancer('commits', '0'.repeat(40), mauvais);
    assert.equal(sansBase.status, 0);
    assert.match(sansBase.stdout, /::warning/);
    assert.equal(lancer('inconnu').status, 2);
  } finally {
    d.nettoyer();
  }
});

test('estLotDeDesign : la déclaration est une ligne du message', () => {
  assert.equal(estLotDeDesign('Habillage\n\nLot-Design: oui\n\nCo-Authored-By: x'), true);
  assert.equal(estLotDeDesign('lot-design: OUI'), true);
  assert.equal(estLotDeDesign('Habillage du lot-design: oui dans la phrase'), false);
  assert.equal(estLotDeDesign('Lot-Design: non'), false);
});

// ---- intégrité des outils installés ---------------------------------------------------------

const sha = (texte) => createHash('sha256').update(texte).digest('hex');

function depotAvecOutil() {
  const d = depot();
  const contenus = {
    'SKILL.md': '# Outil\nVoir mobile/securite/ZONES_DESIGN.md\n',
    LICENSE: 'MIT License\n',
    'data/regles.csv': 'No,Regle\n1,Contraste\n',
  };
  const dossierOutil = '.claude/skills/outil';
  for (const [rel, contenu] of Object.entries(contenus)) d.ecrire(`${dossierOutil}/${rel}`, contenu);
  const manifeste = {
    outils: [
      {
        nom: 'outil',
        dossier: dossierOutil,
        origine: 'https://exemple.com/outil',
        commit: 'a'.repeat(40),
        licence: 'MIT',
        fichiers: Object.fromEntries(Object.entries(contenus).map(([rel, c]) => [rel, { sha256: sha(c) }])),
      },
    ],
  };
  return { ...d, dossierOutil, manifeste };
}

test('intégrité : un outil conforme passe', () => {
  const d = depotAvecOutil();
  try {
    const { erreurs, fichiers } = controlerIntegrite(d.dossier, d.manifeste);
    assert.deepEqual(erreurs, []);
    assert.equal(fichiers, 3);
  } finally {
    d.nettoyer();
  }
});

test('intégrité : fichier modifié, ajouté, exécutable, lien, script ou MCP → refusé', () => {
  const cas = [
    ['fichier modifié', (d) => d.ecrire(`${d.dossierOutil}/data/regles.csv`, 'No,Regle\n1,Autre\n'), /différent de l’empreinte/],
    ['fichier ajouté', (d) => d.ecrire(`${d.dossierOutil}/references/nouveau.md`, 'x'), /non prévu/],
    ['script Python', (d) => d.ecrire(`${d.dossierOutil}/scripts/search.py`, 'print(1)'), /seul du texte/],
    ['script shell exécutable', (d) => d.ecrire(`${d.dossierOutil}/data/regles.csv`, 'No,Regle\n1,Contraste\n', 0o755), /exécutable/],
    ['réglage de projet', (d) => d.ecrire('.claude/settings.json', '{"hooks":{}}'), /seul du texte|non prévu/],
    ['commande', (d) => d.ecrire('.claude/commands/x.md', 'x'), /non prévu/],
    ['serveur MCP', (d) => d.ecrire('.mcp.json', '{"mcpServers":{}}'), /MCP/],
    ['autre outil sans manifeste', (d) => d.ecrire('.claude/skills/autre/SKILL.md', 'x'), /non prévu/],
    ['fichier manquant', (d) => rmSync(path.join(d.dossier, '.claude/skills/outil/LICENSE')), /absent/],
    ['règle des zones supprimée du skill', (d) => d.ecrire(`${d.dossierOutil}/SKILL.md`, '# Outil sans règle\n'), /ne rappelle plus la règle des zones/],
  ];
  for (const [nom, alterer, attendu] of cas) {
    const d = depotAvecOutil();
    try {
      alterer(d);
      // Les outils modifiés ne doivent pas être « validés » par le simple fait d'exister.
      const { erreurs } = controlerIntegrite(d.dossier, d.manifeste);
      assert.ok(erreurs.length >= 1, `${nom} : aucune erreur`);
      assert.ok(erreurs.some((e) => attendu.test(e)), `${nom} : ${JSON.stringify(erreurs)}`);
    } finally {
      d.nettoyer();
    }
  }
});

test('intégrité : un lien symbolique est refusé', () => {
  const d = depotAvecOutil();
  try {
    symlinkSync('/etc/hostname', path.join(d.dossier, '.claude/skills/outil/lien.md'));
    const { erreurs } = controlerIntegrite(d.dossier, d.manifeste);
    assert.ok(erreurs.some((e) => /lien symbolique/.test(e)), JSON.stringify(erreurs));
  } finally {
    d.nettoyer();
  }
});

test('intégrité : le manifeste doit figer un commit et une licence', () => {
  const d = depotAvecOutil();
  try {
    d.manifeste.outils[0].commit = 'main';
    d.manifeste.outils[0].licence = '';
    const { erreurs } = controlerIntegrite(d.dossier, d.manifeste);
    assert.ok(erreurs.some((e) => /commit figé/.test(e)));
    assert.ok(erreurs.some((e) => /licence/.test(e)));
  } finally {
    d.nettoyer();
  }
});

test('intégrité : aucun outil installé et manifeste vide → rien à signaler', () => {
  const d = depot();
  try {
    d.ecrire('README.md', 'x');
    assert.deepEqual(controlerIntegrite(d.dossier, { outils: [] }), { erreurs: [], fichiers: 0 });
  } finally {
    d.nettoyer();
  }
});
