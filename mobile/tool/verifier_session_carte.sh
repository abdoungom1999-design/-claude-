#!/usr/bin/env bash
# Vérification réelle auprès de Google (CI) : la clé ouvre-t-elle une
# session de carte (Map Tiles API) avec le style « Sprint sombre » ?
#
# Usage : CLE=… verifier_session_carte.sh <libellé> <style.json> [en-tête…]
#   ex. "Referer: https://sprint-vtc.web.app/" pour la clé web,
#   "X-Android-Package: …" et "X-Android-Cert: …" pour la clé Android.
#
# Non bloquant : un refus produit un avertissement dans le résumé du run
# (l'app repasse alors sur une carte sans style, ou sur OpenStreetMap).
# La clé n'est jamais affichée (secret masqué par GitHub).
set -u

libelle=$1
style=$2
shift 2
entetes=()
for entete in "$@"; do entetes+=(-H "$entete"); done
reponse="${RUNNER_TEMP:-/tmp}/session-carte.json"

essai() {
  curl -s -o "$reponse" -w '%{http_code}' -X POST \
    "https://tile.googleapis.com/v1/createSession?key=$CLE" \
    -H 'Content-Type: application/json' "${entetes[@]}" -d "$1"
}

motif() { grep -o '"message": *"[^"]*"' "$reponse" | head -n 1 | sed 's/"message": *//'; }

code=$(essai "{\"mapType\":\"roadmap\",\"language\":\"fr-FR\",\"region\":\"SN\",\"styles\":$(cat "$style")}")
if [ "$code" = 200 ] && grep -q '"session"' "$reponse"; then
  echo "$libelle : session Google ouverte avec le style Sprint sombre."
  exit 0
fi
refus_style="HTTP $code $(motif)"
echo "$libelle : refus avec le style ($refus_style)"

code=$(essai '{"mapType":"roadmap","language":"fr-FR","region":"SN"}')
if [ "$code" = 200 ] && grep -q '"session"' "$reponse"; then
  echo "::warning title=$libelle::Style Sprint sombre refusé par Google ($refus_style) : carte Google sans style."
else
  echo "::warning title=$libelle::Clé refusée par Google (HTTP $code $(motif)) : la carte restera sur OpenStreetMap."
fi
