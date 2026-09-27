/// Montant en francs CFA avec séparateur de milliers : `2 500 FCFA`
/// (espace fine insécable, pour ne jamais couper le nombre à la ligne).
String formaterFcfa(int montant) {
  final chiffres = montant.abs().toString();
  final groupes = <String>[];
  for (var fin = chiffres.length; fin > 0; fin -= 3) {
    groupes.insert(0, chiffres.substring(fin - 3 < 0 ? 0 : fin - 3, fin));
  }
  return '${montant < 0 ? '-' : ''}${groupes.join(' ')} FCFA';
}
