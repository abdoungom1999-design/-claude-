#!/usr/bin/env bash
# Contrôle réel auprès de Google (CI) : la clé de carte est-elle REFUSÉE quand
# on s'en sert autrement que prévu ? Pendant de verifier_session_carte.sh, qui
# vérifie, lui, qu'elle fonctionne pour notre site et notre application.
#
#   appelant <libellé> [en-tête…]   la clé présentée par un site ou une application
#                                   que nous ne sommes pas (en-têtes d'un faux
#                                   appelant) : Google doit la refuser. C'est la
#                                   restriction « sites web » ou « applications
#                                   Android » de la clé.
#   api <libellé> [en-tête…]        la clé présentée par le VRAI appelant (en-têtes
#                                   du site ou de l'APK) pour une API qui n'est pas
#                                   la carte (autocomplétion Places) : Google doit la
#                                   refuser. C'est la restriction d'API de la clé.
#
# Usage : CLE=… verifier_refus_cle_google.sh appelant "Clé web" "Referer: https://exemple.invalid/"
#         CLE=… verifier_refus_cle_google.sh api "Clé web" "Referer: https://sprint-vtc.web.app/"
#
# Non bloquant : sort toujours avec 0. Un refus est une simple ligne ; une clé
# acceptée à tort, ou un contrôle impossible, produit un avertissement dans le
# résumé du run. La clé et la réponse de Google ne sont jamais affichées (le
# journal de la CI est public).
set -u

mode=${1:-}
libelle=${2:-Clé Google}
shift 2 2>/dev/null || true
entetes=()
for entete in "$@"; do entetes+=(-H "$entete"); done
reponse="${RUNNER_TEMP:-/tmp}/refus-cle-google.json"

if [ -z "${CLE:-}" ]; then
  echo "$libelle : pas de clé fournie, contrôle ignoré."
  exit 0
fi

# L'URL contient la clé : elle ne doit jamais être écrite par ce script.
case "$mode" in
  appelant)
    code=$(curl -s -m 20 -o "$reponse" -w '%{http_code}' -X POST \
      "https://tile.googleapis.com/v1/createSession?key=$CLE" \
      -H 'Content-Type: application/json' ${entetes[@]+"${entetes[@]}"} \
      -d '{"mapType":"roadmap","language":"fr-FR","region":"SN"}' 2>/dev/null || true)
    accepte="acceptée par Google depuis un appelant inconnu : sa restriction d'application est à vérifier dans la console Google Cloud."
    refuse="refusée depuis un appelant inconnu"
    ;;
  api)
    code=$(curl -s -m 20 -o "$reponse" -w '%{http_code}' -X POST \
      'https://places.googleapis.com/v1/places:autocomplete' \
      -H 'Content-Type: application/json' -H "X-Goog-Api-Key: $CLE" ${entetes[@]+"${entetes[@]}"} \
      -d '{"input":"Dakar","languageCode":"fr"}' 2>/dev/null || true)
    accepte="acceptée par Google pour une API qui n'est pas la carte : sa restriction d'API est à vérifier dans la console Google Cloud."
    refuse="refusée pour une API qui n'est pas la carte"
    ;;
  *)
    echo "::warning title=$libelle::Contrôle mal appelé (mode « $mode » inconnu)."
    exit 0
    ;;
esac
rm -f "$reponse"

case "$code" in
  200)
    echo "::warning title=$libelle::Clé $accepte"
    ;;
  400 | 401 | 403)
    echo "$libelle : clé $refuse (HTTP $code), comme prévu."
    ;;
  *)
    echo "$libelle : contrôle non concluant (HTTP ${code:-aucune réponse}), refait au prochain push."
    ;;
esac
exit 0
