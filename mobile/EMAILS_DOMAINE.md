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
réponses et les rapports DMARC dans ce guide. (Le lot de la publication 130 remplace `support@` et `donnees@` de l'app
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

## 4. Le message « Bienvenue chez SPRINT » par e-mail (facultatif, non activé)

> **Décision du client (15 novembre 2026) : pas d'e-mail de bienvenue pour le
> moment.** Cette partie est conservée pour le jour où vous le voudrez ;
> `EMAIL_BIENVENUE` reste à `false` et rien de ce qui suit n'est à faire
> maintenant.

Le message de bienvenue part **toujours** dans l'app (écran) et en notification
sur les appareils du compte. L'envoi **par e-mail** en plus demande un service
d'envoi : Firebase n'en fournit pas pour les e-mails libres.

Ce qui est prêt côté code (fermé, aucun effet tant que vous ne l'ouvrez pas) :
à la bienvenue, le serveur écrit un document dans la collection `mail` de la
base. L'extension Firebase officielle **« Trigger Email from Firestore »**, que
vous installez, lit cette collection et envoie le message par le serveur d'envoi
de votre choix.

À faire (une seule fois) :

1. Choisissez le serveur d'envoi (SMTP) : celui de votre hébergeur de
   messagerie, ou un service d'envoi spécialisé (Brevo, Mailjet, Mailgun,
   Amazon SES…). Il vous donne un **nom de serveur**, un **port**, un
   **identifiant** et un **mot de passe**.
2. Chez ce service, **ajoutez votre domaine** : il vous indique ses propres
   enregistrements SPF et DKIM (même principe qu'à l'étape 2). Pour le SPF,
   **ajoutez son `include:`** à votre ligne existante (2.3). N'ajoutez **pas**
   de second DMARC : celui de l'étape 2.2 couvre le domaine entier.
3. Console Firebase → **Extensions** → **Trigger Email from Firestore** →
   **Installer**. Réglages à saisir :
   * *Email documents collection* : `mail`
   * *SMTP connection URI* : l'adresse de connexion que votre service d'envoi
     vous donne (elle commence par `smtps` et contient l'identifiant, le mot de
     passe, le serveur et le port ; la plupart des services la fournissent
     toute prête). C'est l'extension qui range ce secret dans Secret
     Manager : **ne le collez ni dans un message ni dans le code**.
   * *Default FROM address* : `SPRINT <bienvenue@sprintvtc.sn>`
   * *Default REPLY-TO address* : `contact@sprintvtc.sn`
4. Dites-moi quand c'est fait : je passe `EMAIL_BIENVENUE` à `true` (serveur),
   avec votre accord de publication. Après chaque bienvenue, le document
   `mail/bienvenue_<identifiant du compte>` montre dans `delivery` si l'envoi
   a réussi (`SUCCESS`) ou pourquoi il a échoué.

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
