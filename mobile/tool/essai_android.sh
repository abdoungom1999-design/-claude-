#!/usr/bin/env bash
# Essai sur émulateur Android (voir .github/workflows/essai-android.yml).
# Lancé depuis mobile/ par l'action android-emulator-runner, une fois
# l'émulateur démarré. L'APK a été compilé avec ESSAI_PLANTAGE : dix secondes
# après le démarrage, l'app se plante exprès (plantage natif de Crashlytics).
#
# Le journal complet de la CI n'est pas lisible de l'extérieur : les
# résultats sortent en annotations GitHub (une par constat).
#
# Vérifie :
#  1. l'APK s'installe et l'app démarre, sans planter pendant ses premières secondes ;
#  2. Crashlytics s'initialise (pas d'« identifiant de build manquant ») ;
#  3. le plantage de test a bien lieu ;
#  4. à l'ouverture suivante, le rapport du plantage est envoyé à Firebase.
set -u

apk=build/app/outputs/flutter-apk/app-release.apk
paquet=sn.groupesantine.sprint
sortie="${RUNNER_TEMP:-/tmp}/essai-android"
mkdir -p "$sortie"
echecs=0

# annoter <notice|warning|error> <titre> <message sur plusieurs lignes>
annoter() {
  local message
  message=$(printf '%s' "$3" | head -c 12000 | sed ':a;N;$!ba;s/%/%25/g;s/\r/%0D/g;s/\n/%0A/g')
  echo "::$1 title=$2::$message"
}

constat() { # <ok|ko> <titre> <détail>
  if [ "$1" = ok ]; then
    annoter notice "OK · $2" "$3"
  else
    annoter error "ÉCHEC · $2" "$3"
    echecs=$((echecs + 1))
  fi
}

vivant() { adb shell pidof "$paquet" 2> /dev/null | tr -d '\r' | grep -q '[0-9]'; }

# Lignes utiles du journal : Crashlytics, plantages, Flutter, Firebase.
filtrer() {
  grep -E "Crashlytics|AndroidRuntime|FATAL|Fatal signal|DEBUG  |flutter|Firebase|ComponentDiscovery|DataTransport" "$1" \
    | grep -v "chatty\|Choreographer\|ViewRootImpl" | cut -c1-260 | tail -n "${2:-40}"
}

# --- 1. installation et premier démarrage --------------------------------------
if ! adb install -r "$apk" > "$sortie/installation.txt" 2>&1; then
  constat ko "Installation de l'APK" "$(cat "$sortie/installation.txt")"
  exit 1
fi
constat ok "Installation de l'APK" "$(ls -l "$apk" | awk '{print $5}') octets"

# Journaux détaillés du SDK Crashlytics (messages « report upload »).
adb shell setprop log.tag.FirebaseCrashlytics VERBOSE
adb shell input keyevent KEYCODE_WAKEUP > /dev/null 2>&1
adb logcat -c
adb shell am start -W -n "$paquet/.MainActivity" > "$sortie/lancement1.txt" 2>&1
sleep 9

if vivant; then
  constat ok "Démarrage" "L'app tourne 9 secondes après son lancement."
else
  constat ko "Démarrage" "L'app s'est arrêtée dans les 9 premières secondes."
fi

# Image de l'écran : non vide ? (un écran uni se compresse en quelques Ko), puis
# réduite pour tenir dans une annotation (lisible en base64).
adb exec-out screencap -p > "$sortie/ecran.png" 2> /dev/null
taille=$(stat -c %s "$sortie/ecran.png" 2> /dev/null || echo 0)
if [ "$taille" -gt 60000 ]; then
  constat ok "Écran affiché" "Capture de $taille octets (écran non vide)."
else
  constat ko "Écran affiché" "Capture de $taille octets : écran vide ou capture impossible."
fi
reduire=$(command -v convert || command -v magick || true)
if [ -n "$reduire" ] && [ "$taille" -gt 0 ]; then
  "$reduire" "$sortie/ecran.png" -resize 220x -quality 40 "$sortie/ecran.jpg" 2> /dev/null
  [ -s "$sortie/ecran.jpg" ] && annoter notice "Écran à 9 s (JPEG en base64)" "$(base64 -w0 "$sortie/ecran.jpg")"
else
  annoter notice "Écran à 9 s" "Réduction de la capture impossible (ImageMagick absent : '${reduire:-aucun}')."
fi

# --- 2 et 3. initialisation de Crashlytics, puis plantage de test --------------
sleep 20
adb logcat -d > "$sortie/journal1.txt" 2>&1
annoter notice "Journal du 1er lancement (extrait)" "$(filtrer "$sortie/journal1.txt" 45)"
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
if grep -qiE "build ID is missing|mapping_file_id|RequireBuildId" "$sortie/journal1.txt"; then
  constat ko "Identifiant de build" "$(grep -iE 'build ID is missing|mapping_file_id|RequireBuildId' "$sortie/journal1.txt" | head -n 3)"
else
  constat ok "Identifiant de build" "Aucune plainte du SDK sur l'identifiant de build."
fi

if vivant; then
  constat ko "Plantage de test" "L'app tourne encore 27 secondes après le lancement : le plantage de test n'a pas eu lieu."
else
  if grep -qE "FATAL EXCEPTION|Fatal signal" "$sortie/journal1.txt"; then
    constat ok "Plantage de test" "L'app s'est arrêtée par plantage : $(grep -E 'FATAL EXCEPTION|Fatal signal' "$sortie/journal1.txt" | head -n 1 | cut -c1-200)"
  else
    constat ko "Plantage de test" "L'app s'est arrêtée sans trace de plantage dans le journal."
  fi
fi

# --- 4. ouverture suivante : le rapport est envoyé -----------------------------
adb logcat -c
adb shell am start -W -n "$paquet/.MainActivity" > "$sortie/lancement2.txt" 2>&1
sleep 45
adb logcat -d > "$sortie/journal2.txt" 2>&1
annoter notice "Journal du 2e lancement (extrait)" "$(filtrer "$sortie/journal2.txt" 45)"

envoi=$(grep -i "Crashlytics" "$sortie/journal2.txt" | grep -iE "upload|sent|enqueue|send" | cut -c1-300)
annoter notice "Lignes Crashlytics du 2e lancement" "$(grep -i 'Crashlytics' "$sortie/journal2.txt" | cut -c1-260 | head -n 40)"
if [ -n "$envoi" ]; then
  constat ok "Rapport envoyé à Crashlytics" "$(echo "$envoi" | head -n 4)"
else
  constat ko "Rapport envoyé à Crashlytics" "Aucune ligne d'envoi de rapport dans le journal du 2e lancement."
fi

exit "$echecs"
