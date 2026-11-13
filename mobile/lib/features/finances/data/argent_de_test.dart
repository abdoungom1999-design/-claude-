/// Argent réel ou argent de test (décision du client, 13 novembre 2026).
///
/// Tant que Wave est simulé (le « faux Wave » du serveur), un paiement ou une
/// recharge Wave ne débite personne : c'est de l'argent de test. Il est réservé
/// aux comptes de test et ne doit jamais entrer dans la comptabilité. Le
/// serveur marque lui-même chaque course (`argentDeTest`, voir
/// `functions/src/argent_reel.ts`) ; l'app ne fait que lire cette marque.
library;

/// Orange Money encaisse de l'argent réel depuis la publication 114 (fonctions
/// déployées le 2 novembre 2026 entre 9 h 41 et 9 h 43, heure de Dakar = UTC) ;
/// avant : bac à sable, argent de test. Jumeau de `DEBUT_ARGENT_REEL_ORANGE`
/// (functions/src/argent_reel.ts) : un test du serveur vérifie qu'ils sont
/// d'accord.
final debutArgentReelOrange = DateTime.utc(2026, 11, 2, 9, 43);

/// Une course créée AVANT le marquage n'a pas de champ `argentDeTest` : elle est
/// jugée sur son moyen de paiement et sa date, jamais en argent réel par défaut
/// pour ce qui était simulé.
///
/// - `WAVE` : le seul Wave de l'époque est le faux Wave : argent de test ;
/// - `ORANGE_MONEY` : argent réel depuis [debutArgentReelOrange], bac à sable avant ;
/// - `PORTEFEUILLE` : le solde était alimenté par le faux Wave pendant les essais, et
///   l'origine de l'argent d'une ancienne course n'est pas enregistrée : par
///   prudence, de l'argent de test (la comptabilité ne compte que ce qui est sûr) ;
/// - autre (courses d'avant le mobile money, sans moyen connu) : comptée comme avant.
bool courseSansMarqueEnArgentDeTest({required String methodePaiement, required DateTime date}) =>
    switch (methodePaiement) {
      'WAVE' => true,
      'ORANGE_MONEY' => date.isBefore(debutArgentReelOrange),
      'PORTEFEUILLE' => true,
      _ => false,
    };
