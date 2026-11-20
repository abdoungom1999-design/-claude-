# E-mails de Sprint depuis le domaine officiel (anti-spam)

Guide pour **vous** (le client) : à faire une seule fois, chez l'hébergeur du
domaine, puis dans la console Firebase. Aucun code à toucher, aucune clé à
m'envoyer.

> **À retenir.** Un e-mail n'est pas rangé en « courrier indésirable » parce
> qu'il est mal écrit, mais parce que le serveur qui l'envoie ne peut pas
> prouver qu'il a le droit d'écrire au nom de l'expéditeur. Trois
> enregistrements DNS apportent cette preuve :
>
> | Sigle | Ce que c'est | Rôle |
> |---|---|---|
> | **SPF** | liste des serveurs autorisés à envoyer pour votre domaine | « ce serveur a le droit » |
> | **DKIM** | signature numérique ajoutée à chaque e-mail | « ce message n'a pas été modifié et vient bien de ce domaine » |
> | **DMARC** | consigne aux boîtes de réception en cas d'échec de SPF/DKIM, et rapports | « que faire des faux, et dites-moi qui en envoie » |

Décisions du client (novembre 2026) : le domaine est **`sprintvtc.sn`** (`sprint.sn` n'était pas disponible ;
revendeur Afriregister, DNS sous Cloudflare) et l'adresse officielle **`contact@sprintvtc.sn`** : c'est elle qui reçoit les
réponses et les rapports DMARC dans ce guide. (La publication 130 (18 novembre 2026) a remplacé `support@` et `donnees@` de l'app
par cette adresse unique, après le test de la redirection.)

---

## 0. Ce que vous devez avoir sous la main

1. L'accès à la **zone DNS** du domaine. Elle se trouve chez celui qui gère les
   *serveurs de noms* du domaine, ce qui n'est pas forcément celui qui l'a
   vendu. Chez la plupart des hébergeurs, l'écran s'appelle « Zone DNS »,
   « Éditeur de zone DNS » ou « Gestion DNS ».
2. L'accès **Propriétaire / Éditeur** au projet Firebase `sprint-vtc`
   (console Firebase).
3. Une adresse de messagerie que vous lisez réellement pour recevoir les
   rapports DMARC : `contact@sprintvtc.sn` (voir 5 pour éviter qu'ils
   encombrent la boîte).

Ce que l'on ajoute ne casse rien : ce sont des lignes **ajoutées** à la zone.
Seule exception, le SPF : il ne peut y avoir qu'**un seul** enregistrement SPF
par nom (voir 2.3).

---

## 1. Étape 1 : demander à Firebase d'envoyer depuis votre domaine

Aujourd'hui, les e-mails de l'app (vérification de l'adresse à l'inscription,
mot de passe oublié) partent de `noreply@sprint-vtc.firebaseapp.com`. Un
domaine inconnu du destinataire : c'est la cause principale des e-mails qui
arrivent en courrier indésirable.

