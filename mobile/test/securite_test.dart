import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/features/auth/data/auth_repository.dart';

void main() {
  test('Clé d\'annuaire : rôle et téléphone, alignée sur firestore.rules', () {
    expect(AuthRepository.cleAnnuaire('client', ' +221770000000 '), 'client_+221770000000');
    expect(AuthRepository.cleAnnuaire('conducteur', '+221770000000'), 'conducteur_+221770000000');
  });

  test('Clé d\'annuaire : aucun identifiant Firestore invalide', () {
    expect(AuthRepository.cleAnnuaire('client', ''), isNull);
    expect(AuthRepository.cleAnnuaire('client', '77/000'), isNull);
  });
}
