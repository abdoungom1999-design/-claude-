# Contrôles de sécurité de la CI

Ces contrôles tournent à chaque push (jobs `build`, `backend`, `android`,
`hebergement` de `.github/workflows/flutter-web.yml`). Ceux marqués
« bloque » arrêtent le déploiement. Le dépôt GitHub et les journaux de la CI
sont **publics** : une alerte doit être traitée tout de suite.

| Contrôle | Script | Bloque si |
|---|---|---|
| Secrets dans les fichiers suivis par git | `garde_fuites.mjs fichiers` | clé privée, jeton GitHub/AWS/Slack/Wave, compte de service Google, clé Google inconnue, adresse avec mot de passe, nom d'un secret du serveur dans le code client |
| Secrets dans les lignes ajoutées par le push | `garde_fuites.mjs diff` | idem, y compris un secret ajouté puis retiré dans le même push |
| Secrets dans le site compilé | `garde_fuites.mjs dossier build/web` | idem |
| Secrets dans l'APK | `garde_fuites.mjs apk …` | **n'avertit que** (non bloquant tant qu'il n'a pas tourné sur un vrai APK de la CI) |
| Vulnérabilités des Cloud Functions (production) | `audit_npm.mjs functions --prod --seuil high` | avis de gravité haute ou critique |
| Vulnérabilités des outils de test (jamais déployés) | `audit_npm.mjs firestore_rules_test --seuil critical` | avis critique |
| Avis de sécurité des paquets Dart | `avis_dart.mjs pubspec.lock` | un avis touche une version verrouillée |
| En-têtes de sécurité du site en ligne | étape du job `hebergement` | **n'avertit que** |

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
```

## Outils de design externes

Règle des zones autorisée / interdite, fixée par le client : voir
`ZONES_DESIGN.md`.

## Ce que ces contrôles ne font pas

- Ils ne détectent que les failles **déjà publiées** et les secrets **de
  forme connue**. Ils ne remplacent ni une revue de code indépendante ni un
  test d'intrusion.
- Les bibliothèques natives Android (SDK Firebase, Play Services) et iOS ne
  sont pas auditées ici.
- Ils agissent **après** le push. L'alerte préventive est la protection des
  pushs de GitHub (Settings > Code security > Secret scanning + Push
  protection), à activer sur le dépôt.
