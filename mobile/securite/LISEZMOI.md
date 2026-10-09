# Contrôles de sécurité de la CI

Ces contrôles tournent à chaque push (jobs `build`, `backend`, `android`,
`hebergement` de `.github/workflows/flutter-web.yml`). Ceux marqués
« bloque » arrêtent le déploiement. Le dépôt GitHub et les journaux de la CI
sont **publics** : une alerte doit être traitée tout de suite.

| Contrôle | Script | Bloque si |
|---|---|---|
| Secrets dans les fichiers suivis par git | `garde_fuites.mjs fichiers` | clé privée, jeton GitHub/AWS/Slack/Wave, compte de service Google, clé Google inconnue, adresse avec mot de passe, nom d'un secret du serveur dans le code client |
| Secrets dans les lignes ajoutées depuis le dernier déploiement réussi | `garde_fuites.mjs diff` | idem, y compris un secret ajouté puis retiré avant la publication. La plage couvre aussi les commits « [skip ci] » poussés entre deux publications |
| Secrets dans le site compilé | `garde_fuites.mjs dossier build/web` | idem |
| Secrets dans l'APK | `garde_fuites.mjs apk …` | **n'avertit que** (non bloquant tant qu'il n'a pas tourné sur un vrai APK de la CI) |
| Vulnérabilités des Cloud Functions (production) | `audit_npm.mjs functions --prod --seuil high` | avis de gravité haute ou critique |
| Vulnérabilités des outils de test (jamais déployés) | `audit_npm.mjs firestore_rules_test --seuil critical` | avis critique |
| Avis de sécurité des paquets Dart | `avis_dart.mjs pubspec.lock` | un avis touche une version verrouillée |
| Outils externes installés sous `.claude/` | `outils_design.mjs integrite` | un fichier absent du manifeste `outils_externes.json`, modifié depuis sa validation, exécutable, qui n'est pas du texte (`.md`, `.csv`, `LICENSE`), un lien symbolique ou un serveur MCP |
| Lots de design (commits déclarés `Lot-Design: oui`) | `outils_design.mjs commits` | un fichier hors de la zone visuelle autorisée, ou une ligne nouvelle qui appelle le serveur, la base ou les secrets, ou qui touche aux moyens de paiement ouverts (Orange Money reste fermé) |
| En-têtes de sécurité du site en ligne | étape du job `hebergement` | **n'avertit que** |
| Sauvegardes de la base Firestore | `sauvegardes.mjs droits\|planifier\|verifier` (flux `.github/workflows/sauvegardes.yml`, chaque jour) | aucune sauvegarde récente (plus de 36 h), planification absente, droits manquants. **Ne bloque aucun déploiement** : flux séparé, ticket GitHub en cas d'échec planifié (`FIREBASE_SETUP.md`, section 10) |

Une trouvaille n'est jamais affichée en entier (4 premiers caractères et
longueur). Si la base d'avis (registre npm, pub.dev) est injoignable, le
contrôle le signale sans bloquer et se refait au push suivant.

## Une alerte s'affiche : que faire ?

- **Secret trouvé** : le retirer du code **et le révoquer chez son émetteur**
  (le retirer du dépôt ne suffit pas : il a pu être copié). Les clés de
  paiement vivent dans Secret Manager, jamais dans le dépôt ni dans l'app.
- **Dépendance vulnérable** : la mettre à jour. Si aucune version corrigée
  n'existe ou si la faille n'est pas atteignable par notre code, ajouter une
  exception **motivée et datée** dans `exceptions.json` :

  ```json
  { "avis": "GHSA-xxxx-xxxx-xxxx", "projet": "functions",
    "raison": "Fonction jamais appelée par le serveur (vérifié le …).",
    "jusqu_au": "2026-12-31" }
  ```

  `projet` : dossier du projet npm (`functions`, `firestore_rules_test`),
  `dart` pour `pubspec.lock`, ou `*`. Passée la date, l'exception est
  ignorée et le contrôle bloque de nouveau : un risque accepté se réexamine.

