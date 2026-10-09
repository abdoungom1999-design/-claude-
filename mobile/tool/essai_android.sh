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
  grep -E "FirebaseCrashlytics|Crashlytics|AndroidRuntime|FATAL|Fatal signal|DEBUG  |flutter|FirebaseApp|FlutterFirebase|DataTransport" "$1" \
    | grep -v "chatty\|Choreographer\|ViewRootImpl" | tail -n "${2:-40}"
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
sleep 7

if vivant; then
  constat ok "Démarrage" "L'app tourne 7 secondes après son lancement."
else
  constat ko "Démarrage" "L'app s'est arrêtée dans les 7 premières secondes."
fi

# Image de l'écran, réduite pour tenir dans une annotation (lisible par base64).
adb exec-out screencap -p > "$sortie/ecran.png" 2> /dev/null
if [ -s "$sortie/ecran.png" ] && command -v convert > /dev/null; then
  convert "$sortie/ecran.png" -resize 220x -quality 40 "$sortie/ecran.jpg" 2> /dev/null
  [ -s "$sortie/ecran.jpg" ] && annoter notice "Écran à 7 s (JPEG en base64)" "$(base64 -w0 "$sortie/ecran.jpg")"
fi

# --- 2 et 3. initialisation de Crashlytics, puis plantage de test --------------
sleep 20
adb logcat -d > "$sortie/journal1.txt" 2>&1
annoter notice "Journal du 1er lancement (extrait)" "$(filtrer "$sortie/journal1.txt" 45)"

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

if grep -qiE "upload (complete|successful)|report.*(sent|uploaded)|successfully (enqueued|sent)|Crashlytics report upload" "$sortie/journal2.txt"; then
  constat ok "Rapport envoyé à Crashlytics" "$(grep -iE 'upload (complete|successful)|report.*(sent|uploaded)|successfully (enqueued|sent)|Crashlytics report upload' "$sortie/journal2.txt" | head -n 3 | cut -c1-300)"
else
  constat ko "Rapport envoyé à Crashlytics" "Aucune ligne d'envoi de rapport dans le journal du 2e lancement."
fi

exit "$echecs"