1. Console Firebase → **Authentication** → onglet **Modèles** (*Templates*).
2. Ouvrez un modèle (crayon à droite de « Validation de l'adresse e-mail »).
3. À côté de l'adresse d'expéditeur, cliquez **Personnaliser le domaine**
   (*Customize domain*).
4. Saisissez `sprintvtc.sn` puis validez. Firebase affiche alors **les
   enregistrements DNS à créer**. Laissez cette fenêtre ouverte (ou notez les
   valeurs) : elles sont propres à votre projet et **font foi** (voir 2.1).

Les libellés peuvent varier légèrement d'une version de la console à l'autre.

---

## 2. Étape 2 : les enregistrements DNS à ajouter chez l'hébergeur

### 2.1 Ceux que Firebase vous donne (SPF + DKIM + preuve de propriété)

Firebase affiche quatre lignes. Voici à quoi elles ressemblent, pour que vous
reconnaissiez chacune ; **copiez les valeurs exactes de la console**, pas
celles de ce tableau si elles diffèrent. (La documentation de Firebase ne publie
pas ces valeurs : seule votre console les donne ; le tableau reprend la forme
décrite dans les exemples publics, avec votre domaine. La partie après
`firebase=` de la première ligne est celle qui varie le plus d'un exemple à
l'autre : recopiez-la depuis la console.)

| # | Type | Nom (host) | Valeur | À quoi ça sert |
|---|---|---|---|---|
| 1 | `TXT` | `sprintvtc.sn` (ou `@`) | `firebase=sprint-vtc` | prouve que le domaine est à vous |
| 2 | `TXT` | `sprintvtc.sn` (ou `@`) | `v=spf1 include:_spf.firebasemail.com ~all` | **SPF** : autorise les serveurs de Firebase |
| 3 | `CNAME` | `firebase1._domainkey` | `mail-sprintvtc-sn.dkim1._domainkey.firebasemail.com` | **DKIM** (clé 1) |
| 4 | `CNAME` | `firebase2._domainkey` | `mail-sprintvtc-sn.dkim2._domainkey.firebasemail.com` | **DKIM** (clé 2) |

### 2.2 Celui que Firebase ne donne pas, mais qu'il faut : DMARC

| Type | Nom (host) | Valeur |
|---|---|---|
| `TXT` | `_dmarc` | `v=DMARC1; p=none; rua=mailto:contact@sprintvtc.sn; fo=1` |

`p=none` signifie « surveiller sans rien bloquer » : c'est le bon réglage de
départ (voir l'étape 5 pour le durcir progressivement).

### 2.3 Attention : un seul SPF par domaine

Regardez d'abord s'il existe **déjà** un enregistrement `TXT` commençant par
`v=spf1` sur `sprintvtc.sn` (c'est le cas si vos adresses e-mail
`contact@…` sont hébergées chez votre hébergeur ou chez Google/Microsoft).
Si oui, **ne créez pas une deuxième ligne** : deux SPF rendent les deux
invalides. Modifiez la ligne existante en y **ajoutant**
`include:_spf.firebasemail.com` juste avant le `~all` (ou `-all`) final :

| Avant | Après |
|---|---|
| `v=spf1 include:_spf.google.com ~all` | `v=spf1 include:_spf.google.com include:_spf.firebasemail.com ~all` |
| `v=spf1 +a +mx include:spf.mon-hebergeur.com ~all` | `v=spf1 +a +mx include:spf.mon-hebergeur.com include:_spf.firebasemail.com ~all` |

Gardez tout le reste de la ligne tel quel.

### 2.4 Pièges fréquents à l'écran de l'hébergeur

* **Le nom (host)** : certains hébergeurs ajoutent d'eux-mêmes `.sprintvtc.sn`
  à ce que vous tapez ; d'autres demandent le nom complet. Si vous voyez
  `firebase1._domainkey.sprintvtc.sn.sprintvtc.sn` après enregistrement,
  retirez la fin que vous avez tapée en trop.
* **Le point final** : sur les `CNAME`, certains hébergeurs veulent un point
  après la valeur (`….firebasemail.com.`), d'autres non. Suivez l'exemple de
  leur écran.
* **Guillemets** : sur un `TXT`, ne mettez pas de guillemets si l'écran n'en
  demande pas ; s'il en met tout seul, ne les doublez pas.
* **Cloudflare ou tout service « proxy »** : les lignes `CNAME` doivent être
  en **« DNS seulement »** (nuage gris), jamais en proxy (nuage orange).
* **Les délais** : de quelques minutes à 24 heures (rarement 48 h) pour que le
  monde entier voie les nouvelles lignes.

---

## 3. Étape 3 : vérifier

1. Retournez dans la fenêtre Firebase de l'étape 1 et cliquez **Vérifier**
   (*Verify*). Tant que c'est en attente, revenez plus tard : rien à refaire
   (jusqu'à 24 heures ; un outil comme <https://www.whatsmydns.net> montre si
   les lignes sont déjà visibles).
2. Quand l'onglet Modèles affiche le message vert **« Vérification terminée »**,
   cliquez **« Appliquer le domaine personnalisé »** (*Apply custom domain*) :
   sans ce clic, les e-mails continuent de partir de l'ancienne adresse. Puis
   réglez dans le même modèle :
   * **Nom de l'expéditeur** : `SPRINT` ;
   * **Répondre à** : `contact@sprintvtc.sn` ;
   * **Langue** du modèle : **Français** (pour *chaque* modèle utilisé :
     validation de l'adresse et réinitialisation du mot de passe), puis relisez
     l'objet et le texte.
3. Testez : créez un compte avec une adresse Gmail, puis ouvrez le message reçu →
   menu **⋮** → **Afficher l'original**. Vous devez lire :
   `SPF: PASS`, `DKIM: PASS`, `DMARC: PASS`.
4. Pour une note sur 10 : envoyez le même e-mail à l'adresse affichée par
   <https://www.mail-tester.com> (gratuit) et visez **9/10 ou plus**.
5. Contrôle des lignes DNS (facultatif) : <https://mxtoolbox.com/SuperTool.aspx>
   → `SPF Record Lookup` avec `sprintvtc.sn`, puis `DKIM Lookup` avec
   `sprintvtc.sn:firebase1`.

---

## 4. L'e-mail d'activation du chauffeur, envoyé par Resend

> **Décision du client (20 novembre 2026) : l'extension « Trigger Email from
> Firestore » est abandonnée.** Le serveur appelle directement l'API de
> **Resend** (<https://resend.com>), depuis une Cloud Function. L'ancien
> envoi par la collection `mail` (`EMAIL_BIENVENUE`) reste fermé et ne sert
> plus : ne l'ouvrez pas.

**Ce qui part, et quand.** Quand l'Admin approuve le dossier d'un chauffeur
(`statutValidation` passe à `valide`), la fonction `activationChauffeurEmail`
envoie « Bienvenue chez SPRINT : votre compte chauffeur est activé », UNE SEULE
FOIS par chauffeur :

* expéditeur `SPRINT <contact@sprintvtc.sn>`, réponses vers `contact@sprintvtc.sn` ;
* destinataire : l'adresse du compte, **seulement si elle est vérifiée** (relue
  chez Firebase Auth) ; un compte suspendu ou banni ne reçoit rien ;
* design noir Onyx et orange, avec les trois étapes pour recevoir une première
  course et le bouton « Ouvrir SPRINT » ;
* seuls les dossiers approuvés APRÈS l'ouverture reçoivent l'e-mail : les
  chauffeurs déjà validés n'en reçoivent pas.

**Ouverture (lot 149, préparé le 20 novembre 2026).** `EMAIL_ACTIVATION_CHAUFFEUR`
(`functions/src/email_activation.ts`) vaut désormais `true` : à la prochaine
publication, la fonction est déployée et liée à la clé. Avant de déployer quoi
que ce soit, la publication (et déjà l'essai sans publication) vérifie, avec
`scripts/controle_email_activation.sh` : que la clé existe et a la bonne forme,
puis, pour cette toute première fonction déclenchée par la base (Eventarc), les
droits que Google exige (voir « Droits du premier déclencheur » plus bas). Au
moindre manque, elle s'arrête avec un message clair et l'app en ligne ne change
pas. Pour refermer : remettre la ligne à `false` et publier.

**Où renseigner la clé Resend (une seule fois, par vous).** Elle ne passe JAMAIS
par un message, GitHub ni le code : elle va dans **Secret Manager**, sous le nom
exact `RESEND_API_KEY`.

1. Chez Resend : **API Keys**, **Create API Key**, permission **Sending access**,
   domaine `sprintvtc.sn`. Copiez la clé (elle commence par `re_` et ne
   s'affiche qu'une fois).
2. <https://console.cloud.google.com> : en haut, choisissez le projet
   **`sprint-vtc`**.
3. Menu **Sécurité** (*Security*), puis **Secret Manager**
   (ou <https://console.cloud.google.com/security/secret-manager?project=sprint-vtc>).
4. **Créer un secret** (*Create secret*).
5. **Nom** : `RESEND_API_KEY` (en majuscules, exactement).
6. **Valeur du secret** : collez la clé, **sans espace ni retour à la ligne**.
   Ne cochez pas « Importer un fichier ».
7. Laissez le reste par défaut (réplication automatique), puis **Créer le secret**.
8. Dites-moi « clé Resend créée » : je lance l'essai sans publication, qui vérifie
   le nom et la forme sans jamais afficher la valeur, ainsi que les droits ci-dessous ;
   puis j'attends votre go de publication.

Avant cela, chez Resend, page **Domains** : `sprintvtc.sn` doit être marqué
**Verified** (sinon chaque envoi est refusé, code `resend/403`).

**Droits du premier déclencheur (seulement si l'essai le demande).** Le déploiement
d'une première fonction déclenchée par la base exige trois droits pour des comptes
techniques de Google. Si le compte `github-deploy` ne peut pas les poser lui-même,
l'essai s'arrête sur « Droits Eventarc manquants » et liste ceux qui manquent, avec
le numéro du projet (`NUMÉRO` ci-dessous, aussi visible sur le tableau de bord du
projet). Dans <https://console.cloud.google.com/iam-admin/iam?project=sprint-vtc>,
**Accorder l'accès** (*Grant access*) :

1. Compte principal `NUMÉRO-compute@developer.gserviceaccount.com` : rôles
   **Demandeur Cloud Run** (*Cloud Run Invoker*) et **Destinataire d'événements
   Eventarc** (*Eventarc Event Receiver*), puis **Enregistrer**.
2. Compte principal `service-NUMÉRO@gcp-sa-pubsub.iam.gserviceaccount.com` : rôle
   **Créateur de jetons du compte de service** (*Service Account Token Creator*), puis
   **Enregistrer**.

Si l'essai s'arrête sur « Droits Eventarc invérifiables » : sur la même page, crayon
à droite de `github-deploy`, **+ Ajouter un autre rôle** : **Navigateur** (*Browser*,
lecture seule), **Enregistrer**. Puis dites-le-moi : je relance l'essai. Une fois la
fonction en place, ce contrôle n'est plus refait.

Pour **changer de clé** plus tard : dans Secret Manager, ouvrez `RESEND_API_KEY`,
**Nouvelle version**, collez la nouvelle clé, puis relancez une publication
(onglet Actions) : le serveur lit la dernière version. Désactivez ensuite
l'ancienne chez Resend. Si une clé a été écrite dans un message ou un document, **supprimez-la
chez Resend et recréez-en une**.

**Contrôler un envoi.** Console Google Cloud, **Logs Explorer**, filtre
`E-mail d'activation chauffeur` : « envoyé » ou « échec de l'envoi » avec un code
(`resend/401` clé refusée, `resend/403` domaine non vérifié ou clé non
autorisée, `resend/422` message refusé, `resend/429` trop d'envois,
`resend/reseau` ou `resend/delai`). L'adresse et la clé n'y apparaissent jamais.
Après un envoi, le profil du chauffeur porte `emailActivationEnvoyeLe` et
`emailActivationId` (identifiant du message chez Resend). Un échec n'est pas
rejoué tout seul : le chauffeur n'a alors pas reçu d'e-mail et son compte
fonctionne normalement.

**Côté DNS.** Resend vous fait ajouter ses propres enregistrements (DKIM, et un
SPF sur un sous-domaine d'envoi). Il ne doit toujours y avoir **qu'un seul SPF
à la racine** (voir 2.3) : si Resend en propose un à la racine, ajoutez son
`include:` à la ligne existante au lieu d'en créer une deuxième. Contrôlez
ensuite un e-mail reçu (« Afficher l'original » : SPF, DKIM et DMARC en PASS).

---

## 5. Durcir DMARC, progressivement (sur 4 à 6 semaines)

Tant que DMARC est à `p=none`, les faux e-mails ne sont pas bloqués : on ne fait
que regarder. Une fois que les rapports (envoyés à votre adresse `rua`) ne
montrent plus que des envois légitimes qui passent SPF ou DKIM :

| Étape | Quand | Valeur du `TXT` `_dmarc` |
|---|---|---|
| 1 | semaines 0 à 2 | `v=DMARC1; p=none; rua=mailto:contact@sprintvtc.sn; fo=1` |
| 2 | semaines 3 à 4 | `v=DMARC1; p=quarantine; pct=25; rua=mailto:contact@sprintvtc.sn` |
| 3 | semaine 5 | `v=DMARC1; p=quarantine; pct=100; rua=mailto:contact@sprintvtc.sn` |
| 4 | après 6 semaines sans surprise | `v=DMARC1; p=reject; rua=mailto:contact@sprintvtc.sn` |

Les rapports sont des fichiers XML illisibles à l'œil : un service gratuit comme
Postmark DMARC (<https://dmarc.postmarkapp.com>) les transforme en résumé
hebdomadaire lisible. **Ne passez pas à `quarantine` ni `reject` si vos propres
e-mails (ceux de `contact@…`) échouent aux tests de l'étape 3** : ils seraient
eux aussi mis de côté.

---

## 6. Ce que cela change (et ne change pas)

* L'app et le serveur ne changent pas : seuls l'adresse d'expéditeur et la
  réputation des e-mails changent.
* Les e-mails déjà envoyés ne sont pas concernés ; les liens de vérification
  restent valables.
* Retour arrière : supprimer les lignes ajoutées, ou, dans la console Firebase,
  revenir au domaine par défaut. Rien n'est perdu.

## 7. Décisions prises (15 novembre 2026)

1. Domaine d'envoi : `sprintvtc.sn` ; adresse officielle : `contact@sprintvtc.sn`.
2. E-mail de bienvenue : non, pas pour le moment (l'écran et la notification
   suffisent).
3. Rapports DMARC : `contact@sprintvtc.sn`. Si les rapports encombrent la
   boîte, créez une adresse `dmarc@sprintvtc.sn` qui les redirige vers un
   dossier, puis remplacez `rua=mailto:…` dans la ligne `_dmarc`.

Sources : [Utiliser un domaine personnalisé pour les e-mails d'authentification (Firebase)](https://firebase.google.com/docs/auth/email-custom-domain),
[exemple public des enregistrements `firebasemail.com` et piège des noms d'hôte (Namecheap)](https://medium.com/the-solo-developer-journey/connecting-firebase-with-a-namecheap-domain-f0fc88a8c548).
