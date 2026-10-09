#!/usr/bin/env bash
# Essai sur émulateur Android (voir .github/workflows/essai-android.yml).
# Lancé depuis mobile/ par l'action android-emulator-runner, une fois
# l'émulateur démarré. L'APK a été compilé avec ESSAI_PLANTAGE : trente
# secondes après le démarrage, l'app se plante exprès (plantage de test de
# Crashlytics).
#
# Le journal complet de la CI n'est pas lisible de l'extérieur : les
# résultats sortent en annotations GitHub. GitHub n'en garde que dix de chaque
# genre par étape : les constats « OK » sont donc regroupés dans un seul bilan,
# et seuls les échecs ont leur propre annotation.
#
# Vérifie :
#  1. l'APK s'installe, l'app démarre et affiche un écran, sans exception ;
#  2. Crashlytics s'initialise (pas d'« identifiant de build manquant ») ;
#  3. le plantage de test a bien lieu et Crashlytics en garde un rapport ;
#  4. à l'ouverture suivante, ce rapport est envoyé à Firebase.
set -u

apk=build/app/outputs/flutter-apk/app-release.apk
paquet=sn.groupesantine.sprint
sortie="${RUNNER_TEMP:-/tmp}/essai-android"
mkdir -p "$sortie"
echecs=0
bilan=""

# annoter <notice|warning|error> <titre> <message sur plusieurs lignes>
annoter() {
  local message
  message=$(printf '%s' "$3" | head -c 12000 | sed ':a;N;$!ba;s/%/%25/g;s/\r/%0D/g;s/\n/%0A/g')
  echo "::$1 title=$2::$message"
}

constat() { # <ok|ko> <titre> <détail>
  if [ "$1" = ok ]; then
    bilan="$bilan"$'\n'"OK    $2 : $(printf '%s' "$3" | head -n 1 | cut -c1-220)"
  else
    bilan="$bilan"$'\n'"ÉCHEC $2 : $(printf '%s' "$3" | head -n 1 | cut -c1-220)"
    annoter error "ÉCHEC · $2" "$3"
    echecs=$((echecs + 1))
  fi
}

vivant() { adb shell pidof "$paquet" 2> /dev/null | tr -d '\r' | grep -q '[0-9]'; }

# Lignes d'un journal qui concernent Crashlytics et l'envoi des rapports.
lignes_crashlytics() {
  grep -E "Crashlytics|TRuntime|DataTransport|CctTransport|FirebaseSessions" "$1" | cut -c1-250
}

# --- 1. installation et premier démarrage --------------------------------------
if ! adb install -r "$apk" > "$sortie/installation.txt" 2>&1; then
  constat ko "Installation de l'APK" "$(cat "$sortie/installation.txt")"
  exit 1
fi
constat ok "Installation de l'APK" "$(stat -c %s "$apk") octets"

# Journaux détaillés du SDK Crashlytics ; accès aux fichiers de l'app (image sans Play Store).
adb shell setprop log.tag.FirebaseCrashlytics VERBOSE
adb root > /dev/null 2>&1
sleep 3
adb shell input keyevent KEYCODE_WAKEUP > /dev/null 2>&1
adb logcat -c
adb shell am start -W -n "$paquet/.MainActivity" > "$sortie/lancement1.txt" 2>&1
sleep 12

if vivant; then
  constat ok "Démarrage" "L'app tourne 12 secondes après son lancement."
else
  constat ko "Démarrage" "L'app s'est arrêtée dans les 12 premières secondes (avant le plantage de test prévu à 30 s)."
fi

# Image de l'écran : l'app (et non l'écran d'accueil du téléphone) est-elle au premier plan ?
adb exec-out screencap -p > "$sortie/ecran.png" 2> /dev/null
taille=$(stat -c %s "$sortie/ecran.png" 2> /dev/null || echo 0)
premier_plan=$(adb shell dumpsys activity activities 2> /dev/null | grep -E "topResumedActivity|mResumedActivity" | head -n 1 | tr -d '\r')
if echo "$premier_plan" | grep -q "$paquet"; then
  constat ok "Écran affiché" "L'app est au premier plan (capture de $taille octets)."
else
  constat ko "Écran affiché" "L'app n'est pas au premier plan : ${premier_plan:-inconnu} (capture de $taille octets)."
fi
reduire=$(command -v convert || command -v magick || true)
if [ -n "$reduire" ] && [ "$taille" -gt 0 ]; then
  "$reduire" "$sortie/ecran.png" -resize 220x -quality 40 "$sortie/ecran.jpg" 2> /dev/null
  [ -s "$sortie/ecran.jpg" ] && annoter notice "Écran à 12 s (JPEG en base64)" "$(base64 -w0 "$sortie/ecran.jpg")"
