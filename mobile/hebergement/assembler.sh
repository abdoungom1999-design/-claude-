#!/usr/bin/env bash
# Assemble le site Firebase Hosting (build/hebergement), publié en un seul
# déploiement (Firebase Hosting remplace tout le site à chaque fois) :
#
#   /             app web Sprint (build Flutter, --base-href "/")
#   /android/     page de téléchargement de l'APK
#   /sprint.apk   APK Android
#
# Usage : hebergement/assembler.sh <dossier du build web> <apk> <page android>
#   <page android> : hebergement/android/index.html avec version, taille et
#   date déjà inscrites (ou la page en ligne, si l'APK n'a pas été recompilé).
set -euo pipefail
cd "$(dirname "$0")/.."

web=$1
apk=$2
page=$3
sortie=build/hebergement

for fichier in "$web/index.html" "$apk" "$page"; do
  [ -s "$fichier" ] || { echo "Fichier manquant ou vide : $fichier" >&2; exit 1; }
done

rm -rf "$sortie"
mkdir -p "$sortie/android"
cp -R "$web"/. "$sortie"/
cp hebergement/android/icone.png hebergement/android/favicon.png "$sortie/android/"
cp "$page" "$sortie/android/index.html"
cp "$apk" "$sortie/sprint.apk"

if grep -q '__VERSION__\|__TAILLE__\|__DATE__' "$sortie/android/index.html"; then
  echo "La page Android contient encore des marqueurs non remplis." >&2
  exit 1
fi
echo "Site assemblé dans $sortie :"
ls -la "$sortie" "$sortie/android"
