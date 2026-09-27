import 'alerte_sonore_stub.dart' if (dart.library.js_interop) 'alerte_sonore_web.dart' as plateforme;

/// Sonnerie "Nouvelle course" du chauffeur : trois bips aigus et forts,
/// générés par le navigateur (Web Audio, aucun fichier son à charger),
/// plus une vibration sur Android.
///
/// Les navigateurs n'autorisent le son qu'après un geste de
/// l'utilisateur : [preparer] doit être appelé lors d'un appui (passage
/// "En ligne"), ensuite [nouvelleCourse] peut sonner à tout moment.
/// Limites : sur iPhone, le bouton silencieux coupe ce son et la
/// vibration n'existe pas pour les applications web.
abstract final class AlerteSonore {
  static void preparer() => plateforme.preparer();

  static void nouvelleCourse() => plateforme.nouvelleCourse();
}
