# Provenance de ui-ux-pro-max

Outil externe de conseils de design, installé **en texte seul** dans le cadre
fixé par le client (`mobile/securite/ZONES_DESIGN.md`, 5 protections).

| | |
|---|---|
| Origine | https://github.com/nextlevelbuilder/ui-ux-pro-max-skill |
| Version figée | commit `1a2c459b35f26116fd165b0a0f30597f252749ff` (8 octobre 2026, « docs: sync stale catalog counts in stack docs (#517) ») |
| Licence | MIT, © 2024 Next Level Builder (texte intégral dans `LICENSE`, à conserver) |
| Installé le | 8 octobre 2026 |
| Contrôle | `node securite/outils_design.mjs integrite` (CI, job `backend`) compare chaque fichier à `securite/outils_externes.json` |

## Fichiers installés

| Fichier | Nature | sha256 |
|---|---|---|
| `SKILL.md` | **adapté par nous** (en français : zone visuelle, identité Sprint, plus aucun script). Original amont : `ea087c341bfb5b23195c7302027268ede86da802554c18a5c4896a6017b439f9` | voir `securite/outils_externes.json` |
| `LICENSE` | identique à l'amont | `738f69dfa83db5c347c678fb9d90e560877059f0de93a327c39001bff92dc014` |
| `references/pro-rules.md` | identique à l'amont | `d28442d61c310b49c054a4ea736f89fb3008beebdbbc38c4b3a540b8f7fadf23` |
| `references/quick-reference.md` | identique à l'amont | `0609bc7c89dacb40472465d8fc14257b56b2c43439660fc8d6fa3b8c022e1876` |
| `data/stacks/flutter.csv` | identique à l'amont | `64dba0ac17349f28bce517a0f5f48c54d9ed2e487ec0c0258303463b382f41a0` |

Les quatre fichiers « identiques » se vérifient octet par octet avec le dépôt
d'origine, au commit ci-dessus.

## Ce qui n'est volontairement PAS installé

- **Les scripts Python** (`search.py`, `design_system.py`, `core.py`,
  `reasoning_contract.py`, `validate_data.py` et leurs tests) : exécuter du
  code tiers est interdit (règle 3). L'outil d'origine sait aussi écrire des
  fichiers (`--persist`) ; ici, rien de tel.
- **Les bases de données de styles, palettes, polices, produits, icônes,
  graphiques, pages d'atterrissage, GSAP (bibliothèque web) et les 21 autres
  piles techniques** : l'identité de Sprint est fixée par le client, et ces
  bases serviraient surtout à proposer d'autres identités.
  `ux-guidelines.csv` (119 règles, surtout web) et `app-interface.csv`
  (32 règles, exemples React Native) ont été lus mais ne sont pas installés :
  l'index `references/quick-reference.md` en reprend l'essentiel, pas la
  totalité (par exemple, rien sur l'actualisation en tirant, les formats de
  date, les assistants IA ni VisionOS), et ses exemples de code sont absents.
- **Les six autres skills du dépôt d'origine** (`banner-design`, `brand`,
  `design`, `design-system`, `slides`, `ui-styling`), orientés web.
- **Le dossier `stack/` du dépôt d'origine**, un modèle de projet qui lance des
  serveurs MCP par `npx -y …@latest` (code non figé, téléchargé à chaque
  utilisation) et autorise leur usage sans confirmation : à ne jamais copier.

## Ce qui a été vérifié avant installation (8 octobre 2026)

- Lecture intégrale de chaque fichier installé (`SKILL.md` d'origine,
  `pro-rules.md`, `quick-reference.md`, `flutter.csv`, ainsi que
  `ux-guidelines.csv` et `app-interface.csv`).
- Balayage automatique des fichiers installés : aucun caractère invisible ou
  de contrôle, aucune consigne cachée adressée à l'agent, aucune commande.
  Seules URL : 29 liens de documentation de `flutter.csv` (`api.flutter.dev`,
  `docs.flutter.dev`, `pub.dev`, `riverpod.dev`).
- Aucun crochet (`hooks`), réglage de projet ni serveur MCP dans le dossier
  du skill d'origine.

## Mise à jour

Jamais automatique. Une nouvelle version suppose une nouvelle lecture
intégrale, un nouveau commit figé, un nouveau manifeste
(`securite/outils_externes.json`) et l'accord du client.