fi

# --- 2 et 3. initialisation de Crashlytics, puis plantage de test (à 30 s) -----
sleep 45
adb logcat -d > "$sortie/journal1.txt" 2>&1

if grep -q "ComponentDiscovery" "$sortie/journal1.txt"; then
  annoter warning "Composants Firebase non instanciés" "$(grep 'ComponentDiscovery' "$sortie/journal1.txt" | cut -c1-220 | head -n 30)"
fi
if grep -q "Unhandled Exception" "$sortie/journal1.txt"; then
  constat ko "Exceptions au démarrage" "$(grep -A3 'Unhandled Exception' "$sortie/journal1.txt" | cut -c1-400 | head -n 12)"
else
  constat ok "Exceptions au démarrage" "Aucune exception Dart non rattrapée."
fi
if grep -qiE "Initializing Firebase Crashlytics" "$sortie/journal1.txt"; then
  constat ok "Crashlytics initialisé" "$(grep -iE 'Initializing Firebase Crashlytics' "$sortie/journal1.txt" | head -n 1 | cut -c1-300)"
else
  constat ko "Crashlytics initialisé" "Aucune ligne « Initializing Firebase Crashlytics » dans le journal."
fi
if grep -qiE "build ID is missing" "$sortie/journal1.txt"; then
  constat ko "Identifiant de build" "$(grep -iE 'build ID is missing' "$sortie/journal1.txt" | head -n 3)"
else
  constat ok "Identifiant de build" "$(grep -E 'Mapping file ID is' "$sortie/journal1.txt" | head -n 1 | cut -c1-200)"
fi

if vivant; then
  constat ko "Plantage de test" "L'app tourne encore 57 secondes après le lancement : le plantage de test n'a pas eu lieu."
elif grep -qE "FirebaseCrashlyticsTestCrash" "$sortie/journal1.txt"; then
  constat ok "Plantage de test" "Plantage volontaire capté : $(grep -E 'Handling uncaught exception' "$sortie/journal1.txt" | head -n 1 | cut -c1-200)"
else
  constat ko "Plantage de test" "L'app s'est arrêtée, mais pas par le plantage de test."
fi

# Ce que Crashlytics a gardé sur le téléphone après le plantage.
fichiers=$(adb shell 'find /data/data/sn.groupesantine.sprint/files/.com.google.firebase.crashlytics -type f 2>/dev/null' | tr -d '\r' | sed 's|.*/\.com\.google\.firebase\.crashlytics/||' | head -n 40)
annoter notice "Fichiers de Crashlytics après le plantage" "${fichiers:-aucun (ou accès impossible)}"
apres=$(awk '/FATAL EXCEPTION/{f=1} f' "$sortie/journal1.txt" | grep -E "Crashlytics|CctTransport|TRuntime|DataTransport" | cut -c1-250 | head -n 45)
annoter notice "Crashlytics juste après le plantage (lancement 1)" "${apres:-aucune ligne}"

# --- 4. ouverture suivante : le rapport est envoyé -----------------------------
adb logcat -c
adb shell am start -W -n "$paquet/.MainActivity" > "$sortie/lancement2.txt" 2>&1
sleep 40
adb logcat -d > "$sortie/journal2.txt" 2>&1
annoter notice "Crashlytics au 2e lancement (envoi du rapport)" "$(lignes_crashlytics "$sortie/journal2.txt" | grep -v 'automatic data collection' | head -n 60)"

if grep -q "successfully enqueued to DataTransport" "$sortie/journal2.txt"; then
  constat ok "Rapport remis à l'envoi" "$(grep 'successfully enqueued to DataTransport' "$sortie/journal2.txt" | head -n 1 | cut -c1-250)"
else
  constat ko "Rapport remis à l'envoi" "Aucune ligne « successfully enqueued to DataTransport » au 2e lancement."
fi
if grep -E "CctTransport|TRuntime" "$sortie/journal2.txt" | grep -qiE "status code: 200|HTTP 200|response code: 200"; then
  constat ok "Serveur Crashlytics" "$(grep -E 'CctTransport|TRuntime' "$sortie/journal2.txt" | grep -iE 'status code: 200|HTTP 200|response code: 200' | head -n 1 | cut -c1-250)"
else
  constat ko "Serveur Crashlytics" "Aucune réponse HTTP 200 du serveur de rapports."
fi

annoter notice "Bilan de l'essai" "$bilan"
exit "$echecs"
