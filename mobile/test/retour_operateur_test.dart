import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/notifications/capacites_navigateur.dart';
import 'package:sprint/core/paiement/retour_operateur.dart';

const _commande = '41b5aaaabbbbccccddddeeee';
const _recharge = 'rch_0123456789abcdef01234567';

/// Retour dans Sprint après un paiement Orange Money (signalé par le client,
/// 12 novembre 2026 : le téléphone ouvrait le navigateur, puis une page
/// d'installation, au lieu de revenir dans l'application).
void main() {
  group('paiement « sans retour » : seulement le site installé sur l\'écran d\'accueil d\'un iPhone', () {
    test('iPhone installé : oui, avec l\'option envoyée au serveur', () {
      const installe = CapacitesNavigateur(iphone: true, ecranAccueil: true);
      expect(paiementSansRetour(installe), isTrue);
      expect(optionRetour(installe), {'sansRetour': true});
    });

    test('tous les autres cas : non, rien n\'est envoyé (Safari, Android, APK, ordinateur, tests)', () {
      for (final c in const [
        CapacitesNavigateur(iphone: true),
        CapacitesNavigateur(android: true),
        CapacitesNavigateur(android: true, ecranAccueil: true),
        CapacitesNavigateur(ecranAccueil: true),
        CapacitesNavigateur(),
      ]) {
        expect(paiementSansRetour(c), isFalse);
        expect(optionRetour(c), isEmpty);
      }
      // Hors navigateur (APK, tests) : valeurs neutres.
      expect(paiementSansRetour(), isFalse);
      expect(optionRetour(), isEmpty);
    });
  });

  group('lien qui rouvre l\'APK Sprint depuis un navigateur Android', () {
    test('course et recharge, paiement validé ou annulé : adressé au seul paquet Sprint, repli sur la page avec app=0', () {
      for (final (reference, etat) in [(_commande, 'ok'), (_commande, 'annule'), (_recharge, 'ok'), (_recharge, 'annule')]) {
        final repli = Uri.encodeComponent('https://sprint-vtc.web.app/paiement/retour?ref=$reference&etat=$etat&app=0');
        expect(
          lienRetourDansLApplication(reference: reference, etat: etat).toString(),
          'intent://sprint-vtc.web.app/paiement/retour?ref=$reference&etat=$etat'
          '#Intent;scheme=https;package=sn.groupesantine.sprint;S.browser_fallback_url=$repli;end',
        );
      }
    });

    test('rien d\'autre qu\'une référence et un état connus n\'est jamais transmis à l\'APK', () {
      for (final reference in [null, '', 'rch_', '41B5AAAABBBBCCCCDDDDEEEE', '../commandes', 'essai-sprint-1', '$_commande;end', '$_commande&app=1']) {
        expect(lienRetourDansLApplication(reference: reference, etat: 'ok'), isNull, reason: '$reference');
      }
      for (final etat in [null, '', 'OK', 'annulé', 'ok;package=autre.app', 'ok&x=1']) {
        expect(lienRetourDansLApplication(reference: _commande, etat: etat), isNull, reason: '$etat');
      }
    });
  });
}