## En local

```bash
cd mobile
node --test securite/test/*.test.mjs
node securite/garde_fuites.mjs fichiers
node securite/audit_npm.mjs functions --prod --seuil high
node securite/avis_dart.mjs pubspec.lock
node securite/outils_design.mjs integrite
node securite/outils_design.mjs diff <base> HEAD   # liste des fichiers d'un lot de design
```

## Outils de design externes

Règle des zones autorisée / interdite, fixée par le client : voir
`ZONES_DESIGN.md`.

**Installés** (8 octobre 2026), en texte seul, sous `.claude/skills/` ; détail
dans le `PROVENANCE.md` de chacun, empreintes dans `outils_externes.json` :

- `ui-ux-pro-max` : règles et liste de contrôle de design (licence MIT, commit
  figé `1a2c459b…`).
- `frontend-design` : démarche de design et rédaction d'interface, d'Anthropic
  (licence Apache-2.0, dépôt `anthropics/skills`, commit figé `683bc88e…`),
  indiquée par le client via la liste `travisvn/awesome-claude-skills`. Cette
  liste n'est qu'un ensemble de liens, sans compétence propre ni licence. Le
  texte d'origine est conservé sans changement dans `references/` ; le
  `SKILL.md` est une adaptation écrite par nous, en français.

**Examinés et refusés** (8 octobre 2026), car ils violent la règle 3
(« aucun script tiers, aucun hook, aucun service en arrière-plan ») :

- `claude-mem` 13.34.2 (Apache-2.0, commit `71ddd117…`) : des crochets sur
  chaque appel d'outil, chaque message et chaque fin de session, qui lancent un
  service en arrière-plan ; il enregistre et résume tout ce que fait l'agent
  (serveur, paiements et secrets compris) par l'intermédiaire d'un fournisseur
  de modèle, avec une sauvegarde optionnelle chez cmem.ai (désactivée tant que
  l'on ne se connecte pas à ce service) ; son installeur télécharge puis
  exécute les scripts d'installation de Bun et de uv (`curl … | bash`).
- `superpowers` 6.4.2 (MIT, commit `8ca22dba…`) : un crochet de démarrage qui
  injecte des consignes impératives dans chaque session, des scripts shell et
  un serveur local, des flux de fusion, de pull request et de worktrees. C'est
  une méthode de travail générale, qui ne se limite pas au visuel :
  incompatible avec la zone.

Les autres compétences de `anthropics/skills` (art génératif, affiches,
thèmes de présentation, charte d'Anthropic, scripts Python et shell) et celles
de la communauté citées par `awesome-claude-skills` (web, React, agents
autonomes, tests d'intrusion…) ont été écartées : voir le `PROVENANCE.md` de
`frontend-design`.

Un nouvel outil externe suppose : lecture intégrale, commit figé, licence
vérifiée, entrée au manifeste `outils_externes.json` et accord du client.

**Lots de design** : le commit porte la ligne `Lot-Design: oui` ; avant de
l'envoyer, `outils_design.mjs diff <base> HEAD` donne la liste de ses fichiers,
classés par zone, à joindre au compte rendu. La zone autorisée est une liste
blanche : un fichier qui n'est écrit nulle part est refusé comme un fichier
interdit.

## Ce que ces contrôles ne font pas

- Ils ne détectent que les failles **déjà publiées** et les secrets **de
  forme connue**. Ils ne remplacent ni une revue de code indépendante ni un
  test d'intrusion.
- Les bibliothèques natives Android (SDK Firebase, Play Services) et iOS ne
  sont pas auditées ici.
- Ils agissent **après** le push. L'alerte préventive est la protection des
  pushs de GitHub (Settings > Code security > Secret scanning + Push
  protection), à activer sur le dépôt.
