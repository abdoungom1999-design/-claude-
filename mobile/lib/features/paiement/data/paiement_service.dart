import '../../../core/widgets/payment_method_selector.dart';

enum StatutTransaction { succes, echec, annule }

class TransactionResult {
  const TransactionResult({required this.statut, required this.id, this.message});

  final StatutTransaction statut;

  /// Référence de la transaction chez l'opérateur (vide si échec).
  final String id;

  /// Raison lisible en cas d'échec ou d'annulation.
  final String? message;

  bool get estReussie => statut == StatutTransaction.succes;
}

/// Encaissement d'une course par mobile money (Wave / Orange Money).
///
/// Le tunnel de commande ne dépend que de cette interface : seule
/// [PaiementServiceSandbox] existe aujourd'hui. Pour passer en réel, il
/// suffira d'ajouter une implémentation qui appelle le backend (le
/// module NestJS `payments` expose déjà `POST /payments/wave/initier`
/// et `POST /payments/orange-money/initier`, avec vérification HMAC des
/// webhooks) puis de la renvoyer depuis [PaiementService.parDefaut].
/// Les clés API (Wave, Orange Money ou PayDunya) doivent rester côté
/// serveur : ce client Flutter Web est public, toute clé secrète qui y
/// serait injectée serait lisible par n'importe quel visiteur.
abstract interface class PaiementService {
  factory PaiementService.parDefaut() = PaiementServiceSandbox;

  Future<TransactionResult> initierPaiementWave(double montant);

  Future<TransactionResult> initierPaiementOrangeMoney(double montant);
}

extension PaiementParMethode on PaiementService {
  Future<TransactionResult> initierPaiement(PaymentMethod methode, double montant) {
    switch (methode) {
      case PaymentMethod.wave:
        return initierPaiementWave(montant);
      case PaymentMethod.orangeMoney:
        return initierPaiementOrangeMoney(montant);
    }
  }
}

/// Mode Sandbox : aucun appel réseau, aucun argent débité. Simule le
/// délai de confirmation de l'opérateur puis renvoie toujours un succès.
class PaiementServiceSandbox implements PaiementService {
  const PaiementServiceSandbox({this.delai = const Duration(seconds: 2)});

  final Duration delai;

  @override
  Future<TransactionResult> initierPaiementWave(double montant) => _simuler('WAVE');

  @override
  Future<TransactionResult> initierPaiementOrangeMoney(double montant) => _simuler('OM');

  Future<TransactionResult> _simuler(String prefixe) async {
    await Future.delayed(delai);
    return TransactionResult(
      statut: StatutTransaction.succes,
      id: 'TXN-$prefixe-DEMO-${DateTime.now().millisecondsSinceEpoch}',
    );
  }
}
