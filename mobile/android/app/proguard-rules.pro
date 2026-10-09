# Règles R8 de l'APK de production (le plugin Flutter les ajoute aux siennes).

# Les composants Firebase (Crashlytics, App Check…) sont instanciés par leur
# nom au démarrage (ComponentDiscovery lit leur nom dans le manifeste, puis
# appelle leur constructeur sans argument). En mode complet, R8 retire ce
# constructeur : « NoSuchMethodException », puis « FirebaseCrashlytics
# component is not present », ce qui fait échouer Firebase.initializeApp et
# laisse l'app sans écran. Vu à l'essai sur émulateur de la CI
# (.github/workflows/essai-android.yml).
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
