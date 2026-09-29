// Hors navigateur (APK Android, tests) : rien à maintenir. Sur Android,
// le GPS reste actif écran éteint grâce au service de premier plan (voir
// PositionChauffeurService.reglagesSuivi).
Future<void> activer() async {}

Future<void> desactiver() async {}
