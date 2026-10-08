# Provenance de frontend-design

Compétence d'Anthropic, installée **en texte seul** dans le cadre fixé par le
client (`mobile/securite/ZONES_DESIGN.md`, 5 protections). Elle a été
indiquée par le client via la liste
[travisvn/awesome-claude-skills](https://github.com/travisvn/awesome-claude-skills).

| | |
|---|---|
| Origine | https://github.com/anthropics/skills, dossier `skills/frontend-design` |
| Version figée | commit `683bc88e56f3e09ba94f7055977f3d3aa499f202` (5 octobre 2026, « Update claude-api skill: managed-agents-onboard… (#1962) ») |
| Licence | Apache-2.0 (texte intégral dans `LICENSE`, à conserver) |
| Liste d'où elle vient | `travisvn/awesome-claude-skills`, commit `1da55aa8` (28 avril 2026) : une simple liste de liens, sans licence et sans compétence propre |
| Installé le | 8 octobre 2026 |
| Contrôle | `node securite/outils_design.mjs integrite` (CI, job `backend`) compare chaque fichier à `securite/outils_externes.json` |

## Fichiers installés

| Fichier | Nature | sha256 |
|---|---|---|
| `SKILL.md` | **écrit par nous** (en français), adapté à une app Flutter dont l'identité est fixée par le client ; il ne reprend pas le texte d'origine mais en résume et en traduit les idées utiles | voir `securite/outils_externes.json` |
| `references/frontend-design-amont.md` | **texte d'origine, sans aucun changement** (le `SKILL.md` amont, en anglais) | `d91970639e9f5c37682ac7ab60094d35f1c7c1f38d731bd56396563aee10c1d3` |
| `LICENSE` | identique au `LICENSE.txt` amont | `0d542e0c8804e39aa7f37eb00da5a762149dc682d7829451287e11b938e94594` |

Les deux fichiers d'origine se vérifient octet par octet avec le dépôt
`anthropics/skills` au commit ci-dessus. Aucun fichier d'origine n'est
modifié (Apache-2.0, article 4) ; le dossier d'origine ne contient pas de
fichier `NOTICE`.

## Ce qui a été examiné et volontairement PAS installé

Dans `anthropics/skills` (écartés d'après leur description et la liste de leurs
fichiers ; seuls `frontend-design` et `theme-factory` ont été lus en entier) :

- `canvas-design` : 5,6 Mo de polices et création d'affiches PNG/PDF, pas
  l'interface d'une app.
- `algorithmic-art` : art génératif en code p5.js (modèles HTML et JavaScript).
- `theme-factory` : thèmes de couleurs et de polices pour présentations ;
  l'identité de Sprint est fixée par le client.
- `brand-guidelines` : la charte d'Anthropic, pas celle de Sprint.
- `web-artifacts-builder`, `webapp-testing`, `slack-gif-creator` : scripts
  shell et Python (règle 3 : aucun script tiers).
- Les autres (documents Word, PDF, tableurs, API Claude, MCP, rédaction
  interne, rappels et conseils) : sans rapport avec le design de l'app.

Dans la liste `travisvn/awesome-claude-skills` : les compétences de la
communauté (`web-asset-generator`, `frontend-slides`, shadcn/ui,
`claude-d3js-skill`, Expo, `playwright-skill`, `ios-simulator-skill`,
`get-shit-done`, `loki-mode`, Trail of Bits, `ffuf-web-fuzzing`, etc.) n'ont
pas été installées : d'après leur description dans la liste, elles visent le
web ou React, exigent des scripts ou des agents autonomes, ou n'ont aucun
rapport avec le visuel d'une app Flutter. Elles n'ont pas été ouvertes dans
leurs dépôts.

## Mise à jour

Jamais automatique. Une nouvelle version suppose une nouvelle lecture
intégrale, un nouveau commit figé, un nouveau manifeste
(`securite/outils_externes.json`) et l'accord du client.
