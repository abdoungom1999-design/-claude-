/// Groupe Santine est passé au 100% mobile money : les chauffeurs ne
/// gèrent plus d'espèces. Le client paie avec le solde du Portefeuille Sprint
/// [portefeuille] (rechargé par mobile money), ou par mobile money : Orange
/// Money selon [accesOrangeMoney], et Wave, qui est encore le FAUX Wave (aucune
/// somme débitée) : réservé aux comptes de test ([waveReel]) ; voir
/// `payment_method_sheet.dart` et `PaymentProcessingPage`.
///
/// [orangeMoney] reste dans l'énumération pour l'historique (courses et
/// recharges, libellés). Son fournisseur réel est branché côté serveur, mais
/// il n'est proposé que selon [accesOrangeMoney] : voir
/// [moyensMobileMoneyPour].
enum PaymentMethod { wave, orangeMoney, portefeuille }

/// Qui peut payer avec Orange Money (décisions du client, 29 octobre 2026).
enum AccesOrangeMoney {
  /// Personne : ni proposé, ni accepté par le serveur.
  ferme,

  /// Seulement les comptes clients marqués « Testeur Orange Money » par un
  /// Admin (essai réel de bout en bout) ; les autres clients ne voient rien.
  testeurs,

  /// Tous les clients (ouverture officielle).
  tous,
}

/// Réglage en service. Ne change qu'avec le go du client, en même temps que
/// son jumeau du serveur (`ACCES_ORANGE_MONEY`,
/// `functions/src/methodes_paiement.ts`) : un test du serveur vérifie qu'ils
/// sont d'accord.
const accesOrangeMoney = AccesOrangeMoney.testeurs;

/// Le vrai Wave est-il branché ? Tant qu'il ne l'est pas, « Wave » est le faux
/// Wave : aucune somme n'est débitée. Décision du client (13 novembre 2026) :
/// il est cloisonné aux COMPTES DE TEST (les comptes marqués par un Admin) et
/// tout ce qu'il produit est de l'argent de test, jamais compté dans la
/// comptabilité ; les autres clients ne le voient pas.
///
/// Ne change qu'avec le go du client, quand le vrai Wave est branché, en même
/// temps que son jumeau du serveur (`WAVE_REEL`,
/// `functions/src/methodes_paiement.ts`) : un test du serveur vérifie qu'ils
/// sont d'accord.
const waveReel = false;

/// Où Orange Money encaisse (décision du client).
enum EnvironnementOrangeMoney {
  /// Bac à sable d'Orange : données de test, aucun argent réel.
  bacASable,

  /// Production : argent réel, versé sur le compte marchand de Groupe Santine.
  production,
}

/// Réglage en service. Ne change qu'avec le go du client, en même temps que
/// son jumeau du serveur (`ENVIRONNEMENT_ORANGE_MONEY`,
/// `functions/src/methodes_paiement.ts`) : un test du serveur vérifie qu'ils
/// sont d'accord.
const environnementOrangeMoney = EnvironnementOrangeMoney.production;

/// Le profil (`users/{uid}`) porte-t-il la marque posée par un Admin sur les
/// COMPTES DE TEST (champ `testeurOrangeMoney`, historiquement « Testeur Orange
/// Money »), qui ouvre Orange Money pendant l'essai et le faux Wave ? Seul `true`
/// compte, comme pour le serveur.
bool estTesteurOrangeMoney(Map<String, dynamic>? profil) => profil?['testeurOrangeMoney'] == true;

/// Moyens de mobile money proposés à ce client, dans l'ordre d'affichage. Le
/// serveur applique la même règle (`methodesPour`, functions/src/methodes_paiement.ts).
///
/// [testeur] : compte de test. Le faux Wave (tant que [vraiWave] est faux) et
/// Orange Money pendant l'essai ne sont proposés qu'à lui : un client ordinaire
/// n'a, pour l'instant, aucun mobile money, seulement son solde Sprint.
/// [demo] : l'app tourne sans Firebase (mode démo, tests d'interface) : aucun
/// serveur, aucune comptabilité, Wave y est proposé comme avant.
List<PaymentMethod> moyensMobileMoneyPour({
  required bool testeur,
  bool demo = false,
  AccesOrangeMoney acces = accesOrangeMoney,
  bool vraiWave = waveReel,
}) =>
    [
      if (vraiWave || testeur || demo) PaymentMethod.wave,
      if (acces == AccesOrangeMoney.tous || (acces == AccesOrangeMoney.testeurs && testeur)) PaymentMethod.orangeMoney,
    ];

/// Ce moyen débite-t-il vraiment le client ? Wave passe encore par le faux
/// opérateur du serveur (aucune somme débitée, [waveReel]) ; Orange Money, en
/// production. Le solde Sprint, lui, ne « débite » rien d'autre que le solde.
extension PaymentMethodArgentReel on PaymentMethod {
  bool argentReel({EnvironnementOrangeMoney environnement = environnementOrangeMoney, bool vraiWave = waveReel}) =>
      switch (this) {
        PaymentMethod.orangeMoney => environnement == EnvironnementOrangeMoney.production,
        PaymentMethod.wave => vraiWave,
        PaymentMethod.portefeuille => false,
      };

  /// Mobile money qui ne débite personne : de l'argent de test (jamais compté dans la comptabilité).
  bool argentDeTest({EnvironnementOrangeMoney environnement = environnementOrangeMoney, bool vraiWave = waveReel}) =>
      this != PaymentMethod.portefeuille && !argentReel(environnement: environnement, vraiWave: vraiWave);
}

/// Mention sous les [moyens] proposés : lesquels débitent vraiment le client.
String mentionPaiement(List<PaymentMethod> moyens, {EnvironnementOrangeMoney environnement = environnementOrangeMoney}) {
  final reels = [for (final m in moyens) if (m.argentReel(environnement: environnement)) m.label];
  final simules = [for (final m in moyens) if (!m.argentReel(environnement: environnement)) m.label];
  if (reels.isEmpty) return 'Paiement sécurisé — argent de test, aucun débit réel';
  if (simules.isEmpty) return 'Paiement sécurisé';
  return 'Paiement sécurisé — ${reels.join(', ')} : argent réel · ${simules.join(', ')} : argent de test, aucun débit réel';
}

extension PaymentMethodLabel on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.wave:
        return 'Wave';
      case PaymentMethod.orangeMoney:
        return 'Orange Money';
      case PaymentMethod.portefeuille:
        return 'Solde Sprint';
    }
  }
}

/// Ce que le client fait une fois la page de l'opérateur ouverte (sas de
/// paiement et de recharge). Orange Money s'ouvre dans Max It ou Orange
/// Money, où seul le client tape son code secret.
extension PaymentMethodConsigne on PaymentMethod {
  String get consignePaiement => switch (this) {
        PaymentMethod.orangeMoney =>
          'Validez le paiement dans Max It ou Orange Money avec votre code secret '
              '(Sprint ne vous le demandera jamais)',
        _ => "Payez sur la page $label qui vient de s'ouvrir",
      };
}

/// Valeur attendue par le serveur (callables `creerPaiement` et `creerRecharge`).
extension PaymentMethodApi on PaymentMethod {
  String get apiValue {
    switch (this) {
      case PaymentMethod.wave:
        return 'WAVE';
      case PaymentMethod.orangeMoney:
        return 'ORANGE_MONEY';
      case PaymentMethod.portefeuille:
        return 'PORTEFEUILLE';
    }
  }
}
