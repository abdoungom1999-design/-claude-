{{flutter_js}}
{{flutter_build_config}}

// Sprint : aucun service worker Flutter (il est déprécié et ne met rien en
// cache dans cette version ; l'enregistrer provoquait seulement des rechargements
// en cascade). La fraîcheur du site est assurée par les en-têtes « no-cache » et
// par le contrôle de version d'index.html (rechargement quand une nouvelle
// publication est en ligne).
_flutter.loader.load();
