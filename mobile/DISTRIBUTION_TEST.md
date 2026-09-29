# Distribuer Sprint aux chauffeurs (phase de test)

## Android : l'APK

À chaque push, GitHub Actions compile l'APK et le publie sur Firebase
Hosting (projet sprint-vtc), toujours aux mêmes adresses, à envoyer sur
WhatsApp :

- page de téléchargement (logo, version, étapes d'installation) :
  https://sprint-vtc.web.app/
- lien direct du fichier : https://sprint-vtc.web.app/sprint.apk

La page est dans `hebergement/index.html` ; la CI y inscrit la version,
la taille et la date à chaque publication, puis vérifie que le lien
public sert bien l'APK qui vient d'être compilé.

Nom de domaine Sprint : dans la Console Firebase > Hosting > **Ajouter
un domaine personnalisé** (ex. `app.sprint.sn`), puis ajouter chez le
registraire du domaine les enregistrements DNS indiqués. Les mêmes
fichiers sont alors servis aussi à cette adresse, sans rien changer au
pipeline.

Installation par le chauffeur :

1. Ouvrir le lien (ou le fichier reçu sur WhatsApp) : « Télécharger ».
2. Ouvrir `sprint.apk`. La première fois, Android demande d'autoriser
   l'installation depuis Chrome (ou WhatsApp) : **Paramètres** >
   **Autoriser cette source**, puis revenir et **Installer**.
3. Si Play Protect affiche « Application inconnue » : **Plus de détails**
   > **Installer quand même** (normal pour une app hors Play Store).
4. Au premier passage « En ligne » : autoriser la localisation
   (**Lorsque vous utilisez l'application**) et les notifications.

Mises à jour : renvoyer le même lien ; la nouvelle version s'installe
par-dessus l'ancienne, sans perdre la connexion. Toutes les versions sont
signées avec la même clé, créée par la CI et gardée dans Google Secret
Manager (`ANDROID_SIGNATURE`) : ne jamais la supprimer, sinon les
chauffeurs devront désinstaller l'app avant la mise à jour suivante.

Ce que l'APK apporte par rapport au site :

- le GPS continue écran verrouillé tant que le chauffeur est en ligne
  (notification permanente « Sprint : vous êtes en ligne ») ;
- alerte « Nouvelle course » avec le son de notification du téléphone
  et des vibrations.

Limites connues de l'APK de test :

- carte OpenStreetMap (la clé Google du fond de carte est réservée au
  site) ; recherche d'adresses et prix restent fournis par Google, côté
  serveur ;
- paiement : la page de paiement s'ouvre dans le navigateur ; revenir
  ensuite dans l'app.

## iPhone : le site installé sur l'écran d'accueil

Apple n'autorise pas les APK ni l'installation d'un site en un clic : le
chauffeur ajoute le site à son écran d'accueil, une fois.

1. Ouvrir https://abdoungom1999-design.github.io/-claude-/ dans **Safari**.
2. Toucher **Partager** (carré avec une flèche), puis **« Sur l'écran
   d'accueil »**, puis **Ajouter**. Un bandeau rappelle ce geste sur
   iPhone tant que Sprint n'est pas installé.
3. Ouvrir Sprint depuis l'icône : plein écran, sans barre Safari.

Limites sur iPhone : le GPS s'arrête écran verrouillé (l'écran reste
allumé tant que le chauffeur est en ligne) ; pas de vibration, et le
bouton silencieux coupe l'alerte sonore.
